// DATE: JUNE 3, 2015
// PURPOSE: RE-EXTRACT SAUDI ARABIA SUBNATIONAL ESTIMATES FOR SECONDHAND SMOKE DATA FROM SAUDI ARABIA HEALTH INTERVIEW SURVEY 2013 AND COMPUTE PREVALENCE IN 5 YEAR AGE-SEX GROUPS 

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

// Prepare country codes dataset 
	clear
	#delim ;
	odbc load, exec("SELECT ihme_loc_id, location_name, location_id, location_type
	FROM shared.location_hierarchy_history 
	WHERE (location_type = 'admin0' OR location_type = 'admin1' OR location_type = 'admin2')
	AND location_set_version_id = (
	SELECT location_set_version_id FROM shared.location_set_version WHERE 
	location_set_id = 9
	and end_date IS NULL)") dsn(epi) clear;
	#delim cr
	
	keep if regexm(ihme_loc_id, "SAU")
	rename ihme_loc_id subnational 
	
	tempfile countrycodes
	save `countrycodes', replace 
	
// Bring in dataset
	use "`data_dir'/SAU_HEALTH_INTERVIEW_SURVEY_2013_Y2013M12D31.DTA", clear 
	
// Map region code variable in dataset to subnational GBD locations 
	tostring rgn_code, replace
	gen iso3 = "SAU" 
	gen subnational = ""
	replace subnational = "Riyadh" if rgn_code == "1" 
	replace subnational = "Makkah" if rgn_code == "2" 
	replace subnational = "Madinah" if rgn_code == "3" 
	replace subnational = "Qassim" if rgn_code == "4"
	replace subnational = "Eastern Province" if rgn_code == "5"
	replace subnational = "Asir" if rgn_code == "6"
	replace subnational = "Tabuk" if rgn_code == "7" 
	replace subnational = "Ha'il" if rgn_code == "8" 
	replace subnational = "Northern Borders" if rgn_code == "9" 
	replace subnational = "Jizan" if rgn_code == "10" 
	replace subnational = "Najran" if rgn_code == "11" 
	replace subnational = "Bahah" if rgn_code == "12" 
	replace subnational = "Jawf" if rgn_code == "13" 
	
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
	drop age
	
// Set survey weights
	svyset hhid [pweight=post_strat_pweight]	
	
	tempfile all 
	save `all', replace
	
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

levelsof age_start, local(ages)

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
					mata: sample_size = sample_size \ `e(N_sub)'
			}
		}
	}
	
// Get stored prevalence calculations from matrix
	clear

	getmata age_start sex sample_size mean_hh_shs se_hh_shs mean_workhh_shs se_workhh_shs 
	drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results	
	gen subnational = "Saudi Arabia" 
	
	tempfile national_mata
	save `national_mata', replace
	
// Now for each of the subnational units, calculate mean SHS exposure for each age-sex group 

use `all', clear

	mata 
		subnational = J(1,1, "subnational") 
		age_start = J(1,1,999)
		sex = J(1,1,999)
		sample_size = J(1,1,999)
		mean_hh_shs = J(1,1,999)
		se_hh_shs = J(1,1,999)
		mean_workhh_shs = J(1,1,999)
		se_workhh_shs = J(1,1,999)
	end	
	
levelsof subnational, local(subnationals)

foreach subnational of local subnationals { 
	foreach sex in 1 2 {	
			foreach age of local ages {
	
	use `all', clear
	
	di in red "Subnational: `subnational' Age: `age' Sex: `sex'"
	count if subnational == "`subnational'" & age_start == `age' & sex == `sex' & hh_shs != .
	local sample_size = r(N)
			
		if `sample_size' > 0 {
			// Extract exposure at home				
				svy linearized, subpop(if subnational == "`subnational'" & age_start ==`age' & sex == `sex'): mean hh_shs
			
				matrix mean_matrix = e(b)
				local mean_scalar = mean_matrix[1,1]
				mata: mean_hh_shs = mean_hh_shs \ `mean_scalar'
					
				matrix variance_matrix = e(V)
				local se_scalar = sqrt(variance_matrix[1,1])
				mata: se_hh_shs = se_hh_shs \ `se_scalar'
				
			// Extract exposure at home or work (for cross walk)
				svy linearized, subpop(if subnational == "`subnational'" & age_start ==`age' & sex == `sex'): mean shs_home_work
					
				matrix mean_matrix = e(b)
				local mean_scalar = mean_matrix[1,1]
				mata: mean_workhh_shs = mean_workhh_shs \ `mean_scalar'
					
				matrix variance_matrix = e(V)
				local se_scalar = sqrt(variance_matrix[1,1])
				mata: se_workhh_shs = se_workhh_shs \ `se_scalar'
				
			// Extract other key variables
					mata: subnational = subnational \ "`subnational'"
					mata: age_start = age_start \ `age'
					mata: sex = sex \ `sex'
					mata: sample_size = sample_size \ `e(N_sub)'
			}
		}
	}
}
	

// Get stored prevalence calculations from matrix
	clear

	getmata subnational age_start sex sample_size mean_hh_shs se_hh_shs mean_workhh_shs se_workhh_shs 
	drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results	

// Append using national-level results 
	append using `national_mata' 
	rename subnational location_name
	replace location_name = "'Asir" if location_name == "Asir" 
	
// Replace standard error as missing if its zero 
	recode se_workhh_shs se_hh_shs (0 = .)
	tempfile mata_calculations 
	save `mata_calculations', replace 
	
// Merge with country codes 
	use `countrycodes', clear 
	merge 1:m location_name using `mata_calculations' 
	
// Reshape household shs and alternative work or home definition long
	reshape long mean_ se_, i(sex age_start subnational) j(case_definition, string)
	replace case_definition = "Exposure to tobacco smoke in the home at least one day in the past week among current nonsmokers" if case_definition == "hh_shs"
	replace case_definition = "Exposure to tobacco smoke at home, work or school at least one day in the past week among current nonsmokers" if case_definition == "workhh_shs"
	rename se_ standard_error
	rename mean_ mean

// Create variables that are always tracked		
	rename subnational iso3 
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
	replace orig_uncertainty_type = "ESS" if standard_error == .
	gen national_type =  4 // nationally & subnationally representative
	replace national_type = 1 if iso3 == "SAU" 
	
//  Organize
	order iso3 year_start year_end sex age_start age_end sample_size mean standard_error, first
	sort iso3 sex age_start age_end
	
// Female sample sizes are very small so we will drop these
	drop if sex == 2
	drop _m
	
// Save to raw file and bring in and append with national estimates 
	save "`outdir'/ksa_subnational.dta", replace			
	
