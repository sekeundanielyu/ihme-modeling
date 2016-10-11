// Date: November, 2013
// Purpose: Extract physical activity data from NHANES and compute  physical activity prevalence in 5 year age-sex groups for each year

// Notes: For years 2007 and beyond NHANES uses GPAQ, earlier years are more inconsistent

// Set up
	clear all
	set more off
	set mem 2g
	capture log close
	capture restore not
	
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	
	else if c(os) == "Windows" {
		global j "J:"
	}
	
	
// Create locals for relevant files and folders
	cd "$j/WORK/05_risk/risks/activity/data/exp"
	local count 0 // local to count loop iterations and save each year as numbered tempfiles to be appended later
	local calc_prevalence = 1 // "1" turns on subgroup categorical prevalence calculations
	
** *********************************************************************
** 1.) Clean and Compile 
** *********************************************************************	
// Use NHANES file that has compiled data for all years to present (compiled by nhanes_compile.do)
	use ./raw/nhanes_compiled_revised.dta, clear
	destring year*, replace
	drop if age < 25 | age == .  // only care about respondents 25 and above for physical inactivity risk
			
	levelsof year_start, local(years)
	foreach year of local years {
			preserve
			keep if year_start == `year'
			di in red `year'
		
		// 1988 is different than all following years so will clean it separately.  Asks about a ton of recreational activities, has frequency and intensity, but no measure of duration)
		if `year' == 1988 {	
			forvalues x = 2(2)16 {
				local z = `x' + 1
				rename hat`z's hat`x's
				
				recode hat`x'met hat`x's  (.=0) if hat`x' == 2
				replace hat`x's = hat`x's / 4 // times per month --> avg times per week
				gen hat`x'_mets = hat`x'met * hat`x's	
			}
				
				recode hat1met (.=0) if hat1s == 0 
				replace hat1s = hat1s / 4 // times per month --> avg times per week
				gen hat1_mets = hat1met * hat1s
				
				egen total_mets = rowtotal(*_mets)
		}
		
		// 1999-2007 are all similar
		if `year' > 1988 & `year' < 2007 {
			// Rename variables for clarity and consistency
				rename pad020 trans
				rename paq050q trans_times
				rename paq050u trans_units
				rename pad080 trans_min
				
				rename paq100 domestic
				rename pad120 domestic_times
				rename pad160 domestic_min
				
				rename pad440 muscle_strength
				rename pad460 muscle_strength_time
				
				rename paq180 avg_activity
				rename pad200 vig_activity
				rename pad320 mod_activity
				
			// Clean variables (asks about recreational activities, transport and domestic activities)
				recode vig_activity mod_activity (7 9 = .) (3 = 0)
				
				recode trans_times trans_units trans_min (.=0) if trans == 2
				gen trans_pw = trans_times * 7 if trans_units == 1 // times per day --> avg times per week
				replace trans_pw = trans_times / 4 if trans_units == 3 // times per month --> avg times per week
				replace trans_pw = trans_times if trans_units == 2 // times per week 
				replace trans_pw = 0 if trans == 2
				gen trans_total = trans_pw * trans_min
				gen trans_mets = trans_total * 4
				
				recode domestic_times domestic_min (.=0) if domestic == 2
				replace domestic_times = domestic_times / 4 // times per month --> avg times per week
				gen domestic_total = domestic_min * domestic_times
				gen domestic_mets = domestic_total * 4
				
			// Recreational MET-min/week
				replace padtimes = padtimes / 4
				gen rec_min = padtimes * paddurat 
				gen pa_mets = rec_min * padmets 
				bysort seqn: egen rec_mets = total(pa_mets)
				duplicates drop year_start seqn rec_mets, force	
						
			// Specify domains included in total_mets figure
				gen gpaq = 1
				gen work = 1
				gen rec = 1
				gen walk = 1
				drop domestic
				gen domestic = 1
		}		
		
		// 2007 and beyond uses GPAQ
			if `year' >= 2007 {
				// Rename variables for the loop below (makes summing accross time, activity levels and activity domains easier)
					rename paq605 work_vig
					rename paq610 work_vig_days
					rename pad615 work_vig_min
					rename paq620 work_mod
					rename paq625 work_mod_days
					rename pad630 work_mod_min
					rename paq635 trans
					rename paq640 trans_days
					rename pad645 trans_min
					rename paq650 rec_vig
					rename paq655 rec_vig_days
					rename pad660 rec_vig_min
					rename paq665 rec_mod
					rename paq670 rec_mod_days
					rename pad675 rec_mod_min
					
				// Loop through each domain and activity levels and estimate total minutes per week of activity in each domain-level
					// Transport domain only has moderate level so I will deal with it separately from work and recreational
						foreach domain in trans work rec {
							if "`domain'" == "trans" {
							di "`domain'"
								recode `domain'_days `domain'_min (. = 0) if `domain' == 2 // make days and minutes 0 if respondent does not perform transport activity
								recode `domain'_days  (77 99 =.) // don't know and refusals as missing
								recode `domain'_min (9999 7777 = .) // don't know and refusals as missing
								replace `domain'_days = . if `domain'_days > 7 // not more than 7 days/week
								replace `domain'_min = 0 if `domain'_min < 10 // less than 10 min a domain should not count according to GPAQ guidelines
								drop if `domain'_min > 960 & `domain'_min != . // GPAQ cleaning guidelines say to drop cases where the total minutes of activity per day of a subdomain alone is > 16 hours
								gen `domain'_total = `domain'_min * `domain'_days // calculate total minutes/week
							}
							
							if "`domain'" == "work" | "`domain'" == "rec" {
								foreach level in vig mod {
								di "`domain'_`level'"
									recode `domain'_`level'_days `domain'_`level'_min (. = 0) if `domain'_`level' == 2 // make days and minutes 0 if respondent does not perform activity in subdomain
									recode `domain'_`level'_days  (77 99 =.) // don't know and refusals as missing
									recode `domain'_`level'_min (9999 7777 = .) // don't know and refusals as missing
									replace `domain'_`level'_days = . if `domain'_`level'_days > 7 // not more than 7 days/week
									replace `domain'_`level'_min = 0 if `domain'_`level'_min < 10 // less than 10 min a domain should not count according to GPAQ guidelines
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
					replace total_mets = . if total_hrs > 16
					drop pa*
					
				// Specify domains included in total_mets figure
					gen gpaq = 1
					gen work = 1
					gen rec = 1
					gen walk = 1
					gen domestic = 1
			}
			
		tempfile nhanes`count'
		save `nhanes`count'', replace
		local count = `count' + 1
		restore
	}
	
