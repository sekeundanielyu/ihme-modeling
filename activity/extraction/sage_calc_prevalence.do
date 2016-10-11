// Date: Updated July 2015 (original date: November 6, 2013)
// Purpose: Extract physical activity data from the WHO Study on global AGEing and adult health (SAGE) and compute  physical activity prevalence in 5 year age-sex groups for each country

// Notes: SAGE uses the GPAQ.  This code has two parts: 
	** 1.) Cleans the data (internal consistency checks and converts to total mets per week).  Also compiles all country datasets into one  and estimates correlations.  
	** 2.) Calculate proportion of each country/age/sex subpopulation in each activity level and save compiled/prepped SAGE dataset


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
	
// Create locals for relevant files and folders
	cd "$j/WORK/05_risk/risks/activity/data/exp"
	local data_dir  "J:/DATA/WHO_SAGE"
	local count 0 // local to count loop iterations and save each country as numbered tempfiles to be appended later

	/*
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
	
	rename ihme_loc_id iso3
	keep if regexm(iso3, "IND") | regexm(iso3, "MEX") | regexm(iso3, "ZAF") | regexm(iso3, "CHN") 
	
	replace location_name = subinstr(location_name, "?", "a", .) 
	replace location_name = "Chhattisgarh" if location_name == "Chhattasgarh"
	replace location_name = "Chhattisgarh, Rural" if location_name == "Chhattasgarh, Rural" 
	replace location_name = "Chhattisgarh, Urban" if location_name == "Chhattasgarh, Urban" 
	replace location_name = "Jammu and Kashmir" if location_name == "Jammu and Kashmar" 
	replace location_name = "Jammu and Kashmir, Rural" if location_name == "Jammu and Kashmar, Rural"
	replace location_name = "Jammu and Kashmir, Urban" if location_name == "Jammu and Kashmar, Urban" 
	
	
	rename location_name subnational
	
	tempfile countrycodes
	save `countrycodes', replace 
	*/
