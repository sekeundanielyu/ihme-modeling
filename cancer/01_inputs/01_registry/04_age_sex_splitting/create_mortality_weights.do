** *****************************************************************************	
// Purpose:	Create mortality rates that will be used to generate weights in age age/sex splitting and acause disaggregation
// Location: /home/j/WORK/07_registry/cancer/01_inputs/programs/age_sex_splitting/code/create_mortality_weights.do
** *****************************************************************************	
** *************
** Configure
** *************
// Clear memory and set memory and variable limits
	clear all
	set more off

// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"

// Get date
	local today = date(c(current_date), "DMY")
	local today = string(year(`today')) + "_" + string(month(`today'),"%02.0f") + "_" + string(day(`today'),"%02.0f")

** ********************
** Get outside resources and append data
** ********************
// get fastcollapse function
	do "$j/WORK/10_gbd/00_library/functions/fastcollapse.ado"

// prepare the cause list and generate age-sex restrictions
	// get data
		use "$j/WORK/00_dimensions/03_causes/gbd2015_causes_all.dta", clear
		keep acause male female yll_age_start yll_age_end 
		keep if substr(acause,1,4) == "neo_"
		drop if regexm(acause, "_benign") | regexm(acause, "_cancer")
	
	// save cause list
		tempfile cause
		save `cause', replace
	
	// // Generate age_sex restrictions
		// keep relevant data
			rename (yll_age_start yll_age_end) (age_start age_end)
			drop if acause == "neo_nmsc_bcc"
	
		// edit age formats
			foreach var in age_start age_end {
				replace `var' = floor(`var'/5) + 6 if `var' >= 5
				replace `var' = 0 if `var' < 5
			}
			
		// save
			tempfile age_sex_restrictions
			save `age_sex_restrictions', replace

// Prep the completeness weights
	use "$j/Project/Mortality/GBD Envelopes/00. Input data/00. Format all age data/d08_smoothed_completeness.dta", clear
		keep iso3 year iso3_sex_source u5_comp_pred trunc_pred
		** drop if completeness isn't for VR
		drop if substr(iso3_sex_source, -2, .)!="VR"
		** there are duplicates, create mean across them
		** and create both sex mean for saudi, which is by sex
		replace iso3_sex_source= subinstr(iso3_sex_source, "male", "both", .)
		replace iso3_sex_source= subinstr(iso3_sex_source, "feboth", "both", .)
		fastcollapse u5_comp_pred trunc_pred, by(iso3 year) type(mean)
		** generate a weight for 5-14
		egen double kid_comp = rowmean(u5 trunc)
		replace u5=1 if u5>1
		replace trunc=1 if trunc>1
		replace kid=1 if kid>1
		tempfil comp
		save `comp', replace

// Prep the pop_file
	do "$j/WORK/03_cod/01_database/02_programs/prep/code/env_wide.do"
	drop env* pop91 pop93 pop94
	rename pop3 pop2
	tempfile pop
	save `pop', replace

// Get US county-level location_ids and their state parent_ids for aggregation
	odbc load, exec("SELECT location_id, location_parent_id AS parent_id FROM shared.location") dsn(prodcod) clear
	tempfile parent_ids
	save `parent_ids', replace
	
// // Append datasets
	// get list of vr sources
		insheet using "$j/WORK/03_cod/01_database/02_programs/age_sex_splitting/code/age_sex_split_vr_sources.csv", comma names clear
		capture levelsof vr_sources, local(data_sources)
	
	// combine data sources
	local firstrun = 1
	quietly foreach data_source of local data_sources {
		if regexm("`data_source'", "South_Africa") continue
		noisily di "Reading `data_source'"
		use "`in_dir'/`data_source'/data/intermediate/01_mapped.dta", clear
		keep if substr(acause,1,4) == "neo_"
		if inlist("`data_source'","US_NCHS_counties_ICD9","US_NCHS_counties_ICD10") {
			merge m:1 location_id using `parent_ids', assert(2 3) keep(3) nogen
			replace location_id = parent_id
			drop parent_id
		}
		compress
		if `firstrun' {
			tempfile temp
			local firstrun = 0
		}
		else append using `temp'
		save `temp', replace
	}
	save "`data_dir'/all_data.dta", replace

