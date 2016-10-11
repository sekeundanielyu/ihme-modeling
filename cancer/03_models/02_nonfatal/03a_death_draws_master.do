// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Submit mortality jobs

** **************************************************************************
** Configuration
** 		
** **************************************************************************
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"

// Set STATA workspace 
	clear all
	set more off
	set maxvar 32000
	
// Set common directories, functions, and globals (shell, finalize_worker, finalization_folder...)
	run "$j/WORK/07_registry/cancer/03_models/02_yld_estimation/01_code/subroutines/set_paths.do"
			
** ****************************************************************
** SET MACROS FOR CODE
** ****************************************************************	
// Accept or default arguments	
	args CoD_model resubmission

	// set arguments if none sent
	if "`CoD_model'" == "" local acause neo_bladder
	if "`resubmission'" == "" local resubmission = 1

// Output folder
	local output_folder "$mortality_folder/`CoD_model'"
	capture make_directory_tree, path("`output_folder'")

** ****************************************************************
** Generate Log Folder and Start Logs 
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/death_draws_`CoD_model'"
	capture mkdir "`log_folder'"

// Start Logs	
	capture log close _all
	log using "`log_folder'/_master.log", text replace

** ****************************************************************
** GET GBD RESOURCES
** ****************************************************************	
// Get list of location ids
	use "$parameters_folder/locations.dta", clear
	capture levelsof(location_id) if model == 1, local(modeled_locations) clean
	capture levelsof(location_id), clean local(all_locations)
	keep location_id location_type
	tempfile location_info
	save `location_info', replace	

** **************************************************************************
** Submit Jobs, Check For Completion, Aggregate, and Save
** **************************************************************************
// Submit jobs
if !`resubmission' {
	local submission_cause = substr("`CoD_model'", 5, .)
	foreach local_id in `modeled_locations' {
		$qsub -pe multi_slot 2 -l mem_free=4g -N "mrtW_`submission_cause'_`local_id'" "$shell" "$mortality_worker" "`CoD_model' `local_id'"
	}
}
noisily di "`output_folder'"
// Check for completion
	clear
	noisily di "Finding outputs... "
	foreach local_id in `modeled_locations' {
		local checkfile = "`output_folder'/death_summary_`local_id'.dta"
		check_for_output, locate_file("`checkfile'") sleepInterval(20) timeout(0) failScript("$mortality_worker") scriptArguments("`CoD_model' `local_id'")
	}

// Aggregate files to parent locations
	run "$aggregate_locations" "death" "death_" `output_folder'

// Compile summaries
	clear
	foreach local_id in `modeled_locations' {
		local appendFile = "`output_folder'/death_summary_`local_id'.dta"
		append using "`appendFile'"
	}
	merge m:1 location_id using `location_info', keep(1 3) nogen
	compress
	save "`output_folder'/death_summary.dta", replace
	
// close log		
	capture log close

** *******
** END
** *******
