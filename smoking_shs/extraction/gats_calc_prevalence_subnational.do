// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 			May 20, 2015 
// Project:		RISK
// Purpose:		Update existing code to include subnationals (Brazil & India); Calculate secondhand smoke exposure prevalence among nonsmokers in GATS data
** **************************************************************************

// Notes: 
// QUESTIONS:
	** Household secondhand smoke question: 
	// e01: Which of the following best describes the rules on tobacco use inside your home? (1=Permitted, 2=Not permitted, but there are exceptions, 3=not permitted at all, 4= no rules, 7=don't know) 
	// e03: If answered anything except 3 [not permitted at all], then respondent is asked  "How often does anyone smoke inside your home?" (1=Daily, 2=Weekly, 3=Monthly, 4=Less than monthly, 5=Never, 7=Don't know, 9 = Refused)

	** b01: Smoking status question: "Do you currently smoke tobacco..." 1=Daily, 2=Less than daily, 3=Not at all, 7=Don't know, 9=Refused)

// DEFINITIONS:
	** A smoker is defined as anyone who smokes on a daily basis (excluded from analysis)
	** Household secondhand smoke exposure is daily or weekly exposure to secondhand smoke in the home (gold standard definition)
	** Exposure at home or work is secondhand smoke exposure 

// SUBNATIONALS
	** In 2015, we are adding subnationals for a number of countries. GATS data from Mexico & China doesn't include subnational units, but both India and Brazil do 
	** India - state and urban/rural 
	** Brazil - state 
	
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
	local dat_folder_gats "$j/DATA/GLOBAL_ADULT_TOBACCO_SURVEY/"
	local datadir "$j/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw" 
	local outdir "$j/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped"