// Append all years together
	use `nhanes0', clear
	local max = `count' - 1
	forvalues x = 1/`max' {
		append using `nhanes`x''
	}

// Make variables and variable names consistent with other sources 
	label define sex 1 "Male" 2 "Female"
	label values sex sex
	gen survey_name = "National Health and Nutrition Examination Survey"
	gen questionnaire = "GPAQ" if gpaq == 1
	gen iso3 = "USA"
	keep sex age psu strata wt year_start year_end total_mets rec_mets trans_mets work_mets domestic_mets vig_activity mod_activity gpaq survey_name iso3 hh_income general_health race_1 questionnaire file
	
// Save clean and compiled raw dataset	
	save ./raw/nhanes_clean_revised.dta, replace	
	
** *******************************************************************************************
** 2.) Calculate Prevalence in each year/age/sex subgroup and save compiled/prepped dataset
** *******************************************************************************************	
// Deal with years that use GPAQ first (2007-2011)
	preserve
	keep if year_start >= 2007 
	
	// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category (inactive, moderately active and highly active)
		mata 
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
		svyset psu [pweight=wt], strata(strata)
					
	//  Compute prevalence
		levelsof year_start, local(years)
		
		foreach year of local years {
			foreach sex in 1 2 {
				foreach age of local ages {
					
					di in red  "year:`year' sex:`sex' age:`age'"
					count if year_start == `year' & age_start == `age' & sex == `sex'
					if r(N) != 0 {
						// Calculate mean and standard error for each activity category	
							foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
								svy linearized, subpop(if year_start == `year' & age_start == `age' & sex == `sex'): mean `category'
								
								matrix `category'_meanmatrix = e(b)
								local `category'_mean = `category'_meanmatrix[1,1]
								mata: `category'_mean = `category'_mean \ ``category'_mean'
								
								matrix `category'_variancematrix = e(V)
								local `category'_se = sqrt(`category'_variancematrix[1,1])
								mata: `category'_se = `category'_se \ ``category'_se'
							}
			
						// Extract other key variables	
							mata: year_start = year_start \ `year'
							mata: sex = sex \ `sex'
							mata: age_start = age_start \ `age'
							mata: sample_size = sample_size \ `e(N_sub)'
							levelsof file if year_start == `year' & age_start == `age' & sex == `sex', local(file) clean
							mata: file = file \ "`file'"
					}
				}
			}
		}

	// Get stored prevalence calculations from matrix
		clear
		getmata year_start age_start sex sample_size file highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se lowmodhighactive_mean lowmodhighactive_se modhighactive_mean modhighactive_se
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
	
	// Create variables that are always tracked		
		generate year_end = year_start + 1
		generate age_end = age_start + 4
		egen maxage = max(age_start)
		replace age_end = 100 if age_start == maxage
		drop maxage
		gen national_type =  1 // nationally representative
		gen urbanicity_type = 1 // representative
		gen survey_name = "National Health and Nutrition Examination Survey"
		gen iso3 = "USA"
		gen questionnaire = "GPAQ"
		gen source_type = "Survey"
		gen data_type = "Survey: other"

	// Replace standard error as missing if its zero (so that dismod calculates error using the sample size instead)
		recode *_se (0 = .)
	
	//  Organize
		sort sex age_start age_end		
	
	// Save survey weighted prevalence estimates 
		save "./prepped/nhanes_prepped.dta", replace	
	
	restore
