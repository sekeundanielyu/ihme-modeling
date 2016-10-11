// Date: March 3, 2013
// Purpose: Get Iran Surveillance of Risk Factors of Non-Communicable Diseases data sent by experts into the right format for compilation with other datasets and upload into Dismod

// Set up
	clear all
	set more off
	set mem 2g
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j "J:"
		version 11
	}
	
// Make locals for relevant files and folders
	local data_dir "$j/WORK/05_risk/risks/activity/data/exp"
	
// Bring in dataset
	import excel using "`data_dir'/raw/IRN_surfncd.xlsx", firstrow clear

// Parse mean +/- and make variables for 95% ci
	foreach var in inactive lowactive modactive highactive {
		split `var', gen(`var') parse("±")
		destring `var'1 `var'2, replace
		replace `var'1 = `var'1 / 100
		replace `var'2 = `var'2 / 100
		rename `var'1 mean_`var'
		gen upper_`var' = mean_`var' + `var'2
		gen lower_`var' = mean_`var' - `var'2
	}

// Construct age variables
	split agegrp, parse("-") gen(age)
	rename age1 age_start
	rename age2 age_end
	destring age_start age_end, replace
	
// Reshape long
	reshape long mean@ upper@ lower@, i(source_name iso3 year year sex age_start age_end) j(healthstate, string)
	replace healthstate = "activity_inactive" if healthstate == "_inactive"
	replace healthstate = "activity_low" if healthstate == "_lowactive"
	replace healthstate = "activity_mod" if healthstate == "_modactive"
	replace healthstate = "activity_high" if healthstate == "_highactive"
	
// Calculate variance so that error can be propagated 
	gen variance = (((upper - lower)/2)/1.96) ^2
	
// There are 6 Dismod models for physical activity, each with a different MET-min/week threshold so we will sum means across relevant categories
	local varlist iso3 year sex age_start age_end questionnaire source_name
	// Model A: Percent inactive (<600 MET-min/week)
		preserve
		keep if healthstate == "activity_inactive"
		tempfile inactive
		save `inactive'
		restore
	
	//  Model B: Percent low, moderate or highly active (>=600 MET-min/week)
		preserve
		keep if healthstate != "activity_inactive"
		collapse (sum) mean variance, by(`varlist')
		gen healthstate = "activity_lowmodhigh"
		tempfile lowmodhighactive
		save `lowmodhighactive'
		restore
	
	// Model C: Percent with low activity (600-4000 MET-min/week)
		preserve
		keep if healthstate == "activity_low"
		collapse (sum) mean variance, by(`varlist')
		gen healthstate = "activity_low"
		tempfile lowactive
		save `lowactive'
		restore
		
	// Model D: Percent moderate or highly active (>=4000 MET-min/week)
		preserve
		keep if inlist(healthstate, "activity_mod", "activity_high")
		collapse (sum) mean variance, by(`varlist')
		gen healthstate = "activity_modhigh"
		tempfile modhighactive
		save `modhighactive'
		restore
		
	// Model E: Percent moderately active (4000-7999 MET-min/week)
		preserve
		keep if healthstate == "activity_mod"
		collapse (sum) mean variance, by(`varlist')
		gen healthstate = "activity_mod"
		tempfile modactive
		save `modactive'
		restore
	
	// Model F: Percent highly active (>=8000 MET-min/week)
		preserve
		keep if healthstate == "activity_high"
		collapse (sum) mean variance, by(`varlist')
		gen healthstate = "activity_high"
		tempfile highactive
		save `highactive'
		restore

// Append data for all four models together to make master dataset	
	use `inactive', clear
	foreach dataset in lowmodhighactive lowactive modactive modhighactive highactive {
		append using ``dataset''
	}
	
// Calculate standard error of aggregated year/age/sex proportions 
	gen standard_error = sqrt(variance)

// Only keep necessary variables
	keep source_name iso3 year sex age_start age_end healthstate questionnaire mean standard_error
	
// Fill in standard epi variables
	rename year year_start
	gen year_end = year_start
	gen national_type = 1 // nationally representative
	gen urbanicity_type = 1 // representative
	gen data_type = "Surveillance: disease"
	gen source_type = "Survey"
	gen orig_uncertainty_type = "SE"
	
// Save
	save "`data_dir'/prepped/irn_surfncd_formatted.dta", replace