// Prepare countrycodes database for merge (to fill in missing ISO3s)	
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
	
	rename ihme_loc_id iso3
	drop location_type location_id
	
	tempfile countrycodes
	save `countrycodes', replace

// Loop through country directories and prep dta files in each directory
	// local to count loop iterations and save each country as numbered tempfiles to be appended later
		local counter 1 
	// Get list of country directories to loop through
		local iso_list: dir "`dat_folder_gats'" dirs "*", respectcase
		
	// Loop through country directories and use the .dta files in each directory
		foreach country of local iso_list {
			di "`country'"
		
			// If data is in a year specific folder
				local year: dir "`dat_folder_gats'/`country'" dirs "*", respectcase
				if "`year'" == "" {
					local year ""
				}
				
				if "`country'" == "ROU" {
					local year /2011
				}
				
				if "`country'" == "CHN" {
					local year /2009_2010
				}
				
				if "`country'" == "ARG" {
					local year /2012
				}
				
				if "`country'" == "MYS" {
					local year /2011
				}
				
				if "`country'" == "IDN" { 
					local year /2011
				}
				
			// Identify any dta files for the country
				local filenames: dir "`dat_folder_gats'/`country'/`year'" files "*.DTA", respectcase
				foreach file of local filenames {
					if "`country'" == "ARG" {
						use "`dat_folder_gats'/`country'`year'/ARG_GATS_2012_Y2014M02D10", clear
					}
					
					else {
						use "`dat_folder_gats'/`country'`year'/`file'", clear
					}
					renvars, lower // Make variable names lower case
	
					generate filename = "`file'"
					generate filepath = "`dat_folder_gats'/`country'`year'/`file'"

					// Renaming variables that are different in 1 or 2 surveys and to make names more meaningful
						cap rename b01 smoker // smoking status indicator
						cap rename e03 hh_shs // household secondhand smoke exposure indicator
						cap rename e01 rule // Indicator for whether smoking is allowed in the home
						cap rename idade age // Variable for Age of respondent is different in Brail
						cap rename v2701 smoker // Variable for current smoking status of respondent is different in Brazil
						cap rename sexo sex // variable for sex of respondent is different in Brazil
						cap rename v2763 e04
						label var e04 "Do you currently work outside of your home?"
						cap rename v2764 e05 // variable for usually working indoors or outdoors
						label var e05 "Do you usually work indoors or outdoors?"
						cap rename v2765 e06 // variable for indoor areas at workplace is different in Brazil
						label var e06 "Are there any indoor areas at your work place?"
						cap rename v2766 e07 // variable for indoor smoking policy at workplace is different in Brazil
						cap label var e07 "Which of the best describes the indoor smoking policy where you work?"
						cap rename v2767 e08 // variable for smoking indoors in last 30 days is different in Brazil
						label var e08 "During the past 30 days, did anyone smoke in indoor areas where you work?"
						cap rename a01 sex 
						cap rename v2762 hh_shs // Variable for shs exposure status of respondent is different in Brail
						cap rename v2760 rule // variable name for rule about smoking in home is different in Brazil
						cap rename ee01 rule // variable name for rules is different in India
		
						gen urbanicity = . 
						gen subnational_ind = . 
						gen subnational_bra = . 
						
					// Several variables are coded differently in Brazil
						if "`country'" == "BRA" {
							replace sex = 1 if sex  == 2
							replace sex = 2 if sex  == 4
							
							replace hh_shs = 1 if hh_shs == 2 // exposure every day
							replace hh_shs = 2 if hh_shs == 4 // weekly
							replace hh_shs = 3 if hh_shs == 6 // monthly
							replace hh_shs = 4 if hh_shs == 8 // less than monthly	
							replace hh_shs = 5 if hh_shs == 0 // never
							
							replace rule = 1 if rule == 2 // allowed
							replace rule = 2 if rule == 4 // not allowed, but exceptions
							replace rule = 3 if rule == 6 // never allowed
							replace rule = 4 if rule == 8 // no rules
							
							replace smoker = 2 if smoker == 3 // less than daily
							replace smoker = 3 if smoker == 5 // do not smoke
							
							recode e04 3=2 
							recode e05 2=1 4=2 6= 3 
							recode e06 3=2
							recode e07 0=7 2=1 4=2 6=3 8=4
							recode e08 3=2 5=7
							
							replace subnational_bra = uf if uf != . 
										
						}
					
					if "`country'" == "IND" {
						replace subnational_ind = state if state != . 
						replace urbanicity = residence if residence != . 
						}
						
			
				// 1 is daily smoker, everything else is not that
					replace smoker = 0 if (smoker == 2 | smoker == 3) 
					replace smoker = . if (smoker == 7 | smoker == 9)
				
				// Keep only nonsmokers, since we are interested in hh_shs exposure prevalence among nonsmokers
					keep if smoker == 0

				// 1 is daily or weekly exposure to secondhand smoke in the household
					replace hh_shs = 1 if inlist(hh_shs, 1, 2) // daily or weekly exposure indoors counts as exposed
					replace hh_shs = 0 if inlist(hh_shs, 3, 4, 5) | rule == 3 
					replace hh_shs = . if hh_shs == 7 | hh_shs == 9
					
				// Make a variable for exposure to secondhand smoke at home or work (for crosswalking within dismod)
					replace e08 = 2 if e04 == 2 | e05 == 2 | e06 == 2 // not exposed to shs indoors at work if does not work outside of the home, works outdoors or no indoor areas at work place
					if "`country'" != "URY" {
						replace e08 = 2 if e07 == 3 // not exposed to shs indoors at work if smoking is not allowed in any indoor areas
					}
					recode e08 (2=0) (7 9=.)
					gen shs_home_work = 1 if e08 == 1 | hh_shs == 1
					replace shs_home_work = 0 if e08 == 0 & hh_shs == 0
					
				// Generate survey-specific variables to be tracked
					generate file_name = "`file'"
					generate file_path = "`dat_folder_gats'/`country'`year'/`file'"
					gen iso3 = substr(file_name, 1, 3)

				//  Formatting year and generating year variables
					split file_name, p(_)
					gen year_start = file_name3
					replace year_start = subinstr(year_start, ".DTA", "", .)
					tostring year_start, replace force
					gen year_end = ""
					cap replace year_end = file_name4
					replace year_end = "" if regexm(year_end, "Y")
					replace year_end = file_name3 if year_end == ""
					replace year_end = subinstr(year_start, ".DTA", "", .)
					destring year_start year_end, replace
					drop if iso3 == "1_A" | file_name == "ARG_GATS_2012_Y2014M02D10.DTA"
					
					keep gatsweight gatsstrata gatscluster iso3 age sex hh_shs shs_home_work smoker rule file_name file_path year_start year_end subnational_ind subnational_bra urbanicity
					tostring gatsstrata, replace force
					
					
				//  Tempfile the data so that each country can be appended
					tempfile data`counter'
					save `data`counter'', replace
					local counter = `counter' + 1
					di "`counter'"
				}
			}
		
