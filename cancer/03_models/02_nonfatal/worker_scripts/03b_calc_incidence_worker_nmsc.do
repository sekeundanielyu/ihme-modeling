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
		
// Accept Arguments
	args acause local_id

// Ensure Presence of subfolders
	local output_folder "$incidence_folder/neo_nmsc"
	local output_folder "$incidence_folder/`acause'"
	capture make_directory_tree, path("`output_folder'")

** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/total_incidence_`acause'"
	capture mkdir "`log_folder'"

// Start Logs	
	capture log close _all
	capture log using "`log_folder'/all_location_ids.log", text replace

** ****************************************************************
** GET GBD RESOURCES
** ****************************************************************
// load summary functions
	run "$summary_functions"

** **************************************************************************
** 
** **************************************************************************
// Load the modeled incidence data
	use "`output_folder'/incidence_download.dta", clear
	gen acause = "`acause'"
	
// Keep relevant data
	keep if location_id == `local_id'
	keep location_id year sex age acause incidence_*
	order location_id year sex age acause incidence_*

// Merge on population
	merge m:1 location_id year sex age using "$population_data", keep(1 3) assert(2 3) nogen
	display "Converting incidence rates to counts"
	foreach var of varlist incidence_* {
		display "converting `var'"
		replace `var' = `var' * pop
	}
	
// Calculate ASR
	asr, relevant_vars("location_id year sex age acause") data_var("incidence")
	
// Save draws
	keep location_id year sex age acause incidence_*
	order location_id year sex age acause
	sort location_id year sex age acause
	compress
	save "`output_folder'/incidence_draws_`local_id'.dta", replace

// Calculate summary statistics
	calculate_summary_statistics, data_var("incidence")

// Reformat
	keep location_id year sex age acause mean_incidence lower_incidence upper_incidence
	order location_id year sex age acause mean_incidence lower_incidence upper_incidence
	sort location_id year sex age

// Save summary
	compress
	save "`output_folder'/incidence_summary_`local_id'.dta", replace

// close log
	capture log close

** ************
** END
** ************
