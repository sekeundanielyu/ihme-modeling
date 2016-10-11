// Date: December 2, 2013
// Purpose: Extract physical activity data from China Health Nutrition Survey for years 1989 - 2006  and compute survey weighted physical activity prevalence in 5 year age-sex groups


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
	local data_dir "$j/DATA/CHN/HEALTH_NUTRITION_SURVEY/1989_2009"
	local outdir "$j/WORK/05_risk/risks/activity/data/exp"

// Bring in and set up dataset
	use "`data_dir'/CHN_HNS_1989_2009_PHYSICAL_ACITIVTY_Y2011M05D10.DTA", clear
	renvars, lower
	
	rename wave year
	rename gender sex
	
	keep if age >= 25 & age != . & year > 1996 // only care about respondents 25 and above for physical inactivity risk, and survey only has physical activity questions in 1997 and beyond
** *********************
// Transport
** *********************
	// Rename variables for clarity and to facilitate cleaning loop below (min variables are minutes/week)
		rename u126 bike
		rename u127_mn bike_min
		rename u128 walk
		rename u129_mn walk_min
		rename u143_mn walk_min_exercise
		rename u144_mn bike_min_exercise
	
	foreach trans_type in bike walk {	
		recode `trans_type'_min (99 = .)
		replace `trans_type'_min = 0 if `trans_type' == 0 // replace . as 0 if respondent does not undertake active transportation
		replace `trans_type'_min = `trans_type'_min * 5 // assume 5 days of school/work per week
		replace `trans_type'_min = `trans_type'_min_exercise if (`trans_type'_min == . | `trans_type'_min == 0) & (`trans_type'_min_exercise != . & `trans_type'_min != 0)
	}
	
	gen bike_mets = bike_min * 4
	gen walk_mets = walk_min * 2.5 
	