** *********************************************************************
** 1.) Clean and Compile 
** ********************************************************************
//  Loop through each country dataset
	local iso3s = "CHN GHA IND MEX RUS ZAF"
	foreach iso3 of local iso3s {
		di in red `count'
		di in red "`iso3'"
		
		if "`iso3'" == "CHN" { 
			use "`data_dir'/`iso3'/2007_2010/CHN_SAGE_WAVE_1_2007_2010_INDV_Y2015M09D18.DTA", clear
			gen filename = "CHN_SAGE_WAVE_1_2007_2010_INDV_Y2015M09D18.DTA"
		}
			
		if "`iso3'" == "GHA" { 
			use "`data_dir'/`iso3'/2007_2008/GHA_SAGE_WAVE_1_2007_2008_INDV_Y2015M09D18.DTA", clear
			gen filename = "GHA_SAGE_WAVE_1_2007_2008_INDV_Y2015M09D18.DTA"
		} 
		
		if "`iso3'" == "IND" { 
			use "`data_dir'/`iso3'/2007/IND_SAGE_WAVE_1_2007_INDV_Y2015M09D18.DTA", clear 
			gen filename = "IND_SAGE_WAVE_1_2007_INDV_Y2015M09D18.DTA"
		} 
		
		if "`iso3'" == "MEX" { 
			use "`data_dir'/`iso3'/2009_2010/MEX_SAGE_WAVE_1_2009_2010_INDV_Y2015M09D18.DTA", clear 
			gen filename = "MEX_SAGE_WAVE_1_2009_2010_INDV_Y2015M09D18.DTA" 
		} 
		
		if "`iso3'" == "RUS" { 
			use "`data_dir'/`iso3'/2007_2010/RUS_SAGE_WAVE_1_2007_2010_INDV_Y2015M09D18.DTA", clear 
			gen filename = "RUS_SAGE_WAVE_1_2007_2010_INDV_Y2015M09D18.DTA"
		}
		
		if "`iso3'" == "ZAF" { 
			use "`data_dir'/`iso3'/2007_2008/ZAF_SAGE_WAVE_1_2007_2008_INDV_Y2015M09D18.DTA", clear 
			gen filename = "ZAF_SAGE_WAVE_1_2007_2008_INDV_Y2015M09D18.DTA"
		}
	
			gen iso3 = "`iso3'"

			rename q0105a subnational 
			cap rename q0104 urban 
			
			replace q0407 = q1011 if q0407 == . // If the standard age variable is missing we will use the "age in yyys" variable instead
			drop if  q0407 < 25 | q0407 == . // only care about respondents 25 and above for physical inactivity risk

			// Rename variables for the loop below (makes summing accross time, activity levels and activity domains easier)
				rename q1503 currently_working
				rename q3016 work_vig
				rename q3017 work_vig_days
				rename q3018h work_vig_hrs
				rename q3018m work_vig_min
				rename q3019 work_mod
				rename q3020 work_mod_days
				rename q3021h work_mod_hrs
				rename q3021m work_mod_min
				rename q3022 trans
				rename q3023 trans_days
				rename q3024h trans_hrs
				rename q3024m trans_min
				rename q3025 rec_vig
				rename q3026 rec_vig_days
				rename q3027h rec_vig_hrs
				rename q3027m rec_vig_min
				rename q3028 rec_mod
				rename q3029 rec_mod_days
				rename q3030h rec_mod_hrs
				rename q3030m rec_mod_min
			
				recode work_vig work_mod (.=0) if currently_working == 2 // Cannot have work activity if not currently working so will assume missing is "none"

			// Loop through each domain and activity levels and estimate total minutes per week of activity in each domain-level
				// Transport domain only has moderate level so I will deal with it separately from work and recreational
				foreach domain in trans work rec {
					if "`domain'" == "trans" {
					di "`domain'"
						recode `domain' 8=. 9=2 // Don't know to missing and not applicable to "no" 
						recode `domain'_days `domain'_hrs `domain'_min (missing = 0) if `domain' == 2 // make days hours and minutes 0 if respondent does not perform transport activity
						recode `domain'_min `domain'_hrs (-8=.) // don't knows as missing
						replace `domain'_days = . if `domain'_days > 7 // not more than 7 days/week
						replace `domain'_min = 0 if `domain'_min < 10 // less than 10 min a domain should not count according to GPAQ guidelines
						replace `domain'_min = `domain'_hrs if (`domain'_min == 0 | `domain'_min == .) & (`domain'_hrs == 15 | `domain'_hrs == 30 |`domain'_hrs == 45 | `domain'_hrs == 60) // check if minutes were accidentally entered as hours
						replace `domain'_hrs = 60*`domain'_hrs // convert hours to minutes
						
						replace `domain'_hrs = 0 if `domain'_hrs == . & `domain'_min !=.
						replace `domain'_min = 0 if `domain'_min == . & `domain'_hrs !=.
						replace `domain'_min = `domain'_hrs + `domain'_min // calculate total minutes/average day
						drop if `domain'_min > 960 & `domain'_min != . // GPAQ cleaning guidelines say to drop cases where the total minutes of activity per day of a subdomain alone is > 16 hours
						gen `domain'_total = `domain'_min * `domain'_days // calculate total minutes/week
					}
					
					if "`domain'" == "work" | "`domain'" == "rec" {
						foreach level in vig mod {
						di "`domain'_`level'"
							recode `domain'_`level' 8=. 9=2 // Don't know to missing and not applicable to "no"
							recode `domain'_`level'_days `domain'_`level'_hrs `domain'_`level'_min (missing = 0) if `domain'_`level' == 2 // make days, hours and minutes 0 if respondent does not perform activity in subdomain
							recode `domain'_`level'_min `domain'_`level'_hrs (-8=.)
							replace `domain'_`level'_days = . if `domain'_`level'_days > 7 // not more than 7 days/week
							replace `domain'_`level'_min = 0 if `domain'_`level'_min < 10 // less than 10 min a domain should not count according to GPAQ guidelines
							replace `domain'_`level'_min = `domain'_`level'_hrs if (`domain'_`level'_min == 0 | `domain'_`level'_min == .) &  (`domain'_`level'_hrs == 15 | `domain'_`level'_hrs == 30 |`domain'_`level'_hrs == 45 | `domain'_`level'_hrs == 60) // check if minutes were accidentally entered as hours
							replace `domain'_`level'_hrs = 60*`domain'_`level'_hrs //  convert hours to minutes 
							
							replace `domain'_`level'_hrs = 0 if `domain'_`level'_hrs == . & `domain'_`level'_min !=.
							replace `domain'_`level'_min = 0 if `domain'_`level'_min == . & `domain'_`level'_hrs !=.
							replace `domain'_`level'_min = `domain'_`level'_hrs + `domain'_`level'_min // calculate total minutes/average day
							drop if `domain'_`level'_min > 960 & `domain'_`level'_min != . // GPAQ cleaning guidelines say to drop cases where the total minutes of activity per day of a subdomain alone is > 16 hours
							gen `domain'_`level'_total = `domain'_`level'_min * `domain'_`level'_days // calculate total minutes/week
					}
				}
			}
			
			// Calculate total mets/week in each activity domain and total of all domains combined
				foreach domain in work rec {
					generate `domain'_vig_mets = `domain'_vig_total * 8
					generate `domain'_mod_mets = `domain'_mod_total * 4
					egen `domain'_mets = rowtotal(`domain'_mod_mets `domain'_vig_mets)
					egen `domain'_miss = rowmiss(`domain'_mod_mets `domain'_vig_mets)
					replace `domain'_mets = . if `domain'_miss == 2 // should be missing not 0 if both subdomains are missing
					drop `domain'_miss 
				}
				
				generate trans_mets = trans_total * 4
				
				egen total_mets = rowtotal(trans_mets work_mets rec_mets)
				egen total_miss = rowmiss(trans_mets work_mets rec_mets)
				replace total_mets = . if total_miss == 3 // according to GPAQ guildines, should exclude only respondents with missing values in all subdomains, and as long as at least one subdomain has valid answers and all others are missing, we should assume no activity in other domains.  
			
			// Cross-check total hours accross all domains (shouldn't be active more than 16 hours a day, 7 days a week)
				egen total_hrs = rowtotal(work_vig_total work_mod_total rec_vig_total rec_mod_total trans_total) 
				replace total_hrs = total_hrs / (60*7) // calculate average hours per day
				replace total_mets = . if total_hrs > 16 | (work_vig == . & work_mod == . & rec_vig == . & rec_mod == . & trans == .)
			
			// Keep only necessary variables
				if "`iso3'" == "MEX" {
					rename q1009 sex
					rename q1011 age
				}
				else {
				rename q0407 age
				rename q0406 sex
				}
				rename q0101b psu
				keep iso3 subnational urban psu pweight strata file* trans* work* rec* total* age sex
			
		tempfile data`count'
		save `data`count'', replace
		local count = `count' + 1
	}

