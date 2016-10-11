// DATE: JANUARY 31, 2013
// PURPOSE: CLEAN AND EXTRACT PHYSICAL ACTIVITY DATA FROM USA NATIONAL HEALTH INTERVVIEW SURVEY, AND COMPUTE PHYSICAL ACTIVITY PREVALENCE IN 5 YEAR AGE-SEX GROUPS FOR EACH YEAR 

// NOTES: PA STARTED TO BE MEASURED IN 1998

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
	local data_dir "$j/WORK/05_risk/risks/activity/data/exp/raw/nhis"
	local outdir "$j/WORK/05_risk/02_models/02_data/physical_inactivity/exp/prepped"
	
// Loop through each year with physical activity
forvalues year = 1998(1)2014 {
	di in red `year'
	use "`data_dir'/samadult_`year'.dta", clear
	keep if age_p >=25 & age_p != .
	foreach domain in vig mod {
		// times per week
			decode (`domain'freqw), gen (`domain'_t_w_decode)
			replace `domain'_t_w_decode = lower(`domain'_t_w_decode)
			gen `domain'_t_w=`domain'freqw

			replace `domain'_t_w = . if regexm(`domain'_t_w_decode,"don't know") | regexm(`domain'_t_w_decode,"dont know") | regexm(`domain'_t_w_decode,"don't know") | regexm(`domain'_t_w_decode,"not ascertained") | regexm(`domain'_t_w_decode,"refused") 
			replace `domain'_t_w = 0 if regexm(`domain'_t_w_decode,"unable") |  regexm(`domain'_t_w_decode,"never")

		// month or year response
			decode `domain'tp, gen(`domain'_month_year_decode)
			replace `domain'_t_w = `domain'no / 4 if regexm(`domain'_month_year_decode,"month")  

			replace `domain'_t_w = `domain'no / 12 / 4 if regexm(`domain'_month_year_decode,"year") 

		// minutes 
			decode (`domain'min), gen (`domain'_min_decode)
			replace `domain'_min_decode = lower(`domain'_min_decode)
			gen `domain'_min=`domain'min


			replace `domain'_min = . if regexm(`domain'_t_w_decode,"don't know") | regexm(`domain'_t_w_decode,"dont know") | regexm(`domain'_t_w_decode,"don't know") | regexm(`domain'_t_w_decode,"not ascertained") | regexm(`domain'_t_w_decode,"refused") 
			replace `domain'_min = 0 if regexm(`domain'_t_w_decode,"unable") |  regexm(`domain'_t_w_decode,"never")
	}

	// total met minutes per week
		gen mod_mets = (mod_t_w * mod_min * 4)
		gen vig_mets = (vig_t_w * vig_min * 8)
		egen total_mets = rowtotal(mod_mets vig_mets)
		egen checkmiss = rowmiss(mod_mets vig_mets)
		replace total_mets = . if checkmiss == 2

	// Standardize survey weight variables 
		lookfor wtfa_
		local weight = r(varlist)
		rename `weight' weight

		lookfor stratum
		local strata = r(varlist)
		rename `strata' strat

		lookfor psu
		local psu = r(varlist)
		rename `psu' primary_sample_unit

	// Fill in variables we want to keep track of
		gen file = "J:/DATA/NATIONAL_HEALTH_INTERVIEW_SURVEY/`year'"
		gen year_start = `year'
		gen year_end = year_start
		label define sexlab 1 "Male" 2 "Female"
		label values sex sexlab
		rename age_p age	
	
	// Clean up and save
		keep sex age total_mets year_start year_end file weight strat primary_sample_unit
		drop if total_mets == .
		tempfile `year'
		save ``year''
}

// Append all years
	use `1998', clear
	forvalues year = 1999/2014 {
		append using ``year''
	}
	
// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category (inactive, moderately active and highly active)
	mata 
		iso3 = J(1,1, "todrop")
		year = J(1,1, 9999)
		age_start = J(1,1,999)
		sex = J(1,1,999)
		sample_size = J(1,1,999)
		file = J(1,1,"todrop")
		inactive_mean = J(1,1,999)
		inactive_se = J(1,1,999)
		lowactive_mean = J(1,1,999)
		lowactive_se = J(1,1,999)
		modactive_mean = J(1,1,999)
		modactive_se = J(1,1,999)
		highactive_mean = J(1,1,999)
		highactive_se = J(1,1,999)
	end
		
// Set age groups
	egen age_start = cut(age), at(25(5)120)
	replace age_start = 80 if age_start > 80
	drop age
	
// Set survey weights
	svyset primary_sample_unit [pweight=weight], strata(strat)
	
// Make categorical physical activity variables
	gen inactive = total_mets < 600
	gen lowactive = total_mets >= 600 & total_mets < 4000
	gen modactive = total_mets >= 4000 & total_mets < 8000
	gen highactive = total_mets >=8000 & total_mets != .
	recode inactive lowactive modactive highactive (0=.) if total_mets == .		
				
//  Loop through sexes and ages and calculate smoking prevalence using survey weights
	levelsof year_start, local(years)
	levelsof age_start, local(ages)
	
	foreach year of local years {
		foreach sex in 1 2 {
			foreach age of local ages {	
				di in red  "year:`year' sex:`sex' age:`age'"
				// Calculate mean and standard error for each activity category	
					foreach category in inactive lowactive modactive highactive {
						svy linearized, subpop(if year_start == `year' & age_start == `age' & sex == `sex'): mean `category'
						
						matrix `category'_meanmatrix = e(b)
						local `category'_mean = `category'_meanmatrix[1,1]
						mata: `category'_mean = `category'_mean \ ``category'_mean'
						
						matrix `category'_variancematrix = e(V)
						local `category'_se = sqrt(`category'_variancematrix[1,1])
						mata: `category'_se = `category'_se \ ``category'_se'
					}
						
				// Extract other key variables	
					mata: year = year \ `year'
					mata: sex = sex \ `sex'
					mata: age_start = age_start \ `age'
					mata: sample_size = sample_size \ `e(N_sub)'
					levelsof file if year_start == `year' & age_start == `age' & sex == `sex', local(file) clean
					mata: file = file \ "`file'"
			}
		}
	}	
	
// Get stored prevalence calculations from matrix
	clear

	getmata year age_start sex sample_size file highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se
	drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
	
// Replace standard error as missing if its zero
	recode inactive_se lowactive_se modactive_se highactive_se (0 = .)
	
// Create variables that are always tracked		
	gen iso3 = "USA"
	rename year year_start
	generate year_end = year_start	
	generate age_end = age_start + 4
	egen maxage = max(age_start)
	replace age_end = 100 if age_start == maxage
	drop maxage
	gen GBD_cause = "physical_inactivity"
	gen national_type_id =  1 // nationally representative
	gen urbanicity_type_id = 1 // representative
	gen survey_name = "National Health Interview Survey"
	gen source = "micro_nhis"
	gen ss_level = "age_sex"
	gen questionnaire = "recreational only"
	
//  Organize
	order iso3 year_start year_end sex age_start age_end sample_size highactive* modactive* lowactive* inactive*, first
	sort iso3 sex age_start age_end	
	
// Save survey weighted prevalence estimates 
	save "`outdir'/nhis_prepped.dta", replace
	
