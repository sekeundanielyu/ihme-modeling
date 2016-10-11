// PURPOSE: Append VIGITEL files for each Brazilian city for SHS prevalence

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
	
	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & inlist(level, 3, 4)

	keep location_id location_ascii_name ihme_loc_id
	rename location_ascii_name location_name 

	duplicates tag location_name, gen(dup)
	drop if dup == 1 & regexm(ihme_loc_id, "MEX") & location_name == "Distrito Federal" // only looking at Brazil here so don't want this  

	duplicates drop location_name, force
	drop dup

	tempfile country_codes 
	save `country_codes', replace

// Set up locals 
	local codebook "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw" 
	local out_dir "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped"

	local data_dir "/share/epi/risk/temp/smoking_shs/"
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
	save "/snfs1/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/vigitel_compiled.dta", replace

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
	tostring year_start, replace
	replace file = "J:/DATA/BRA/SURVEILLANCE_SYSTEM_OF_RISK_FACTORS_FOR_CHRONIC_DISEASES_BY_TELEPHONE_INTERVIEWS_VIGITEL/" + year_start
	destring year_start, replace

// Urbanicity / representativeness variable 
	
	//gen urbanicity = 2 // just sampled in capital cities of the states 
	//gen representative_name = 3 // not representative of that subnational location (state)

// Save

	tostring location_id, replace 
	replace iso3 = iso3 + "_" + location_id 
	destring location_id, replace

	save "`out_dir'/vigitel_prepped.dta", replace
