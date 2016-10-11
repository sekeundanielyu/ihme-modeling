// Date: March 3, 2013
// Purpose: Extract physical activity data from the Welsh Health Survey and compute survey weighted physical activity prevalence in 5 year age-sex groups for each year

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
	local outdir "$j/WORK/05_risk/risks/activity/data/exp/prepped"
	local year_list : dir "$j/DATA/GBR/WELSH_HEALTH_SURVEY" dirs "*", respectcase
	local count 0 // local to count loop iterations and save each year as numbered tempfiles to be appended later
	
** *********************************************************************
** 1.) Clean and Compile 
** *********************************************************************		
// Loop through year directories and identify outliers, translate minutes of PA into mets, and calculate prevalence estimates
	foreach year of local year_list { 

		if "`year'" != "CRUDE" & "`year'" != "1998" {
		local files : dir "$j/DATA/GBR/WELSH_HEALTH_SURVEY/`year'" files "*ADULT*.DTA", respectcase
			foreach file of local files {	
					use "$j/DATA/GBR/WELSH_HEALTH_SURVEY/`year'/`file'", clear
					gen year = "`year'"
					gen file = "$j/DATA/GBR/WELSH_HEALTH_SURVEY/`year'/`file'"
					keep sex age5yrm exercise exergrp exerv exerm year file *wt*
				}
			}

		if "`year'" == "2013" { 
			// local files: dir "$j/DATA/GBR/WELSH_HEALTH_SURVEY/`year'" files "*AGES_16_ABOVE*.DTA", respectcase
			use "$j/DATA/GBR/WELSH_HEALTH_SURVEY/2013/GBR_WELSH_HEALTH_SURVEY_2013_AGES_16_ABOVE_Y2015M06D04.DTA" , clear
			gen year = "`year'" 
			gen file = "$j/DATA/GBR/WELSH_HEALTH_SURVEY/2013/GBR_WELSH_HEALTH_SURVEY_2013_AGES_16_ABOVE_Y2015M06D04.DTA" 
			keep if age5yrm >= 3
			keep sex age5yrm exercise exergrp exerv exerm year file *wt*

		}

				local count = `count' + 1
				tempfile data_`count'
				save `data_`count''
		}

	
// Append all years to make one master dataset
	use `data_1', clear
	forvalues x = 2/`count' {
		append using `data_`x'', force
	}

// Make GBD age variables
	decode age5yrm, gen(agegrp)
	split agegrp, parse("-") gen(age)
	rename age1 age_start
	replace age_start = "75" if age_start == "75+"
	destring age_start, replace
	drop if age_start < 25 | age_start == .

// Make GBD year variables
	gen year_start = substr(year, 1, 4)
	gen year_end = substr(year, -4, .)
	destring year_start year_end, replace
	
// Minimum total_mets 	
	recode exerv exerm (-9=.)
	gen mod_mets = exerm * 4 * 30
	gen vig_mets = exerv * 8 * 30
	egen total_mets = rowtotal(vig_mets mod_mets)
	egen checkmiss = rowmiss(vig_mets mod_mets)
	replace total_mets = . if checkmiss == 2
	
// Make categorical physical activity variables
	drop if total_mets == .
	gen inactive = total_mets < 600
	gen lowmodhighactive = total_mets >= 600
	
// Set survey weights
	replace wt_adult = int_wt if wt_adult == .
	svyset [pweight=wt_adult]
	
// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category
	mata 
		year = J(1,1,"todrop")
		age_start = J(1,1,999)
		sex = J(1,1,999)
		sample_size = J(1,1,999)
		file = J(1,1, "todrop")
		inactive_mean = J(1,1,999)
		inactive_se = J(1,1,999)
		lowmodhighactive_mean = J(1,1,999)
		lowmodhighactive_se = J(1,1,999)
	end	
	
//  Compute prevalence
	levelsof year, local(years)
	levelsof age_start, local(ages)
	foreach year of local years {
		foreach sex in 1 2 {
			foreach age of local ages {
				preserve
				keep if year == "`year'" & age_start == `age' & sex == `sex'
				di in red  "year:`year' sex:`sex' age:`age'"
					// Calculate mean and standard error for each activity category	
						foreach category in inactive lowmodhighactive {
							svy: mean `category'
							
							matrix `category'_meanmatrix = e(b)
							local `category'_mean = `category'_meanmatrix[1,1]
							mata: `category'_mean = `category'_mean \ ``category'_mean'
							
							matrix `category'_variancematrix = e(V)
							local `category'_se = `category'_variancematrix[1,1]
							mata: `category'_se = `category'_se \ ``category'_se'
						}
		
					// Extract other key variables
						count 
						mata: sample_size = sample_size \ `r(N)'
						mata: year = year \ "`year'"
						mata: sex = sex \ `sex'
						mata: age_start = age_start \ `age'
						levelsof file, local(file) clean
						mata: file = file \ "`file'"
				restore
			}
		}
	}

	// Get stored prevalence calculations from matrix
		clear
		getmata year age_start sex sample_size file lowmodhighactive_mean lowmodhighactive_se inactive_mean inactive_se
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
	
	// Replace standard error as missing if its zero 
		recode *_se (0 = .)
		
	// Create variables that are always tracked		
		gen year_start = substr(year, 1, 4)
		gen year_end = substr(year, -4, .)
		destring year_start year_end, replace
		drop year
		generate age_end = age_start + 4
		egen maxage = max(age_start)
		replace age_end = 100 if age_start == maxage
		drop maxage
		gen national_type =  2 // subnationally representative
		gen urbanicity_type = 1 // representative
		gen survey_name = "Welsh Health Survey"
		gen iso3 = "GBR_4636" // Wales subnational location code
		gen questionnaire = "IPAQ"
		gen source_type = "Survey"
		gen data_type = "Survey: other"
	
	//  Organize
		sort sex age_start age_end		
	
	// Save survey weighted prevalence estimates 
		save "`outdir'/welsh_health_survey_prepped.dta", replace
