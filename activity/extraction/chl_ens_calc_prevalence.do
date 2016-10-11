// DATE: October 5, 2015
// PURPOSE: Clean and extract physical activity data from the Chile National Health Survey (which uses the GPAQ)

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
	local datadir "$j/DATA/CHL/NATIONAL_HEALTH_SURVEY_ENS/2009_2010"

// Bring in CHL ENS 2009-2010 dataset

	use "`datadir'/CHL_ENS_2009_2010_Y2014M01D24.DTA", clear

	rename edad age 
	rename zona urban 
	rename sexo sex 

	keep age urban sex region fexp1 fexp2 fexp_ex fexp_fac a*


// Clean up variables to calculate MET-min/week 

	// Only calculate exposure for people > 25
	drop if age < 25 | age == .  

	// Days per week should not be more than 7
		foreach var in a2 a5 a8 a11 a14 {
			replace `var'=. if `var'>7
		}

	// Total met-minutes per week
		gen work_time_vig = (a3_1 * 60) + a3_2 
		gen work_time_mod = (a6_1 * 60) + a6_2
		gen walk_time = (a9_1 * 60) + a9_2 
		gen rec_time_vig = (a12_1 * 60) + a12_2 
		gen rec_time_mod = (a15_1 * 60) + a15_2

		gen work_mets = (a2 * work_time_vig * 8) + (a5 * work_time_mod * 4)
		gen walk_mets = (a8 * walk_time * 4)
		gen rec_mets = (a11 * rec_time_vig * 8) + (a14 * rec_time_mod * 4)
		egen total_mets = rowtotal(rec_mets walk_mets work_mets)
		egen checkmiss = rowmiss(rec_mets walk_mets work_mets)
		replace total_mets = . if checkmiss == 3

	// Check total hours (should not be greater than 16 hours per day)
		egen total_hrs = rowtotal(a3_1 a6_1 a9_1 a12_1 a15_1)
		replace total_mets = . if total_hrs > 16

	// Keep only necessary variables

		rename fexp1 pweight // using F-1 questionnaire for physical activity

		keep sex age total_mets region pweight urban
	

	// Save compiled raw dataset	
		save "`outdir'/raw/chl_ens_clean.dta", replace

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
		svyset region [pweight=pweight], strata(urban)		
	
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
		
	// Calculate prevalence

		foreach sex in 1 2 {	
			foreach age of local ages {
									
				di in red "Country: `iso3' Age: `age' Sex: `sex'"
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
	
// Replace standard error as missing if its zero
	recode *_se (0 = .)
	

// Create variables that are always tracked
	
	gen iso3 = "CHL"
	gen file = "J:/DATA/CHL/NATIONAL_HEALTH_SURVEY_ENS/2009_2010/CHL_ENS_2009_2010_Y2014M01D24.DTA" 
	gen nid = 120127
	generate year_start = 2009
	generate year_end = 2010 
	generate age_end = age_start + 4
	egen maxage = max(age_start)
	replace age_end = 65 if age_start == maxage
	drop maxage
	gen survey_name = "Chile National Health Survey"
	gen questionnaire = "GPAQ"
	gen source_type = "Survey"
	gen data_type = "Survey: other"
	gen national_type = 1 // nationally representative sample
	gen urbanicity_type = 1 // Representative
	
//  Organize
	sort sex age_start age_end	

// Save survey weighted prevalence estimates 
	save "`outdir'/prepped/chl_ens_prepped.dta", replace
