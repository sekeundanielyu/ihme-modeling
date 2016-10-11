// GBD2015 Fatal Discontinuities: Add confidence intervals for ebola data

	clear all
	set more off

	if c(os) == "Windows" {
		global prefix ""
	}
	else {
		global prefix ""
		set odbcmgr unixodbc
	}

	global datadir ""
	global outdir ""
	
	local date = c(current_date)

	do "create_connection_string.ado"
	do "get_location_metadata.ado"
	
	
	// Population for 1970 - 2015
	create_connection_string
	odbc load, exec("SELECT year_id, location_id, sex_id, age_group_id, mean_pop, age_group_name_short FROM mortality.output JOIN mortality.output_version USING (output_version_id) JOIN shared.age_group USING (age_group_id) WHERE is_best = 1") `r(conn_string)' clear
	keep if sex_id == 3	// Both sexes
	keep if age_group_id == 22	// All ages
	keep year_id location_id mean_pop
	rename year_id year
	tempfile population
	save `population', replace


	// Location metadata
	get_location_metadata, location_set_id(35) clear
	keep if location_type == "admin0"
	keep location_id ihme_loc_id
	rename ihme_loc_id iso3
	isid iso3
	tempfile locations
	save `locations', replace

	
	// bring in formatted data
	use "shocks_formatted.dta", clear
	
	gen cause = "ebola"

	rename location_id old_id

	merge m:1 iso3 using `locations', keep(3) assert(2 3) nogen
	replace location_id = old_id if old_id != .
	drop old_id
	
	tostring sex, replace force
	replace sex = "male" if sex == "1"
	replace sex = "female" if sex == "2"
	replace sex = "both" if sex == "9"
	
	reshape long deaths, i(iso3 location_id cause NID sex year) j(age)
	
	drop if deaths == 0

	// Standardize ages to GBD age_ids
	drop if age == 1
	gen age_group_id = .
	// recode anything under 1 to Perinatal (28-365 days)
	assert !inlist(age, 91, 92, 93, 94)
	replace age_group_id = 4 if age == 2
	replace age_group_id = 5 if age == 3
	replace age_group_id = 6 if age == 7
	replace age_group_id = 7 if age == 8
	replace age_group_id = 8 if age == 9
	replace age_group_id = 9 if age == 10
	replace age_group_id = 10 if age == 11
	replace age_group_id = 11 if age == 12
	replace age_group_id = 12 if age == 13
	replace age_group_id = 13 if age == 14
	replace age_group_id = 14 if age == 15
	replace age_group_id = 15 if age == 16
	replace age_group_id = 16 if age == 17
	replace age_group_id = 17 if age == 18
	replace age_group_id = 18 if age == 19
	replace age_group_id = 19 if age == 20
	replace age_group_id = 20 if age == 21
	replace age_group_id = 21 if age >= 22 & age <= 25
	assert age_group_id != .

	collapse (sum) deaths, by(iso3 location_id year cause NID sex age_group_id)
	rename age_group_id age
	
	merge m:1 year location_id using `population'
	keep if _m == 3
	drop _m
	rename mean_pop pop
	
	// Apply correction factors for reporting vs actual ebola deaths. These correction factors not applied to non-West African 2014 ebola epidemic deaths, assumed these deaths are considered accurate. 3 countries are USA, Mali and Nigeria
	gen tag = 0
	replace tag = 1 if inlist(iso3, "USA","MLI","NGA") & year == 2014
	replace tag = 1 if iso3 == "SSD" & year == 2004
	
	gen best = deaths * 100 / 60 if tag == 0
	replace best = deaths if tag == 1
	
	gen upper = deaths * 100 / 50 if tag == 0
	replace upper = deaths if tag == 1
	
	gen lower = deaths * 100 / 70 if tag == 0
	replace lower = deaths if tag == 1
	
	drop tag	
	drop deaths
	
	// disaster rate
	gen disaster_rate = best / pop
	
	assert lower <= upper

	gen l_disaster_rate = lower / pop
	gen u_disaster_rate = upper / pop
	
	// make sure that disaster rate is between the lower and upper bounds
	assert disaster_rate >= l_disaster_rate
	assert disaster_rate <= u_disaster_rate
	

	compress

	// save in our folder
	save "ebola_cis.dta", replace
	save "ebola_cis_`date'.dta", replace
	
	
	
