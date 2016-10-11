// Date: November, 2013
// Purpose: Extract physical activity data from WHS surveys and compute survey weighted physical activity prevalence in 5 year age-sex groups for each country

// NOTES: WHS uses the short form of the IPAQ

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
	local whs_directory "$j/DATA/WHO_WHS"
	local outdir "$j/WORK/05_risk/risks/activity/data/exp"
	local iso_list: dir "`whs_directory'" dirs "*", respectcase
	local count 0 // local to count loop iterations and save each country as numbered tempfiles to be appended later
	
// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category (inactive, moderately active and highly active)
	mata 
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
		
// Loop through country directories and identify outliers, translate minutes of PA into mets, and calculate prevalence estimates
	local counter = 1 

	foreach country of local iso_list {
	
		if "`country'" != "crude" & "`country'" != "LVA" & "`country'" != "MAR" { // days per week is missing for all activity domains in Latvia and Morocco , so for now we will not calculate estimates for these countries from the WHS
			
			// Prep individual file
				local filenames: dir "`whs_directory'/`country'" files "`country'_WHS_*_INDIV_*", respectcase		
				foreach file of local filenames {
					use "`whs_directory'/`country'/`file'", clear
					di in red "`file'"
					
					gen filepath = "`whs_directory'/`country'/`file'"
					
					capture keep id q1001 q1002 q4030-q4038 filepath
					
					tempfile main
					save `main'
				}
				
			// Merge individual file with survey weight file
				local ids: dir "`whs_directory'/`country'"  files "`country'_WHS_*_ID_*", respectcase
				foreach file of local ids {
					use "`whs_directory'/`country'/`file'", clear
					di in red "`file'"
					
					merge 1:1 id using `main', nogen
					
					tempfile `country'
					save ``country'', replace
				}

			// Continue only for countries with physical activity questions 
			cap lookfor q4030
			cap if r(varlist) {
				
					// Rename variables for cleaning loop below
						rename q4030 vig_days
						rename q4031 vig_hrs
						rename q4032 vig_min
						rename q4033 mod_days
						rename q4034 mod_hrs
						rename q4035 mod_min
						rename q4036 walk_days
						rename q4037 walk_hrs
						rename q4038 walk_min
						rename q1001 sex
						rename q1002 age
						
					// Cleaning loop: Internal consistency checks and calculating total minutes of physical activity performed at each level per week
						foreach level in vig mod walk {
							replace `level'_days = . if `level'_days > 7 | `level'_days < 0 // not more than 7 days per week
							replace `level'_min = 0 if `level'_min < 10 // less than 10 min a domain should not count according to IPAQ guidelines
							replace `level'_min = `level'_hrs if (`level'_min == 0 | `level'_min == .) & (`level'_hrs == 15 | `level'_hrs == 30 | `level'_hrs == 30 | `level'_hrs == 45 | `level'_hrs == 60) // check if minutes were accidentally entered as hours
							replace `level'_hrs = `level'_hrs * 60 // convert hours to minutes
							replace `level'_hrs = 0 if `level'_hrs == `level'_min // assume that when hours and minutes are the same, time was double counted
							replace `level'_hrs = 0 if `level'_hrs == . & `level'_min !=. // respondents usually only report in hours or minutes, not both
							replace `level'_min = 0 if `level'_min == . & `level'_hrs !=.
							replace `level'_min = `level'_hrs + `level'_min // calculate total minutes/average day
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
						
					// Make categorical physical activity variables
						drop if total_mets == .
						gen inactive = total_mets < 600
						gen lowactive = total_mets >= 600 & total_mets < 4000
						gen lowmodhighactive = total_mets >= 600
						gen modactive = total_mets >= 4000 & total_mets < 8000
						gen modhighactive = total_mets >= 4000 
						gen highactive = total_mets >= 8000 
												
					// Set age groups (some countries have sufficient sample sizes for generating estimates of 65+ age groups, others do not so terminal age group is 65+ instead of 80+)
						drop if age < 25 | age == . // only need ages >= 25 for physical activity
						qui: count if age > 75 & age != .
						if r(N) > 200 {
							egen age_start = cut(age), at(25(5)120)
							replace age_start = 80 if age_start > 80 & age_start != .
						}
						else {
							egen age_start = cut(age), at(25(5)120)
							replace age_start = 60 if age_start > 60 & age_start != .
						}
						levelsof age_start, local(ages)

					// Set survey weights
						if "`country'" == "ZMB" {
							svyset [pweight=pweight], strata(strata)
						}
						if "`country'" != "ZMB" & "`country'" != "GTM" & "`country'" != "SVN" {
							svyset PSU [pweight=pweight], strata(strata)
						}

					// Save cleaned version 
						cap keep sex age total_mets mod_mets vig_mets walk_mets country PSU pweight strata file
							tempfile data`counter'
							save `data`counter'', replace
							local counter = `counter' + 1
							di "`counter'"
	
		}
	}
}

