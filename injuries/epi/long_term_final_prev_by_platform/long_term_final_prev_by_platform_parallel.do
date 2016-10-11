// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	calculate proportion of long-term prevalence that is truly short-term due to overlap, and subtract from raw long-term prevalence

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
		local 4 "06b"
		local 5 long_term_final_prev_by_platform
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
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// SETTINGS
	set type double, perm
	** how many slots is this script being run on?
	local slots 1
	** debugging?
	local debug 1

// Filepaths
	local gbd_ado "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local rundir "`root_tmp_dir'/03_steps/`date'"
	local draw_dir "`tmp_dir'/03_outputs/01_draws"
	local summ_dir "`tmp_dir'/03_outputs/02_summary"
	
	cap mkdir "`tmp_dir'/03_outputs"
	cap mkdir "`draw_dir'"
	cap mkdir "`summ_dir'"
	
// Import functions
	adopath + "`code_dir'/ado"
	adopath + `gbd_ado'
	
// Load injury parameters
	load_params

// get file paths for the results for short_term_en_prev_yld_by_platform, prob_long_term long_term_inc_prev
	** not using get_step_num b/c name of global too long
	import excel "`code_dir'/_inj_steps.xlsx", firstrow clear
	preserve
	keep if name == "prob_long_term"
	local this_step=step in 1
	local long_term_prob_dir = "`rundir'/`this_step'_prob_long_term/03_outputs/01_draws"
	restore, preserve
	keep if name == "scaled_short_term_en_prev_yld_by_platform"
	local this_step=step in 1
	local short_term_prev_dir = "`rundir'/`this_step'_scaled_short_term_en_prev_yld_by_platform/03_outputs/01_draws/prev"
	restore
	keep if name == "long_term_inc_to_raw_prev"
	local this_step=step in 1
	local long_term_prev_dir = "`rundir'/`this_step'_long_term_inc_to_raw_prev/03_outputs/01_draws"


// calculate proportion of long-term prevalence that is actually short term (short term prevalence * probability of long-term outcome)

	** load short term prev
use "`short_term_prev_dir'/`location_id'/prevalence_`year'_`sex'.dta", clear 
tostring age, replace force format(%12.3f)
destring age, replace force
tempfile st_prev
save `st_prev'
	
	** load long-term prob
import delimited "`long_term_prob_dir'/prob_long_term_`location_id'_`year'.csv", asdouble clear
tostring age, replace force format(%12.3f)
destring age, replace force
rename draw* prob_draw*
	
	** merge and multiply (drop any 100% or 0% Long-term n-codes b/c we wont need to subtract these from total long-term prev)
merge 1:m age ncode inpatient using `st_prev', keep(match) nogen
forvalues x = 0/$drawmax {
replace draw_`x' = draw_`x' * prob_draw_`x'
drop prob_draw_`x'
}
rename draw* fake_long_draw*
tempfile fake_long_term
save `fake_long_term'
	
	
// Subtract duplicated short-term prev from long-term prev
	** import raw long-term prevalence
insheet using "`long_term_prev_dir'/`location_id'/`year'/`sex'/prevalence_`location_id'_`year'_`sex'.csv", comma names clear
tostring age, replace force format(%12.3f)
destring age, replace force
capture rename e_code ecode
capture rename n_code ncode
	
	** merge with double-counted prevalence and subtract
merge 1:1 age ecode ncode inpatient using `fake_long_term', keep(match master) nogen
forvalues x = 0/$drawmax {
replace draw_`x' = draw_`x' - fake_long_draw_`x' if fake_long_draw_`x' != .
drop fake_long_draw_`x'
}
	
	
// Save results
order ecode ncode inpatient age, first
sort ecode ncode inpatient age

forvalues i = 0/999 {
replace draw_`i' = . if draw_`i' < 0 | draw_`i' > 2
}
fastrowmean draw*, mean_var_name("mean")
forvalues i = 0/999 {
replace draw_`i' = mean if draw_`i' == .
}
drop mean
	
// TEMP EDIT - delete outpatient poisoning and contusion
forvalues i = 0/999 {
replace draw_`i' = 0 if ncode == "N41" & inpatient == 0
}
forvalues i = 0/999 {
replace draw_`i' = 0 if ncode == "N44" & inpatient == 0
}

// TEMP EDIT - ng 6/8/16 - remove a lot of otp and inp N-codes from lt animal contact 
preserve 
	insheet using "$prefix/WORK/04_epi/01_database/02_data/_inj/05_diagnostics/gbd2015/india_animal/combos_to_remove.csv", comma names clear
	gen remove = 1
	tempfile animal_remove
	save `animal_remove', replace
restore
merge m:1 ncode ecode inpatient using `animal_remove', keep(1 3) assert(1 3) nogen
forvalues i = 0/999 {
	replace draw_`i' = 0 if remove == 1
}
drop remove

// EDIT ng 6/20/16 - Theo has decided we shouldn't allow long-term prevalence of outpatient injuries from N48, N26, N11, N19, N43, N25, N23
forvalues i = 0/999 {
replace draw_`i' = 0 if (ncode == "N48" | ncode == "N26" | ncode == "N11" | ncode == "N19" | ncode == "N43" | ncode == "N25" | ncode == "N23") & inpatient == 0
}

	** draws
format draw* %16.0g
cap mkdir "`draw_dir'/`location_id'"
save "`draw_dir'/`location_id'/prevalence_`location_id'_`year'_`sex'.dta", replace
		
	** summary stats
fastrowmean draw*, mean_var_name("mean")
fastpctile draw*, pct(2.5 97.5) names(ll ul)
drop draw*
cap mkdir "`summ_dir'/`location_id'"
save "`summ_dir'/`location_id'/prevalence_`location_id'_`year'_`sex'.dta", replace


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

		