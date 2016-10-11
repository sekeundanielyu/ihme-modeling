// Date: May 31 2016
// Purpose: Find age/sex-specific adjustment factor to shift BRFSS up to represent total activity

// NOTES: BRFSS only asks about leisure/recreation & transport, excluding occupational activity. Thus we are using NHANES, which measures total activity across all three domains, to adjust BRFSS up to total. 

// Set up
	clear all
	set more off
	set mem 2g
	capture log close
	capture restore not
	set maxvar 30000, permanently 
	set matsize 10000, permanently
	
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	
	else if c(os) == "Windows" {
		global j "J:"
	}


// Set local dirs 
	local data_dir "$j/WORK/05_risk/risks/activity/data/exp"

// NHANES	
	use "`data_dir'/prepped/nhanes_prepped.dta", clear 

	collapse *_mean, by(sex age_start)

	gen survey_name = "NHANES"
	tempfile nhanes 
	save `nhanes', replace 

// BRFSS
	use "`data_dir'/prepped/brfss_prepped.dta", clear 
	
	collapse *_mean, by(sex age_start)

	gen survey_name = "BRFSS"

	tempfile brfss 
	save `brfss', replace 

	append using `nhanes'

	reshape wide *_mean, i(age_start sex ) j(survey, string)

	tempfile all 
	save `all', replace 


// Create ratio of BRFSS to NHANES
	local activity_cats "highactive modactive inactive lowactive modhighactive lowmodhighactive"

	foreach var of local activity_cats { 
		gen ratio_`var' = `var'_meanBRFSS / `var'_meanNHANES

	}

	keep sex age_start ratio_*

	tempfile ratios 
	save `ratios', replace 
	
	save "J:/WORK/05_risk/risks/activity/data/exp/ratio_brfss_nhanes.dta", replace 

// Apply ratios to BRFSS data 
	use "`data_dir'/prepped/brfss_prepped.dta", clear 

	merge m:1 sex age_start using `ratios', keep(3) nogen

	foreach var of local activity_cats { 
		replace `var'_mean = `var'_mean / ratio_`var' 

	}

	duplicates drop location_id survey_name iso3 year_start year_end sex age_start age_end, force

	save "`data_dir'/prepped/adjusted_brfss_prepped.dta", replace 


	/*
// Generate means 
	
	// Set age groups
		drop if age < 25
		egen age_start = cut(age), at(25(5)120)
		replace age_start = 80 if age_start > 80 & age_start != .
		levelsof age_start, local(ages)
		drop age

	// Set survey weights
		svyset psu [pweight=wt], strata(strata)
		
	// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category (inactive, moderately active and highly active)
			mata 
				agegrp = J(1,1,999)
				sex = J(1,1,999)
				mean = J(1,1,999)
				se = J(1,1,999)
				survey = J(1,1,"todrop")
			end	

		levelsof age_start, local(agegrps)
		levelsof survey_name, local(surveys)

		label drop sex 

		save `all', replace 

		foreach survey of local surveys { 
			foreach sex in 1 2 {
				foreach agegrp of local agegrps {
						use `all', clear
						keep if sex == `sex' & age_start == `agegrp' & survey_name == "`survey'"
						
						svy linearized, subpop(if sex == `sex' & age_start == `agegrp' & survey_name == "`survey'" ): mean total_mets
								
							matrix meanmatrix = e(b)
							local mean = meanmatrix[1,1]
							mata: mean = mean \ `mean'
								
							matrix variancematrix = e(V)
							local se = sqrt(variancematrix[1,1])
							mata: se = se \ `se'
						
							mata: agegrp = agegrp \ `agegrp'
							mata: sex = sex \ `sex'
							mata: survey = survey \ "`survey'"
					}
				}
			}
	
		

	// Get stored prevalence calculations from matrix
		clear
		getmata agegrp sex mean se survey 
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
	

// Reshape 
	drop se 
	reshape wide mean, i(agegrp sex ) j(survey, string)

// Generate ratio 
	gen ratio = meanBRFSS / meanNHANES

// Save file for use in BRFSS state mean calculations 
	rename agegrp age_start 

	keep age_start sex ratio 

	save "J:/WORK/05_risk/risks/activity/data/exp/ratio_brfss_nhanes.dta", replace 
