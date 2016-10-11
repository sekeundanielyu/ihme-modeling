
// Purpose:	Map causes as they appear in data sources to GBD causes

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

// Accept Arguments
	args group_folder data_name data_type

// Create Arguments if Running Manually
if "`group_folder'" == "" {
	local group_folder = "TUR"
	local data_name = "TUR_provinces_2002_2008"
	local data_type = "inc"
}

// Load common settings and default folders.
	do `load_common' 0 "`group_folder'" "`data_name'" "`data_type'"

// set folders
	local data_folder = r(data_folder)
	local metric = r(metric)
	local temp_folder = r(temp_folder)

// set output_filename
	local output_filename = "03_mapped_`data_type'"

// set location at which to save missing codes if found
	local missing_codes = "`temp_folder'/`data_name'_MISSING_CODES_`data_type'.dta"
	capture remove "`missing_codes'"

** **************************************************************************
** Get Additional Resources
** **************************************************************************
// Get cause map
	use "$j/WORK/07_registry/cancer/01_inputs/programs/mapping/data/map_cancer_`data_type'.dta", clear
	levelsof coding_system, clean local(coding_system_maps)
	tempfile cause_map
	save `cause_map', replace

// Get age-sex restrictions
	use "$j/WORK/00_dimensions/03_causes/gbd2015_causes_all.dta", clear
	keep acause male female
	keep if substr(acause, 1, 4) == "neo_"
	rename acause gbd_cause
	tempfile sex_restrictions
	save `sex_restrictions', replace

