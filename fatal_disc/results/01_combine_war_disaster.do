// Purpose:	make final war and disaster file

clear all 

	if c(os) == "Windows" {
		global prefix ""
	}
	else {
		global prefix ""
	}
	
	
	local input_folder ""
	local output_folder ""


local date = c(current_date)

// bring in disaster file
	use "formatted_disaster_data_rates_with_cis.dta", clear
	
	gen deaths_high = u_disaster_rate * pop
	gen deaths_low = l_disaster_rate * pop
	
	collapse (sum) disaster deaths*, by(iso3 location_id year cause pop) fast
	
	gen float l_disaster_rate = deaths_low / pop
	gen float u_disaster_rate = deaths_high / pop
	gen float disaster_rate = disaster / pop
		
	keep iso3 location_id cause disaster disaster_rate l_disaster_rate u_disaster_rate year
	rename (disaster disaster_rate l_disaster_rate u_disaster_rate) (deaths_best rate l_rate u_rate)
	
	drop if iso3 == ""
	drop if deaths_best == .
	drop if deaths_best == 0
	
	// For merge
	replace location_id = . if !inlist(iso3, "CHN", "MEX", "GBR", "IND", "BRA", "JPN") & !inlist(iso3,"SAU","SWE","USA","KEN","ZAF")

	// Assert the relationship between low, best, high
	count if l_rate>rate
	assert `r(N)'==0
	count if rate>u_rate
	assert `r(N)'==0
	
	tempfile disaster
	save `disaster', replace

// bring in the final war database
	use "USABLE_EST_GLOBAL_vWARDEATHS.dta", clear


	// Collapse to iso3 year
	destring location_id, replace
	replace location_id = . if !inlist(iso3, "CHN", "MEX", "GBR", "IND", "BRA", "JPN") & !inlist(iso3,"SAU","SWE","USA","KEN","ZAF")

	collapse (sum) war_deaths_best war_deaths_low war_deaths_high, by(iso3 location_id year tot cause) fast

	assert war_deaths_low<=war_deaths_best
	assert war_deaths_best<=war_deaths_high
	
	gen war_rate = war_deaths_best / tot
	gen l_war_rate = war_deaths_low / tot
	gen u_war_rate = war_deaths_high / tot

	keep iso3 location_id year cause war_deaths_best war_rate l_war_rate u_war_rate
	rename (war_deaths_best war_rate l_war_rate u_war_rate) (deaths_best rate l_rate u_rate)
	
	// For merge	
	// Assert the relationship between low deaths high
	assert l_rate<=rate
	assert rate<=u_rate
	
	merge 1:1 iso3 location_id year cause using `disaster'
	drop _merge
	gen sex = "both"
	replace iso3 = iso3 + "_" + string(location_id) if location_id != .
	drop location_id
	
	tempfile all
	save `all', replace

// grab location names
	odbc load, exec("SELECT ihme_loc_id, location_name FROM shared.location_hierarchy_history WHERE location_set_version_id IN (SELECT max(location_set_version_id) AS location_set_version_id FROM shared.location_set_version WHERE location_set_id=35)") dsn(strConnection) clear

	tempfile loc_names
	save `loc_names', replace 

	// add location name for china no macau/hkg
	odbc load, exec("SELECT 'CHN_44533' AS ihme_loc_id, location_name FROM shared.location WHERE location_id=44533") dsn(strConnection) clear
	append using `loc_names'
	save `loc_names', replace

// merge in population
	do "$prefix/WORK/03_cod/01_database/02_programs/prep/code/env_long.do"

	// turn iso3 + location_id into ihme_loc_id
	gen ihme_loc_suffix = "_" + string(location_id) if location_id != .
	replace ihme_loc_suffix = "" if location_id==.
	gen ihme_loc_id = iso3 + ihme_loc_suffix

	// add location names
	merge m:1 ihme_loc_id using `loc_names', assert(2 3) keep(3) nogen

	// collapse to iso3 year
	collapse (sum) pop, by(ihme_loc_id year location_id location_name)
	gen sex = "both"
	rename ihme_loc_id iso3
	
	merge 1:m iso3 year sex using `all'
	drop if year < 1970
	drop if _m != 3
	drop _m
	
	
	rename pop total_population
	tostring year, gen(year2)
	drop year
	rename year2 year
	destring year, replace
	
	
	order iso3 year cause deaths_best rate l_rate u_rate total_population
	keep iso3 year cause deaths_best rate l_rate u_rate total_population
	
	isid iso3 year cause
	
	// save the final dataset
	saveold "WAR_DISASTER_DEATHS.dta", replace
	saveold "WAR_DISASTER_DEATHS_`date'.dta", replace
