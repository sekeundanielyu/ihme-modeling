// PURPOSE: Append BRFSS files for each state for physical activity prevalence

// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		set maxvar 32000
		capture restore, not
	// Set to run all selected code without pausing
		set more off
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}

// Install "moss" function 

	ssc install moss 

// Set up locals 
	local data_dir "/snfs3/WORK/05_risk/temp/explore/second_hand_smoke/BRFSS"
	local files: dir "`data_dir'" files "*.dta"

//  Append datasets for each extracted microdata survey series/country together 
		use "`data_dir'/brfss_Alabama.dta", clear
		foreach file of local files {
			if "`file'" != "brfss_Alabama.dta" {
				di in red "`file'" 
				append using "`data_dir'/`file'", force
			}
		}
		
// Drop states / territories with no BRFSS data 
	drop if iso3 == ""

// Add spaces to state names so that they merge with the locations in the database 
	replace state = "District of Columbia" if state == "DistrictofColumbia"
	// replace state = "Puerto Rico" if state == "PuertoRico" 

// For the rest, can split based on capital letter 	
	moss state, match("([A-Z][^A-Z]*)") regex
	cap replace state = _match1 + " " + _match2 
	drop _count _match1 _pos1 
	cap drop _match2 _pos2 
	
	replace state = strrtrim(state)
	replace state = "Louisiana" if state == "Lousiana" 
	replace state = "Illinois" if state == "Illionis" 
	replace state = "District of Columbia" if state == "District of  Columbia"
	replace state = "Virgin Islands, U.S." if state == "Virgin Islands"
	tempfile data 
	save `data', replace 
	
// Bring in country codes 

	use "/snfs1/WORK/05_risk/02_models/smoking_shs/01_exp/01_tabulate/data/raw/countrycodes2015.dta", clear 
	keep if regexm(iso3, "USA") | location_type == "nonsovereign" 
	
	rename location_name state 
	tempfile country_codes
	save `country_codes', replace 
	
// Merge with dataset 

	merge 1:m state using `data', keep(2 3 4 5) nogen 
	
// Save 

	save "/snfs1/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped/brfss_prepped_states.dta", replace
	
	

	
	
	
	
	

	
