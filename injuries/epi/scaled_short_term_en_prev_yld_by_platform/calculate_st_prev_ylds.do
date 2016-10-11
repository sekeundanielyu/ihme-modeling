// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	This code applies durations data to short-term incidence data to get Ecode-Ncode-platform-level prevalence of short-term injury data, the applies disability weights to get ylds

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
		local 4 "05a"
		local 5 scaled_short_term_en_prev_yld_by_platform
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

// Filepaths
	local gbd_ado "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local stepfile "`code_dir'/`functional'_steps.xlsx"
	local dws = "`out_dir'/01_inputs/st_dws_by_ncode.csv"
	local pop_file = "`out_dir'/01_inputs/pops.dta"
// Import functions
	adopath + "`code_dir'/ado"
	adopath + `gbd_ado'

// load params
	load_params

	import excel using "`code_dir'/_inj_steps.xlsx", firstrow clear
// where are the durations saved
	preserve
	keep if name == "durations"
	local this_step=step in 1
	local durations_dir = "`root_tmp_dir'/03_steps/`date'/`this_step'_durations"
	restore
// where are the short term incidence results by EN combination saved
	keep if name == "scaled_short_term_en_inc_by_platform"
	local this_step=step in 1
	local short_term_inc_dir = "`root_tmp_dir'/03_steps/`date'/`this_step'_scaled_short_term_en_inc_by_platform"
		
	// Import and save durations
	import delimited using "`durations_dir'/03_outputs/01_draws/durations_`location_id'_`year'.csv", delim(",") clear asdouble
	rename draw* dur_draw*
	tempfile durations
	save `durations'
	
	// Import and save disability weight draws
	import delimited "`dws'", delim(",") asdouble clear
	rename n_code ncode
	rename draw* dw*
	tempfile dws
	save `dws', replace

	// Import populations
	// Bring in pops to redistribute incidence for age groups under 1
	insheet using "`code_dir'/convert_to_new_age_ids.csv", comma names clear
		tempfile age_ids 
		save `age_ids', replace
	use `pop_file', clear
		merge m:1 age_group_id using `age_ids', keep(3) assert(3) nogen
		rename age_start age 
		tostring age, replace force format(%12.3f)
		destring age, replace force
		gen collapsed_age = age
		replace collapsed_age = 0 if age < 1 
		tempfile fullpops
		save `fullpops', replace
		replace age = 0 if age < 1
		fastcollapse pop, type(sum) by(location_id year_id age sex_id)
		rename pop total_pop
		rename age collapsed_age
		tempfile pops
		save `pops', replace
	// Make pop fractions under 1
	use `fullpops', clear
		merge m:1 location_id year_id collapsed_age sex_id using `pops', keep(3) nogen
		gen pop_fraction = pop/total_pop
		keep location_id year_id age sex_id pop_fraction
		tostring age, replace force format(%12.3f)
		destring age, replace force
		tempfile pop_fractions
		save `pop_fractions', replace

local filemaker=1
	
