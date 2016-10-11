// DATE: JANUARY 22, 2013
// PURPOSE: CLEAN AND EXTRACT SECONDHAND SMOKE DATA FROM SAUDI ARABIA HEALTH INTERVIEW SURVEY 2013 AND COMPUTE PREVALENCE IN 5 YEAR AGE-SEX GROUPS 

// NOTES: Sampled individuals age 15+.  
	** During the past 7 days, on how many days did someone in your home smoke when you were present?
	** During the past 7 days, on how many days did someone smoke in closed areas in your workplace or school (in the building, in a work area or a specific office) when you were present?

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
	
// Make locals for relevant folders
	local data_dir $j/DATA/SAU/HEALTH_INTERVIEW_SURVEY_2013
	local outdir $j/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped
	
// Bring in dataset
	use "`data_dir'/SAU_HEALTH_INTERVIEW_SURVEY_2013_Y2013M12D31.DTA", clear 

// Keep only nonsmokers, since we are interested in hh_shs exposure prevalence among nonsmokers
	keep if tobacco_smoker_current == 0
	
// Generate secondhand smoke exposure dummy
	gen hh_shs = tobacco_secondhanddays > 0 & tobacco_secondhanddays != .
	recode hh_shs (0=.) if tobacco_secondhanddays == .
	
// Make a variable for exposure to secondhand smoke at home or work (for crosswalking within dismod)
	recode tobacco_workdays (.=0) if inlist(work_status, 7, 8, 9)
	gen shs_home_work = 1 if hh_shs == 1 | (tobacco_workdays > 0 & tobacco_workdays != .)
	replace shs_home_work = 0 if hh_shs == 0 & tobacco_workdays == 0 
	
// Set age groups
	drop if ageage < 25
	egen age_start = cut(ageage), at(25(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	levelsof age_start, local(ages)
	drop ageage
	
// Set survey weights
	svyset hhid [pweight=post_strat_pweight]	
	
// Create empty matrix for storing proportion of nonsmokers in each age/sex subpopulation that are exposed to secondhand smoke
	mata 
		age_start = J(1,1,999)
		sex = J(1,1,999)
		sample_size = J(1,1,999)
		mean_hh_shs = J(1,1,999)
		se_hh_shs = J(1,1,999)
		mean_workhh_shs = J(1,1,999)
		se_workhh_shs = J(1,1,999)
	end	
		
// Compute prevalence
	foreach sex in 1 2 {	
		foreach age of local ages {
			di in red "Age: `age' Sex: `sex'"
			count if age_start == `age' & sex == `sex' & hh_shs != .
			local sample_size = r(N)
			if `sample_size' > 0 {
				// Extract exposure at home				
					svy linearized, subpop(if age_start ==`age' & sex == `sex'): mean hh_shs
					
					matrix mean_matrix = e(b)
					local mean_scalar = mean_matrix[1,1]
					mata: mean_hh_shs = mean_hh_shs \ `mean_scalar'
					
					matrix variance_matrix = e(V)
					local se_scalar = sqrt(variance_matrix[1,1])
					mata: se_hh_shs = se_hh_shs \ `se_scalar'
				
				// Extract exposure at home or work (for cross walk)
					svy linearized, subpop(if age_start ==`age' & sex == `sex'): mean shs_home_work
					
					matrix mean_matrix = e(b)
					local mean_scalar = mean_matrix[1,1]
					mata: mean_workhh_shs = mean_workhh_shs \ `mean_scalar'
					
					matrix variance_matrix = e(V)
					local se_scalar = sqrt(variance_matrix[1,1])
					mata: se_workhh_shs = se_workhh_shs \ `se_scalar'
				
				// Extract other key variables
					mata: age_start = age_start \ `age'
					mata: sex = sex \ `sex'
					mata: sample_size = sample_size \ `sample_size'
			}
		}
	}

// Get stored prevalence calculations from matrix
	clear

	getmata age_start sex sample_size mean_hh_shs se_hh_shs mean_workhh_shs se_workhh_shs 
	drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results	
	
// Replace standard error as missing if its zero (so that dismod calculates error using the sample size instead)
	recode se_workhh_shs se_hh_shs (0 = .)

// Reshape household shs and alternative work or home definition long
	reshape long mean_ se_, i(sex age_start) j(case_definition, string)
	replace case_definition = "Exposure to tobacco smoke in the home at least one day in the past week among current nonsmokers" if case_definition == "hh_shs"
	replace case_definition = "Exposure to tobacco smoke at home, work or school at least one day in the past week among current nonsmokers" if case_definition == "workhh_shs"
	rename se_ standard_error
	rename mean_ mean
	
// Create variables that are always tracked		
	gen iso3 = "SAU"
	gen file = "J:\DATA\SAU\HEALTH_INTERVIEW_SURVEY_2013\SAU_HEALTH_INTERVIEW_SURVEY_2013_Y2013M12D31.DTA"
	gen year_start = 2013
	gen year_end = 2013
	generate age_end = age_start + 4
	egen maxage = max(age_start)
	replace age_end = 100 if age_start == maxage
	drop maxage
	gen risk = "smoking_shs"
	gen parameter_type = "Prevalence"
	gen survey_name = "Saudi Arabia Health Interview Survey"
	gen source = "micro_ksa"
	gen data_type = 10
	gen orig_unit_type = 2 // Rate per 100 (percent)
	gen orig_uncertainty_type = "SE" 
	gen national_type_id = 1 // Nationally representative	
	
//  Organize
	order iso3 year_start year_end sex age_start age_end sample_size mean standard_error, first
	sort sex age_start age_end
	
// Female sample sizes are very small so we will drop these
	drop if sex == 2
	
// Save survey weighted prevalence estimates 
	save "`outdir'/ksa.dta", replace			
	
