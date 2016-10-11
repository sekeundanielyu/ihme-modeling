// Date: November 2, 2015
// Purpose: Compile and prep 2013 China subnational secondhand smoke data from the China Chronic Disease Risk Factor Surveillance


// Set up STATA
	clear all
	set more off
	set mem 2g
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

// Set locals for relevant files 

	cd "$prefix/WORK/05_risk/risks/activity/data/exp/raw"
	local data_dir "$prefix/LIMITED_USE/PROJECT_FOLDERS/CHN/GBD_COLLABORATORS/CHRONIC_DISEASE_RISK_FACTOR_SURVEILLANCE/2013"


// Bring in 2015 locations 
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	get_demographics, gbd_team(epi) make_template clear 
	keep location_name location_id
	collapse (first) location_id, by(location_name)

	tempfile country_codes
	save `country_codes', replace 

// NATIONAL 
	// Case definition #1: Under normal circumstances, it is your fate to be the recipient of second hand smoke: 1. __ days per week? 2. Basically never
	import excel using "`data_dir'/CHN_CHRONIC_DISEASE_RISK_FACTOR_SURVEILLANCE_2013_NATIONAL_Y2015M09D30.XLSX", sheet(inactivity) firstrow clear
	gen file = "`data_dir'/CHN_CHRONIC_DISEASE_RISK_FACTOR_SURVEILLANCE_2013_NATIONAL_Y2015M09D30.XLSX" 
	gen national_type = 4 // Nationally & subnationally representative 
	rename inactivity_prevalence_rate proportion
	tempfile nat 
	save `nat', replace

// SUBNATIONAL 
	import excel using "`data_dir'/CHN_CHRONIC_DISEASE_RISK_FACTOR_SURVEILLANCE_2013_Y2015M09D28.XLSX", sheet(inactivity) firstrow clear
	gen file = "`data_dir'/CHN_CHRONIC_DISEASE_RISK_FACTOR_SURVEILLANCE_2013_Y2015M09D28.XLSX"
	gen national_type = 2 // Subnationally representative 
	rename inactivity_prevalence_rate proportion

	append using `nat'

// Format locations for matching 
	rename province_name location_name 
	replace location_name = "China" if location_name == "" 
	drop if location_name == "Jining" // prefecture-level city in the Shandong province, but we already have Shandong estimates

	tempfile all 
	save `all', replace

	merge m:1 location_name using `country_codes' 
	keep if _m == 3 
	drop _m

// Create other necessary variables
	
	// Put proportion in correct units 
	replace proportion = proportion / 100 
	drop if proportion == . 

	tostring location_id, gen(new_loc_id)
	gen iso3 = "CHN_" + new_loc_id
	drop location_id 
	rename new_loc_id location_id
	rename location_name site_new
	gen nid = 225627 
	gen source_name = "China Chronic Disease Risk Factor Surveillance" 
	rename age_category age_start
	gen year_start = 2013
	gen year_end = year_start
	gen data_type = "Survey" 
	gen domain = "all"
	gen category = "inactive" 
	gen category_definition = "<150" 
	gen units = "min/week of moderate activity per week or its metabolic equivalent"
	gen questionnaire = "GPAQ" 
	gen met_threshold = "<600"

	gen sex_new = "1" if sex == "male" 
	replace sex_new = "2" if sex == "female" 
	destring sex_new, replace
	drop sex
	rename sex_new sex 
	
	gen orig_uncertainty_type = "ESS"


// Save 
	save "./china_subnational_tabulated.dta", replace


