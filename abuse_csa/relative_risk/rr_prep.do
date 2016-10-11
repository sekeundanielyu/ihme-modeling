** *******************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 		July 29, 2016
// Project:		RISK
// Purpose:		Run custom meta-analysis for two twin studies for CSA and outcomes 
** **************************************************************************
** RUNTIME CONFIGURATION
** **************************************************************************
// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		set mem 12g
		set maxvar 32000
	// Set to run all selected code without pausing
		set more off
	// Set graph output color scheme
		set scheme s1color
	// Remove previous restores
		cap restore, not
	// Reset timer (?)
		timer clear	
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}
	// Close previous logs
		cap log close


// Run central functions ado file 
	run "$prefix/WORK/10_gbd/00_library/functions/get_ids.ado" 
	
	// Cause id 
	get_ids, table(cause) clear

	// Depressive disorders = cause_id 567 
	// Alcohol use disorders = cause_id 560 
	// Self-harm = cause_id = 718 

	get_ids, table(modelable_entity) clear 

	// CSA against females RR = 9086 
	// CSA against males RR = 9087

// Set seed for random draws
	set seed 55616167

// Set macros for relevant file locations
	local data_dir "$prefix/WORK/05_risk/risks/abuse_csa/data/rr"

// Bring in spreadsheet with twin study 
	import excel using "`data_dir'/twin_study_rrs.xlsx", firstrow clear

// Generate draws from normal distribution
	gen sd = ((ln(upper)) - (ln(lower))) / (2*invnormal(.975))
   forvalues draw = 0/999 {
       gen rr_`draw' = exp(rnormal(ln(mean), sd))
   }

   drop mean lower upper 


// Generate necessary columns for save results 
	
	// Expand for both sexes 
	expand 2, gen(dup)
	sort acause
	bysort acause: gen number = _n

	gen sex_id = 1 if number == 1 
	replace sex_id = 2 if number == 2 

	drop dup number 

	// Duplicate for all years
	expand 6, gen(dup)
	sort acause

	bysort acause sex_id: gen number = _n
	gen year_id = 1990 if number == 1 
	replace year_id = 1995 if number == 2 
	replace year_id = 2000 if number == 3 
	replace year_id = 2005 if number == 4 
	replace year_id = 2010 if number == 5
	replace year_id = 2015 if number == 6

	drop dup number 

	order acause year_id sex_id
	sort acause year_id sex_id

	// Expand for all ages 

	gen age_group_id = . 

	forvalues i=2/21 { 
		replace age_group_id = `i' 

		tempfile temp_`i'
		save `temp_`i'', replace 

	}

	use `temp_2', clear 

	forvalues i=3/21 { 
		append using `temp_`i''

	}

// Expand for both categories (cat1 and cat2) 
	expand 2, gen(dup) 

	bysort acause sex_id age_group_id year_id: gen number = _n 
	gen parameter = "cat2" if number == 2 
	replace parameter = "cat1" if number == 1 

	forvalues i=0/999 { 
		replace rr_`i' = 1 if parameter == "cat2"
	}

	sort acause sex_id age_group_id year_id parameter
	order acause sex_id age_group_id year_id parameter


// Location_id 
	replace location_id = 1 // global RR 

// Mortality and morbidity 
	gen mortality = 1 
	gen morbidity = 1 

// Cause_id
	gen cause_id = 567 if acause == "mental_unipolar" 
	replace cause_id = 560 if acause == "mental_alcohol" 
	replace cause_id = 718 if acause == "inj_suicide"

// Keep only necessary variables and drop all else 
	keep acause risk age_group_id year_id cause_id location_id sex_id mortality morbidity parameter rr_*


	// Female CSA
	preserve 
	keep if sex_id == 2 
	gen re_id = 244 
	gen me_id = 9086

// Export excel 
	
	tempfile female_all
	save `female_all', replace 

	forvalues i=1990(5)2015 { 
		use `female_all', clear
		keep if year_id == `i' 

		outsheet using "`data_dir'/gbd_2015/female_rrs/rr_1_`i'_2.csv", comma names replace 

	}


	restore

	// Male CSA
	keep if sex_id == 1 
	gen rei_id = 245
	gen me_id = 9087

	tempfile male_all
	save `male_all', replace 

		forvalues i=1990(5)2015 { 
		use `male_all', clear
		keep if year_id == `i' 

		outsheet using "`data_dir'/gbd_2015/male_rrs/rr_1_`i'_1.csv", comma names replace 

	}

	

