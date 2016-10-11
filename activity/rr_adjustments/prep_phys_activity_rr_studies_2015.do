** 11/13/14
** convert all extracted studies on physical activity to METs
** rewritten based on J:/WORK/05_risk/temp/explore/physical_activity/RR/code/Physical Activity RR prep code.do

** **************************************************************************
** RUNTIME CONFIGURATION
** **************************************************************************
// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		macro drop _all
		set mem 700m
		set maxvar 32000
	// Set to run all selected code without pausing
		set more off
	// Set graph output color scheme
		set scheme s1color
	// Remove previous restores
		cap restore, not
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}
// Close previous logs
	cap log close
	
	
// create macros with relevant filepaths
	local exposure_data							"$prefix/WORK/2013/05_risk/02_models/02_data/physical_inactivity/exp/raw/compiled/compiled.dta"
	local gbd_distribution						"$prefix/temp/strUser/physical_inactivity/data/pa_exposure_gbd2013_11_06_14.dta"
	local regression_adjust						"$prefix/WORK/05_risk/risks/activity/data/rr/domain_crosswalk_adjusted_for_ipaq.xlsx"
	local regression_unadjust					"$prefix/WORK/05_risk/risks/activity/data/rr/domain_crosswalk_unadjusted_for_ipaq.xlsx"
	local data_dir								"$prefix\DATA\Incoming Data\WORK\05_risk\0_ongoing\physical_inactivity\new data\new articles"
	local out_dir								"$prefix/WORK/05_risk/risks/activity/data/rr/prepped/gbd_2015"
	local outcomes 								"diabetes"


// toggle for ipaq adjustment 
	local ipaq_adjust = 0

*** * *********************************************************************************************
*** CROSSWALK ACTIVITY LEVEL, KCAL, KJ STUDIES TO METS USING GBD MET DISTRIBUTION, 
*** CONVERT MET PAPERS AND PAPERS CONVERTED TO METS TO TOTAL DAILY METS USING REGRESSION COEFFICIENTS
*** * *********************************************************************************************

*** * *****************************************
*** ** compute maximum mets and store in a local
*** * *****************************************	
// use the 99th percentile of gpaq exposure data; for gbd 2013, ipaq is considered gold standard survey
use "`exposure_data'", clear

summ total_mets if ipaq == 1, detail

local max_mets = `r(p99)'

*** * ****************************************
*** ** PREP REGRESSION DATA FROM KRISTEN
*** * ****************************************

// load data
import excel using "`regression_adjust'", firstrow clear

sort(iso3)
keep domain sex agegrp iso3 beta

// compute sex = 3 values using the mean 
expand 2, gen(dup)
replace sex = 3 if dup == 1
collapse (mean) beta, by(domain sex agegrp iso3)
sort(iso3)

// add "total" category if studies do not need to be adjusted because they include all 3 domains
expand 2, gen(dup)
replace domain = "total" if dup == 1 
replace beta = 0 if domain == "total" 
//replace cons = 0 if domain == "total" 
//replace standard_error = 0 if domain == "total"

collapse (mean) beta, by(domain sex agegrp iso3)

// rename vars for merging purposes later on
rename iso3 iso3_match

tempfile coeff
save `coeff'

*** * *****************************************
*** ** 1. PREP GBD EXPOSURE DATA
*** * *****************************************	

// load data
use "`gbd_distribution'", clear

// clean up names and format
	// destring sex var
		// drop weird empty observations
		drop if sex == ""
		// drop subnationals
		drop if regexm(iso3, "^X")
	replace sex = "1" if sex == "male"
	replace sex = "2" if sex == "female"
	destring sex, replace
	
	// convert activity level category to a numerical indicator 1 = low, 4 = high
	rename healthstate cat
	replace cat = "cat1" if cat == "activity_inactive"
	replace cat = "cat2" if cat == "activity_low"
	replace cat = "cat3" if cat == "activity_mod"
	replace cat = "cat4" if cat == "activity_high"
	
	// reshape so that category is wide
	reshape wide mean, i(location_name iso3 year sex age) j(cat) string
	
