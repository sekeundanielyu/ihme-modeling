// Date: March 3, 2013
// Purpose: Extract physical activity data from the Northern Ireland Health Survey and compute survey weighted physical activity prevalence in 5 year age-sex groups for each year

// NOTES: This survey uses the short form of the IPAQ.  I could not find sampling weights.  

// Set up
	clear all
	set more off
	set mem 2g
	capture log close
	
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	
	else if c(os) == "Windows" {
		global j "J:"
	}
		
	
// Create locals for relevant files and folders
	local outdir "$j/WORK/05_risk/risks/activity/data/exp"
	local year_list : dir "$j/DATA/GBR/NORTHERN_IRELAND_HEALTH_SURVEY" dirs "*", respectcase
	local count 0 // local to count loop iterations and save each year as numbered tempfiles to be appended later
	
** *********************************************************************
** 1.) Clean and Compile 
** *********************************************************************		
// Loop through year directories and identify outliers, translate minutes of PA into mets, and calculate prevalence estimates
	foreach year of local year_list { 
		if "`year'" != "CRUDE" & "`year'" != "1997" {
		local files : dir "$j/DATA/GBR/NORTHERN_IRELAND_HEALTH_SURVEY/`year'" files "*.DTA", respectcase
			foreach file of local files {	
				if !regexm("`file'", "CHILD") {
					use "$j/DATA/GBR/NORTHERN_IRELAND_HEALTH_SURVEY/`year'/`file'", clear
					renvars, lower
					gen year = "`year'"
					gen file = "$j/DATA/GBR/NORTHERN_IRELAND_HEALTH_SURVEY/`year'/`file'"
					keep sex *age* phy* hard* mod* walk* year file
				
					local count = `count' + 1
					tempfile data_`count'
					save `data_`count''
				}
			}
		}
	}
	
// Append all years to make one master dataset
	use `data_1', clear
	forvalues x = 2/`count' {
		append using `data_`x'', force
	}
	
// Make age groups (only make physical activity estimates for age 25+)
	egen age_start = cut(age), at(25(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	
	// 2010-2011 survey year uses respondent age groups instead of actual age
	decode phirbage, gen(agegrp)
	split agegrp, parse("-") gen(age)
	replace age1 = "80" if age1 == "85+"
	destring age1 age2, replace
	replace age_start = age1 if age_start == .
	drop if age < 25 | age_start == . | age_start < 25
	levelsof age_start, local(ages)
	
// Calculate total minutes of moderate, vigorous and walking activity per week
	foreach level in mod hard walk {
		// Recode refusals & don't knows to missing
			recode `level'days (8 9 = .) 
			recode `level'min (999 9999 = .)
			replace `level'min = 0 if `level'min < 10 // According to IPAQ analysis guidelines, less than 10 min of sustained activity does not count
			gen `level'_total = `level'days * `level'min 
	}
	
// Calculate total mets from each activity level and the total across all levels combined
	gen mod_mets = mod_total * 4
	gen vig_mets = hard_total * 8
	gen walk_mets = walk_total * 3.3
	egen total_mets = rowtotal(vig_mets mod_mets walk_mets)
	egen total_miss = rowmiss(vig_mets mod_mets walk_mets)
	replace total_mets = . if total_miss == 3 // should only exclude respondents with missing values in all PA levels, so as long as at least one level has valid answers and all others are missing, we will assume no activity in other domains
	
// Check to make sure total reported activity time is plausible	
	egen total_time = rowtotal(hard_total  mod_total walk_total) // Shouldn't be more than 6720 minutes (assume no more than 16 active waking hours per day on average)
	replace total_mets = . if total_time > 6720
	drop total_time

// Make variables and variable names consistent with other sources 
	gen survey_name = "Northern Ireland Health Survey"
	gen questionnaire = "IPAQ" 
	gen iso3 = "XNI" // Northern Ireland code
	split year, parse("_") gen(year)
	gen year_start = year1
	gen year_end = year2
	replace year_end = year_start if year_end == ""
	destring year_start year_end, replace
	generate age_end = age_start + 4
	keep sex age_start age_end year year_start year_end total_mets survey_name iso3 questionnaire file
	
// Save clean and compiled raw dataset	
	save "`outdir'/raw/nihs_clean.dta", replace	

** *******************************************************************************************
** 2.) Calculate Prevalence in each year/age/sex subgroup and save compiled/prepped dataset
** *******************************************************************************************	
// Make categorical physical activity variables
	drop if total_mets == .
	gen inactive = total_mets < 600
	gen lowactive = total_mets >= 600 & total_mets < 4000
	gen lowmodhighactive = total_mets >= 600
	gen modactive = total_mets >= 4000 & total_mets < 8000
	gen modhighactive = total_mets >= 4000 
	gen highactive = total_mets >= 8000 
	
// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category
	mata 
		year = J(1,1,"todrop")
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
	
//  Compute prevalence
	levelsof year, local(years)
	foreach year of local years {
		foreach sex in 1 2 {
			foreach age of local ages {
				
				di in red  "year:`year' sex:`sex' age:`age'"
					// Calculate mean and standard error for each activity category	
						foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
							mean `category' if year == "`year'" & age_start == `age' & sex == `sex'
							
							matrix `category'_matrix = r(table)
							local `category'_mean = `category'_matrix[1,1]
							mata: `category'_mean = `category'_mean \ ``category'_mean'
							
							local `category'_se = `category'_matrix[2,1]
							mata: `category'_se = `category'_se \ ``category'_se'
						}
		
					// Extract other key variables	
						count if year == "`year'" & age_start == `age' & sex == `sex'
						mata: sample_size = sample_size \ `r(N)'
						mata: year = year \ "`year'"
						mata: sex = sex \ `sex'
						mata: age_start = age_start \ `age'
						levelsof file if year == "`year'" & age_start == `age' & sex == `sex', local(file) clean
						mata: file = file \ "`file'"
			}
		}
	}

	// Get stored prevalence calculations from matrix
		clear
		getmata year age_start sex sample_size file highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se lowmodhighactive_mean lowmodhighactive_se modhighactive_mean modhighactive_se
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
	
	// Replace standard error as missing if its zero
		recode *_se (0 = .)
		
	// Create variables that are always tracked		
		split year, parse("_") gen(year)
		gen year_start = year1
		gen year_end = year2
		replace year_end = year_start if year_end == ""
		destring year_start year_end, replace
		generate age_end = age_start + 4
		egen maxage = max(age_start)
		replace age_end = 100 if age_start == maxage
		drop maxage
		gen national_type =  2 // subnationally representative
		gen urbanicity_type = 1 // representative
		gen iso3 = "GBR_433" // Northern Ireland code
		gen questionnaire = "IPAQ"
		gen source_type = "Survey"
		gen data_type = "Survey: other"
	
	//  Organize
		order iso3 year_start year_end sex age_start age_end sample_size highactive* modactive* inactive*, first
		sort sex age_start age_end		
	
	// Save survey weighted prevalence estimates 
		save "`outdir'/prepped/nihs_prepped.dta", replace
