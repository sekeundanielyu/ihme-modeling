// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	Append all long-term prevalence results from ODE process

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM STEP CODE (NO NEED TO EDIT THIS SECTION)

	// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	if "`1'"=="" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "05b"
		local 5 long_term_inc_to_raw_prev
		local 6 "/share/code/injuries/strUser/inj/gbd2015"
		local 7 160
		local 8 2000
		local 9 1
	}
	// base directory on J 
	local root_j_dir `1'
	// base directory on clustertmp
	local root_tmp_dir `2'
	// timestamp of current run (i.e. 2014_01_17)
	local date `3'
	// step number of this step (i.e. 01a)
	local step_num `4'
	// name of current step (i.e. first_step_name)
	local step_name `5'
    // directory where the code lives
    local code_dir `6'
    // iso3
	local location_id `7'
	// year
	local year `8'
	// sex
	local sex `9'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for standard code files
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Settings
	local slots 1
	local debug 99
	set type double, perm

// Get iso3
	quiet run "$prefix/WORK/10_gbd/00_library/functions/create_connection_string.ado"
		create_connection_string, strConnection
		local conn_string = r(conn_string)
	odbc load, exec("SELECT ihme_loc_id, location_name, location_id, location_type, super_region_name, most_detailed FROM shared.location_hierarchy_history WHERE location_set_version_id = (SELECT location_set_version_id FROM shared.location_set_version WHERE location_set_id = 9 and end_date IS NULL)") `conn_string' clear
	keep if most_detailed == 1
	keep if location_id == `location_id'
	local iso3 = [ihme_loc_id]

// Filepaths
	local gbd_ado "${prefix}/WORK/04_epi/01_database/01_code/00_library/ado"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local prev_results_dir "/share/injuries/dm/prev_results_tree/`iso3'/`year'/`sex'"
	local output_dir "`tmp_dir'/03_outputs"
	local draw_dir "`output_dir'/01_draws"
	local summ_dir "`output_dir'/02_summary"
	
// Import GBD functions
	adopath + `gbd_ado'
	adopath + `code_dir'/ado

// Start timer
	//start_timer, dir("`diag_dir'") name("append_results_`iso3'_`year'_`sex'") slots(`slots')
	
// Load injury parameters
	load_params
	
// Append results
	tempfile appended
	
	** loop over platform
		
		local e_codes: dir "`prev_results_dir'" dirs "*", respectcase
		local e_codes = subinstr(`"`e_codes'"',`"""',"",.)
		
		** loop over e-code
		foreach e of local e_codes {
		
			local e_dir "`prev_results_dir'/`e'"
			local files: dir "`e_dir'" files "prevalence_*", respectcase
			
			** loop over files
			foreach file of local files {
				cap import delimited "`e_dir'/`file'", asdouble clear
				if _rc == 0 {
					gen file = "`file'"
					split file, parse("_")
					rename file2 n_code
					replace file3 = subinstr(file3, ".csv", "", .)
					local pf = file3
					gen e_code = "`e'"
					if "`pf'" == "inp" gen inpatient = 1
					else gen inpatient = 0
					capture rename prev_* draw_*
					drop file*
					cap confirm file `appended'
					if _rc == 0 append using `appended'
					save `appended', replace
				}
			}
		}
	
// Pull shocks results and append 
	if `sex' == 1 {
		local sex_string = "male"
	}
	if `sex' == 2 {
		local sex_string = "female"
	}
	clear
	tempfile shocks_appended
	local shocks_dir = "/share/injuries/dm/prev_results_tree/shocks/`iso3'/`sex_string'"
	local platforms: dir "`shocks_dir'" dirs "*"
	foreach plat of local platforms {
		local ecodes: dir "`shocks_dir'/`plat'" dirs "*"
		foreach ecode of local ecodes {
			local ncodes: dir "`shocks_dir'/`plat'/`ecode'" dirs "*"
			foreach ncode of local ncodes {
				local files: dir "`shocks_dir'/`plat'/`ecode'/`ncode'" files "*`iso3'_`year'_`sex_string'*"
				foreach file of local files {
					import delimited "`shocks_dir'/`plat'/`ecode'/`ncode'/`file'", asdouble clear
					gen e_code = "`ecode'"
					gen n_code = "`ncode'"
					if "`plat'" == "inp" {
						gen inpatient = 1 
					}
					if "`plat'" == "otp" {
						gen inpatient = 0
					}
					cap confirm file `shocks_appended'
					if _rc == 0 append using `shocks_appended'
					save `shocks_appended', replace
				}
			}
		}
	}
append using `appended'

// Format
	order e_code n_code inpatient age, first
	sort_by_ncode n_code, other_sort(inpatient age)
	sort e_code
	format draw* %16.0g
	
// Save draws
	local outfile_name prevalence_`location_id'_`year'_`sex'.csv
	cap mkdir "`draw_dir'/`location_id'"
	cap mkdir "`draw_dir'/`location_id'/`year'"
	cap mkdir "`draw_dir'/`location_id'/`year'/`sex'"
	export delimited "`draw_dir'/`location_id'/`year'/`sex'/`outfile_name'", replace
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