// Several extractions across all outcomes are from multinational studies. Compute mean cat1_mean, cat2_mean, cat3_mean, and cat4_mean across the countries used in the multinational study and and create new, multinational iso3 observations.
	expand 2 if iso3 == "FRA" | iso3 == "ITA" | iso3 == "ESP" | iso3 == "GBR" | iso3 == "NLD" | iso3 == "GRC" | iso3 == "DEU" | iso3 == "SWE" | iso3 == "DNK", gen(dup) 
	replace iso3 = "FRA, ITA, ESP, GBR, NLD, GRC, DEU, SWE, DNK" if dup == 1
	collapse (mean) meancat1 meancat2 meancat3 meancat4, by (iso3 year sex age) 
		
	expand 2 if iso3 == "NOR" | iso3 == "SWE", gen(dup)
	replace iso3 = "NOR, SWE" if dup ==1
	collapse (mean) meancat1 meancat2 meancat3 meancat4, by (iso3 year sex age)
		
	expand 2 if iso3 == "GBR" | iso3 == "FRA", gen(dup)
	replace iso3 = "GBR, FRA" if dup == 1
	collapse (mean) meancat1 meancat2 meancat3 meancat4, by (iso3 year sex age) 
	
// create mean percent per cat for both sexes combined
	expand 2, gen(dup)
	replace sex = 3 if dup == 1
	collapse (mean) meancat1 meancat2 meancat3 meancat4, by(iso3 year sex age)
	
// compute upper percentile cutoffs associated wtih each activity category
	local count = 0
	forvalues n = 1/4 {

		if `n' == 1 {
			gen gbd_cat`n'_upper = meancat`n' 
		}
		
		else {
			gen gbd_cat`n'_upper = meancat`n' + gbd_cat`count'_upper
		}
		
		local count = `count' + 1
	}

	drop meancat*
	
// save 
	tempfile gbd_data
	save `gbd_data', replace
	
	
*** * ***************************************************************
*** PREP EXTRACTION DATA -  Assign percentiles to RR extractions based on percent in each activity level category
*** * ***************************************************************

