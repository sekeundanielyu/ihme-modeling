// Purpose: Compile and prep China subnational secondhand smoke data from the China Chronic Disease Risk Factor Surveillance

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
	cd "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped"
	local data "$prefix/LIMITED_USE/PROJECT_FOLDERS/CHN/GBD_COLLABORATORS/CHRONIC_DISEASE_RISK_FACTOR_SURVEILLANCE/2_CHN_CHRONIC_DISEASE_RISK_FACTOR_SURVEILLANCE_2004_2007_2010_RISK_FACTORS_EXT_Y2016M03D24.XLSX"
	local data_2015_nat "$prefix/LIMITED_USE/PROJECT_FOLDERS/CHN/GBD_COLLABORATORS/CHRONIC_DISEASE_RISK_FACTOR_SURVEILLANCE/2013/CHN_CHRONIC_DISEASE_RISK_FACTOR_SURVEILLANCE_2013_NATIONAL_Y2015M09D30.XLSX"
	local data_2015_sub "$prefix/LIMITED_USE/PROJECT_FOLDERS/CHN/GBD_COLLABORATORS/CHRONIC_DISEASE_RISK_FACTOR_SURVEILLANCE/2013/CHN_CHRONIC_DISEASE_RISK_FACTOR_SURVEILLANCE_2013_Y2015M09D28.XLSX" 

// Bring in 2015 locations 
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	get_demographics, gbd_team(epi) make_template clear 
	keep location_name location_id
	collapse (first) location_id, by(location_name)

	tempfile country_codes
	save `country_codes', replace 

// Case definition #1: Under normal circumstances, it is your fate to be the recipient of second hand smoke: 1. __ days per week? 2. Basically never
	import excel using "`data'", sheet(second_hand_smoking) firstrow clear
	gen case_definition = "any exposure to second-hand smoke at any location, both indoors and outdoors"
	rename second_hand_smoking_prev mean
	tempfile shs1
	save `shs1'

// Case definition #2: 	If you are the recipient, how many days per week does the cumulative time around 2nd hand smoke per day exceed 15 minutes?  1. __ days per week  2. It doesn’t
	import excel using "`data'", sheet(second_hand_smoking_15m) firstrow clear
	gen case_definition = "at least 15 minutes of exposure to second-hand smoke on any day in a typical week (includes exposure at any location, both indoors and outdoors)"
	rename second_hand_smoking_15m_prev mean
	
	append using `shs1'

// ADD IN NEW 2015 DATA FROM CHINESE COLLABORATORS
	
	// National data 
	import excel using "`data_2015_nat'", sheet(scd_smoking) firstrow clear
	gen case_definition = "exposure to second hand smoke in a typical week" 
	gen year = 2013
	gen file = "`data_2015_nat'" 
	rename scd_smoking_prevalence_rate mean 
	gen sex_new = "1" if sex == "male" 
	replace sex_new = "2" if sex == "female"
	destring sex_new, replace 
	drop sex 
	rename sex_new sex 
	gen national_type = 1 

	tempfile 2015
	save `2015' 

	// Subnational data 
	import excel using "`data_2015_sub'", sheet(secondhand_smoking) firstrow clear 
	gen case_definition = "exposure to second hand smoke in a typical week" 
	gen year = 2013
	gen file = "`data_2015_sub'"
	rename scd_smoking_prevalence_rate mean 
	gen sex_new = "1" if sex == "male" 
	replace sex_new = "2" if sex == "female"
	destring sex_new, replace 
	drop sex 
	rename sex_new sex 
	gen national_type = 4 // nationally and subnationally representative

	append using `2015' `shs1' 


// Rename and re-format variables to fit epi template
	replace age_category = "80-100" if age_category == "80+"
	split age_category, parse("-") destring gen(age)
	rename age1 age_start
	rename age2 age_end
	drop age_category
	rename iso iso3
	rename year year_start
	gen year_end = year_start
	replace mean = mean/100
	drop if mean == .
	replace file = "`data'" if file == ""
	gen nid = 120994 if year_start == 2004
	replace nid = 111916 if year_start == 2007
	replace nid = 103981 if year_start == 2010
	replace nid = 225627 if year_start == 2013
	gen cv_work_home = 1
	gen cv_outdoor = 1
	gen cv_smokerathome = 0
	replace national_type = 4 if national_type == . // Nationally and subnationally representative
	gen urbanicity_type = 1
	gen orig_uncertainty_type = "ESS"


	tempfile all 
	save `all', replace
	
// Match old China subnationals to new GBD 2015 subnationals 
	
	// Bring in GBD 2013 subnational China locations 
	odbc load, exec("select local_id as iso3, name as country from locations") dsn(codmod) clear
	keep if regexm(iso3, "^X")
	
	merge 1:m iso3 using `all' 
	drop if _m == 1 
	drop _m

	replace country = province_name if country == ""
	drop province_name iso3
	rename country location_name
	replace location_name = "China" if location_name == ""
	drop if location_name == "Jining" // prefecture-level city in the Shandong province 
	// replace location_name = "Shandong" if location_name == "Jining" 

	save `all', replace
	
	// Bring in 2015 subnational China locations 
	
	merge m:1 location_name using `country_codes' 
	keep if _m == 3 
	drop _m
		
save "./china_subnational_revised.dta", replace