foreach shocktype in shocks nonshocks  {
	** this local will get set to 1 if there is any shock data for this sex/year/country, and will always get set to 1 if this is nonshock data
	local this_yr = 0
	** verify that there is shock incidence for this (GBD DisMod) year
	if "`shocktype'"=="shocks" {
	
		capture confirm file "`short_term_inc_dir'/03_outputs/01_draws/`shocktype'/incidence_`location_id'_inp_`sex'.dta"
		if _rc {
			di "no shocks data at all for `location_id' `sex'"
		}
		else {
			use "`short_term_inc_dir'/03_outputs/01_draws/`shocktype'/incidence_`location_id'_inp_`sex'.dta", clear
			keep if year == `year'
			capture generate inpatient = 1
			tempfile inp
			save `inp', replace
			use "`short_term_inc_dir'/03_outputs/01_draws/`shocktype'/incidence_`location_id'_otp_`sex'.dta", clear
			keep if year == `year'			
			capture generate inpatient = 0
			append using `inp'
				gen location_id = `location_id'
				gen sex_id = `sex'
			count
			if `r(N)'>0 {
				local this_yr = 1
				rename year year_id
				tempfile shocks_tmp
				save `shocks_tmp'
			}
		}
	}

	if "`shocktype'"=="nonshocks" {		
		local this_yr = 1
	}
	
	if `this_yr'==1 {
	// get the short-term incidence data
		if "`shocktype'"=="nonshocks" {
			use "`short_term_inc_dir'/03_outputs/01_draws/`shocktype'/collapsed/incidence_`location_id'_`year'_`sex'.dta", clear
				gen location_id = `location_id'
				gen year_id = `year'
				gen sex_id = `sex'
				expand 2 if age == 0, gen(dup)
				replace age = 0.01 if dup == 1
				drop dup
				expand 2 if age == 0, gen(dup)
				replace age = 0.1 if dup == 1
				drop dup
				// Redistribute collapsed 0-1 incidence to more granular age groupings
				tostring age, replace force format(%12.3f)
				destring age, replace force
				drop if age > 80
				merge m:1 location_id year_id age sex_id using `pop_fractions', keep(3) nogen
				forvalues i = 0/999 {
				replace draw_`i' = draw_`i' * pop_fraction
				}
		}
		if "`shocktype'"=="shocks" {
			use `shocks_tmp', clear
		}
		rename draw_* inc_draw*

	// Calculate prev
		merge m:1 ncode inpatient using `durations', nogen keep(match)
	
		forvalues j=0/$drawmax {
			quietly replace inc_draw`j'=(dur_draw`j' * inc_draw`j')/( 1 + (dur_draw`j' * inc_draw`j'))
			drop dur_draw`j'
		}
		rename inc_draw* prev_draw*
		
		preserve
	// save the intermediate prevalence numbers
		rename prev_draw* draw_*
		order age, first
		sort age
		quietly format draw* %16.0g
		capture mkdir "`tmp_dir'/03_outputs/01_draws/prev/"
		if `filemaker'==1 {
			tempfile prevnums
			save `prevnums', replace
		}
		else {
			append using `prevnums'
			save `prevnums', replace
		}
		restore
		
	// Calculate YLDs	
		// Merge disability weights
		merge m:1 ncode using `dws', keep(3) nogen
		// Merge populations
		merge m:1 location_id year_id age sex_id using `fullpops', keep(3) nogen
		
		forvalues j=0/$drawmax {
			generate draw_`j'=dw`j' * (prev_draw`j' * pop_scaled)
			drop dw`j' prev_draw`j'
		}
		// save YLD draws
		quietly {
			format draw* %16.0g
		}
		order age, first
		sort age
		if `filemaker'==1 {
			tempfile yldnums
			save `yldnums', replace
		}
		else {
			append using `yldnums'
			save `yldnums', replace
		}
		local ++filemaker
	}
	** end check of existance of results for this year
}

** end nonshock/shock loop

use `prevnums', clear

** round up the age values
gen double true_age = round(age, 0.01)
drop age
rename true_age age
levelsof age
sort_by_ncode ncode, other_sort(inpatient age)
sort ecode

cap mkdir "`tmp_dir'/03_outputs/01_draws/prev"
cap mkdir "`tmp_dir'/03_outputs/01_draws/prev/`location_id'"
keep age draw* ecode ncode inpatient 
save "`tmp_dir'/03_outputs/01_draws/prev/`location_id'/prevalence_`year'_`sex'.dta", replace
// save summaries
fastrowmean draw*, mean_var_name("mean")
fastpctile draw*, pct(2.5 97.5) names(ll ul)
drop draw*
order age ecode ncode inpatient mean ll ul
qui format mean ul ll %16.0g
compress
capture mkdir "`tmp_dir'/03_outputs/02_summary/prev"
capture mkdir "`tmp_dir'/03_outputs/02_summary/prev/`location_id'"
save "`tmp_dir'/03_outputs/02_summary/prev/`location_id'/prevalence_`year'_`sex'.dta", replace

use `yldnums', clear
** round up the age values
gen double true_age = round(age, 0.01)
drop age
rename true_age age
sort_by_ncode ncode, other_sort(inpatient age)
sort ecode
capture mkdir "`tmp_dir'/03_outputs/01_draws/ylds"
capture mkdir "`tmp_dir'/03_outputs/01_draws/ylds/`location_id'"
keep age draw* ecode ncode inpatient
save "`tmp_dir'/03_outputs/01_draws/ylds/`location_id'/ylds_`year'_`sex'.dta", replace

// save YLD summary stats
fastrowmean draw*, mean_var_name("mean")
fastpctile draw*, pct(2.5 97.5) names(ll ul)
drop draw*
format mean ul ll %16.0g
order age ecode ncode inpatient mean ll ul
capture mkdir "`tmp_dir'/03_outputs/02_summary/ylds"
capture mkdir "`tmp_dir'/03_outputs/02_summary/ylds/`location_id'"
compress
save  "`tmp_dir'/03_outputs/02_summary/ylds/`location_id'/ylds_`year'_`sex'.dta", replace

