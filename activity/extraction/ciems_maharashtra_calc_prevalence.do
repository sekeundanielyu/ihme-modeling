// DATE: OCTOBER 27, 2015 
// PURPOSE: CLEAN AND EXTRACT PHYSICAL ACTIVITY DATA CENTRAL INDIA EYE MEDICAL STUDY (CIEMS) FOR MAHARASHTRA AND COMPUTE PHYSICAL ACTIVITY PREVALENCE IN 5 YEAR AGE-SEX GROUPS FOR EACH YEAR 

// NOTES: 


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
	local datadir "$j/DATA/IND/MAHARASHTRA_CENTRAL_INDIA_EYE_MEDICAL_STUDY_CIEMS_2006_2008"


// Bring in dataset 

	use "`datadir'/IND_MAHARASHTRA_CIEMS_2006_2008_ALL_AVAILABLE_RISK_FACTORS_Y2014M06D14.DTA", clear 

	keep age_YEars gender DailyActivity_* 
	rename age_YEars age 
	rename gender sex 

	// Check weekly variables to make sure they don't go over 7 days 
	foreach var in DailyActivity_da_5 DailyActivity_da_7 DailyActivity_da_10 DailyActivity_da_14 DailyActivity_da_17 { 
		replace `var' = . if `var' > 7 
	}

	// Calculate Work, Transport and Recreation METs

		gen work_mets = (DailyActivity_da_4 * DailyActivity_da_5 * 8) + (DailyActivity_da_7 * DailyActivity_da_8 * 4) 
		gen transport_mets = (DailyActivity_da_10 * DailyActivity_da_11 * 4)
		gen recreation_mets = (DailyActivity_da_14 * DailyActivity_da_15 * 8) + (DailyActivity_da_17 * DailyActivity_da_18 * 4)	

		egen total_mets = rowtotal(work_mets transport_mets recreation_mets) 
		egen checkmiss = rowmiss(work_mets transport_mets recreation_mets) 
		replace total_mets = . if checkmiss == 3

		// Check total hours (should not be greater than 16 hours per day or 960 minutes)
	
		egen total_mins = rowtotal(DailyActivity_da_4 DailyActivity_da_8 DailyActivity_da_11 DailyActivity_da_15 DailyActivity_da_18)
		replace total_mets = . if total_mins > 960


	//	keep iso3 location_id location_name sex age total_mets
		keep sex age total_mets 
	
	// Save compiled raw dataset	
		// save "`outdir'/raw/ciems_maharashtra_clean.dta", replace
	
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
		
	// No psu or strata variables, so set psu equal to the observation number and strata equal to 0 
		gen strata = 0 
		gen psu = _n 
		gen pweight = 1 

	// Set survey weights
		svyset psu [pweight=pweight]			
	
	// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category 
		mata 
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

		foreach sex in 1 2 {	
			foreach age of local ages {
									
				di in red "Age: `age' Sex: `sex'"
				count if age_start == `age' & sex == `sex' & total_mets != .
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
							mata: age_start = age_start \ `age'
							mata: sex = sex \ `sex'
							mata: sample_size = sample_size \ `sample_size'
					}
				}
			}

	// Get stored prevalence calculations from matrix
	clear

	getmata age_start sex sample_size highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se lowmodhighactive_mean lowmodhighactive_se modhighactive_mean modhighactive_se
	drop if _n == 1 // drop top row which was a placehcolder for the matrix created to store results	
	
// Replace standard error as missing if its zero (so that dismod calculates error using the sample size instead)
	recode *_se (0 = .)
		
// Create variables that are always tracked
	
	gen file = "J:/DATA/IND/MAHARASHTRA_CENTRAL_INDIA_EYE_MEDICAL_STUDY_CIEMS_2006_2008/IND_MAHARASHTRA_CIEMS_2006_2008_ALL_AVAILABLE_RISK_FACTORS_Y2014M06D14.DTA" 
	gen year_start = 2006 
	gen year_end = 2008
	generate age_end = age_start + 4
	egen maxage = max(age_start)
	replace age_end = 65 if age_start == maxage
	drop maxage
	gen survey_name = "CIEMS"
	gen questionnaire = "other"
	gen source_type = "Survey"
	gen data_type = "Survey: other"
	gen domain = "recreation, work, transport"
	gen national_type = 2 // sunationally representative sample
	gen urbanicity_type = "rural" 
	
//  Organize
	sort sex age_start age_end
	gen iso3 = "IND_43927" 
	gen location_id = 43927 
	gen location_name = "Maharashtra, Rural"

// Save prevalence estimates
	save "`outdir'/prepped/ciems_prepped.dta", replace