** **************************************************************************
** Map Data
**		Connect each cause/cause_name with it's corresponding GBD cause
** **************************************************************************
	** ************************
	** Prepare Data
	** ************************
	// GET DATA
		use "`data_folder'/02_subtotals_disaggregated_`data_type'.dta", clear
		
	// regenerate metric totals (some metric totals were dropped during subtotal disaggregation)
		capture drop `metric'1
		egen `metric'1 = rowtotal(`metric'*)
	
	// keep only data of interest
		keep iso3 subdiv location_id national source NID registry gbd_iteration year_start year_end frmat_* im_frmat_* sex coding_system cause cause_name `metric'* 
		
	// Check coding systems
		replace coding_system = trim(coding_system)
		gen ok_coding_system = 0
		foreach sys in `coding_system_maps'{
			replace ok_coding_system = 1 if coding_system == "`sys'"
		}
		count if ok_coding_system == 0
		if r(N) {
			display in red "ERROR: There are non-standard coding systems.  Coding systems must be ICD10, ICD9_detail, ICCC, CUSTOM, or CUSTOM_CHN"
			BREAK
		}
		drop ok_coding_system

	** ************************
	** Merge with Map
	** ************************
		// // Merge with special custom maps. 
			foreach special_map_name in `coding_system_maps' {
				// skip non-exception maps
					if substr("`special_map_name'", 1, 7) != "CUSTOM_" continue
				
				// determine the map type and set item to check
					if length("`special_map_name'") == 10 local check_var = "iso3"
					else local check_var = "source"
					local check_for = substr("`special_map_name'", 8, .)
				
				// check for data that matches the map type. if it does, exit the loop
					levelsof `check_var', clean local(to_check)
					local has_special = 0
					foreach tick in `to_check' {
						if "`tick'" == "`check_for'" {
							local map_name = "`special_map_name'"
							local has_special = 1
							exit
						}
					}
			}

			// if dataset contains a special map type...
			if `has_special' {
				di "`map_name'"
				// create a unique CUSTOM map specific to the dataset
				preserve 
					use `cause_map',clear
					duplicates tag cause_name, gen(tag)
					drop if tag != 0 & coding_system != "`map_name'"
					drop tag
					replace coding_system = "CUSTOM" if coding_system == "`map_name'"
					tempfile special_map
					save `special_map', replace
				restore
				
				// merge the unique map with the data
				keep if `check_var' == "`check_for'"
				merge m:1 cause cause_name coding_system using `special_map', keep(1 3)
				gen mapped = 1 if _merge == 3
				drop _merge
				tempfile specially_mapped
				save `specially_mapped', replace
				
			// merge the results with the rest of the data
				drop if mapped == 1
				merge m:1 cause cause_name coding_system using `cause_map', keep(1 3 4) update nogen
				replace mapped = 1
				append using `specially_mapped'
				drop if mapped != 1
				drop mapped
			}
			else merge m:1 cause cause_name coding_system using `cause_map', keep(1 3) nogen 
	
	** ************************
	** Verify Mapping
	** ************************
	// Check for unmapped codes
		count if gbd_cause == "" 
		if r(N) {
			keep cause cause_name coding_system gbd_cause acause*
			keep if gbd_cause == ""
			duplicates drop
			save "`missing_codes'", replace
			display in red "ALERT: Not all codes matched to GBD causes. Please add the unmatched codes to the cause map before proceeding."
			BREAK
		}

	** ************************
	** Expand any remaining ICD10 code ranges. 
	** ************************
	// Expand any remaining ICD10 code ranges if they are mapped as garbage codes and have no additional causes. 
		count if regexm(cause, "-") & coding_system == "ICD10" & gbd_cause == "_gc" & acause1 == "_gc"
		if r(N) {
			// Disaggregate ranges
			preserve
				keep if regexm(cause, "-") & coding_system == "ICD10" & gbd_cause == "_gc" & acause1 == "_gc"
				duplicates drop
				save "`temp_folder'/03_to_be_disaggregated.dta", replace
				capture saveold "`temp_folder'/03_to_be_disaggregated.dta", replace
				// Run python script 
					!python "$code_prefix/01_inputs/01_registry/03_mapping/subroutines/disaggregate_codes.py" "`group_folder'" "`data_folder'" "`data_type'"
					
					// format outputs of python script
					use "`temp_folder'/03_causes_disaggregated_`data_type'.dta", clear
					keep orig_cause subcauses
					duplicates drop
					rename (orig_cause subcauses) (cause acause)
					split acause, p(",")
					drop acause
					gen gbd_cause = "_gc"
					tempfile range_causes
					save `range_causes', replace
			restore
			merge m:1 cause gbd_cause using `range_causes', keep(1 3 4 5) update replace nogen
		}
		
		// handle comma-separated causes
		count if regexm(cause, ",")  & !regexm(cause, "-") & coding_system == "ICD10" & gbd_cause == "_gc" & acause1 == "_gc"
		if r(N) {
			preserve
				keep if regexm(cause, ",")  & !regexm(cause, "-") & coding_system == "ICD10" & gbd_cause == "_gc" & acause1 == "_gc"
				keep cause
				duplicates drop
				gen acause = cause
				split acause, p(",")
				drop acause
				gen gbd_cause = "_gc"
				tempfile comma_separated_causes
				save `comma_separated_causes', replace
			restore
			merge m:1 cause gbd_cause using `comma_separated_causes', keep(1 3 4 5) update replace nogen
		}
	
	** ************************
	** Finalize
	** ************************
	
	// Drop subtotals and codes that cannot be disaggregated
		drop if gbd_cause == "sub_total" | gbd_cause == "_none"

	// Replace special coding system (replace ICCC mark with "CUSTOM")
		replace coding_system = "CUSTOM" if !inlist(coding_system, "ICD10", "ICD9_detail")
	
	// Apply sex restrictions
		merge m:1 gbd_cause using `sex_restrictions', keep(1 3)
		drop if _merge == 3 & sex == 1 & male == 0
		drop if _merge == 3 & sex == 2 & female == 0
		drop male female _merge
	
	// Collapse
		collapse (sum) `metric'*, by(iso3 subdiv location_id national source NID registry gbd_iteration year_start year_end frmat_* im_* sex coding_system cause cause_name gbd_cause acause*) fast
	
	// SAVE
		compress
		save "`r(output_folder)'/`output_filename'.dta", replace
		save "`r(archive_folder)'/`output_filename'_$today.dta", replace
		save "`r(permanent_copy)'/`output_filename'.dta", replace


	capture log close
** **************************************************************************
** END mapping.do
** **************************************************************************