** **********************
** Keep and format only data of interest
** **********************
// Drop null data
	drop if source==""
	
// keep only age formats meeting GBD-cancer standard
	keep if inlist(frmat, 0, 1, 2, 131) & inlist(im_frmat, 1, 2, 4, 5, 6, 7, 8, 9)

// Drop pre-1970 data
	drop if year < 1970	
	
// Format acause and keep only causes of interest
	replace acause = subinstr(acause, "_cancer", "", .)
	drop if regexm(acause, "_benign")
	merge m:1 acause using `cause', keep(1 3) assert(3) nogen

// keep only variables of interest and collapse
	keep source iso3 location_id acause year sex frmat im_frmat deaths*
	fastcollapse deaths*, by(source iso3 location_id acause year sex frmat im_frmat) type(sum)
	
// // Keep only data from countries of interest
	// Replace Hong Kong
		replace location_id = 354 if iso3 == "HKG"
		replace iso3 = "CHN" if iso3 == "HKG"
	// Replace Macao
		replace location_id = 361 if iso3 == "MAC"
		replace iso3 = "CHN" if iso3 == "MAC"
	// Drop CHN data if not corrected
		drop if inlist(iso3, "HKG", "MAC")

	// Drop South Africa because HIV throws-off age patterns
		drop if iso3=="ZAF"

// // Keep only sexes of interest		
	// drop "unknown" sex
		drop if sex == 9
			
	// Confirm that deaths for males and females add up to the number for both.  If they don't, there may be a problem in the dataset.
		// once confirmed, drop "both" sex 
		count if sex == 3
		if r(N) {
			sort source iso3 location_id acause year sex frmat im_frmat
			
			// determine the number of sexes represented by sex = 3. drop if the datapoint has only sex = 3
				egen uid = concat(source iso3 location_id year sex acause)
				gen temp = 1
				bysort uid: egen num_sex = total(temp)
				drop if sex == 3 & num_sex == 1
				drop temp uid
			
			// determine difference between sex = 3 data and male and/or female data
			count if sex == 3
			if r(N) {
				quietly foreach var of varlist deaths* {
					replace `var' = `var' - (`var'[_n-1] + `var'[_n-2]) if sex == 3 & num_sex == 3 & (sex[_n-1] == 1 | sex[_n-1] == 2) & (sex[_n-2] == 1 | sex[_n-2] == 2)
					replace `var' = `var' - `var'[_n-1] if sex == 3 & num_sex == 2 & (sex[_n-1] == 1 | sex[_n-1] == 2)
				}
				drop num_sex
			}
			
			// determine the number of datasets that failed the test. 
			egen sex_check = rowtotal(deaths*) if sex == 3
			count if sex == 3 & sex_check != 0
			if r(N) > 5 {
				di "ERROR: sex == 3 does not equal the sum of both sexes for all datasets."
				di "Press Enter to drop these `r(N)' datapoints. Enter 'break' to cancel."
				pause
			}
			if r(N) {
				egen uid = concat(source iso3 location_id acause year sex frmat im_frmat)
				bysort uid: egen to_drop = total(sex_check)
				drop if to_drop != 0
				drop uid to_drop sex_check
			}
			else drop sex_check
		}
		drop if sex == 3		
		
// Verify that deaths2 has been correctly calculated, then drop deaths91-deaths94 
	egen im_tot = rowtotal(deaths91-deaths94)
	drop if !inrange(deaths2, im_tot-1, im_tot+1)
	drop im_tot deaths91 deaths92 deaths93 deaths94
	
// drop if dataset contains deaths for unknown age
	aorder
	capture drop total_deaths
	egen total_deaths = rowtotal(deaths2-deaths25)
	replace deaths26 = 0 if deaths26 == .
	gen has_unknown = 1 if deaths26 > 1
	replace has_unknown = 1 if has_unknown != 1 & !inrange(deaths1, .99*total_deaths, 1.01*total_deaths)
	drop if has_unknown == 1
	drop has_unknown total_deaths deaths26

