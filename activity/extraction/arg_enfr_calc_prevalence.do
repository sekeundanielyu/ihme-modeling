// Date: December 9, 2013
//  Purpose:  Extract physical activity data from Argentina National Survey of Risk Factors (ENFR) for years 2005 and 2009  and compute survey weighted physical activity prevalence in 5 year age-sex groups

// Notes: Uses the IPAQ

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

// Create globals and locals for relevant files and folders	
	global data_dir "$j/data/arg/national_survey_of_risk_factors_enfr"
	local outdir "$j/WORK/05_risk/risks/activity/data/exp"
	global years: dir "$data_dir" dirs "2*"
	local counter 1 // local to count loop iterations and save each country as numbered tempfiles to be appended later
	
// Loop through years and insheet text files
	foreach year of global years {
		global file: dir "$data_dir/`year'" files "*hh_ind*.txt"
		global file = subinstr(`"$file"', `"""', "", .) // fix quotation issue with the global so that the filepath works
		if "`year'" == "2005" {
			insheet using `"$data_dir/`year'/$file"', delim(";") clear
			local filepath = `"$data_dir/`year'/$file"'
			// "
			gen file = "`filepath'"
		}
		if "`year'" == "2009" {
			insheet using `"$data_dir/`year'/$file"', delim("|") clear
			local filepath = `"$data_dir/`year'/$file"'
			// "
			gen file = "`filepath'"
		}
		
	// Variable names start with c in 2005 and b in 2009 so i'm standardizing them here so that datasets append properly
		capture rename ciaf* biaf*
		capture rename chch* bhch*
		capture rename chch05 bch05
		capture rename chch04 bhch04
		foreach var in biaf02 biaf04 biaf06 {
			capture rename `var' `var'_m
		}
	
		// keep biaf* niv_af identifi bhch04_j bhch05_j w_pers file
		gen year_start = `year'
			
		//  Tempfile the data so that each year can be appended
			tempfile data`counter'
			save `data`counter'', replace
			local counter = `counter' + 1
			di "`counter'"
	}

// Append data from each country to make a compiled master dataset 
	use `data1', clear
	local max = `counter' -1
	forvalues x = 2/`max' {
		append using `data`x''
	}
	
// Rename variables for cleaning loop below
	rename biaf01 vig_days
	rename biaf02_m vig_min
	rename biaf03 mod_days
	rename biaf04_m mod_min
	rename biaf05 walk_days
	rename biaf06_m walk_min
	rename bhch04 sex
	rename bhch05 age
	rename w_pers pweight
	
// Cleaning loop: Internal consistency checks and calculating total minutes of physical activity performed at each level per week
		foreach level in vig mod walk {
			recode `level'_days (8=0) // 8 is respondent doesn't do activity at specified level
			replace `level'_min = 0 if `level'_min < 10 // less than 10 min a domain should not count according to IPAQ guidelines
			gen `level'_total = `level'_min * `level'_days
		}	
	
// Calculate total mets from each activity level and the total across all levels combined
	gen mod_mets = mod_total * 4
	gen vig_mets = vig_total * 8
	gen walk_mets = walk_total * 3.3
	egen total_mets = rowtotal(vig_mets mod_mets walk_mets)
	egen total_miss = rowmiss(vig_mets mod_mets walk_mets)
	replace total_mets = . if total_miss == 3 // should only exclude respondents with missing values in all PA levels, so as long as at least one level has valid answers and all others are missing, we will assume no activity in other domains
					
// Check to make sure total reported activity time is plausible	
	egen total_time = rowtotal(vig_total  mod_total walk_total) // Shouldn't be more than 6720 minutes (assume no more than 16 active waking hours per day on average)
	replace total_mets = . if total_time > 6720
	drop total_time
					
// Make variables and variable names consistent with other sources
	label define sex 1 "Male" 2 "Female"
	label values sex sex
	gen survey_name = "Argentina National Survey of Risk Factors"
	gen questionnaire = "IPAQ"
	gen year_end = year_start
	gen iso3 = "ARG"

// Clean up
	keep sex age total_mets iso3 year_start year_end questionnaire survey_name file pweight		
	
// Save compiled raw dataset	
	save "`outdir'/raw/arg_enfr_clean.dta", replace
	
// Make categorical physical activity variables
	drop if total_mets == .
	gen inactive = total_mets < 600
	gen lowactive = total_mets >= 600 & total_mets < 4000
	gen lowmodhighactive = total_mets >= 600
	gen modactive = total_mets >= 4000 & total_mets < 8000
	gen modhighactive = total_mets >= 4000 
	gen highactive = total_mets >= 8000  
											
// Set age groups 
	drop if age < 25 | age == . // only need ages >= 25 for physical activity
	egen age_start = cut(age), at(25(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .	
	levelsof age_start, local(ages)

// Set survey weights	
	svyset _n [pweight=pweight]
	
// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category 
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

// Compute prevalence
	foreach year of global years {
		foreach sex in 1 2 {	
			foreach age of local ages {
				
				di in red "Year: `year'  Age: `age' Sex: `sex'"
				count if year_start == `year' & age_start == `age' & sex == `sex'
				if r(N) != 0 {
					// Calculate mean and standard error for each activity category	
						foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
							svy linearized, subpop(if year_start == `year' & age_start ==`age' & sex == `sex'): mean `category'
							
							matrix `category'_meanmatrix = e(b)
							local `category'_mean = `category'_meanmatrix[1,1]
							mata: `category'_mean = `category'_mean \ ``category'_mean'
							
							matrix `category'_variancematrix = e(V)
							local `category'_se = sqrt(`category'_variancematrix[1,1])
							mata: `category'_se = `category'_se \ ``category'_se'
						}
					
					// Extract other key variables	
						mata: year_start = year_start \ `year'
						mata: age_start = age_start \ `age'
						mata: sex = sex \ `sex'
						mata: sample_size = sample_size \ `e(N_sub)'
						mata: file = file \ "`filepath'"
				}
			}
		}
	}
					
// Get stored prevalence calculations from matrix
	clear

	getmata year_start age_start sex sample_size file highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se lowmodhighactive_mean lowmodhighactive_se modhighactive_mean modhighactive_se
	drop if _n == 1 // drop top row which was a placehcolder for the matrix created to store results	

// Replace standard error as missing if its zero (so that dismod calculates error using the sample size instead)
	recode *_se (0 = .)
	
// Set variables that are always tracked
	gen iso3 = "ARG"
	gen year_end = year_start
	gen national_type =  1 // nationally representative
	gen urbanicity_type = 1 // representative
	gen survey_name = "Argentina National Survey of Risk Factors "
	gen age_end = age_start + 4
	egen maxage = max(age_start)
	replace age_end = 100 if age_start == maxage
	drop maxage
	gen questionnaire = "IPAQ"
	gen source_type = "Survey"
	gen data_type = "Survey: other"
	replace file = "J:/DATA/ARG/NATIONAL_SURVEY_OF_RISK_FACTORS_ENFR/2009/HH_IND_Y2012M30D12.TXT" 
	replace file = "J:/DATA/ARG/NATIONAL_SURVEY_OF_RISK_FACTORS_ENFR/2005/HH_IND_Y2012M30D12.TXT" if year_start == 2005
	gen nid = 57119 if year_start ==2005
	replace nid = 57125 if year_start == 2009
//  Organize
	sort year_start sex age_start age_end	
	
// Save survey weighted prevalence estimates 
	save `outdir'/prepped/arg_enfr_prepped.dta, replace	
