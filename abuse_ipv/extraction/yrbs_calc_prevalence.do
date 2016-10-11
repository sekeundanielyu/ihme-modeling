// DATE: September 2, 2015	
// PURPOSE: Clean and Extract IPV data from the National Youth Risk Behavior Survey (2013)


// NOTES
	// YRBS 2003 & 2005 & 2007 & 2009 & 2011 National Questionnaire 
		// During the past 12 months, did your boyfriend or girlfriend ever hit, slap, or physically hurt you on purpose? 
		**// Have you ever been physically forced to have sexual intercourse when you did not want to? 

	// YRBS 2013 National Questionnaire
		**// Have you been physically forced to have sexual intercourse when you did not want to? 
		// During the past 12 months, how many times did someone you were dating or goign out with physically hurt you on purpose? 
		// During the past 12 months, how many times did someone you were dating or going out with force you to do sexual things that you did not want to do? 


***// Just using lifetime sexual violence as the parameter value and then adjusting based on study-level covariate

// Set up
	clear all
	set more off
	set mem 2g
	capture restore not
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j "J:"
	}

// Create locals for relevant files and folders
	local data_dir "$j/DATA/USA/NATIONAL_YOUTH_RISK_BEHAVIOR_SURVEY"
	local prepped_dir "$j/WORK/05_risk/risks/abuse_ipv_exp/data/exp/01_tabulate/prepped"
	
	local years 2003 2005 2007 2009 2011 2013
	
// Country codes 

	clear
	#delim ;
	odbc load, exec("SELECT ihme_loc_id, location_name, location_id, location_type
	FROM shared.location_hierarchy_history 
	WHERE (location_type = 'admin0' OR location_type = 'admin1' OR location_type = 'admin2' OR location_type = 'nonsovereign')
	AND location_set_version_id = (
	SELECT location_set_version_id FROM shared.location_set_version WHERE 
	location_set_id = 9
	and end_date IS NULL)") dsn(epi) clear;
	#delim cr
	
	rename ihme_loc_id iso3 
	keep if regexm(iso3, "USA") | location_type == "nonsovereign" 
	tempfile countrycodes
	save `countrycodes', replace


** *********************************************************************
** 1.) Clean and Compile 
** *********************************************************************
	// Loop through files for each year for IPV
	
	foreach year of local years {
	
		if inlist(`year', 2003, 2005, 2007, 2009, 2011) {
			use "`data_dir'/`year'/USA_YRBS_`year'_Y2015M08D03.dta", clear
			renvars, lower
			gen year = `year'
			gen file = "J:/DATA/USA/NATIONAL_YOUTH_RISK_BEHAVIOR_SURVEY/`year'"
			di in red `year'
			
			destring q*, replace
			//gen ipv_phys_1yr = 1 if q22 == 1
			//replace ipv_phys_1yr = 0 if q22 == 2 

			gen ipv_sex_ever = 1 if q23 == 1 
			replace ipv_sex_ever = 0 if q23 == 2
		}


		if inlist(`year', 2013) { 
			use "`data_dir'/`year'/USA_YRBS_`year'_Y2015M08D03.dta", clear 
			renvars, lower
			gen year = `year' 
			gen file = "J:/DATA/USA/NATIONAL_YOUTH_RISK_BEHAVIOR_SURVEY/`year'" 
			di in red `year' 

			destring q*, replace
			//gen ipv_any_1yr = 1 if inlist(q22, 3, 4, 5, 6) | inlist(q23, 3, 4, 5, 6)
			//replace ipv_any_1yr = 0 if inlist(q22, 1, 2) | inlist(q22, 1, 2) 

			gen ipv_sex_ever = 1 if q21 == 1 
			replace ipv_sex_ever = 0 if q21 == 2 

		}

			// Keep only necessary variables
			rename q1 age 
			rename q2 sex
			tempfile yrbs_`year'
			save `yrbs_`year'', replace

		}

	// Append all years of YRBS together 

	use `yrbs_2013', clear
	foreach year of local years {
		if `year' != 2013 {
			append using `yrbs_`year'', force
		}
	}

	keep file year weight stratum psu sex age ipv_sex_ever 
	rename ipv_sex_ever parameter_value
	keep if sex == 2 // only females

	tempfile all 
	save `all', replace

	// Calculate missingness 
	bysort file: gen total = _N 

	levelsof file, local(surveys)

	local count = 1 
	foreach survey of local surveys {
		preserve 
		keep if file == "`survey'" 
		count if parameter_value == .
		gen missingness = `r(N)' / total
		tempfile `count'
		save ``count'', replace
		local count = `count' + 1
		restore
		
	}

	local terminal = `count' - 1
	clear
	forvalues x = 1/`terminal' {
		di `x'
		qui: cap append using ``x'', force
	}


	keep file missingness
	collapse (first) missingness, by(file)
	tempfile missing 
	save `missing', replace

// EXTRACT PREVALENCE
	
	use `all', clear

	mata
		file = J(1,1,"todrop") 
		year = J(1,1,999)
		age = J(1,1,-999)
		sex = J(1,1,-999)
		sample_size = J(1,1,-999)
		mean = J(1,1,-999.999)
		standard_error = J(1,1,-999.999)
		lower = J(1,1,-999.999)
		upper = J(1,1,-999.999)
	end

