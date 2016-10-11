// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	Format and save draws of long-term probabilities

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
		local 4 "04a"
		local 5 prob_long_term
		local 6 "/share/code/injuries/ngraetz/inj/gbd2015"
		local 7 89
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
// WRITE CODE HERE

// Settings
	set seed 0
	local debug 99
	set type double, perm

// update adopath
	adopath + "`code_dir'/ado"
	adopath + "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	
// Filepaths
	local draw_dir "`tmp_dir'/03_outputs/01_draws"
	local summ_dir "`tmp_dir'/03_outputs/02_summary"
	
// Get list of reporting years and load injury parameters
	load_params
	get_demographics, gbd_team("epi")
	local reporting_years $year_ids	

// Get name of shock incidence folder
	** can't use get_step_num (too long of a global name
	import excel "`code_dir'/_inj_steps.xlsx", clear sheet("steps") firstrow
	keep if name == "impute_short_term_shock_inc"
	local this_step_num = step[1]
	local shock_output_dir "`root_tmp_dir'/03_steps/`date'/`this_step_num'_impute_short_term_shock_inc/03_outputs/01_draws"
	
// Get additional years for which we need prob_long_term (years w/ shock incidence)
	local shock_file : dir "`shock_output_dir'" files "incidence_`location_id'_inp_male.csv", respectcase
	if !missing("`shock_file'") {
		local shock_file = subinstr(`"`shock_file'"',`"""',"",.)
		import delimited "`shock_output_dir'/`shock_file'", clear
		levelsof year, l(shock_years) clean
		global years `shock_years'
		foreach year of local reporting_years {
			if !regexm("$year_ids","`year'") global years $year_ids `year'
		}
	}
		

// get percent treated
	get_pct_treated, prefix("$prefix") allyears code_dir("`code_dir'")
	keep if location_id	 == `location_id'
	tempfile pct_treated
	save `pct_treated'
	
	
// bring in draws, keep if in platform
	import delimited using "`tmp_dir'/03_outputs/03_other/compiled_ltp_by_ncode_platform.csv", delim(",") clear
	tempfile prob_draws
	save `prob_draws', replace

	
// get multiplier draws

	** import and format
	import excel using "`in_dir'/parameters/long_term_probabilities.xlsx", cellrange(A2:E49) firstrow clear
	drop Nname
	rename Ncode n_code
	** drop N-codes that have no long-term probability
	drop if mean == "n/a"
	replace LL = 1 if mean == "same"
	replace UL = 1 if mean == "same"
	replace mean = "1" if mean == "same"
	destring mean, replace force
	
	** generate draws
	calc_se LL UL, newvar(se)
	forvalues x = 0/$drawmax {
		gen mult_draw_`x' = rnormal(mean,se)
		** if assumed same as treated, will have mean 1 and se 0 --> stata gives all draws = 0 in this situation which is incorrect
		replace mult_draw_`x' = mean if se == 0
		
	}
	drop mean se LL UL
	
// Multiply out to get country-year-specific long-term probs
	// merge 1:m n_code using `prob_draws'' , assert(match) nogen
	merge 1:m n_code using `prob_draws' // FOR NOW - need to not assert match because we have no N35 probability if we drop the NLD data
	keep if _merge == 3
	drop _merge
	gen location_id = `location_id'
	tempfile probs_and_mult
	save `probs_and_mult'
	
	foreach year of global year_ids {
		use `probs_and_mult', clear
		tempfile `year'
		gen year_id = `year'
		merge m:1 year_id using `pct_treated', keep(match) nogen
	
		forvalues x = 0/$drawmax {
		// Edit 8/21/14 ng - We are setting many N-codes to 100% if untreated, regardless of platform.  Try setting all "outpatient" to same probability treated vs. untreated rather than 100%.
			replace mult_draw_`x' = 1 if mult_draw_`x' == . & inpatient == 0
		// Get untreated probabilities
			gen untreated_`x' = draw_`x' * mult_draw_`x'
			** account for "100% long term for untreated" cases
			replace untreated_`x' = 1 if mult_draw_`x' == .
			
		// Multiply
			replace draw_`x' = draw_`x' * pct_treated + untreated_`x' * (1 - pct_treated)
			
		// Cap
			replace draw_`x' = 1 if draw_`x' > 1
		
		// Drop unneeded vars
			drop untreated_`x' mult_draw_`x'
		}
		
		
	// Save
		rename n_code ncode
		rename age_gr age
		keep ncode age inpatient draw*
		order ncode inpatient, first
		sort_by_ncode ncode, other_sort(inpatient)
		format draw* %16.0g
		export delimited using "`draw_dir'/prob_long_term_`location_id'_`year'.csv", delimiter(",") replace
		
		
	// collapse and make summary measures- mean, 97.5, 2.5
		fastrowmean draw*, mean_var_name(mean)
		fastpctile draw*, pct(2.5 97.5) names(ll ul)
		drop draw*
		format mean ul ll %16.0g
		export delimited "`summ_dir'/prob_long_term_`location_id'_`year'.csv", delim(",") replace
		
	}