// Append all countries together
	use `data0', clear
	local max = `count' - 1
	forvalues x = 1/`max' {
		qui: append using `data`x''
	}
	
// Fill in iso3 codes
/*
	generate iso3 = ""
	replace iso3 = "CHN" if regexm(filename, "CHN") == 1
	replace iso3 = "MEX" if regexm(filename, "MEX") == 1
	replace iso3 = "GHA" if regexm(filename, "GHA") == 1
	replace iso3 = "IND" if regexm(filename, "IND") == 1
	replace iso3 = "RUS" if regexm(filename, "RUS") == 1
	replace iso3 = "ZAF" if regexm(filename, "ZAF") == 1
	*/
	
// Subnationals 
	replace subnational = "" if inlist(iso3, "RUS", "GHA") 

//  Fill in year start and end variables 
	generate year_start = .
	generate year_end = .
	replace year_start = 2007 if iso3 == "CHN"
	replace year_end = 2010 if iso3 == "CHN"
	replace year_start = 2009 if iso3 == "MEX"
	replace year_end = 2010 if iso3 == "MEX"
	replace year_start = 2007 if iso3 == "GHA"
	replace year_end = 2008 if iso3 == "GHA"
	replace year_start = 2007 if iso3 == "IND"
	replace year_end = 2007 if iso3 == "IND"
	replace year_start = 2007 if iso3 == "RUS"
	replace year_end = 2010 if iso3 == "RUS"
	replace year_start = 2007 if iso3 == "ZAF"
	replace year_end = 2008 if iso3 == "ZAF"
	
// Make variables and variable names consistent with other sources 
	label define sex 1 "Male" 2 "Female"
	label values sex sex
	gen survey_name = "WHO Study on global AGEing and adult health"
	gen questionnaire = "GPAQ"
	
	replace subnational = lower(subnational)
	replace subnational = strproper(subnational) 
	
	keep sex age subnational urban total_mets work_mets rec_mets trans_mets iso3 survey_name questionnaire year_start year_end psu pweight strata file

// Save compiled raw dataset	
	save ./raw/sage_clean_test.dta, replace
	tempfile compiled
	save `compiled', replace

