// DATE: JANUARY 30, 2013
// PURPOSE: CLEAN AND EXTRACT PHYSICAL ACTIVITY DATA FROM Brazil Household Survey on Risk Factors, Morbidity, and NCDs, AND COMPUTE PHYSICAL ACTIVITY PREVALENCE IN 5 YEAR AGE-SEX GROUPS FOR EACH YEAR 

// NOTES: Uses IPAQ.  Use weight2 variable as sample weight since not every respondent in the sample completed the physical activity module

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
	local data "$j/DATA/BRA/RISK_FACTOR_MORBIDITY_NCD_SURVEY/2002_2005/BRA_RISK_FACTOR_MORBIDITY_NCD_SURVEY_2002_2005_PHYSICAL_ACTIVITY.DTA"
	local outdir "$j/WORK/05_risk/risks/activity/data/exp"

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
	
	keep if regexm(ihme_loc_id, "BRA")
	rename ihme_loc_id iso3
	rename location_name state
	
	tempfile countrycodes
	save `countrycodes', replace 

// Bring in dataset
	use "`data'", clear
	recode sexo (0=2) 
	drop if fissitu == -4 
	keep psu uf fissitu sexo idade dias* temp* ipaq* insufati atv* weight2
	rename idade age
	rename sexo sex

// Cleaning loop: Internal consistency checks and calculating total minutes of physical activity performed at each level per week	
	foreach level in vig mod cam {
		if "`level'" == "vig" | "`level'" == "mod" {
			recode dias`level' (9=0) (-1=0) (-5=.)
		}
		recode temp`level'h temp`level'm (-1=0) if dias`level' == 0
		replace temp`level'm = temp`level'h * 60 + temp`level'm // convert to min/day
		gen `level'_total = dias`level' * temp`level'm // total minutes per week
	}
	
// Calculate total mets from each activity level and the total across all levels combined
	gen mod_mets = mod_total * 4
	gen vig_mets = vig_total * 8
	gen walk_mets = cam_total * 3.3
	egen total_mets = rowtotal(vig_mets mod_mets walk_mets)
	egen total_miss = rowmiss(vig_mets mod_mets walk_mets)
	replace total_mets = . if total_miss >2  
	drop total_miss
	
// Check to make sure total reported activity time is plausible	
	egen total_time = rowtotal(vig_total mod_total cam_total) // Shouldn't be more than 6720 minutes (assume no more than 16 active waking hours per day on average)
	replace total_mets = . if total_time > 6720
	drop total_time 

// Make variables and variable names consistent with other sources
	label define sex 1 "Male" 2 "Female"
	label values sex sex
	gen survey_name = "Brazil Household Survey on Risk Factors, Morbidity, and NCDs"
	gen questionnaire = "IPAQ"
	gen iso3 = "BRA"
	gen year_start = 2002
	gen year_end = 2005
	keep uf sex age total_mets iso3 survey_name questionnaire year_start year_end weight2 psu
		
	save "`outdir'/raw/bra_rfncd_clean.dta", replace
	
// Make categorical physical activity variables
	drop if total_mets == .
	gen inactive = total_mets < 600
	gen lowactive = total_mets >= 600 & total_mets < 4000
	gen lowmodhighactive = total_mets >= 600
	gen modactive = total_mets >= 4000 & total_mets < 8000
	gen modhighactive = total_mets >= 4000 
	gen highactive = total_mets >= 8000
	
// Set age groups
	drop if age < 25 | age == .
	egen age_start = cut(age), at(25(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	levelsof age_start, local(ages)
	drop age
	decode uf, gen(city) 
	
	
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
		

// Set survey weights
	svyset psu [pweight=weight2]
	
	tempfile all 
	save `all', replace
	
// Compute prevalence at national level for age/sex group 

	foreach sex in 1 2 {	
		foreach age of local ages {
							
			di in red "Age: `age' Sex: `sex'"
			count if age_start == `age' & sex == `sex' & total_mets != .
			local sample_size = r(N)
			if `sample_size' > 0 {
				// Calculate mean and standard error for each activity category
					foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
						svy linearized, subpop(if age_start ==`age' & sex == `sex'): mean `category'
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

		tempfile mata_calc
		save `mata_calc', replace 
		
	
//  Compute prevalence in each city/age/sex group

use `all', clear 
levelsof city, local(cities)
	
	// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category 
	mata 
		city = J(1,1,"city") 
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
	
foreach city of local cities { 
	foreach sex in 1 2 {	
		foreach age of local ages {
							
			di in red "City: `city' Age: `age' Sex: `sex'"
			count if city == "`city'" & age_start == `age' & sex == `sex' & total_mets != .
			local sample_size = r(N)
			if `sample_size' > 0 {
				// Calculate mean and standard error for each activity category
					foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
						svy linearized, subpop(if city == "`city'" & age_start ==`age' & sex == `sex'): mean `category'
						matrix `category'_stats = r(table)
						
						local `category'_mean = `category'_stats[1,1]
						mata: `category'_mean = `category'_mean \ ``category'_mean'
						
						local `category'_se = `category'_stats[2,1]
						mata: `category'_se = `category'_se \ ``category'_se'
					}
						
				// Extract other key variables	
					mata: city = city \ "`city'" 
					mata: age_start = age_start \ `age'
					mata: sex = sex \ `sex'
					mata: sample_size = sample_size \ `sample_size'
			}
		}
	}
}
					
		// Get stored prevalence calculations from matrix
			clear

			getmata city age_start sex sample_size highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se lowmodhighactive_mean lowmodhighactive_se modhighactive_mean modhighactive_se
			drop if _n == 1 // drop top row which was a placehcolder for the matrix created to store results
		
			append using `mata_calc' 
			
		// Replace standard error as missing if its zero (so that dismod calculates error using the sample size instead)
			recode *_se (0 = .)		
			
			save `all', replace
			
// Join with country codes and match cities to states 
	import excel using "`outdir'/raw/RFNCD_brazil_codebook.xlsx", firstrow clear 
	drop if state == ""
	merge 1:1 state using `countrycodes', keep(1 3 4 5) nogen
	
	merge 1:m city using `all' 
	
	replace iso3 = "BRA" if _m == 2
	replace state = "National" if _m == 2
	drop _m location_type
	
// Create variables that are always tracked
	generate file = "`data'"
	generate year_start = 2002
	generate year_end = 2005
	// generate iso3 = "BRA"
	generate age_end = age_start + 4
	egen maxage = max(age_start)
	replace age_end = 100 if age_start == maxage
	drop maxage
	gen survey_name = "Brazil Household Survey on Risk Factors, Morbidity, and NCDs"
	gen questionnaire = "IPAQ"
	gen source_type = "Survey"
	gen data_type = "Survey: household"
	gen national_type = 1 if state == "National" // Nationally representative
	gen national_type = 10 if state != "National" // Representative of urban areas 
	gen urbanicity_type = 1 // Representative
	
//  Organize
	sort location_id sex age_start age_end
	
// Save survey weighted prevalence estimates 
	save "`outdir'/prepped/bra_rfncd_prepped.dta", replace			
	
