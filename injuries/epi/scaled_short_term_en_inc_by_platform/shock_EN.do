// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	This code applies the EN matrices to the Ecode-platform incidence data FOR SHOCK E-CODES THAT ARE NOT THE USUAL GBD YEARS to get Ecode-Ncode-platform-level incidence data

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
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
		local 4 "04b"
		local 5 scaled_short_term_en_inc_by_platform
		local 6 "/share/code/injuries/ngraetz/inj/gbd2015"
		local 7 101
		local 8 2010
		local 9 1
		local 10 inp
	}
	forvalues i = 1/10 {
		di "``i''"
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
	// platform
	local platform `10'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for standard code files
	adopath + "$prefix/WORK/04_epi/01_database/01_code/04_models/prod"
	
	// write log if running in parallel and log is not already open
	//log using "`out_dir'/02_temp/02_logs/`step_num'_`location_id'_`sex'_`platform'_shocks.smcl", replace name(worker)
	
	// start the timer for this substep
	adopath + "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	** start_timer
	local diag_dir "`tmp_dir'/02_temp/04_diagnostics"

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// SETTINGS
	
// Filepaths
	local gbd_ado "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	
// Import functions
	adopath + "`code_dir'/ado"
	adopath + `gbd_ado'
	// start_timer, dir("`diag_dir'") name("shock_`location_id'_`platform'_`sex'") slots(`slots')
	
	if "`platform'"=="otp" {
		local platform_num 0
	}
		
	if "`platform'"=="inp" {
		local platform_num 1
	}
** set locals for the location of the non-shock incidence results, the shock incidence results and the EN matrices based on the "steps" files
import excel using "`code_dir'/_inj_steps.xlsx", firstrow clear
** shock incidence
preserve
keep if name == "impute_short_term_shock_inc"
local this_step=step in 1
local shock_inc_dir = "`root_tmp_dir'/03_steps/`date'/`this_step'_impute_short_term_shock_inc"
restore
** EN Matrices results
preserve
keep if name == "EN_matrices"
local this_step=step in 1
local this_step=step in 1
local EN_mat_dir = "`root_tmp_dir'/03_steps/`date'/`this_step'_EN_matrices"
restore

** pull the list of iso3 codes that the results are saved at- written as an ado function and get the income level of the location - do this outside of the parallelized code now and saves to inputs file
use if location_id==`location_id' using "`out_dir'/01_inputs/income_map.dta", clear
local income_level=high_income in 1

** need to change this if in the future you have multiple age categories for EN matrices. In GBD 2013 all under 1 ncodes were aggergated to age=0
global collapsed_under1=1

local counter 0
** get the years with shock data for this iso3/ type
foreach shock in inj_war inj_disaster {
	
	** grab the EN matrix for this cause and store the n-codes in memory
	import delimited "`EN_mat_dir'/03_outputs/01_draws/`platform'//`shock'.csv", delim(",") varnames(1) asdouble clear
	keep if high_income==`income_level'
	keep if sex == `sex'
	rename draw* n_draw*
	preserve
	keep n_code
	duplicates drop
	levelsof n_code, local(`shock'_ns) clean			
	clear mata
	putmata n_code
	count
	local n_count=`r(N)'
	restore
	
	tempfile en_matrix
	save `en_matrix', replace
		
	import delimited "`shock_inc_dir'/03_outputs/01_draws/incidence_`location_id'_`platform'_`sex'.csv", delim(",") varnames(1) asdouble clear
	levelsof ecode
	count if ecode=="`shock'"
	if `r(N)'==0 {
		di "there are no `shock' incidence for `location_id' `platform' `sex'"
	}
	** if there is are results for this e-code, then we want to apply the EN matrix
	else {
		keep if ecode=="`shock'"
		rename draw* inc_draw*
		capture generate inpatient = 1
		replace inpatient=0 if "`platform'"=="otp"
		
		** expand to the number of n_codes that have EN data for this E-code, generate a new variable for "N code" which will make age-n_code combination a unique identifier
		expand `n_count'
		bysort age year: gen n=_n
		gen n_code=""
		forvalues i=1/`n_count' {
			mata: st_local("n_code",n_code[`i'])
			replace n_code="`n_code'" if n==`i'
		}
		
		// Recode age_group_ids to actual ages, as this is how the EN matrices are formatted based on that data. I've decided to leave all intermediate injuries results with actual ages instead of GBD age_group_ids. I'll recode whenever I need to upload results - 11/4/2015
		preserve
			insheet using "`code_dir'/convert_to_new_age_ids.csv", comma names clear
			tempfile age_codes
			save `age_codes', replace
		restore
		merge m:1 age_group_id using `age_codes', keep(3) nogen
		drop age_group_id
		rename age_start age
	
		** depending on what ages we have e-n data for, we create a new age variable for merging on the EN matrix
		rename age true_age
		gen age = true_age
		replace age = 80 if true_age >= 80
		if $collapsed_under1 {
			replace age = round(age, 1)
		}
		
		** merge on the E-N matrix and generate the proportions of this e-code that get allocated to each n-code
		merge m:1 age n_code using `en_matrix', keep(3) nogen
			
		** generate proportion of each incidence number alloted to each n-code
			forvalues j=0(1)999 {
				quietly gen draw_`j'=n_draw`j'*inc_draw_`j'
				drop n_draw`j' inc_draw_`j'
			}
		drop age
		rename true_age age 
		keep age n_code ecode year inpatient draw_*
		fastrowmean draw_*, mean_var_name(mean_)
		fastpctile draw_*, pct(2.5 97.5) names(ll ul)
		format mean ul ll draw_* %16.0g			
		local ++counter
		
		if `counter'==1 {
			tempfile all_appended
			save `all_appended', replace
		}
		if `counter'>1 {
			append using `all_appended'
			save `all_appended', replace
		}
	}
	** end loop confirming there are results for this e-code
}
** end shock code loop

	use `all_appended', clear
	levelsof age
	
	** keep only the EN combinations that have nonzero draws
	if "`platform'"=="otp" {
		foreach n of global inp_only_ncodes {
			drop if n_code=="`n'"
		}
	}
	egen double dropthisn=rowtotal(draw_*)
	drop if dropthisn==0			
	bysort ecode n_code inpatient : egen ensum = sum(dropthisn)
	drop if ensum==0
	
	capture mkdir "`tmp_dir'/03_outputs/01_draws/shocks"
	rename n_code ncode
	sort_by_ncode ncode, other_sort(inpatient year age)
	sort ecode
	preserve
	keep ecode ncode inpatient year age draw_*
	save "`tmp_dir'/03_outputs/01_draws/shocks/incidence_`location_id'_`platform'_`sex'.dta", replace	
	restore
	
	** get rid of the trailing _ on ul and ll (this should be cleaned up earlier but don't want to mess things up - IB 5/7/14)
	rename *_ *
	capture mkdir "`tmp_dir'/03_outputs/02_summary/shocks"
	keep ecode ncode inpatient year age mean ll ul
	save "`tmp_dir'/03_outputs/02_summary/shocks/incidence_`location_id'_`platform'_`sex'.dta", replace