** *********************
// Work
** *********************
	foreach var in u141 u142 {
		recode `var' (-9 = .)
		recode `var'_mn (99 = .)
		replace `var'_mn = `var' if (`var'_mn == 0 | `var'_mn == .) & (`var' == 15 | `var' == 30 | `var' == 45 | `var' == 60) // Check if minutes were accidentally entered as hours 
		replace `var' = `var' * 60 // convert hours to minutes
		egen `var'_min = rowtotal(`var' `var'_mn) // total time is sum of minutes and hours * 60 min/hr
		egen miss = rowmiss(u140 u140_mn)
		replace `var'_min = . if miss == 2
		drop miss
	}
	
	// Calculate MET min/week equivalents based on time spent in moderate and vigorous work
		gen work_mod_mets = u141_min * 4
		gen work_vig_mets = u142_min * 8
		
** *********************	
// Recreation: Survey asks about martial arts, dancing/gymnastics/acrobatics, track and field (running, etc.)/swimming, soccer/basketball/tennis, volleyball/badminton, other(ping pong, Tai Chi, etc.)
** *********************
	// Rename variables for clarity and cleaning loop below
		rename u145 mma
		rename u327_mn mma_wkdy
		rename u328_mn mma_wknd
		
		rename u149 dance
		rename u329_mn dance_wkdy
		rename u330_mn dance_wknd
		
		rename u147 run
		rename u331_mn run_wkdy
		rename u332_mn run_wknd
		
		rename u151 vigsprt
		rename u333_mn vigsprt_wkdy
		rename u334_mn vigsprt_wknd
		
		rename u153 modsprt
		rename u335_mn modsprt_wkdy
		rename u336_mn modsprt_wknd
		
		rename u155 ltsprt
		rename u337_mn ltsprt_wkdy
		rename u338_mn ltsprt_wknd
	
	// Cleaning loop that calculates total minutes/week spent doing each activity
		foreach activity in mma dance run vigsprt modsprt ltsprt {
			recode `activity'_wkdy `activity'_wknd (99 = .)
			recode `activity'_wkdy `activity'_wknd (.=0) if `activity' == 0
			replace `activity'_wkdy = `activity'_wkdy * 5
			replace `activity'_wknd = `activity'_wknd * 2
			egen `activity'_min = rowtotal(`activity'_wkdy `activity'_wknd)
			egen miss = rowmiss(`activity'_wkdy `activity'_wknd)
			replace `activity'_min = . if miss == 2
			drop miss
		}
	
	// Calculate MET min/week equivalents based on time spent in different activities
		gen dance_mets = dance_min * 4
		gen vigsprt_mets = vigsprt_min * 7 
		gen modsprt_mets = modsprt_min * 4
		gen ltsprt_mets = ltsprt_min * 4
		gen run_mets = run_min * 8

// Compute total MET min / week across all domains
	egen total_mets = rowtotal(bike_mets walk_mets dance_mets run_mets vigsprt_mets modsprt_mets ltsprt_mets work_vig_mets work_mod_mets)
	egen miss = rowmiss(bike_mets walk_mets dance_mets run_mets vigsprt_mets modsprt_mets ltsprt_mets work_vig_mets work_mod_mets)
	replace total_mets = . if miss == 9
	drop miss

// Cross check that total reported activity time is plausible (Shouldn't be more than 6720 minutes (assume no more than 16 active waking hours per day on average))
	egen total_min = rowtotal(bike_min walk_min dance_min run_min vigsprt_min modsprt_min ltsprt_min u141_min u142_min)
	replace total_mets = . if total_min > 6720
	drop total_min
		
// Fill in provinces
	gen province = ""
	replace province = "Liaoning" if t1 == 21
	replace province = "Heilongjiang" if t1 == 23
	replace province = "Jiangsu" if t1 == 32
	replace province = "Shandong" if t1 == 37
	replace province = "Henan" if t1 == 41
	replace province = "Hubei" if t1 == 42
	replace province = "Hunan" if t1 == 43
	replace province = "Guangxi" if t1 == 45
	replace province = "Guizhou" if t1 == 52
	
	rename province location_name
	tempfile china_data
	save `china_data', replace
	
// Pull subnational ids from database 
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
	
	keep if regexm(ihme_loc_id, "CHN")
	rename ihme_loc_id iso3
	
	merge 1:m location_name using `china_data'
	keep if _merge == 3
	drop _merge location_type

** *******************************************************************************************
** 2.) Calculate Prevalence in each year/province/age/sex subgroup and save compiled/prepped dataset 
** ****************************************************************************
	// Create empty matrix for storing proportion of a year/age/sex subpopulation in each physical activity category
		mata 
			iso3 = J(1,1,"todrop")
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

	// Set age groups (had small sample size issue so terminal age group will be 70+)
		egen age_start = cut(age), at(25(5)120)
		replace age_start = 70 if age_start > 70 & age_start != .
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
		
	// Compute prevalence
	levelsof year, local(years)
	levelsof iso3, local(iso3s)
	
	foreach year of local years {
		foreach iso3 of local iso3s {
			foreach sex in 1 2 {	
				foreach age of local ages {
					
					di in red "Year: `year' iso3: `iso3' Age: `age' Sex: `sex'"
					count if year == `year' & iso3 == "`iso3'" & age_start == `age' & sex == `sex'
					local sample_size = `r(N)'
					if `sample_size' > 0 {
						// Calculate mean and standard error for each activity category	
							foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
								mean `category' if year == `year' & iso3 == "`iso3'" & age_start == `age' & sex == `sex'
								matrix `category'_stats = r(table)
								
								local `category'_mean = `category'_stats[1,1]
								mata: `category'_mean = `category'_mean \ ``category'_mean'
								
								local `category'_se = `category'_stats[2,1]
								mata: `category'_se = `category'_se \ ``category'_se'
							}
									
						// Extract other key variables
							mata: iso3 = iso3 \ "`iso3'"
							mata: age_start = age_start \ `age'
							mata: sex = sex \ `sex'
							mata: sample_size = sample_size \ `sample_size'
							mata: year_start = year_start \ `year'
					}
				}
			}
		}
	}
	

	// Get stored prevalence calculations from matrix
		clear

		getmata year_start age_start sex sample_size iso3 highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se lowmodhighactive_mean lowmodhighactive_se modhighactive_mean modhighactive_se
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results	
		
	// Set variables that are always tracked
		gen file = "`data_dir'/CHN_HNS_1989_2009_PHYSICAL_ACITIVTY_Y2011M05D10.DTA"
		gen national_type = 2 // subnationally representative
		gen urbanicity_type = 1 // representative
		gen survey_name = "China Health Nutrition Survey"
		gen age_end = age_start + 4
		egen maxage = max(age_start)
		replace age_end = 100 if age_start == maxage
		drop maxage
		gen year_end = year_start
		gen source_type = "Survey"
		gen data_type = "Survey: other"
		gen questionnaire = "GPAQ" // according to sources, questions were modeled based on GPAQ 
		
//  Organize
	sort sex age_start age_end iso3
	
// Replace standard error as missing if its zero (so that dismod calculates error using the sample size instead)
	recode *_se (0 = .)
	
save "`outdir'/prepped/chn_health_nutrition_survey_prepped.dta", replace

	