// Set age groups
	destring age, replace
	keep if age >= 4 // 15 or older
	
// Specify survey design
	svyset psu [pweight=weight], strata(stratum)

// Compute prevalence, sample size and missigness for each year sex age group

	levelsof file, local(surveys) 

	foreach survey of local surveys { 
				
				di in red "File: `survey'"
				count if file == "`survey'" & parameter_value != . 
				if r(N) != 0 {
				
				svy linearized, subpop(if file == "`survey'"): mean parameter_value

					matrix mean_matrix = e(b)
					local mean_scalar = mean_matrix[1,1]
					mata: mean = mean \ `mean_scalar'
					
					matrix variance_matrix = e(V)
					local se_scalar = sqrt(variance_matrix[1,1])
					mata: standard_error = standard_error \ `se_scalar'
					
					local degrees_freedom = `e(df_r)'
					local lower = invlogit(logit(`mean_scalar') - (invttail(`degrees_freedom', .025)*`se_scalar')/(`mean_scalar'*(1-`mean_scalar')))
					mata: lower = lower \ `lower'
					local upper = invlogit(logit(`mean_scalar') + (invttail(`degrees_freedom', .025) * `se_scalar') / (`mean_scalar' * (1 - `mean_scalar')))
					mata: upper = upper \ `upper'
	
					mata: file = file \ "`survey'"
					
					mata: sample_size = sample_size \ `e(N_sub)'
			}
		}

// Get stored prevalence calculations from matrix
	clear

	getmata file sample_size mean standard_error upper lower, replace
	drop if _n == 1 // Drop empty top row of matrix
	replace standard_error = (3.6/sample_size)/(2*1.96) if standard_error == 0 // Greg's standard error fix for binomial outcomes
	
	gen year = regexs(1) if regexm(file,"([0-9]?[0-9]?[0-9]?[0-9])$")
	destring year, replace force

	gen age_start = 15
	gen age_end = 19 
	gen year_start = year
	gen year_end = year_start
	gen iso3 = "USA"
	gen location_id = "102"
	gen data_type = "Survey: unspecified"
	gen source_type = 2
	label define source_type 2 "Survey"
	label values source_type source_type
	gen orig_uncertainty_type = "SE" 
	gen national_type = 1 // Nationally representative
	gen urbanicity_type = "representative" // Representative
	gen units = 1
	gen health_state = "abuse_ipv"

		// Specify Epi covariates
		gen subnational = 0
		gen urban = 0
		gen rural = 0
		gen mixed = 0
		gen nointrain = 1
		gen notviostudy1 = 1
		gen sexvio = 1 // just asking about lifetime sexual violence
		gen physvio = 0
		gen spouseonly = 0
		gen pstatall = 0
		gen pstatcurr = 0
		gen pastyr = 0
		gen past2yr = 0
		gen severe = 0
		gen currpart = 0

// Merge with missingness
merge m:1 file using `missing' 
drop _m 

// Save 
save "`prepped_dir'/yrbs_prepped.dta", replace



	

