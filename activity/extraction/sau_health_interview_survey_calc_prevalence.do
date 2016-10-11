// DATE: JANUARY 22, 2013
// PURPOSE: CLEAN AND EXTRACT PHYSICAL ACTIVITY DATA FROM SAUDI ARABIA HEALTH INTERVIEW SURVEY 2013 AND COMPUTE PHYSICAL ACTIVITY PREVALENCE IN 5 YEAR AGE-SEX GROUPS 

// NOTES: Sampled individuals age 15+.  Long form of the IPAQ.  

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
	local raw_dir $j/WORK/05_risk/risks/activity/data/exp/raw
	local outdir $j/WORK/05_risk/risks/activity/data/exp/prepped
	
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
	rename ihme_loc_id iso3
	rename location_name subnational
	
	tempfile countrycodes
	save `countrycodes', replace 
	
// Bring in dataset
	use "`data_dir'/SAU_HEALTH_INTERVIEW_SURVEY_2013_Y2013M12D31.DTA", clear 
	
	// Map region code variable in dataset to subnational GBD locations 
	tostring rgn_code, replace
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
	
// Calculate total minutes per week of activity performed at each domain and intensity level
	foreach domain in work rec travel_walk10 {
		// Travel domain does not have intensity levels
			if "`domain'" == "travel_walk10" {
				replace `domain'_timeminutes = `domain'_timehours * 60 if `domain'_timeminutes == . & `domain'_timehours != .
				gen `domain'_total = `domain'_daysdays * `domain'_timeminutes
				recode `domain'_total (.=0) if `domain' == 0
				gen `domain'_mets = `domain'_total * 3.3
			}
		
		// Work and recreational domains have intensity level
			else {
				foreach level in vigactivity modactivity {
					recode `domain'_`level' `domain'_`level'_daysdays `domain'_`level'_timehours `domain'_`level'_timeminutes (.=0) if `domain'_`level' == 0 | inlist(work_status, 7, 8, 9)
					replace `domain'_`level'_timeminutes = `domain'_`level'_timehours * 60 if `domain'_`level'_timeminutes == . & `domain'_`level'_timehours != .
					gen `domain'_`level'_total = `domain'_`level'_daysdays * `domain'_`level'_timeminutes
					recode `domain'_`level'_total (.=0) if `domain'_`level' == 0
				}
				
		// Compute total MET-min per week in each domain
			gen `domain'_vigactivity_mets = `domain'_vigactivity_total * 8
			gen `domain'_modactivity_mets = `domain'_modactivity_total * 4
		}
	}
		
		egen total_mets = rowtotal(*_mets)
		egen miss = rowmiss(*_mets)
		recode total_mets (0=.) if miss == 5
		
// Check to make sure total minutes of activity per week is believable
	egen total_time = rowtotal(*_total) 
	replace total_mets = . if total_time > 6720 // Shouldn't be more than 6720 minutes (assume no more than 16 active waking hours per day on average)
	
// Make variables and variable names consistent with other sources 
	drop age
	rename ageage age
	label define sex 1 "Male" 2 "Female"
	label values sex sex
	gen survey_name = "Saudi Arabia Health Interview Survey"
	gen questionnaire = "IPAQ_long"
	gen iso3 = "SAU"
	gen year_start = 2013
	gen year_end = 2013
	keep subnational sex age total_mets iso3 survey_name questionnaire year_start year_end hhid post_strat_pweight

// Save compiled raw dataset	
	save "`raw_dir'/sau_his_clean.dta", replace
	
// Make categorical physical activity variables
	drop if total_mets == .
	gen inactive = total_mets < 600
	gen lowactive = total_mets >= 600 & total_mets < 4000
	gen lowmodhighactive = total_mets >= 600
	gen modactive = total_mets >= 4000 & total_mets < 8000
	gen modhighactive = total_mets >= 4000 
	gen highactive = total_mets >= 8000 
	
// Set age groups
	drop if age < 25
	egen age_start = cut(age), at(25(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	levelsof age_start, local(ages)
	drop age
	
// Set survey weights
	svyset hhid [pweight=post_strat_pweight]	
	
	tempfile all 
	save `all', replace 
	
// Create empty matrix for storing proportion of an age/sex subpopulation in each physical activity category 
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
			
// Compute prevalence
	foreach sex in 1 2 {	
		foreach age of local ages {
			di in red "Age: `age' Sex: `sex'"
			count if age_start == `age' & sex == `sex' & total_mets != .
			local sample_size = r(N)
			
			if `sample_size' > 0 {
				// Calculate mean and standard error for each activity category	
					foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
						svy linearized, subpop(if age_start ==`age' & sex == `sex'): mean `category'
						
						matrix `category'_meanmatrix = e(b)
						local `category'_mean = `category'_meanmatrix[1,1]
						mata: `category'_mean = `category'_mean \ ``category'_mean'
						
						matrix `category'_variancematrix = e(V)
						local `category'_se = `category'_variancematrix[1,1]
						mata: `category'_se = `category'_se \ ``category'_se'
					}
				
				// Extract other key variables
					mata: age_start = age_start \ `age'
					mata: sex = sex \ `sex'
					mata: sample_size = sample_size \ `e(N_sub)'
			}
		}
	}

// Get stored prevalence calculations from matrix
	clear

	getmata age_start sex sample_size highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se lowmodhighactive_mean lowmodhighactive_se modhighactive_mean modhighactive_se
	drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results	
	
	tempfile mata_calc 
	save `mata_calc', replace 
	
// Subnational exposure estimation in addition to national level 
	
	use `all', clear 
	levelsof subnational, local(subnationals) 
	
	mata 
		subnational = J(1,1,"subnational") 
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
			
// Compute prevalence

foreach subnational of local subnationals {
	foreach sex in 1 2 {	
		foreach age of local ages {
			di in red "Subnational: `subnational' Age: `age' Sex: `sex'"
			count if subnational == "`subnational'" & age_start == `age' & sex == `sex' & total_mets != .
			local sample_size = r(N)
			
			if `sample_size' > 0 {
				// Calculate mean and standard error for each activity category	
					foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
						svy linearized, subpop(if subnational == "`subnational'" & age_start ==`age' & sex == `sex'): mean `category'
						
						matrix `category'_meanmatrix = e(b)
						local `category'_mean = `category'_meanmatrix[1,1]
						mata: `category'_mean = `category'_mean \ ``category'_mean'
						
						matrix `category'_variancematrix = e(V)
						local `category'_se = `category'_variancematrix[1,1]
						mata: `category'_se = `category'_se \ ``category'_se'
					}
				
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

	getmata subnational age_start sex sample_size highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se lowmodhighactive_mean lowmodhighactive_se modhighactive_mean modhighactive_se
	drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results	
	
	append using `mata_calc' 
	
// Replace standard error as missing if its zero (so that dismod calculates error using the sample size instead)
	recode *_se (0 = .)
	
	replace subnational = "'Asir" if subnational == "Asir"
// Bring in country codes 

	merge m:1 subnational using `countrycodes' 

	
// Create variables that are always tracked		
	replace iso3 = "SAU" if iso3 == "" 
	gen file = "J:\DATA\SAU\HEALTH_INTERVIEW_SURVEY_2013\SAU_HEALTH_INTERVIEW_SURVEY_2013_Y2013M12D31.DTA"
	gen year_start = 2013
	gen year_end = 2013
	generate age_end = age_start + 4
	egen maxage = max(age_start)
	replace age_end = 100 if age_start == maxage
	drop maxage
	gen survey_name = "Saudi Arabia Health Interview Survey"
	gen questionnaire = "IPAQ_long"
	gen source_type = "Survey"
	gen data_type = "Survey: other"
	gen national_type = 1 // Nationally representative	
	replace national_type = 2 if subnational != "" // subnationally representative 
	gen urbanicity_type = 1 // Representative
	
//  Organize
	drop location_id location_type _m 
	order iso3 subnational sex age_start age_end
	sort iso3 subnational sex age_start age_end
	
// Save survey weighted prevalence estimates 
	save "`outdir'/ksa_prepped.dta", replace			