// loop through prep and crosswalk for each outcome
foreach outcome of local outcomes {
	di in red "`outcome'"
	
	// load crosswalk data set
	import excel using "`data_dir'/`outcome'/new_articles_Mar 2016/extraction/extraction_for_crosswalk/extractions_to_crosswalk.xlsx", firstrow clear

	// generate variable for percent_per_cat
	replace percent_per_cat = sample_per_cat / sample_size 

	// drop empty entries
	//drop if nid == .
	
	// drop unnecessary variables - will merge met values into data set later in code
	// site dropped as a variable 
	keep  source iso3 site sex year_start year_end age_start age_end  percent_per_cat activity_cat_num exposure_type

		//nid extraction age_mean activity_cat_num
	// reshape data so that each extraction is in one row
	reshape wide percent_per_cat, i(source iso3 site sex year_start year_end age_start age_end exposure_type) j(activity_cat_num)
	
	// create a local corresponding to the maximum number of activity level categories. 
	// This range (1-4, 1-5 or 1-6), will be used through out the rest of the loop to apply the analysis and assign new MET values to each category. 
	// Generate the correct number range in the local by using the number of categories and dropping the rest of the text 
		unab categories: percent_per_cat*
		local categories = subinstr("`categories'", "percent_per_cat", "", .)
		
	// compute upper percentile limits associated with each activity category 
		local count = 0
		foreach n of local categories {
		
			if `n' == 1 {
				gen data_cat`n'_upper = percent_per_cat`n'
			}
			
			else {
				gen data_cat`n'_upper = data_cat`count'_upper + percent_per_cat`n'
			}
			
			local count = `count' + 1
		}
	
	// prep extraction data to merge with GBD exposure data. will merge on iso3, sex, year, age
		// assign each study a gbd year
		generate year = (year_start + year_end) / 2
		// if year is less than 1990, assign to 1990
		replace year = 1990 if year <= 1990 | year == .
		// assign every other year to 5 year gbd year bins
		local gbd_years 1990 1995 2000 2005 2010
		foreach gbdy of local gbd_years {
			di in red `gbdy'
			replace year = `gbdy' if year > (`gbdy' - 2.99) & year <= (`gbdy' + 2)
		}
		
	// Compute an average age for each study and classify into a GBD 2010 age bin
		// 1. Create numerical entries for all ages reported by papers
		capture confirm string var age_start  // if age is stringed, these two loops will destring it first 
		if _rc == 0 {
			foreach a in age_start {
				replace `a' = subinstr(`a', "<", "", .)
				replace `a' = subinstr(`a', ">", "", .)
				replace `a' = subinstr(`a', ">=", "", .)
				replace `a' = subinstr(`a', "<=", "", .)
				replace `a' = subinstr(`a', "=<", "", .)
			}
			destring age_start, replace
		}
		
		capture confirm string var age_end
			if _rc == 0 {
				foreach a in age_end {
					replace `a' = subinstr(`a', "<", "", .)
					replace `a' = subinstr(`a', ">", "", .)
					replace `a' = subinstr(`a', ">=", "", .)
					replace `a' = subinstr(`a', "<=", "", .)
					replace `a' = subinstr(`a', "=<", "", .)
					replace `a' = subinstr(`a', "=", "", .)
				}
				destring age_end, replace
			}
						
		// a. for papers that didn't report a mean age or end age use 99 as age_end and then compute age_mean. for papers that didn't report a starting age or mean age assign starting age = 20
			replace age_start = 20 if age_start == . // & age_mean == . 
			replace age_end = 99 if age_end == . //& age_mean == .
		
		// 2. compute mean age for papers that did not report this information
		gen age_mean = ((age_start + age_end)/2) 
		rename age_mean age
		
		// 3. Assign each mean age to a GBD2010 age category 
			local ages 25 30 35 40 45 50 55 60 65 70 75 80
			foreach age of local ages {
				di in red "`age'"
				if `age' == 25 & age <`age' {
					replace age = `age'
				}
				else {
					replace age = `age' if age >= `age' & age < (`age' + 5)
				}
			}
			
	drop percent_per_cat*

	gen sex_new = 1 if sex == "Men" | sex == "Male" 
	replace sex_new = 2 if sex == "Female" | sex == "Women"
	replace sex_new = 3 if sex == "Both"

	drop sex 
	rename sex_new sex 
	
	*** * **************************************************************************
	*** MERGE EXTRACTION AND GBD EXP DATA & PERFORM CROSSWALK
	*** * **************************************************************************

	merge m:1 iso3 sex year age using `gbd_data', assert (2 3) keep (3) nogen

	*** * ****************************************************************************
	*** CROSS WALK GBD AND EXTRACTION DATA
	*** * ****************************************************************************
	// MET MIN NO ADJUSTMENT
	// 1. determine which gbd cat extraction data falls within 
	// 2. compute percent of that category represented by extraction data ie (extraction percentile - lower gbd percentile for category)/(upper gbd percentile for category - lower gbd percentile for category) 
	// 3. compute the percent of MET in that category corresponding to the percent calculated in 2 ie value from 2 * (cat upper MET - cat lower MET) 
	// 4. Add in lower MET values to total ie part 3 + lower cat MET value
	** CURRENTLY USING 30500 as upper bound for category 4 of GBD 2010 exposure (8000 + met min/week). This is the average of the 99th percentile MET value from GPAQ data from SAGE data across all six countries (32200) and the 99th percentile from NHANES from 2007 to 2012(28800)	

	foreach n in `categories' {
			gen met_min_raw`n' = .
			replace met_min_raw`n' = (data_cat`n'_upper / gbd_cat1_upper) * 600 if data_cat`n'_upper <= gbd_cat1_upper
			replace met_min_raw`n' = (((data_cat`n'_upper - gbd_cat1_upper) / (gbd_cat2_upper - gbd_cat1_upper)) * (3400)) + 600 if data_cat`n'_upper > gbd_cat1_upper & data_cat`n'_upper <= gbd_cat2_upper 
			replace met_min_raw`n' = (((data_cat`n'_upper - gbd_cat2_upper) / (gbd_cat3_upper - gbd_cat2_upper)) * 4000) + 4000 if data_cat`n'_upper > gbd_cat2_upper & data_cat`n'_upper <= gbd_cat3_upper
			replace met_min_raw`n' = (((data_cat`n'_upper - gbd_cat3_upper) / (gbd_cat4_upper - gbd_cat3_upper)) * (`max_mets' - 8000)) + 8000 if data_cat`n'_upper > gbd_cat3_upper & data_cat`n'_upper <= gbd_cat4_upper
			replace met_min_raw`n' = `max_mets' if data_cat`n'_upper > 0.99 & data_cat`n'_upper != .
		}	
	
	// Create vars that report MET hr computed converted to MET min, as well as to hr and min with an added in a rough estimate for sedentary time (16 HR TOTAL WAKING TIME * 1.5 MET * 7 DAYS = 168)
	foreach n in `categories' {
		gen met_hr_raw`n' = met_min_raw`n'/60
		gen met_hr_adj`n' = met_hr_raw`n' + 168
		gen met_min_adj`n' = met_hr_adj`n' * 60
	}
	
	*** * ************************************************************
	** MERGE MET HR/WEEK FROM NEW DATA SET BACK INTO RR EXTRACTION SHEET
	*** * ************************************************************
	// drop all categories, except identifiers and metlvl_hr results

	keep source iso3 site sex year_start year_end met_min_raw* met_hr_raw* met_min_adj* met_hr_adj* exposure_type age_*
	reshape long met_min_raw met_hr_raw met_hr_adj met_min_adj, i(source iso3 site sex year_start year_end exposure_type age_start age_end) j(activity_cat_num)

	//rename age_start age_start_replace
	//rename age_end age_end_replace 

	tempfile metlvl
	save `metlvl'

	// merge met values with RR extraction sheet
	import excel using "`data_dir'/`outcome'/new_articles_Mar 2016/extraction/extraction_for_crosswalk/extractions_to_crosswalk.xlsx", firstrow clear	

	//drop if nid == .
	gen sex_new = 1 if sex == "Men" | sex == "Male"
	replace sex_new = 2 if sex == "Female" | sex == "Women"
	replace sex_new = 3 if sex == "Both" 

	drop sex 
	rename sex_new sex 
	
	merge m:1 source iso3 site sex year_start year_end age_start age_end activity_cat_num exposure_type using `metlvl', assert (1 2 3) keep (match master) nogen
	//replace age_start = age_start_replace if age_start == . 
	//replace age_end = age_end_replace if age_end == . 
	
	// generate met ranges for each category
	local met_vars "met_min_raw met_min_adj met_hr_raw met_hr_adj"

	sort source site year_start age_start age_end sex exposure_type activity_cat_num 

	foreach var of local met_vars {
		di in red "`var'"
		gen `var'_start = .
		replace `var'_start = 0 if activity_cat_num == 1
		replace `var'_start = (`var'[_n-1] + 0.1) if activity_cat_num != 1
		rename `var' `var'_end
		order `var'_end, after(`var'_start)
	}
	
		
	// save
	tempfile `outcome'_crosswalk
	save ``outcome'_crosswalk', replace
	
	
*** * *********************************************************************************************
*** CONVERT MET STUDIES TO TOTAL DAILY METS USING LOG-LOG OLS REGRESSION
*** * *********************************************************************************************	
	// import data sets
	local regression_data_types "met_hr_per_week converted_to_mets"
	foreach type of local regression_data_types {
		
		di in red "`type'"

		if "`outcome'" == "breast_cancer" & "`type'" == "met_hr_per_week" { 
			di "no converted extractions to run through analysis"
		}
		
		else if "`outcome'" == "ischemic_stroke" & "`type'" == "met_hr_per_week" { 
			di in red "no converted extractions to run through"
		}
		
		else if "`outcome'" == "ischemic_stroke" & "`type'" == "converted_to_mets" {
			di "no converted extractions to run through analysis"
		}
		
		else {
			import excel using "`data_dir'/`outcome'/new_articles_Mar 2016/extraction/extraction_for_crosswalk/`type'.xlsx", firstrow clear
			
			//drop if nid == .

			// assign extractions age variables that match coeff sheet: 0 : 25-40 yr, 1: 40-65 years 2: 65+, assign based on mean age of study 
				capture confirm string var age_start  // if age is stringed, these two loops will destring it first 
				if _rc == 0 {
					foreach a in age_start {
						replace `a' = subinstr(`a', "<", "", .)
						replace `a' = subinstr(`a', ">", "", .)
						replace `a' = subinstr(`a', ">=", "", .)
						replace `a' = subinstr(`a', "<=", "", .)
						replace `a' = subinstr(`a', "=<", "", .)
					}
			
				// convert  to numerical vars
				destring age_start, replace
		}

				capture confirm string var age_end
				if _rc == 0 {
					foreach a in age_end {
						replace `a' = subinstr(`a', "<", "", .)
						replace `a' = subinstr(`a', ">", "", .)
						replace `a' = subinstr(`a', ">=", "", .)
						replace `a' = subinstr(`a', "<=", "", .)
						replace `a' = subinstr(`a', "=<", "", .)
						replace `a' = subinstr(`a', "=", "", .)
					}
					
					// convert  to numerical vars
					destring age_end, replace
				}

				replace age_start = 20 if age_start == .
				replace age_end = 99 if age_end == .
			
			gen agegrp = ((age_start+age_end)/2)
			replace agegrp = 0 if agegrp <40
			replace agegrp = 1 if agegrp >= 40 & agegrp <65
			replace agegrp = 2 if agegrp >=65
			replace agegrp = 1 if agegrp == . 

			// assign domains to exposure_type in extraction sheet corresponding to those in coeff sheet 
			gen domain = ""
			replace domain = "trans" if exposure_type == "Walking" // do this line first to overwrite all the recreation+walking expsoures to recreation in next line
			replace domain = "trans" if exposure_type == "Commuting" 
			replace domain = "trans" if exposure_type == "Transportation"
			replace domain = "rec" if exposure_type == "Recreation"
			replace domain = "rec" if exposure_type == "recreation"
			replace domain = "rec" if exposure_type == "leisure"
			replace domain = "rec" if exposure_type == "Household"
			replace domain = "rec" if exposure_type == "Housework"
			replace domain = "work" if exposure_type == "Occupational"
			replace domain = "work_rec" if exposure_type == "Recreation and Occupation" 
			replace domain = "trans_rec" if exposure_type == "Transportation and Recreation"
			replace domain = "trans_rec" if exposure_type == "Recreation and Transportation"
			replace domain = "work_rec" if exposure_type == "Recreation and Household"
			replace domain = "total" if exposure_type == "Total"
			replace domain = "total" if exposure_type == "total"

			// assign extractions iso3's that correspond to those used in coeff sheet - for western europe/n. america and high income, use USA
			gen iso3_match = ""
			replace iso3_match = "USA" if regexm(iso3, "USA")
			replace iso3_match = "USA" if regexm(iso3, "DNK")
			replace iso3_match = "USA" if regexm(iso3, "FRA")
			replace iso3_match = "USA" if regexm(iso3, "GBR")
			replace iso3_match = "USA" if regexm(iso3, "CAN")
			replace iso3_match = "USA" if regexm(iso3, "JPN")
			replace iso3_match = "USA" if regexm(iso3, "NLD")
			replace iso3_match = "USA" if regexm(iso3, "FIN")
			replace iso3_match = "USA" if regexm(iso3, "SWE")
			replace iso3_match = "USA" if regexm(iso3, "ITA")
			replace iso3_match = "USA" if regexm(iso3, "KOR")
			replace iso3_match = "USA" if regexm(iso3, "AUS")
			replace iso3_match = "USA" if regexm(iso3, "NOR") 
			replace iso3_match = "USA" if regexm(iso3, "ISR")
			replace iso3_match = "USA" if regexm(iso3, "LTU")
			replace iso3_match = "CHN" if regexm(iso3, "CHN")
			replace iso3_match = "CHN" if regexm(iso3, "TWN")
			
			// convert MET-hr/week to MET-min/week
			rename MET_start met_start
			rename MET_end met_end
			replace met_start = met_start *60
			replace met_end = met_end *60

			gen sex_new = 1 if sex == "Men" | sex == "Male"
			replace sex_new = 2 if sex == "Female" 
			replace sex_new = 3 if sex == "Both"

			drop sex 
			rename sex_new sex 

			***
			** MERGE COEFF AND EXTRACTION SHEETS
			***
			merge m:1 iso3_match agegrp domain sex using `coeff', assert (2 3) keep (3) nogen

			gen MET_llols_start = met_start * exp(-beta)

			gen MET_llols_end = met_end * exp(-beta)

			replace MET_llols_end = `max_mets' if met_end == .

			/*
			// compute total marginal MET min/week start and end using beta and cons. since ln(0) is undefined, use 0.001 in conversion if observed MET value from extraction was 0
			gen MET_llols_start = exp((beta*(ln(met_start))) + cons)
			replace MET_llols_start = exp((beta*ln(0.001))+ cons) if met_start == 0 

			gen MET_llols_end = exp((beta*(ln(met_end))) + cons)
			replace MET_llols_end = exp((beta*ln(0.001))+ cons) if met_end == 0 
			replace MET_llols_end = `max_mets' if met_end == .
			*/

			// convert coefficient converted values back to MET-hr
			gen met_hr_raw_start = MET_llols_start/60
			gen met_hr_raw_end = MET_llols_end/60

			// drop unnecessary vars and save
			drop agegrp domain iso3_match beta
			
			//sort line_id 
			
			tempfile `outcome'_`type'
			save ``outcome'_`type'', replace

			}
		}
	

			
			
