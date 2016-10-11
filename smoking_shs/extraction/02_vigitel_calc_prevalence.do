// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Extract second-hand smoke data from Brazil's Surveillance System of Risk Factors for Chronic Diseases by Telephone Interviews (VIGITEL)
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


// arguments
	local city "`1'"
	
// add logs
	log using "/share/epi/risk/temp/smoking_shs/logs/log_`city'.smcl", replace 
	
	di "`city'"

// Set locals
	local vigitel "$j/DATA/BRA/SURVEILLANCE_SYSTEM_OF_RISK_FACTORS_FOR_CHRONIC_DISEASES_BY_TELEPHONE_INTERVIEWS_VIGITEL" 
	local years 2008 2009 2010 2011 2012 // 2006 & 2007 don't have SHS data
	
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
	keep q6 q7 year ordem replica pesorake cidade fumante fumocasa fumotrab q66a fumapass
	rename q6 age 
	rename q7 sex 
	rename pesorake pweight 
	rename year year_start 
	rename cidade city
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
	drop if age == .
	egen age_start = cut(age), at(25(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .	
	levelsof age_start, local(ages)

// Recode variable of interest 
	
	// Smoking status 
	drop if fumante == 1 // only non-smokers are considered 

	// Second-hand smoke exposure 
	recode q66a (2= 0) (777=.) (888=.)
	rename fumocasa shs 
	replace shs = q66a if shs == . 


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
		shs_mean = J(1,1,999)
		shs_se = J(1,1,999)
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
								svy linearized, subpop(if city == "`city'" & year_start == `year' & age_start == `age' & sex == `sex'): mean shs
								
								matrix shs_meanmatrix = e(b)
								local shs_mean = shs_meanmatrix[1,1]
								mata: shs_mean = shs_mean \ `shs_mean'
								
								matrix shs_variancematrix = e(V)
								local shs_se = sqrt(shs_variancematrix[1,1])
								mata: shs_se = shs_se \ `shs_se'
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

	getmata city year_start age_start sex sample_size file shs_mean shs_se 

	drop if _n == 1 // drop top row which was a placehcolder for the matrix created to store results	

// Replace standard error as missing if its zero (so that dismod calculates error using the sample size instead)
	recode *_se (0 = .)

// Create variables that are always tracked	
		gen modelable_entity_id = 2512
		gen modelable_entity_name = "Second-hand smoke" 
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

//  Organize
		order city year_start year_end sex age_start age_end sample_size shs*, first
		sort sex age_start age_end		
		

// Save survey weighted prevalence estimates 
	save "/share/epi/risk/temp/smoking_shs/vigitel_`city'.dta", replace

	