// collapse deaths2-deaths6 and deaths23-deaths25
	gen youth = deaths2 + deaths3 + deaths4 + deaths5 + deaths6
	gen elderly = deaths22 + deaths23 + deaths24 + deaths25
	drop deaths2 deaths3 deaths4 deaths5 deaths6
	drop deaths22 deaths23 deaths24 deaths25 
	rename (youth elderly) (deaths2 deaths22)

// verify totals
	egen total_check = rowtotal(deaths2-deaths22)
	gen total_diff = floor(total_check - deaths1)
	count if total_diff > 0
	if r(N) {
		di "Error: deaths total does not match before and after death consolidation"
		BREAK
	}
		
// drop if there is no death data
	drop deaths1 
	egen deaths1 = rowtotal(deaths*), missing
	drop if deaths1==0 | deaths1==.
	
// collapse
	fastcollapse deaths*, by(iso3 location_id acause year sex) type(sum)		
	
// save
	keep iso3 location_id acause year sex deaths*
	compress
	save "`data_dir'/acause_weight_data.dta", replace

** *********************************************
** Adjust for completeness and apply age-sex restrictions
** *********************************************
** use "`data_dir'/acause_weight_data.dta", clear

// // Adjust for completeness
	// merge with completeness file
		merge m:1 iso3 year using `comp', keep(1 3)
		
		** As of 10/31/2013 we are missing Pakistan 1993-1994 & Turkey 1999-2012 (Also China, Korea, and US Virgin Islands)
		codebook iso3 if _m==1
		codebook year if _m==1
		** pause
		drop if _m==1
		drop _m
		
	// child completeness
		foreach i of numlist 2 7 {
			replace deaths`i' = deaths`i' / kid_comp
		}
	// adult completeness
		foreach i of numlist 8/22 {
			replace deaths`i' = deaths`i' / trunc_pred
		}

// // Apply age/sex restrictions	
	// Apply sex restrictions
		merge m:1 acause using `age_sex_restrictions', keep(1 3)
		drop if _merge == 3 & sex == 1 & male == 0 
		drop if _merge == 3 & sex == 2 & female == 0 
		drop male female

	// Apply age restrictions
		foreach n of numlist 2 7/22 {
			replace deaths`n' = 0 if _merge == 3 & `n' < age_start
			replace deaths`n' = 0 if _merge == 3 & age_end < `n'	
		}
		drop age_start age_end _merge
	
// Save completeness-adusted file
	save "`data_dir'/acause_weight_adjusted_data.dta", replace

** ******************************************
** Generate rates
** ******************************************
** use "`data_dir'/acause_weight_adjusted_data.dta", clear

// merge with population and collapse so that rates can be calculated
	merge m:1 iso3 location_id year sex using "`pop'", assert (using matched) keep(3) keepusing(pop*) nogen
	fastcollapse pop* deaths*, by(sex acause) type(sum)

// add "average cancer" cause
	preserve
		collapse (mean) deaths* pop*, by(sex)
		gen acause = "average_cancer"
		tempfile average_cancer
		save `average_cancer', replace
	restore
	append using `average_cancer'
	
// Make weights for sex = 3
	preserve
		collapse (sum) deaths* pop*, by (acause) fast
		gen sex = 3
		tempfile sex3
		save `sex3', replace
	restore
	append using `sex3'
	
// create rates
	foreach i of numlist 2 7/22 {
		generate double death_rate`i' = deaths`i'/pop`i'
		replace death_rate`i' = 0 if  death_rate`i' == . | death_rate`i' < 0
	}
	aorder

// Keep only relevant information
	keep sex acause death_rate*
	order sex acause
	sort acause sex
	compress
	
	save "`out_dir'/acause_age_weights_mor.dta", replace
	saveold "`out_dir'/_archive/acause_age_weights_mor_`today'.dta", replace

capture log close

** ****
** END
** ****