** *******************************************************************************************
** 2.) Calculate Prevalence in each country/age/sex subgroup and save compiled/prepped dataset for all 6 SAGE countries
** *******************************************************************************************
	// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category
		mata 
			iso3 = J(1,1,"todrop")
			file = J(1,1,"todrop")
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
		
	// Set age groups
		egen age_start = cut(age), at(25(5)120)
		replace age_start = 80 if age_start > 80 & age_start != .
		levelsof age_start, local(ages)
		drop age
		
	// Make categorical physical activity variables
		drop if total_mets == .
		gen inactive = total_mets < 600
		gen lowactive = total_mets >= 600 & total_mets < 4000
		gen lowmodhighactive = total_mets >= 600
		gen modactive = total_mets >= 4000 & total_mets < 8000
		gen modhighactive = total_mets >= 4000 
		gen highactive = total_mets >= 8000 

	// Set survey weights
		svyset psu [pweight=pweight], strata(strata)
		
	// Drop pweights of zero 
		drop if pweight == 0 

		tempfile all 
		save `all', replace 
		
	// Compute prevalence
		levelsof iso3, local(countries)
		foreach country of local countries {
			use `all', clear 
			keep if iso3 == "`country'"
			di "`country'"

			foreach sex in 1 2 {	
				foreach age of local ages {
					preserve
					di in red "Country: `country' Age: `age' Sex: `sex'"
					count if iso3 == "`country'" & age_start == `age' & sex == `sex'
					if r(N) != 0 {
						// Calculate mean and standard error for each activity category	
							foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
								svy linearized, subpop(if iso3 == "`country'" & age_start ==`age' & sex == `sex'): mean `category'
								
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
							mata: iso3 = iso3 \ "`country'"
							local file = file
							mata: file = file \ "`file'"
						restore
					}
				}
			}
		}

	// Get stored prevalence calculations from matrix
		clear

		getmata iso3 age_start sex sample_size file highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se lowmodhighactive_mean lowmodhighactive_se modhighactive_mean modhighactive_se
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results	
	
		tempfile mata_calc
		save `mata_calc', replace 
		
	// SUBNATIONALS 
	
		use `all', clear 
		drop if iso3 == "GHA" | iso3 == "RUS" 
		
		// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category
		mata 
			iso3 = J(1,1,"todrop")
			subnational = J(1,1,"subnational")
			urban = J(1,1,"urban") 
			file = J(1,1,"todrop")
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
		
	// Make india urban / rural subnationals
	decode urban, gen(urbanicity) 
	replace subnational = subnational + ", " + urbanicity if iso3 == "IND" 
	replace subnational = strproper(subnational) 
	
	// Compute prevalence
		levelsof iso3, local(countries)
		levelsof urbanicity, local(urbanicities) 
		
	// Mexico is not a subnational 
		drop if subnational == "Mexico" 

		save `all', replace 

		foreach country of local countries {

			use `all', clear 
			keep if iso3 == "`country'"
			levelsof subnational, local(subnationals) 


			foreach subnational of local subnationals { 
				foreach sex in 1 2 {	
					foreach age of local ages {
					
					di in red "Country: `country' Subnational: `subnational' Age: `age' Sex: `sex'"
					count if iso3 == "`country'" & subnational == "`subnational'" & age_start == `age' & sex == `sex'
					if r(N) != 0 {
						// Calculate mean and standard error for each activity category	
							foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
								svy linearized, subpop(if iso3 == "`country'" & subnational == "`subnational'" & age_start ==`age' & sex == `sex'): mean `category'
								
								matrix `category'_meanmatrix = e(b)
								local `category'_mean = `category'_meanmatrix[1,1]
								mata: `category'_mean = `category'_mean \ ``category'_mean'
								
								matrix `category'_variancematrix = e(V)
								local `category'_se = `category'_variancematrix[1,1]
								mata: `category'_se = `category'_se \ ``category'_se'
							}
						
						// Extract other key variables
							mata: subnational = subnational \ "`subnational'" 
							mata: urban = urban \ "`urban'" 
							mata: age_start = age_start \ `age'
							mata: sex = sex \ `sex'
							mata: sample_size = sample_size \ `e(N_sub)'
							mata: iso3 = iso3 \ "`country'"
							local file = file
							mata: file = file \ "`file'"

						
					}
					
				}
			}
		}
	}
	
	// Get stored prevalence calculations from matrix
		clear

		getmata iso3 subnational age_start sex sample_size file highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se lowmodhighactive_mean lowmodhighactive_se modhighactive_mean modhighactive_se
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results	
		
		append using `mata_calc'
	
	// Replace standard error as missing if its zero (so that dismod calculates error using the sample size instead)
		recode *_se (0 = .)
		
		replace subnational = "KwaZulu-Natal" if subnational == "Kwazulu-Natal"
		replace subnational = "Shandong" if subnational == "Shangdong"
		replace subnational = "Yucatán" if subnational == "Yucatan" 
		replace subnational = "Veracruz de Ignacio de la Llave" if subnational == "Veracruz De Ignacio"
		replace subnational = "Coahuila" if subnational == "Coahuila De Zaragoza" 
		replace subnational = "Michoacán de Ocampo" if subnational == "Michoacan De Ocampo" 
		replace subnational = "Nuevo León" if subnational == "Nuevo Leon" 
		replace subnational = "Querétaro" if subnational == "Queretaro"
		replace subnational = "San Luis Potosí" if subnational == "San Luis Potosi"


		tempfile all_calc
		save `all_calc', replace
		
	// Bring in country codes from database
	
		merge m:1 subnational using `countrycodes'
		drop if _m == 2
		drop _m 
		
		tostring location_id, replace
		replace iso3 = iso3 + "_" + location_id if location_id != "." 

		
	// Set variables that are always tracked
		gen national_type =  1 // nationally representative
		replace national_type = 2 if subnational != ""  // subnationally representative 
		replace national_type = 10 if regexm(subnational, "Urban") // representative for urban areas 
		replace national_type = 11 if regexm(subnational, "Rural") // representative for rural areas 
		gen urbanicity_type = 1 // representative
		replace urbanicity_type = 2 if regexm(subnational, "Urban") // urban
		replace urbanicity_type = 3 if regexm(subnational, "Rural") // rural 
		gen survey_name = "WHO Study on global AGEing and adult health"
		gen age_end = age_start + 4
		egen maxage = max(age_start)
		replace age_end = 100 if age_start == maxage
		drop maxage
		gen questionnaire = "GPAQ"
		gen source_type = "Survey"
		gen data_type = "Survey: other"
		
	//  Fill in year start and end variables 
		generate year_start = .
		generate year_end = .
		replace year_start = 2007 if regexm(iso3, "CHN")
		replace year_end = 2010 if regexm(iso3, "CHN")
		replace year_start = 2009 if regexm(iso3, "MEX")
		replace year_end = 2010 if regexm(iso3, "MEX") 
		replace year_start = 2007 if regexm(iso3, "GHA")
		replace year_end = 2008 if regexm(iso3, "GHA")
		replace year_start = 2007 if regexm(iso3, "IND")
		replace year_end = 2007 if regexm(iso3, "IND")
		replace year_start = 2007 if regexm(iso3, "RUS")
		replace year_end = 2010 if regexm(iso3, "RUS")
		replace year_start = 2007 if regexm(iso3, "ZAF")
		replace year_end = 2008 if regexm(iso3, "ZAF")
		
	// Fill in nids from GHDx
		generate nid = .
		replace nid = 60405 if regexm(iso3, "CHN")
		replace nid = 111486 if regexm(iso3, "MEX")
		replace nid = 111485 if regexm(iso3, "GHA")
		replace nid = 66763 if regexm(iso3, "IND")
		replace nid = 111487 if regexm(iso3, "RUS")
		replace nid = 111488 if regexm(iso3, "ZAF")

// Drop if sample size less than 10 
	drop if sample_size < 10

	// Save survey weighted categorical prevalence estimates	
		save ./prepped/sage_prepped.dta, replace