// Append data from each country to make a compiled master dataset 
	use `data1', clear
	local max = `counter' -1
	forvalues x = 2/`max' {
		append using `data`x'', force
	}

// Add a few things 
	gen questionnaire = "IPAQ" 
	gen survey_name = "World Health Survey"
	gen urbanicity_type = 1 


/*
					// Compute prevalence
					levelsof filepath, local(filepath) clean
						// Two countries do not have survey weights so I will calculate unweighted mean prevalence
						if "`country'" == "GTM" | "`country'" == "SVN" {
							foreach sex in 1 2 {	
								foreach age of local ages {
									
									di in red "Country: `country' Age: `age' Sex: `sex'"
									count if age_start == `age' & sex == `sex'
									if r(N) != 0 {
										// Calculate mean and standard error for each activity category
											foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
												mean `category' if age_start ==`age' & sex == `sex'
												matrix `category'_stats = r(table)
												
												local `category'_mean = `category'_stats[1,1]
												mata: `category'_mean = `category'_mean \ ``category'_mean'
												
												local `category'_se = `category'_stats[2,1]
												mata: `category'_se = `category'_se \ ``category'_se'
											}
											
										// Extract other key variables	
											mata: age_start = age_start \ `age'
											mata: sex = sex \ `sex'
											mata: sample_size = sample_size \ `e(N)'
											mata: file = file \ "`filepath'"
									}
								}
							}		
						}	
						
						// The rest of the countries do have survey weights				
						if "`country'" != "GTM" & "`country'" != "SVN" {
							foreach sex in 1 2 {	
								foreach age of local ages {
									
									di in red "Country: `country' Age: `age' Sex: `sex'"
									count if age_start == `age' & sex == `sex'
									if r(N) != 0 {
										// Calculate mean and standard error for each activity category	
											foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
												svy linearized, subpop(if age_start ==`age' & sex == `sex'): mean `category'
												
												matrix `category'_meanmatrix = e(b)
												local `category'_mean = `category'_meanmatrix[1,1]
												mata: `category'_mean = `category'_mean \ ``category'_mean'
												
												matrix `category'_variancematrix = e(V)
												local `category'_se = sqrt(`category'_variancematrix[1,1])
												mata: `category'_se = `category'_se \ ``category'_se'
											}
										
										// Extract other key variables	
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

						getmata age_start sex sample_size file highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se lowmodhighactive_mean lowmodhighactive_se modhighactive_mean modhighactive_se
						drop if _n == 1 // drop top row which was a placehcolder for the matrix created to store results	
			}
		}
	}
	
	// Set variables that are always tracked
		gen iso3 = substr(file, -34, 3)
		replace iso3 = substr(file, -39, 3) if iso3 == "HS_"
		gen year_end = 2003
		gen national_type = 1 // nationally representative
		gen urbanicity_type = 1 // representative
		gen survey_name = "World Health Survey"
		gen age_end = age_start + 4
		egen maxage = max(age_start)
		replace age_end = 100 if age_start == maxage
		drop maxage
		gen year_start = year_end - 1
		gen questionnaire = "IPAQ"
		gen source_type = "Survey"
		gen data_type = "Survey: other"
		
	// Replace standard error as missing if its zero 
		recode *_se (0 = .)
		
	//  Organize
		sort sex age_start age_end
	
save `outdir'/prepped/whs_prepped.dta, replace	

