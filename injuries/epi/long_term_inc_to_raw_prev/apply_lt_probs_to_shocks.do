// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	parallel code for applying long term probabilities to short-term incidence to get long-term incidence

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
		local 1 J:/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "05b"
		local 5 long_term_inc_to_raw_prev
		local 6 "H:/repos/inj/gbd2015"
		local 7 44
		local 8 1
		local 9 otp
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
	// sex
	local sex `8'
	// platform
	local platform `9'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for standard code files
	adopath + "$prefix/WORK/04_epi/01_database/01_code/04_models/prod"
	
// SETTINGS
	
// Filepaths
	local gbd_ado "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	
// Import functions
	adopath + "`code_dir'/ado"
	adopath + `gbd_ado'
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
	
	** get the step number of the step with short term incidence numbers
	import excel using "`code_dir'/_inj_steps.xlsx", sheet("steps") firstrow clear
	preserve
	keep if name == "scaled_short_term_en_inc_by_platform"
	local last_step = step in 1
	local st_inc_dir "`root_tmp_dir'/03_steps/`date'/`last_step'_scaled_short_term_en_inc_by_platform"
	restore
	keep if name == "prob_long_term"
	local prev_step = step in 1
	local prob_dir "`root_tmp_dir'/03_steps/`date'/`prev_step'_prob_long_term"
	** loop over platforms
		
** get levelsof inpatient/ncodes/ecodes to calculate
	** bring in the durations for this platform/ncode combination
	import delimited "`prob_dir'/03_outputs/03_other/compiled_ltp_by_ncode_platform.csv", delim(",") varnames(1) asdouble clear
	rename draw_* prob_draw_*
	rename age_gr age
	preserve
	drop if n_code == "N1" | n_code == "N2" | n_code == "N3" | n_code == "N4" | n_code == "N5" | n_code == "N6" | n_code == "N7" 
	tempfile prob_draws
	save `prob_draws', replace
	restore
	// Copy probabilities for ages <1, ages > 80
	preserve
	keep if age == 0 | age == 80
	gen merge_age = 1 if age == 0
	replace merge_age = 2 if age == 80
	tempfile special_ages
	save `special_ages', replace
	restore
	// We are now handling probabilities at the n-code/age level, so we need to merge 100% long-term n-codes separately because they have no age (all amputations)
	keep if n_code == "N1" | n_code == "N2" | n_code == "N3" | n_code == "N4" | n_code == "N5" | n_code == "N6" | n_code == "N7" 
	keep if age == .
	forvalues i = 0/999 {
	replace prob_draw_`i' = 1 if prob_draw_`i' == . | prob_draw_`i' == 0
	}
	tempfile all_lt
	save `all_lt', replace
	
	confirm file "`st_inc_dir'/03_outputs/01_draws/shocks/incidence_`location_id'_`platform'_`sex'.dta"
	use "`st_inc_dir'/03_outputs/01_draws/shocks/incidence_`location_id'_`platform'_`sex'.dta", clear
	// process draws
	rename draw* st_draw*
	rename ncode n_code
	preserve
	merge m:1 n_code inpatient using `all_lt', keep(3) nogen
	tempfile all_lt_draws
	save `all_lt_draws', replace
	restore
	preserve
	gen merge_age = 1 if (age < 1 & age != 0)
	replace merge_age = 2 if age > 80
	merge m:1 n_code inpatient merge_age using `special_ages', keep(3) nogen
	drop if n_code == "N1" | n_code == "N2" | n_code == "N3" | n_code == "N4" | n_code == "N5" | n_code == "N6" | n_code == "N7" 
	tempfile all_special_ages
	save `all_special_ages', replace
	restore
		// Merge everything else
	merge m:1 n_code age inpatient using `prob_draws', keep(3) nogen
	append using `all_lt_draws' `all_special_ages'

	forvalues i=0/999 {
		generate draw_`i' = prob_draw_`i' * st_draw_`i'
		drop prob_draw_`i' st_draw_`i'
	}
	** drop out E/N/inp combinations that have zero long-term incidence
	egen double dropthisn=rowtotal(draw*)
	drop if dropthisn==0
	levelsof ecode, local(ecodes)
	
	tempfile all
	save `all', replace
	

	if "`platform'"=="inp" {
		local platnum=1
	}	
	if "`platform'"=="otp" {
		local platnum=0
	}	

quiet run "$prefix/WORK/10_gbd/00_library/functions/create_connection_string.ado"
create_connection_string, strConnection
local conn_string = r(conn_string)

odbc load, exec("SELECT ihme_loc_id, location_name, location_id, location_type, super_region_name, most_detailed FROM shared.location_hierarchy_history WHERE location_set_version_id = (SELECT location_set_version_id FROM shared.location_set_version WHERE location_set_id = 9 and end_date IS NULL)") `conn_string' clear
keep if location_id == `location_id'
local iso3 = [ihme_loc_id]
if `sex' == 1 {
local sex_string male
}
if `sex' == 2 {
local sex_string female
}
	
	** save the draws in a format for Ian's ODE solver 
	foreach e of local ecodes {
	
		use if ecode=="`e'" & inpatient == `platnum' using `all', clear		
		levelsof n_code, local(ncodes)
		levelsof year, local(years)
		
		foreach n of local ncodes {
			
			foreach year of local years {
				use if ecode == "`e'" & inpatient==`platnum' & n_code=="`n'" & year==`year' using `all', clear
				keep age draw*
				format draw* %16.0g
				cap mkdir "`tmp_dir'/02_temp/03_data/lt_inc/"
				cap mkdir "`tmp_dir'/02_temp/03_data/lt_inc/shocks"
				cap mkdir "`tmp_dir'/02_temp/03_data/lt_inc/shocks/`platform'"
				cap mkdir "`tmp_dir'/02_temp/03_data/lt_inc/shocks/`platform'//`n'"
				cap mkdir "`tmp_dir'/02_temp/03_data/lt_inc/shocks/`platform'//`n'//`e'"
			
			outsheet using "`tmp_dir'/02_temp/03_data/lt_inc/shocks/`platform'//`n'//`e'//incidence_`iso3'_`year'_`sex_string'.csv", comma names replace
				
			}
		}
	}

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

