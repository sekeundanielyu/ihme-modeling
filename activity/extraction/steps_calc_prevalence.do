// DATE: SEPTEMBER 23, 2015
// PURPOSE: CLEAN AND EXTRACT PHYSICAL ACTIVITY DATA FROM SAU, JOR, & VNM STEPS SURVEYS, AND COMPUTE PHYSICAL ACTIVITY PREVALENCE IN 5 YEAR AGE-SEX GROUPS FOR EACH YEAR 

// NOTES: 
	// STEPS surveys that should be included for 2015: 
		// JOR 2007
		// VNM 2009 -- no way to join the population information with the survey design variables to the physical activity questionnaire data

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
	
	local outdir "$j/WORK/05_risk/risks/activity/data/exp"
	local datadir "$j/DATA/WHO_STEPS_NCD/"

// Bring in Jordan dataset

	use "`datadir'/JOR/2007/JOR_STEPS_NCD_2007_Y2011M05D18.dta", clear

		// Rename variables so they match up with the SAU survey
		rename age age_group 
		rename q1_3 age
		rename q5_2 p2 
		replace p2 = 0 if q5_1 == 2 
		rename q5_3 p3 
		replace p3 = 0 if q5_1 == 2
		rename q5_5 p5 
		replace p5 = 0 if q5_4 == 2 
		rename q5_6 p6
		replace p6 = 0 if q5_4 == 2 

		rename q5_8 p8 
		replace p8 = 0 if q5_7 == 2 
		rename q5_9 p9 
		replace p9 = 0 if q5_7 == 2 
		rename q5_11 p11 
		replace p11 = 0 if q5_10 == 2 
		rename q5_12 p12 
		replace p12 = 0 if q5_10 == 2
		rename q5_14 p14 
		replace p14 = 0 if q5_13 == 2 
		rename q5_15 p15
		replace p15 = 0 if q5_13 == 2 
		rename relative pweight
		rename gov region
		
		gen iso3 = "JOR"

		tempfile jor 
		save `jor', replace

// Bring in SAU dataset

	use "`datadir'/SAU/2004_2005/SAU_STEPS_NCD_2004_2005.DTA"

	// Make variables and variable names consistent with other sources 
		rename c1 sex 
		rename combined_wt pweight
		rename i3 region
		label define sex 1 "Male" 2 "Female"
		label values sex sex
		gen iso3 = "SAU"

		append using `jor'

	

// Perform same processes for all surveys now that variables are the same 

	drop if age < 25 | age == . // only care about respondents 25 and above for physical inactivity risk	
	
	// Days per week should not be more than 7
		foreach var in p2 p5 p8 p11 p14 {
			replace `var'=. if `var'>7
		}

	// Total met-minutes per week
		gen work_mets = (p2 * p3 * 60 * 8) + (p5 * p6 * 60 * 4)
		gen walk_mets = (p8 * p9 * 60 * 4)
		gen rec_mets = (p11 * p12 * 60 * 8) + (p14 * p15 * 60 * 4)
		egen total_mets = rowtotal(rec_mets walk_mets work_mets)
		egen checkmiss = rowmiss(rec_mets walk_mets work_mets)
		replace total_mets = . if checkmiss == 3

	// Check total hours (should not be greater than 16 hours per day)
		egen total_hrs = rowtotal(p3 p6 p9 p12 p15)
		replace total_mets = . if total_hrs > 16


		keep sex age total_mets iso3 region pweight
	
	// Save compiled raw dataset	
		save "`outdir'/raw/steps_ncd_clean.dta", replace
	
	// Set age groups
		egen age_start = cut(age), at(25(5)120)
		replace age_start = 60 if age_start > 60 & age_start != .
		levelsof age_start, local(ages)

	// Make categorical physical activity variables
		drop if total_mets == .
		gen inactive = total_mets < 600
		gen lowactive = total_mets >= 600 & total_mets < 4000
		gen lowmodhighactive = total_mets >= 600
		gen modactive = total_mets >= 4000 & total_mets < 8000
		gen modhighactive = total_mets >= 4000 
		gen highactive = total_mets >= 8000 
		
	// Set survey weights
		svyset region [pweight=pweight]			
	
	// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category 
		mata 
			iso3 = J(1,1,"todrop")
			age_start = J(1,1,999)
			sex = J(1,1,999)
			sample_size = J(1,1,999)
			inactive_mean = J(1,1,999)
			inactive_se = J(1,1,999)
			lowmodhighactive_mean = J(1,1,999)
			lowmodhighactive_se = J(1,1,999)
			modhighactive_mean = J(1,1,999)
			modhighactive_se = J(1,1,999)
			lowactive_mean = J(1,1,999)
			lowactive_se = J(1,1,999)
			modactive_mean = J(1,1,999)
			modactive_se = J(1,1,999)
			highactive_mean = J(1,1,999)
			highactive_se = J(1,1,999)
		end
		
		//  Compute prevalence in each age/sex group

		levelsof iso3, local(countries)

		foreach iso3 of local countries {
			foreach sex in 1 2 {	
				foreach age of local ages {
									
					di in red "Country: `iso3' Age: `age' Sex: `sex'"
					count if iso3 == "`iso3'" & age_start == `age' & sex == `sex' & total_mets != .
					local sample_size = r(N)

					if `sample_size' > 0 {
						// Calculate mean and standard error for each activity category
							foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
								mean `category' if age_start ==`age' & sex == `sex'
								matrix `category'_stats = r(table)
								
								local `category'_mean = `category'_stats[1,1]
								mata: `category'_mean = `category'_mean \ ``category'_mean'
								
								local `category'_se = `category'_stats[2,1]
								mata: `category'_se = `category'_se \ ``category'_se'
							}
								
						// Extract other key variables	
							mata: iso3 = iso3 \ "`iso3'"
							mata: age_start = age_start \ `age'
							mata: sex = sex \ `sex'
							mata: sample_size = sample_size \ `sample_size'
					}
				}
			}
		}
					
// Get stored prevalence calculations from matrix
	clear

	getmata iso3 age_start sex sample_size highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se lowmodhighactive_mean lowmodhighactive_se modhighactive_mean modhighactive_se
	drop if _n == 1 // drop top row which was a placehcolder for the matrix created to store results	
	
// Replace standard error as missing if its zero 
	recode *_se (0 = .)
		
// Create variables that are always tracked
	
	gen file = "J:/DATA/WHO_STEPS_NCD/SAU/2004_2005/SAU_STEPS_NCD_2004_2005.DTA" if iso3 == "SAU"
	replace file = "J:/DATA/WHO_STEPS_NCD/JOR/2007/JOR_STEPS_NCD_2007_Y2011M05D18.DTA" if iso3 == "JOR" 
	generate year_start = 2004 if iso3 == "SAU"
	generate year_end = 2005 if iso3 == "SAU" 
	replace year_start = 2007 if iso3 == "JOR" 
	replace year_end = 2007 if iso3 == "JOR"
	generate age_end = age_start + 4
	egen maxage = max(age_start)
	replace age_end = 65 if age_start == maxage
	drop maxage
	gen survey_name = "WHO STEPwise Approach to NCD Surveillance"
	gen questionnaire = "GPAQ"
	gen source_type = "Survey"
	gen data_type = "Survey: other"
	gen national_type = 1 // nationally representative sample
	gen urbanicity_type = 1 // Representative
	
//  Organize
	sort sex age_start age_end
	
// Save survey weighted prevalence estimates 
	save "`outdir'/prepped/steps_ncd_prepped.dta", replace