// Append data from each country to make a compiled master dataset 
	use `data1', clear
	local max = `counter' -1
	forvalues x = 2/`max' {
		append using `data`x'', force
	}
	
	tempfile all 
	save `all', replace
		
	
// Add in subnationals for Brazil and India 
	insheet using "`datadir'/BRA_subnational_codebook.csv", comma names clear
	merge 1:m subnational_bra using `all' 
	drop _m 
	save `all', replace
	
										
	insheet using "`datadir'/IND_subnational_codebook.csv", comma names clear
	merge 1:m subnational_ind urbanicity using `all' 
	drop _m subnational_ind subnational_bra urbanicity
	rename state subnational
	
	order iso3 subnational
	sort iso3 subnational
	
// Set age groups
	egen age_start = cut(age), at(15(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	levelsof age_start, local(ages)
	drop age
		
// Set survey weights
	svyset gatscluster [pweight=gatsweight], strata(gatsstrata)	

	tempfile allcountries
	save `allcountries', replace
		
// Create empty matrix for storing calculation results
	mata 
		iso3 = J(1,1,"iso3")
		subnational = J(1,1,"subnational") 
		age_start = J(1,1,999)
		sex = J(1,1,999)
		sample_size = J(1,1,999)
		mean_hh_shs = J(1,1,999)
		se_hh_shs = J(1,1,999)
		mean_workhh_shs = J(1,1,999)
		se_workhh_shs = J(1,1,999)
	end	
	
