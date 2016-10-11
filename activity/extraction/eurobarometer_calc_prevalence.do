// Date: November 15, 2013
// Purpose:  Extract physical activity data from eurobarometer and compute survey weighted physical activity prevalence in age-sex subgroups for each country-year

// Notes: Eurobarometer 64_3 (2005) and 58_2 (2002) are the only two years with IPAQ questions.  2009 has recreational only.	 2002 and 2005 years ask in the last 7 days, how much physical activity did you get ...(A lot, some little, none, DK) At work, When moving from place to place, Work in and around your house (including housework gardening, general maintenance, or caring for your family, For recreation, sport and leisure time activities), Time spent sitting

// Set up: 
	clear all
	set mem 700m
	set maxvar 30000
	set more off
	capture restore not
	cap log close
	
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
		set mem 3g
	}
	else if c(os) == "Windows" {
		global j "J:"
		set mem 800m
	}
	
	
// Set directory, make locals for relevant files and folders, use csv with variable names/definitions
	cd "$j/WORK/05_risk/risks/activity/data/exp"
	
// Prepare countrycodes database for merge later
	local codes_folder "$j/Usable/Common Indicators/Country Codes"
	use "`codes_folder'/countrycodes_official.dta", clear
	keep if countryname == countryname_ihme
	drop if iso3 == ""
	tempfile countrycodes
	save `countrycodes', replace
	
// Get variable names for survey processing
	insheet using "./raw/eurobarometer_varlist.csv", names clear
	mata: datasets = st_sdata(.,("country", "start_year", "filepath", "pweight_uk", "pweight_germ", "pweight", "sex", "age", "vig_days", "vig_time", "mod_days", "mod_time", "walk_days", "walk_time", "workact", "occupation"))

	local num_surveys = _N

// This loop will run through all of the data files for this country-gender.  Begin by making stata locals from the mata vector datasets.			
	local counter = 1
		forvalues filenum=1(1)`num_surveys' {
				mata: st_local ("country", datasets[`filenum', 1])
				mata: st_local ("start_year", datasets[`filenum', 2])
				mata: st_local ("filepath", datasets[`filenum', 3])
				mata: st_local ("pweight_uk", datasets[`filenum', 4])
				mata: st_local ("pweight_germ", datasets[`filenum', 5])
				mata: st_local ("pweight", datasets[`filenum', 6])
				mata: st_local ("sex", datasets [`filenum', 7])
				mata: st_local ("age", datasets [`filenum', 8])
				mata: st_local ("vig_days", datasets [`filenum', 9])
				mata: st_local ("vig_time", datasets [`filenum', 10]) 
				mata: st_local ("mod_days", datasets [`filenum', 11])
				mata: st_local ("mod_time", datasets [`filenum', 12])
				mata: st_local ("walk_days", datasets [`filenum', 13])
				mata: st_local ("walk_time", datasets [`filenum', 14])
				mata: st_local ("workact", datasets [`filenum', 15])
				mata: st_local ("occupation", datasets [`filenum', 16])
			
			display in red _newline _newline "filename: `filepath'"

			// Use the file referenced by filename.
				use "`filepath'", clear 
			
			// Only estimate physical inactivity for ages 25+
				drop if `age' < 25 | `age' == .
			
			// Generate variables that we want to keep track of
				gen file = "`filepath'"
				
				gen year_start = "`start_year'"
				replace year_start = substr(year_start, 2,4)
				destring year_start, replace
				
				generate sex = `sex'
				generate age = `age'
				
			//  Construct dummy variable for whether respondent had "a lot" of work activity
				decode `workact', gen(workact)
				decode `occupation', gen(occupation)
				replace workact = "Little or none" if workact == "None" | workact == "Little" 
				replace workact = "Little or none" if workact == "" & regexm(occupation, "Retired") | regexm(occupation, "Unemployed") | regexm(occupation, "not working") | regexm(occupation, "ordinary shopping") | regexm(occupation, "Student")
				encode workact, gen(work_activity)
				gen workactive = 1 if work_activity == 1
				replace workactive = 0 if work_activity == 2 | work_activity == 3
					
			// generate iso3 var
				decode `country', g(country_name)
				g iso3 = ""
				replace iso3 = "FRA" if country_name== "FRANCE" | country_name == "France"
				replace iso3 = "BEL" if country_name == "BELGIUM" | country_name == "Belgium"
				replace iso3 = "NLD" if country_name == "NETHERLANDS" | country_name == "Netherlands" | country_name == "The Netherlands"
				replace iso3 = "DEU" if country_name == "GERMANY" | country_name  == "Germany" | country_name == "EAST GERMANY" | country_name == "WEST GERMANY" | country_name == "Germany - West" | country_name == "Germany - East" | country_name == "Germany (West+East)" | country_name == "Germany West" | country_name == "Germany East" | country_name == "GERMANY WEST" | country_name == "GERMANY EAST"
				replace iso3 = "ITA" if country_name == "ITALY" | country_name == "Italy"
				replace iso3 = "LUX" if country_name == "LUXEMBOURG" | country_name == "Luxembourg"
				replace iso3 = "DNK" if country_name == "DENMARK" | country_name == "Denmark"
				replace iso3 = "IRL" if country_name == "IRELAND" | country_name == "Ireland"
				replace iso3 = "GBR" if country_name == "UNITED KINGDOM" | country_name == "United Kingdom" | country_name == "Great Britain" | country_name == "Northern Ireland" | country_name == "GREAT BRITAIN" | country_name == "NORTHERN IRELAND"
				replace iso3 = "GRC" if country_name == "GREECE" | country_name == "Greece"
				replace iso3 = "ESP" if country_name == "SPAIN" | country_name == "Spain"
				replace iso3 = "PRT" if country_name == "PORTUGAL" | country_name == "Portugal"
				replace iso3 = "NOR" if country_name == "NORWAY" | country_name == "Norway"
				replace iso3 = "FIN" if country_name == "FINLAND" | country_name == "Finland"
				replace iso3 = "SWE" if country_name == "SWEDEN" | country_name == "Sweden"
				replace iso3 = "AUT" if country_name == "AUSTRIA" | country_name == "Austria"
				replace iso3 = "BGR" if country_name == "BULGARIA" | country_name == "Bulgaria"
				replace iso3 = "CYP" if country_name == "Cyprus (Republic)" | country_name == "Cyprus (TCC)" | country_name == "CYPRUS (REPUBLIC)" | country_name == "CYPRUS TCC"
				replace iso3 = "CZE" if country_name == "Czech Republic" | country_name == "CZECH REPUBLIC"
				replace iso3 = "EST" if country_name == "Estonia"  | country_name == "ESTONIA"
				replace iso3 = "HUN" if country_name == "Hungary" | country_name == "HUNGARY"
				replace iso3 = "LVA" if country_name == "Latvia" | country_name == "LATVIA"
				replace iso3 = "LTU" if country_name == "Lithuania" | country_name == "LITUANIA"
				replace iso3 = "MLT" if country_name == "Malta" | country_name == "MALTA"
				replace iso3 = "POL" if country_name == "Poland" | country_name == "POLAND"
				replace iso3 = "ROU" if country_name == "Romania" | country_name == "ROMANIA"
				replace iso3 = "SVK" if country_name == "Slovakia" | country_name == "SLOVAKIA"
				replace iso3 = "SVN" if country_name == "Slovenia" | country_name == "SLOVENIA"
				replace iso3 = "TUR" if country_name == "Turkey" | country_name == "TURKEY"
				replace iso3 = "HRV" if country_name == "Croatia" | country_name == "CROATIA"
				replace iso3 = "MKD" if country_name == "MAKEDONIA"

		// Fix the weights that are split by britain/germany subregions
			g pweight = .
			if "`pweight_uk'" != "" {  
				replace pweight = `pweight'
				replace pweight = `pweight_uk' if iso3 == "GBR"
				replace pweight = `pweight_germ' if iso3 == "DEU"
			}
			if "`pweight_uk'" == "" {  
				replace pweight = `pweight'
			}
			if "`pweight_nor'" != "" {
				replace pweight = `pweight_nor' if iso3 == "NOR"
			}


		// Cleaning loop: Internal consistency checks and calculating total minutes of physical activity performed at each level per week
			foreach level in vig mod walk {
				gen `level'_days = ``level'_days'
				gen `level'_time = ``level'_time'
				replace `level'_days = . if `level'_days > 7 | `level'_days < 0 // not more than 7 days per week
				
				// For 2005 year duration is in terms of hours and minutes (i.e. 230 would be 2 hours and 30 minutes)
				if year_start == 2005 {
					tostring `level'_time, replace
					gen `level'_hrs = substr(`level'_time, -3, 1) // Get number of hours 
					gen `level'_min = substr(`level'_time, -2, 2) // Get number of minutes
					destring `level'_min `level'_hrs `level'_time, replace
					replace `level'_hrs = `level'_hrs * 60
					egen `level'_sum = rowtotal(`level'_min `level'_hrs)
					replace `level'_sum = 0 if `level'_sum < 10 | `level'_days == 0 // less than 10 min/day in a domain should not count according to IPAQ guidelines
					gen `level'_total = `level'_sum * `level'_days
					recode `level'_total (0=.) if `level'_days == . | `level'_time == .
				}
				// For 2002 year duration is in minutes
				else {	
					replace `level'_time = 0 if `level'_time < 10 // less than 10 min in a domain should not count according to IPAQ guidelines
					replace `level'_time = 0 if `level'_days == 0 
					replace `level'_time = . if `level'_days != . & (`level'_time == .a | `level'_time == .b) // need to drop respondents who report vigorous activity, but average time per day is missing
					gen `level'_total = `level'_time * `level'_days
				}	
			}
						
		// Calculate total mets from each activity level and the total across all levels combined
			gen mod_mets = mod_total * 4
			gen vig_mets = vig_total * 8
			gen walk_mets = walk_total * 3.3
			egen total_mets = rowtotal(vig_mets mod_mets walk_mets)
			egen total_miss = rowmiss(vig_mets mod_mets walk_mets)
			replace total_mets = . if total_miss == 3 // should only exclude respondents with missing values in all PA levels, so as long as at least one level has valid answers and all others are missing, we will assume no activity in other domains
		
		// Check to make sure total reported activity time is plausible	
			egen total_time = rowtotal(vig_total  mod_total walk_total)
			replace total_mets = . if total_time > 6720 // Shouldn't be more than 6720 minutes (assume no more than 16 active waking hours per day on average)
			drop total_time	

		// Make variables and variable names consistent with other sources
			label define sex 1 "Male" 2 "Female"
			label values sex sex
			gen survey_name = "Eurobarometer"
			gen questionnaire = "IPAQ"
			gen year_end = year_start
			
		// Tempfile the data
			tempfile curr`counter'
			save `curr`counter'', replace 
			local counter = `counter' + 1
	}	
	
// Append all data	
	clear
	local max = `counter' -1
	use `curr1', clear
	forvalues x = 2/`max' {
		append using `curr`x''
	}

	
// Clean up
	drop if total_mets == .
	keep sex age total_mets iso3 year_start year_end questionnaire survey_name file pweight workactive
	
// Save compiled raw dataset	
	save "./raw/eurobarometer_clean.dta", replace
	
// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category 
	mata 
		iso3 = J(1,1,"todrop")
		file = J(1,1,"todrop")
		year_start = J(1,1,999)
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
		workactive_mean = J(1,1,999)
		workactive_se = J(1,1,999)
	end
		
// Set age groups
	egen age_start = cut(age), at(25(10)120)
	replace age_start = 75 if age_start > 75 & age_start != .	
	
// Make categorical physical activity variables
	drop if total_mets == .
	gen inactive = total_mets < 600
	gen lowactive = total_mets >= 600 & total_mets < 4000
	gen lowmodhighactive = total_mets >= 600
	gen modactive = total_mets >= 4000 & total_mets < 8000
	gen modhighactive = total_mets >= 4000 
	gen highactive = total_mets >= 8000 
	
// Set survey weights
	svyset _n [pweight=pweight]
				
//  Loop through sexes and ages and calculate smoking prevalence using survey weights
	levelsof iso3, local(countries) clean
	levelsof year_start, local(years)
	levelsof age_start, local(ages)
	
	foreach year of local years {
		local file file
		foreach country of local countries {
			foreach sex in 1 2 {
				foreach age of local ages {
					
					di in red  "year:`year' country:`country' sex:`sex' age:`age'"
					count if year_start == `year' & iso3 == "`country'" & age_start == `age' & sex == `sex'
					if r(N) != 0 {
						// Calculate mean and standard error for each activity category	
							foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive  {
								svy linearized, subpop(if year_start == `year' & iso3 == "`country'" & age_start == `age' & sex == `sex'): mean `category'
								
								matrix `category'_meanmatrix = e(b)
								local `category'_mean = `category'_meanmatrix[1,1]
								mata: `category'_mean = `category'_mean \ ``category'_mean'
								
								matrix `category'_variancematrix = e(V)
								local `category'_se = sqrt(`category'_variancematrix[1,1])
								mata: `category'_se = `category'_se \ ``category'_se'
							}
							
						// Calculate mean and standard error for work activity level
							svy linearized, subpop(if year_start == `year' & iso3 == "`country'" & age_start == `age' & sex == `sex'): mean workactive
								matrix meanmatrix = e(b)
								local mean = meanmatrix[1,1]
								mata: workactive_mean = workactive_mean \ `mean'
								
								matrix variancematrix = e(V)
								local se = sqrt(variancematrix[1,1])
								mata: workactive_se = workactive_se \ `se'
			
						// Extract other key variables	
							mata: iso3 = iso3 \ "`country'"
							mata: year_start = year_start \ `year'
							mata: sex = sex \ `sex'
							mata: age_start = age_start \ `age'
							mata: sample_size = sample_size \ `e(N_sub)'
							levelsof file if year_start == `year' & iso3 == "`country'" & age_start == `age' & sex == `sex', local(file) clean
							mata: file = file \ "`file'"
					}
				}
			}
		}
	
	}	
	
// Get stored prevalence calculations from matrix
	clear

	getmata iso3 year_start age_start sex sample_size file highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se lowmodhighactive_mean lowmodhighactive_se modhighactive_mean modhighactive_se workactive_mean workactive_se
	drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
	
// Replace standard error as missing if its zero
	recode *_se (0 = .)
	
// Create variables that are always tracked		
	generate year_end = year_start	
	generate age_end = age_start + 9
	egen maxage = max(age_start)
	replace age_end = 100 if age_start == maxage
	drop maxage
	gen national_type =  1 // nationally representative
	gen urbanicity_type = 1 // representative
	gen survey_name = "Eurobarometer"
	gen questionnaire = "IPAQ" 
	gen source_type = "Survey"
	gen data_type = "Survey: other"
	tostring year_start, replace
	replace file = "J:/DATA/EUROPEAN_COMMISSION_EUROBAROMETER/" + iso3 + "/" + year_start + "/" + iso3 + "_EUROBAROMETER_2002_STANDARD_NO_58_2.DTA" if year_start == "2002" 
	replace file = "J:/DATA/EUROPEAN_COMMISSION_EUROBAROMETER/" + iso3 + "/" + year_start + "/" + iso3 + "_EUROBAROMETER_2005_STANDARD_NO_64_3.DTA" if year_start == "2005"
	destring year_start, replace
	
//  Organize
	sort iso3 sex age_start age_end	
	
// Save survey weighted prevalence estimates 
	save "./prepped/eurobarometer_prepped.dta", replace
	
