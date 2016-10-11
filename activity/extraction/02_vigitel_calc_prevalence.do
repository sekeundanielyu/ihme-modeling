// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 		June 29, 2016
// Project:		RISK
// Purpose:		Extract physical activity data from Brazil's Surveillance System of Risk Factors for Chronic Diseases by Telephone Interviews (VIGITEL)
** *****************************************************************************************************************

// Set preferences for STATA
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

// DESCRIPTION: We don't have a way of quantifying the intensity and time that someone does physical activity through work, so we cannot calculate METs for all the domains. 
// However, there is a question where we can quantify how many people are INACTIVE. So this is what we will extract from Vigitel. 

// In case we use this in the future: 

	// "Sufficient" physical activity during leisure time was based on the following metrics: 
		// At least 30 minutes of light to moderate physical activity for 5 or more days of the week OR at least 20 minutes of vigorous activity for 3 or more days of the week 
	
	// q42: In the past three months, has he or she practiced some type of physical exercise or sport? 
	// q43: What type of physical activity has he or she practiced? 
	// q44: Does he or she practice at least once a week? 
	// q45: How many days per week does he/she practice the sport or exercise? (every day, one or two days a week, three or four days a week, five or 5 days a week)
	// q46: On days when he/she practices this sport, how long does the activity last? 
	
	// q50: Does he/she walk or bike from their house to work? 
	// q51: How much time does it take to go to work? 


// arguments
	local city "`1'"
	
// add logs
	log using "/snfs3/WORK/05_risk/temp/explore/physical_activity/exposure/logs/log_`city'.smcl", replace 
	
	di "`city'"

// Set locals
	local vigitel "$j/DATA/BRA/SURVEILLANCE_SYSTEM_OF_RISK_FACTORS_FOR_CHRONIC_DISEASES_BY_TELEPHONE_INTERVIEWS_VIGITEL" 
	local years 2006 2007 2008 2009 2010 2011 2012
	
	tempfile all 
	save `all', emptyok
	
// Bring in all of the years of VIGITEL data 
	foreach year of local years {
	di "`year'" 
	
	use "`vigitel'/`year'/BRA_VIGITEL_`year'_Y2014M09D23.DTA", clear 
	gen year = `year' 
	
	append using `all', force
	save `all', replace
	
	}
	
// Keep relevant variables
	keep year ordem replica pesorake cidade q6 q7 q42 q43 q44 q45 q46 q50 q51 q53 q54 
	rename q6 age
	rename q7 sex 
	rename cidade city 
	rename q42 inactive
	rename q43 activity_type
	rename q44 once_week
	rename q45 frequency
	rename q46 duration 
	rename q50 work_transport
	rename q51 time_work
	rename q53 school_transport 
	rename q54 time_school
	rename pesorake pweight 
	rename year year_start 
	gen year_end = year_start
	tostring year_start, replace
	gen file = "J:/DATA/BRA/SURVEILLANCE_SYSTEM_OF_RISK_FACTORS_FOR_CHRONIC_DISEASES_BY_TELEPHONE_INTERVIEWS_VIGITEL/" + year_start
	destring year_start, replace

	decode city, gen(cities) 
	drop city 
	rename cities city 

	replace city = subinstr(city, " ", "_", .)

	tempfile all_years
	save `all_years', replace

// Only calculate prevalence for age > 25 
	drop if age < 25 | age == .
	egen age_start = cut(age), at(25(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .	
	levelsof age_start, local(ages)

// Recode variable of interest (whether they exercised physically or played a sport in the last 3 months) 
	
	decode inactive, gen(inactive_new) 
	replace inactive_new = "1" if regexm(inactive_new, "n")
	replace inactive_new = "0" if inactive_new == "sim" 
	drop inactive 
	rename inactive_new inactive
	destring inactive, replace

// Set survey weights	
	svyset [pweight=pweight], strata(city)

// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category 
	mata 
		file = J(1,1,"todrop")
		city = J(1,1,"todrop") 
		year_start = J(1,1,999)
		age_start = J(1,1,999)
		sex = J(1,1,999)
		sample_size = J(1,1,999)
		inactive_mean = J(1,1,999)
		inactive_se = J(1,1,999)
	end


	levelsof year_start, local(years)
	levelsof sex, local(sexes) 
	levelsof age_start, local(ages)

	tempfile all 
	save `all', replace

	// Compute prevalence

	di in red "`city'"

		foreach year of local years {
			foreach sex of local sexes {	
				foreach age of local ages {

					use `all', clear 
					//keep if city == "`city'" 

					di in red "City: `city' Year: `year'  Age: `age' Sex: `sex'"
					count if city == "`city'" & year_start == `year' & age_start == `age' & sex == `sex'
					if r(N) != 0 {

						// Calculate mean and standard error for inactive category
								svy linearized, subpop(if city == "`city'" & year_start == `year' & age_start == `age' & sex == `sex'): mean inactive
								
								matrix inactive_meanmatrix = e(b)
								local inactive_mean = inactive_meanmatrix[1,1]
								mata: inactive_mean = inactive_mean \ `inactive_mean'
								
								matrix inactive_variancematrix = e(V)
								local inactive_se = sqrt(inactive_variancematrix[1,1])
								mata: inactive_se = inactive_se \ `inactive_se'
							}
						
						// Extract other key variables	
							mata: city = city \ "`city'"
							mata: year_start = year_start \ `year'
							mata: age_start = age_start \ `age'
							mata: sex = sex \ `sex'
							mata: sample_size = sample_size \ `e(N_sub)'
				}
			}
		}
					

// Get stored prevalence calculations from matrix
	clear

	getmata city year_start age_start sex sample_size file inactive_mean inactive_se 

	drop if _n == 1 // drop top row which was a placehcolder for the matrix created to store results	

// Replace standard error as missing if its zero (so that dismod calculates error using the sample size instead)
	recode *_se (0 = .)

// Create variables that are always tracked	
		gen modelable_entity_id = 2445
		gen modelable_entity_name = "Physical inactivity and low physical activity, inactive" 
		generate year_end = year_start
		generate age_end = age_start + 4
		egen maxage = max(age_start)
		replace age_end = 100 if age_start == maxage
		drop maxage
		gen survey_name = "VIGITEL" 
		gen iso3 = "BRA" 
		gen questionnaire = "other"

		// NIDS 
		gen nid = . 
		replace nid = 141156 if year_start == 2012
		replace nid = 130978 if year_start == 2011
		replace nid = 130973 if year_start == 2010
		replace nid = 130972 if year_start == 2009
		replace nid = 130971 if year_start == 2008 
		replace nid = 111877 if year_start == 2007 
		replace nid = 111878 if year_start == 2006

//  Organize
		order city year_start year_end sex age_start age_end sample_size inactive*, first
		sort sex age_start age_end		
		
	// Save survey weighted prevalence estimates 
		save "/snfs3/WORK/05_risk/temp/explore/physical_activity/exposure/vigitel_`city'.dta", replace

	
	
	