*** * ***************************************************************
*** COMPILE AND FORMAT FINAL DATA SET
*** * ***************************************************************			
	// clean and append data sets from each conversion type
	// start with crosswalked data
	use ``outcome'_crosswalk', clear
	
	rename activity_cat activity_level 

	// keep relevant variables
	if "`outcome'" == "ischemic_stroke" {
		keep source nid file_name sex iso3 year_start year_end age_start age_end activity_cat sample_size sample_per_cat cases_per_cat met_hr_raw_start met_hr_raw_end RR_mean RR_lower RR_upper odds_ratio OR_lower OR_upper OR_std_error hazard_ratio HR_lower HR_upper exposure_type  exposure_definition adjusted adjusted_text notes total_stroke activity_level
	}
	else {
		keep source nid file_name sex iso3 year_start year_end age_start age_end activity_cat sample_size sample_per_cat cases_per_cat met_hr_raw_start met_hr_raw_end RR_mean RR_lower RR_upper odds_ratio OR_lower OR_upper OR_std_error hazard_ratio HR_lower HR_upper exposure_type exposure_definition adjusted adjusted_text notes activity_level
	}

	// exposure_units, exclude

	// make sure age and RR are numeric
	capture confirm string var age_start  // if age is stringed, these two loops will destring it first 
	if _rc == 0 {
		foreach a in age_start {
			replace `a' = subinstr(`a', "<", "", .)
			replace `a' = subinstr(`a', ">", "", .)
			replace `a' = subinstr(`a', ">=", "", .)
			replace `a' = subinstr(`a', "<=", "", .)
			replace `a' = subinstr(`a', "=<", "", .)
		}
						
		// convert  to numerical vars
		destring age_start, replace
	}

	capture confirm string var age_end
	if _rc == 0 {
		foreach a in age_end {
			replace `a' = subinstr(`a', "<", "", .)
			replace `a' = subinstr(`a', ">", "", .)
			replace `a' = subinstr(`a', ">=", "", .)
			replace `a' = subinstr(`a', "<=", "", .)
			replace `a' = subinstr(`a', "=<", "", .)
			replace `a' = subinstr(`a', "=", "", .)
		}				
		destring age_end, replace
	}
					
	capture confirm string var RR_mean
	if _rc == 0 {
		foreach r in RR_mean {
			replace `r' = subinstr(`r', "*", "", .)
		}			
		destring RR_mean, replace
	}
	
	// create indicator variable for GBD converted values. x_MET_est = 1 for crosswalked values and 0 for values that were converted by hand or regression coefficients
	gen x_MET_est = 1
	
	capture confirm numeric var notes
	if _rc == 0 {
		tostring notes, replace
	}
	
	tostring file_name, replace 
	tostring exposure_definition, replace
	
	// save
	tempfile `outcome'_data
	save ``outcome'_data', replace
	
	di in red "compiling results"
	// clean and append in regression converted values
	foreach type of local regression_data_types {
		di in red "`type'"
		
		if "`outcome'" == "ischemic_stroke" & "`type'" == "converted_to_mets" {
			di in red "no converted extractions to run through"
		}

		else if "`outcome'" == "breast_cancer" & "`type'" == "met_hr_per_week" { 
			di in red "no converted extractions to run through"
		}
		
		else if "`outcome'" == "ischemic_stroke" & "`type'" == "met_hr_per_week" { 
			di in red "no converted extractions to run through"
		}
		
		else {
			
			use ``outcome'_`type'', clear
			
			tostring file_name, replace 
			tostring exposure_definition, replace 

			rename activity_cat activity_level 
			tostring activity_level, replace 

			if "`outcome'" == "ischemic_stroke" {
				keep source nid file_name sex iso3 year_start year_end age_start age_end sample_size sample_per_cat cases_per_cat activity_level activity_cat_num met_hr_raw_start met_hr_raw_end RR_mean RR_lower RR_upper odds_ratio OR_lower OR_upper OR_std_error hazard_ratio HR_lower HR_upper exposure_type exposure_definition adjusted adjusted_text notes total_stroke
			}
			else {
				keep source nid file_name sex iso3 year_start year_end age_start age_end sample_size sample_per_cat cases_per_cat activity_level activity_cat_num met_hr_raw_start met_hr_raw_end RR_mean RR_lower RR_upper odds_ratio OR_lower OR_upper OR_std_error hazard_ratio HR_lower HR_upper exposure_type exposure_definition adjusted adjusted_text notes 
			}
			
			capture confirm numeric var notes
				if _rc == 0 {
					tostring notes, replace
				}
			
			// create indicator variable for GBD converted values. x_MET_est = 1 for crosswalked values and 0 for values that were converted by hand or regression coefficients
			gen x_MET_est = 0
		
			append using ``outcome'_data'
			
			sort iso3 year_start sex age_start exposure_type activity_cat_num 


			tempfile `outcome'_data
			save ``outcome'_data', replace

		}
	}
	
	di in red "formatting results"
*** * ************************************************
*** FORMAT
*** **************************************************
	rename met_hr_raw_start met_hr_start
	rename met_hr_raw_end met_hr_end
	
	// recode sex to dismod specificiations. male = 0.5, female = -0.5, both = 0
	gen x_sex = .
	replace x_sex = -0.5 if sex == 2
	replace x_sex = 0 if sex == 3
	replace x_sex = 0.5 if sex == 1

	// create indicator variable if paper reported a HR instead of RR 
	gen x_HR = 0
	replace x_HR = 1 if hazard_ratio != .

	// create indicator varaible if paper reported an OR instead of RR
	gen x_OR = 0
	replace x_OR = 1 if odds_ratio != .
	
	// create integrand category for use in dismod. Treating PA exposure as incidence.
	gen integrand = "incidence"

	// move OR and HR to RR column for papers that did not report RR's. This is noted in the covariates above x_HR and x_OR
	replace RR_mean = hazard_ratio if RR_mean == . & hazard_ratio != . 
	replace RR_lower = HR_lower if RR_lower == . & HR_lower != .
	replace RR_upper = HR_upper if RR_upper == . & HR_upper != . 
				
	drop hazard_ratio HR_lower HR_upper

	replace RR_mean = odds_ratio if RR_mean == . & odds_ratio !=.
	replace RR_lower = OR_lower if RR_lower == . & OR_lower != . 
	replace RR_upper = OR_upper if RR_upper == . & OR_upper != . 
				
	drop odds_ratio OR_lower OR_upper OR_std_error
	
	order integrand nid file_name sex year_start year_end age_start age_end iso3 sample_size sample_per_cat cases_per_cat activity_level activity_cat_num x_sex met_hr_start met_hr_end RR_mean RR_lower RR_upper x_HR x_OR

	// number each category for each extraction. Goal is to have the highest category be the reference group for each extraction 
	replace activity_cat_num = 1 if met_hr_start <0.24 & activity_cat_num == .
	replace activity_cat_num = 1 if nid == 122044 & met_hr_start < 200 
	forvalues n = 2/9 {
		replace activity_cat_num = `n' if activity_cat_num[_n-1] == `n'-1 & activity_cat_num[_n] != 1 & activity_cat_num == .
	}
	
	// label each unique extraction 
	gen extraction = .
	//sort iso3 year_start exposure_type activity_cat_num
	order extraction, after(activity_cat_num)
	local total_obs = _N
	local count = 0
	forvalues n = 1/`total_obs' {
		if activity_cat_num[`n'] == 1 {
			local count = `count'+1
			replace extraction = `count' in `n'
		}
	}
	replace extraction = extraction[_n-1] if extraction == .
	
	// label each extraction's highest category
	bysort extraction: egen ref_cat = max(activity_cat_num)
	gen maxcat = .
	replace maxcat = 1 if ref_cat == activity_cat_num
	replace maxcat = 0 if ref_cat != activity_cat_num
	drop ref_cat
	gsort extraction -activity_cat_num 

	// Fill in upper and lower CI limits for RR for orignial reference categories
	replace RR_lower = 1 if RR_mean == 1 & RR_lower == .
	replace RR_upper = 1 if RR_mean == 1 & RR_upper == .
	
	// generate the value you will divide by for each extraction to convert to reference group having highest activity 
	foreach n in extraction {
		gen ref_mean = RR_mean if maxcat == 1
		gen ref_upper = RR_upper if maxcat == 1
		gen ref_lower = RR_lower if maxcat == 1
	}

	local refcat ref_mean ref_upper ref_lower
	foreach r of local refcat {
		bysort extraction: replace `r' = `r'[_n-1] if `r' == . 
	}

	// create new_RR variables. new_RR vars will set the reference group as the group with the highest cat number

	gen new_RR_mean = RR_mean / ref_mean
	gen new_RR_lower = RR_lower / ref_lower
	gen new_RR_upper = RR_upper / ref_upper

	bysort extraction: replace new_RR_upper = RR_upper if ref_mean == 1 
	bysort extraction: replace new_RR_lower = RR_lower if ref_mean == 1 

	drop maxcat ref_mean ref_upper ref_lower 
	
	// label upper and lower new RR's so that they are in the right order
	gen new_RR_upper_adj = .
	gen new_RR_lower_adj = . 	

	replace new_RR_upper_adj = new_RR_lower if new_RR_lower >= new_RR_upper
	replace new_RR_upper_adj = new_RR_upper if new_RR_upper >= new_RR_lower

	replace new_RR_lower_adj = new_RR_upper if new_RR_upper <= new_RR_lower
	replace new_RR_lower_adj = new_RR_lower if new_RR_lower <= new_RR_upper 
	
	replace new_RR_upper = new_RR_upper_adj
	replace new_RR_lower = new_RR_lower_adj
	
	drop new_RR_upper_adj new_RR_lower_adj

	// compute SD's for new RR's using 1. sigma = (lnupper - lnlower)/(1.96*2) 2. expsigma = exp(sigma) 3. stdev = (expsigma - 1)*meanRR
	gen sigma = ((ln(new_RR_upper)) - (ln(new_RR_lower)))/ (1.96*2)
	
	gen exp_sig = exp(sigma)
	gen stdev = (exp_sig - 1) * new_RR_mean 

	drop sigma exp_sig

	// generate new covariate that represents that the reported values were not reported as RR's in the original paper
	gen x_not_RR = .
	replace x_not_RR = 1 if x_HR == 1 | x_OR == 1
	replace x_not_RR = 0 if x_HR == 0 & x_OR == 0 

	// generate a new covariate that is a label for each study ie S1, S2, S3..
	egen temp = group(source)
	//egen temp = group(source)
	gen study = "S"+string(temp)

	drop temp
	
	order study nid file_name sex x_sex year_start year_end age_start age_end iso3 integrand sample_size sample_per_cat cases_per_cat met_hr_start met_hr_end activity_level activity_cat_num extraction RR_mean RR_lower RR_upper new_RR_mean new_RR_lower new_RR_upper stdev x_HR x_OR x_not_RR

	// save
	//export excel using "`out_dir'/`outcome'_prepped.xlsx", firstrow(var) replace
	export excel using "`out_dir'/`outcome'_prepped.xlsx", firstrow(var) replace 
}

	




