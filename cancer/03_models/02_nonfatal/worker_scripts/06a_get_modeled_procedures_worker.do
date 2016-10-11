// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Extract -ectomies from the epi database

** **************************************************************************
** Configuration
** 		
** **************************************************************************
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"

// Set STATA workspace 
	set more off
	capture set maxvar 32000
	
// Set common directories, functions, and globals (shell, finalize_worker, finalization_folder...)
	run "$j/WORK/07_registry/cancer/03_models/02_yld_estimation/01_code/subroutines/set_paths.do"
		
** ****************************************************************
** SET MACROS FOR CODE
** ****************************************************************
// Accept arguments
	args rate_id data_type resubmission

// Ensure Presence of subfolders
	local output_folder "$modeled_procedures_folder/`rate_id'"
	capture make_directory_tree, path("`output_folder'")

// Set location at which to save a copy of the draws as downloaded (before format)
	local downloaded_draws = "`output_folder'/`rate_id'_`data_type'_draws.dta"

** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/get_mod_proc_`rate_id'"
	capture mkdir "`log_folder'"
 
// Start Logs	
	capture log close _all
	capture log using "`log_folder'/`data_type'.log", text replace

** ****************************************************************
** GET GBD RESOURCES
** ****************************************************************
// Get countries
	use "$parameters_folder/locations.dta", clear
	tempfile locations
	save `locations', replace
	capture levelsof(location_id) if model == 1, local(local_ids) clean

// get measure_ids
	use "$parameters_folder/constants.dta", clear
	local incidence_measure = incidence_measure_id[1]
	local prevalence_measure = prevalence_measure_id[1]

// Import function to retrieve epi estimates 
	run "$get_draws"

** **************************************************************************
** Get Proportion Data
** **************************************************************************
// Get draws
capture confirm file "`downloaded_draws'"
if !`resubmission' | _rc {
	get_draws, gbd_id_field(modelable_entity_id) source(dismod) measure_ids(``data_type'_measure') gbd_id(`rate_id') clear
	save "`downloaded_draws'", replace
}
else use "`downloaded_draws'", clear

// Rename variables and keep variables of interest
	rename (year_id sex_id) (year sex)
	keep location_id year age sex modelable_entity_id draw_*
 	rename draw_* procedure_rate_*

// Reformat Age
	convert_from_age_group
	tostring(age), replace format("%12.2f") force
	destring(age), replace
	
// convert from rate
	drop if age > 80
	merge m:1 location_id year sex age using "$population_data", keep(1 3) assert(2 3) nogen
	foreach i of numlist 0/999 {
		gen procedures_`i' = procedure_rate_`i'*pop 
	}

// keep relevant variables and save
	keep location_id modelable_entity_id sex year age procedures_*
	order location_id modelable_entity_id sex year age procedures_*
	compress
	save "`output_folder'/modeled_`data_type'_`rate_id'.dta", replace

// close log
	capture log close

** ************
** END
** ************
