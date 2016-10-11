// DATE: JANUARY 29, 2013
// PURPOSE: CLEAN AND EXTRACT PHYSICAL ACTIVITY DATA FROM IPAQ LONG FORM DATA SENT TO ME BY MARIA HAGSTROMER, AND COMPUTE PHYSICAL ACTIVITY PREVALENCE IN 5 YEAR AGE-SEX GROUPS FOR EACH YEAR 

// NOTES: 

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
	local data_dir "$j/DATA/Incoming Data/GBD 2013 Expert Sources/Risk Factors/SWE_IPAQ_VALIDATION_STUDY"
	local outdir "$j/WORK/05_risk/risks/activity/data/exp"


** ******************************************************************************************
// 1.) CLEAN AND COMPILE
** ******************************************************************************************	
// Prep 2002 and 2008 datasets.
	// 2002
		insheet using "`data_dir'/ipaq_2002.csv", comma clear 
		gen year_start = 2002
		gen year_end = 2002
		rename totmet total_mets
		tempfile ipaq_2002
		save `ipaq_2002'
	
	// 2008	
		insheet using "`data_dir'/ipaq_2008.csv", comma clear 
		drop if id == 7725 // duplicate id that isn't in the 2002 dataset
		merge 1:1 id using `ipaq_2002', nogen keep(match)
		replace age = age + 6 // aged 6 years since 2002
		keep *2 age sex id
		// Get rid of "2" suffix on 2008 dataset so that variables match the 2002 dataset
			foreach stub in exercise met_tot {
				rename `stub'2 `stub'
			}
		gen year_start = 2008
		gen year_end = 2008
		rename met_tot total_mets
		tempfile ipaq_2008
		save `ipaq_2008'
		
	// Combine both years to make master dataset of total METS on individual level
		append using `ipaq_2002'
		drop if age < 25 
		
	// Make variables and variable names consistent with other sources
		recode sex (0=2) 
		label define sex 1 "Male" 2 "Female"
		label values sex sex
		
		replace total_mets = "" if total_mets == "#NULL!"
		destring total_mets, replace
		
		gen survey_name = "Sweden IPAQ Data from the Karolinska Institutet Department of Biosciences and Nutrition"
		gen questionnaire = "IPAQ_long"
		gen iso3 = "SWE"
		keep sex age total_mets iso3 survey_name questionnaire year_start year_end
		
		save "`outdir'/raw/swe_ipaq_clean.dta", replace

** ******************************************************************************************
// 2.) CALCULATE PREVALENCE IN EACH YEAR/AGE/SEX SUB-POPULATION
** ******************************************************************************************	
// Make categorical physical activity variables
	drop if total_mets == .
	gen inactive = total_mets < 600
	gen lowactive = total_mets >= 600 & total_mets < 4000
	gen lowmodhighactive = total_mets >= 600
	gen modactive = total_mets >= 4000 & total_mets < 8000
	gen modhighactive = total_mets >= 4000 
	gen highactive = total_mets >= 8000 

// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category (inactive, moderately active and highly active)
	mata 
		year_start = J(1,1,999)
		// file = J(1,1,"todrop")
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
		

// Loop through both years
	levelsof year_start, local(years)
	foreach year of local years {
		// Set age groups
		if `year' == 2002 {
			egen age_start = cut(age), at(25(5)120)
			replace age_start = 70 if age_start > 70
			levelsof age_start, local(ages)
			// drop age
		}
		if `year' == 2008 {
			recode age_start (30=25) (40=35) (50=45) (60=55) // want ten year age groups since smaller sample size
			replace age_start = 70 if age_start > 70
			levelsof age_start, local(ages)
		}	
	
		//  Compute prevalence in each age/sex group
			foreach sex in 1 2 {	
				foreach age of local ages {					
					di in red "Year: `year' Age: `age' Sex: `sex'"
					count if year_start == `year' & age_start == `age' & sex == `sex' & total_mets != .
					local sample_size = r(N)
					if `sample_size' > 0 {
						// Calculate mean and standard error for each activity category
							foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
								mean `category' if year_start == `year' & age_start ==`age' & sex == `sex'
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
							mata: year_start = year_start \ `year'
					}
				}
			}
	}
	
// Get stored prevalence calculations from matrix
	clear

	getmata year_start age_start sex sample_size highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se lowmodhighactive_mean lowmodhighactive_se modhighactive_mean modhighactive_se
	// file
	drop if _n == 1 // drop top row which was a placehcolder for the matrix created to store results		
	
// Create variables that are always tracked	
	generate year_end = year_start
	generate iso3 = "SWE"
	generate age_end = age_start + 4 if year_start == 2002
	replace age_end = age_start +9 if year_start == 2008
	egen maxage = max(age_start)
	replace age_end = 100 if age_start == maxage
	drop maxage
	gen survey_name = "Sweden IPAQ Data from the Karolinska Institutet Department of Biosciences and Nutrition"
	gen questionnaire = "IPAQ_long"
	gen source_type = "Survey"
	gen data_type = "Survey: other"
	gen national_type = 3 if year_start == 2008 // 2008 is not a representative sample 
	replace national_type = 1 if year_start == 2002 // 2002 is a representative sample
	gen urbanicity_type = 1 if national_type == 1 // representative
	replace urbanicity_type = 0 if national_type == 3 // Unknown
	gen nid = 135802
	
//  Organize
	sort sex age_start age_end
	
// Save survey weighted prevalence estimates 
	save "`outdir'/prepped/swe_ipaq_prepped.dta", replace			
	
