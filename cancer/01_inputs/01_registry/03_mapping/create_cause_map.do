
// Purpose:	Create cause map for use in cancer prep

** **************************************************************************
** CONFIGURATION  (AUTORUN)
** 		Define J drive location. Sets application preferences (memory allocation, variable limits). 
** **************************************************************************
	// Clear memory and set STATA to run without pausing
		clear all
		set more off
		set maxvar 32000

** ****************************************************************
** SET FORMAT FOLDERS and START LOG (if on Unix) (AUTORUN)
** 		Sets output_folder, archive_folder, data_folder
** 
** ****************************************************************
	// Define load_common function depending on operating system. Load common will load common functions and filepaths relevant for registry intake
		if c(os) == "Unix" local load_common = "/ihme/code/cancer/cancer_estimation/01_inputs/_common/set_common_reg_intake.do"
		else if c(os) == "Windows" local load_common = "J:/WORK/07_registry/cancer/01_inputs/_common/set_common_reg_intake.do"

	// Load common settings and default folders.
		do `load_common' 0 "`_parameters'" "mapping"

	// set folders
		local temp_folder = r(temp_folder)
		local archive_folder = r(archive_folder)

	// set subroutine
		local format_map = "$code_prefix/03_mapping/subroutines/format_map.do"

** *************************************************************************
** Get CoD maps 
** *************************************************************************
	// Get ICD10 YLD causes for incidence
		use "$j/WORK/00_dimensions/03_causes/temp/map_ICD10.dta", clear   
		keep if inlist(substr(cause_code, 1, 1), "C", "D")
		keep cause_code cause_name yll_cause yld_cause yll_cause_name yld_cause_name
		// Add decimal
		replace cause_code = substr(cause_code, 1, 3) + "." + substr(cause_code, 4, .) if strlen(cause_code) > 3
		// Append and save
		gen coding_system = "ICD10"
		duplicates drop
		compress
		tempfile icd_cause_map
		save `icd_cause_map', replace

	// Get ICD9_detail YLD causes for incidence
		use "$j/WORK/00_dimensions/03_causes/temp/map_ICD9_detail.dta", clear
		drop if inlist(substr(lower(cause_code), 1, 1), "v", "e", "a", "z", "c", "u")
		keep cause_code cause_name yll_cause yld_cause yll_cause_name yld_cause_name
		// Add decimal
		replace cause_code = substr(cause_code, 1, 3) + "." + substr(cause_code, 4, .) if strlen(cause_code) > 3
		// drop non-cancer data
		gen test = real(cause_code)
		drop if test < 140 | test >= 240
		drop test
		// append and save
		gen coding_system = "ICD9_detail"
		append using `icd_cause_map'
		duplicates drop
		compress
		save `icd_cause_map', replace
		
	// Drop irrelevant data and remove unnecessary characters
		foreach var of varlist _all {
			tostring `var', replace
		}
		capture _strip_labels * 

	// Ensure that there are no empty entries
		replace yld_cause = yll_cause if yld_cause == "" & yll_cause != ""
		replace yll_cause = yld_cause if yll_cause == "" & yld_cause != ""
		
	// save
		save "`temp_folder'/icd_cause_map.dta", replace

** **************************************************************************
** Get data and keep relevant
** **************************************************************************
	// Get file and save archived copy
		import delimited using "$parameters_folder/mapping/custom_cancer_map.csv", clear varnames(1)
		
	// Check that all data is present. 
		drop if coding_system == "" & cause_name == "" & gbd_cause == "" & cause == ""
		replace gbd_cause = trim(gbd_cause)
		replace gbd_cause = "" if gbd_cause == "."
		count if gbd_cause == "" | (cause == "" & cause_name == "")
		if r(N) > 0 {
			noisily di "All gbd_cause, cause, and cause_name values must be present to format this map. Please correct errors and re-run."
		}	

	// Drop irrelevant data and remove unnecessary characters
		foreach var of varlist _all {
			tostring `var', replace
		}
		keep coding_system cause cause_name gbd* additional_cause*
		capture _strip_labels * 

	// mark data as priority for use in removing duplicates
		gen remap = 1

	// save the verified input
		save "`temp_folder'/formatted_custom_cancer_map.dta", replace
		saveold "`temp_folder'/_archive/formatted_custom_cancer_map`today'.dta", replace

** *************************************************************************
** Create Incidence Map
** *************************************************************************
	// Get ICD YLD causes for incidence
		use "$parameters_folder/mapping/icd_cause_map.dta", clear
		keep coding_system cause_code yld_cause*
		rename (cause_code yld_cause*) (cause gbd_cause*)
		gen additional_cause1 = gbd_cause if gbd_cause != "_gc"
	
	// Add cancer-specific mapping
		append using "`temp_folder'/formatted_custom_cancer_map.dta"
		replace additional_cause1 = gbd_cause if additional_cause1 == "" & gbd_cause != "_gc"
		replace additional_cause1 = cause if additional_cause1 == "" & gbd_cause == "_gc" & regexm(coding_system, "ICD")

	// Format Incidence Map
		do "`format_map'"

	// Save
		save "$parameters_folder/mapping/map_cancer_inc.dta", replace
		save "$archive_folder/map_cancer_inc_${today}.dta", replace

** *************************************************************************
** Create Mortality Map
** *************************************************************************
	// Get ICD YLL causes for mortality
		use "$parameters_folder/mapping/icd_cause_map.dta", clear
		keep coding_system cause_code yll_cause*
		rename (cause_code yll_cause*) (cause gbd_cause*)
		gen additional_cause1 = gbd_cause if gbd_cause != "_gc"
	
	// Add cancer-specific mapping
		append using "`temp_folder'/formatted_custom_cancer_map.dta"
		replace additional_cause1 = gbd_cause if additional_cause1 == "" & gbd_cause != "_gc"
		replace additional_cause1 = cause if additional_cause1 == "" & gbd_cause == "_gc" & regexm(coding_system, "ICD")

	// re-categorize benign causes
		foreach v of varlist gbd_cause additional_cause* {
			replace `v' = subinstr(`v', "_benign", "", .)
		}

	// Format Mortality Map
		do "`format_map'"

	// Save
		save "$parameters_folder/mapping/map_cancer_mor.dta", replace
		save "$archive_folder/map_cancer_mor_${today}.dta", replace

capture log close

** **************************
** END 
** **************************
