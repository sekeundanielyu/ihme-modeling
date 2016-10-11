// DATE: January 4, 2016
// PURPOSE: Append VIGITEL files for each Brazilian city for physical activity prevalence


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

// Get demographics 
	
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	get_demographics, gbd_team(epi) make_template clear
	collapse (first) location_id, by(location_name)
	tempfile country_codes 
	save `country_codes', replace

// Set up locals 
	local codebook "J:/WORK/05_risk/risks/activity/data/exp/raw" 
	local out_dir "J:/WORK/05_risk/risks/activity/data/exp/prepped"

/*
	local data_dir "/snfs3/WORK/05_risk/temp/explore/physical_activity/exposure"
	local files: dir "`data_dir'" files "*.dta"

//  Append datasets for each extracted microdata survey series/country together 
		use "`data_dir'/vigitel_aracaju.dta", clear
		foreach file of local files {
			if "`file'" != "vigitel_aracaju.dta" {
				di in red "`file'" 
				append using "`data_dir'/`file'", force
			}
		}
		
		tempfile compiled 
		save `compiled', replace 

// Save 
	save "/snfs1/WORK/05_risk/risks/activity/data/exp/raw/vigitel_compiled.dta", replace
*/

// Merge on with codebook 
	
	use "`codebook'/vigitel_compiled.dta", clear
	tempfile compiled 
	save `compiled', replace 

	import excel "`codebook'/vigitel_codebook.xlsx", firstrow clear 
	replace state = "Piaui" if state == "Piauí"
	merge 1:m city using `compiled', nogen keep(3) 
	rename state location_name

	merge m:1 location_name using `country_codes', nogen keep(3)


// Drop if sample size < 10 because it will produce unstable estimates
	drop if sample_size < 10 

// Clean up data 
	drop city city_number 

// Urbanicity / representativeness variable 
	
	gen urbanicity = 2 // just sampled in capital cities of the states 
	gen representative_name = 3 // not representative of that subnational location (state)

// Save

	save "`out_dir'/vigitel_prepped.dta", replace