// Loop through countries, sexes and ages and calculate secondhand smoke prevalence among nonsmokers using survey weights
		levelsof iso3, local(countries)
		levelsof subnational, local(subnationals)
		
		foreach country of local countries {
			use `allcountries', clear
			keep if iso3 == "`country'"
			
			foreach sex in 1 2 {
				foreach age of local ages {
				  
					di in red  "ISO3 `country' sex `sex' age `age'"
					svy linearized, subpop(if iso3 == "`country'" & age_start == `age' & sex == `sex' & hh_shs != .): mean hh_shs
					** Extract exposure at home
						mata: iso3 = iso3 \"`country'" 
						mata: subnational = subnational \ "`subnational'"
						mata: age_start = age_start \ `age'
						mata: sex = sex \ `sex'
						mata: sample_size = sample_size \ `e(N_sub)'
						
						matrix mean_matrix = e(b)
						local mean_scalar = mean_matrix[1,1]
						mata: mean_hh_shs = mean_hh_shs \ `mean_scalar'
						
						matrix variance_matrix = e(V)
						local se_scalar = sqrt(variance_matrix[1,1])
						mata: se_hh_shs = se_hh_shs \ `se_scalar'
					
					svy linearized, subpop(if iso3 == "`country'" & age_start == `age' & sex == `sex'): mean shs_home_work
					** Extract exposure at home or work (for cross walk)
						matrix mean_matrix = e(b)
						local mean_scalar = mean_matrix[1,1]
						mata: mean_workhh_shs = mean_workhh_shs \ `mean_scalar'
						
						matrix variance_matrix = e(V)
						local se_scalar = sqrt(variance_matrix[1,1])
						mata: se_workhh_shs = se_workhh_shs \ `se_scalar'
					
					
					if iso3 == "BRA" | iso3 == "IND" {
						foreach subnational of local subnationals {
						
						di in red  "ISO3 `country' Subnational `subnational' sex `sex' age `age'"
						count if iso3 == "`country'" & subnational == "`subnational'" & age_start == `age' & sex == `sex' & hh_shs != .
						local sample_size = r(N)
						
						if `sample_size' > 0 {
						
						svy linearized, subpop(if iso3 == "`country'" & subnational == "`subnational'" & age_start == `age' & sex == `sex' & hh_shs != .): mean hh_shs
						mata: iso3 = iso3 \"`country'" 
						mata: age_start = age_start \ `age'
						mata: sex = sex \ `sex'
						mata: subnational = subnational \ "`subnational'" 
						mata: sample_size = sample_size \ `e(N_sub)'
						
						matrix mean_matrix = e(b)
						local mean_scalar = mean_matrix[1,1]
						mata: mean_hh_shs = mean_hh_shs \ `mean_scalar'
						
						matrix variance_matrix = e(V)
						local se_scalar = sqrt(variance_matrix[1,1])
						mata: se_hh_shs = se_hh_shs \ `se_scalar'
						
						svy linearized, subpop(if iso3 == "`country'" & subnational == "`subnational'" & age_start == `age' & sex == `sex'): mean shs_home_work
						matrix mean_matrix = e(b)
						local mean_scalar = mean_matrix[1,1]
						mata: mean_workhh_shs = mean_workhh_shs \ `mean_scalar'
						
						matrix variance_matrix = e(V)
						local se_scalar = sqrt(variance_matrix[1,1])
						mata: se_workhh_shs = se_workhh_shs \ `se_scalar'
						
						}
						}
					}
	
					}
				}
			}
		
			
	// Get stored prevalence calculations from matrix
		clear

		getmata iso3 subnational age_start sex sample_size mean_hh_shs se_hh_shs mean_workhh_shs se_workhh_shs
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
		
		recode se_hh_shs se_workhh_shs (0=.) // Standard error should not be 0 so we will use sample size to estimate error instead
		tempfile mata_calculations
		save `mata_calculations'
	
	// Clean up all country file for merge with matrix
		use `allcountries', clear
		keep file_name file_path iso3 year_start year_end
		duplicates drop file_name file_path iso3 year_start, force
		drop if file_name == "ARG_GATS_2012_Y2014M02D10.DTA" | file_name == "1_ARG_GATS_2012_Y2014M02D18.DTA"
		
	// Combine filepath, filename and year information with prevalence calculations from matrix
		merge 1:m iso3 using `mata_calculations', nogen
		rename subnational location_name
		tempfile all 
		save `all', replace 
	
	// Merge on country names 
		// First subnational (need to make corrections to names because imported from the database with question marks in the place of language-specific symbols)
		use `countrycodes', clear 
		
		replace location_name = "Arunachal Pradesh" if location_name == "Arun?chal Pradesh"
		replace location_name = "Arunachal Pradesh, Rural" if location_name == "Arun?chal Pradesh, Rural"
		replace location_name = "Arunachal Pradesh, Urban" if location_name == "Arun?chal Pradesh, Urban"
		replace location_name = "Bihar" if location_name == "Bih?r" 
		replace location_name = "Bihar, Rural" if location_name == "Bih?r, Rural" 
		replace location_name = "Bihar, Urban" if location_name == "Bih?r, Urban" 
		replace location_name = "Chhattisgarh" if location_name == "Chhatt?sgarh" 
		replace location_name = "Chhattisgarh, Rural" if location_name == "Chhatt?sgarh, Rural" 
		replace location_name = "Chhattisgarh, Urban" if location_name == "Chhatt?sgarh, Urban"  
		replace location_name = "Gujarat" if location_name == "Gujar?t" 
		replace location_name = "Gujarat, Rural" if location_name == "Gujar?t, Rural" 
		replace location_name = "Gujarat, Urban" if location_name == "Gujar?t, Urban" 
		replace location_name = "Haryana" if location_name == "Hary?na" 
		replace location_name = "Haryana, Rural" if location_name == "Hary?na, Rural"
		replace location_name = "Haryana, Urban" if location_name == "Hary?na, Urban" 
		replace location_name = "Jammu and Kashmir" if location_name == "Jammu and Kashm?r" 
		replace location_name = "Jammu and Kashmir, Rural" if location_name == "Jammu and Kashm?r, Rural"
		replace location_name = "Jammu and Kashmir, Urban" if location_name == "Jammu and Kashm?r, Urban" 
		replace location_name = "Karnataka" if location_name == "Karn?taka"
		replace location_name = "Karnataka, Rural" if location_name == "Karn?taka, Rural"
		replace location_name = "Karnataka, Urban" if location_name == "Karn?taka, Urban" 
		replace location_name = "Maharashtra" if location_name == "Mah?r?shtra" 
		replace location_name = "Maharashtra, Rural" if location_name == "Mah?r?shtra, Rural" 
		replace location_name = "Maharashtra, Urban" if location_name == "Mah?r?shtra, Urban" 
		replace location_name = "Meghalaya" if location_name == "Megh?laya" 
		replace location_name = "Meghalaya, Rural" if location_name == "Megh?laya, Rural"
		replace location_name = "Meghalaya, Urban" if location_name == "Megh?laya, Urban" 
		replace location_name = "Nagaland" if location_name == "N?g?land"
		replace location_name = "Nagaland, Rural" if location_name == "N?g?land, Rural"
		replace location_name = "Nagaland, Urban" if location_name == "N?g?land, Urban" 
		replace location_name = "Rajasthan" if location_name == "R?jasth?n"
		replace location_name = "Rajasthan, Rural" if location_name == "R?jasth?n, Rural"
		replace location_name = "Rajasthan, Urban" if location_name == "R?jasth?n, Urban"
		replace location_name = "Tamil Nadu" if location_name == "Tamil N?du"
		replace location_name = "Tamil Nadu, Rural" if location_name == "Tamil N?du, Rural"
		replace location_name = "Tamil Nadu, Urban" if location_name == "Tamil N?du, Urban"
		save `countrycodes', replace 
		
		// Duplicates are a problem (drop those that aren't relevant) 
		duplicates tag location_name, gen(dup)
		drop if dup == 1 & iso3 != "BRA_4756" 
		drop dup
		
		merge 1:m location_name using `all'
		drop if file_name == ""
		replace location_name = "National" if iso3 == "IND" & location_name == ""
		replace location_name = "National" if iso3 == "BRA" & location_name == ""
		drop _m
		save `combined', replace
	
	// Reshape so household exposure(gold standard) and household/work (alternative) are long
		reshape long mean_@ se_@, i(iso3 location_name year_start sex age_start) j(case_definition, string)
		replace case_definition = "daily or weekly exposure to tobacco smoke inside the home among current nonsmokers" if case_definition == "hh_shs"
		replace case_definition = "daily or weekly exposure to tobacco smoke inside the home or any exposure indoors at work in the last month among current nonsmokers" if case_definition == "workhh_shs"
	
	// Set variables that are always tracked
		rename se_ standard_error
		rename mean_ mean
		gen source = "micro_GATS"
		gen national_type_id = 1 if location_name == "" // Nationally representative
		replace national_type_id = 6 if location_name != "" // Nationally, subnationally and urban/rural representative
		generate age_end = age_start + 4
		egen maxage = max(age_start)
		replace age_end = 100 if age_start == maxage
		drop maxage
		gen orig_unit_type = "Rate per capita"
		gen orig_uncertainty_type = "SE" 
		replace orig_uncertainty_type = "ESS" if standard_error == .

	// Now want to include at both the national and subnational level (this is subject to change in the future but for now want to have both extracted) 
	// drop if iso3 == "IND" | iso3 == "BRA"
	
	// Organize
		order iso3 location_name year_start year_end sex age_start age_end sample_size mean standard_error, first
		sort iso3 location_name sex age_start age_end
		
	// Save survey weighted data
		save `outdir'/gats_prepped_subnational.dta, replace
		
