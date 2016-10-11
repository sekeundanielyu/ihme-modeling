// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	This code sums short-term prevalence data across inpatient/outpatient platforms to Ecode and Ncode YLDs

// *********************************************************************************************************************************************************************
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
		local 6 "/share/code/injuries/ngraetz/inj/gbd2015"
		local 7 165
		local 8 2010
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

// SETTINGS	
	set type double, perm
	
// Filepaths
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local rundir "`root_tmp_dir'/03_steps/`date'"
	
// Import functions
	adopath + "`code_dir'/ado"
	
// Load injury parameters
	load_params
	get_demographics, gbd_team("epi")

// Get location of short term ExN prev/ylds
** NOT USING get_step_num function here because previous step is too long to be the name of a global, so retrieving manually
** get_step_num, name("scaled_short_term_en_prev_yld_by_platform") stepfile("$prefix/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/01_code/`envir'/`functional'_steps.xlsx")
	local stepfile = "`code_dir'/_inj_steps.xlsx"
	local name = "scaled_short_term_en_prev_yld_by_platform"
	import excel using "`stepfile'", sheet("steps") clear firstrow allstring
	keep if name == "`name'"
	local previous_step_num = step[1]
	local st_prev_dir = "`rundir'/`previous_step_num'_scaled_short_term_en_prev_yld_by_platform"
	
// Load map to age_group_id
insheet using "`code_dir'/convert_to_new_age_ids.csv", comma names clear
	rename age_start age
	tempfile age_ids 
	save `age_ids', replace

// Load file of zero draws to copy where missing location/year/sex
insheet using "`in_dir'/parameters/zero_draws.csv", comma names clear
	tempfile zero_draws
	save `zero_draws', replace

// Load codebook for E/platform and N/platform short-term MEs
insheet using "`code_dir'/como_st_yld_mes.csv", comma names clear
	levelsof e_code, l(ecodes)
	levelsof n_code, l(ncodes)
	
// Run on both prevalence and ylds
	// foreach metric in prev ylds {
	foreach metric in ylds {
	
	// Set filepaths and macros
		if "`metric'" == "prev" {
			local draw_outdir "`tmp_dir'/03_outputs/01_draws"
			local fullmetric prevalence
		}
		else {
			local draw_outdir "/share/injuries/04_COMO_input/02_st_ylds"
			local fullmetric ylds
		}
		local summ_outdir "`tmp_dir'/03_outputs/02_summary/`metric'"
			
	// Open file and keep only the reporting age groups
		use "`st_prev_dir'/03_outputs/01_draws/`metric'/`location_id'/`fullmetric'_`year'_`sex'.dta", clear 
		drop if age > 80
		merge m:1 age using `age_ids', keep(3) nogen
		tempfile st_data
		save `st_data', replace

		// EDIT 5/13/16 ng - Collapse to platform E-code and platform N-code for save_results 
		cap mkdir "`draw_outdir'/E"
		cap mkdir "`draw_outdir'/N"

		if "`metric'" == "ylds" {
			// Collapse to E-code platform
			foreach ecode of local ecodes {
				use `st_data' if ecode == "`ecode'", clear
				count
				if r(N) == 0 {
					use `zero_draws', clear
					gen inpatient = 999
				}
				tempfile e_st_data
				save `e_st_data', replace
				forvalues platform = 0/1 {
					use `e_st_data' if inpatient == `platform', clear
					count 
					if r(N) == 0 {
						use `zero_draws', clear
					}
					fastcollapse draw_*, type(sum) by(age_group_id)
					cap mkdir "`draw_outdir'/E/`ecode'"
					cap mkdir "`draw_outdir'/E/`ecode'/`platform'"
					outsheet using "`draw_outdir'/E/`ecode'/`platform'/3_`location_id'_`year'_`sex'.csv", comma names replace
				}
			}
			// Collapse to N-code platform
			foreach ncode of local ncodes {
				use `st_data' if ncode == "`ncode'", clear
				count
				if r(N) == 0 {
					use `zero_draws', clear
					gen inpatient = 999
				}				
				tempfile n_st_data
				save `n_st_data', replace
				forvalues platform = 0/1 {
					use `n_st_data' if inpatient == `platform', clear
					count 
					if r(N) == 0 {
						use `zero_draws', clear
					}					
					fastcollapse draw_*, type(sum) by(age_group_id)
					cap mkdir "`draw_outdir'/N/`ncode'"
					cap mkdir "`draw_outdir'/N/`ncode'/`platform'"
					outsheet using "`draw_outdir'/N/`ncode'/`platform'/3_`location_id'_`year'_`sex'.csv", comma names replace
				}
			}
		}
	}	

// END
	