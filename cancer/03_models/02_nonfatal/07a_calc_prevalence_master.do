// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:	Launch scripts to calculate prevalence for the desired causes, sexes, and locations in conjunction with cancer nonfatal modeling

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
** SET MACROS
** ****************************************************************
// Accept or default arguments
	args acause resubmission
	if "`acause'" == "" local acause neo_lung
	if "`resubmission'" == "" local resubmission = 0
	
// Ensure Presence of subfolders
	local output_folder "$prevalence_folder/`acause'"
	make_directory_tree, path("`output_folder'")

** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/prevalence_`acause'"
	capture mkdir "`log_folder'"

// Start Logs	
	capture log using "`log_folder'/_master.log", text replace

** ****************************************************************
** GET RESOURCES
** ****************************************************************	
// Get list of location ids
	use "$parameters_folder/locations.dta", clear
	capture levelsof(location_id) if model == 1, local(modeled_locations) clean
	capture levelsof(location_id) if location_id != 1, clean local(all_locations)
	keep location_id location_type
	tempfile location_info
	save `location_info', replace	
	local modeled_locations = "10"

** **************************************************************************
** Submit Jobs, Check For Completion, Aggregate, and Save
** **************************************************************************
// Submit jobs
if !`resubmission' {
	local submission_cause = substr("`acause'", 5, .)
	foreach local_id in `modeled_locations' {
			$qsub -pe multi_slot 3 -l mem_free=6g -N "pvW_`submission_cause'_`local_id'" "$shell" "$prevalence_worker" "`acause' `local_id'"
				}	
}

// Check for completion
	noisily di "Finding outputs... "
	foreach local_id in `modeled_locations' {
		local checkfile = "`output_folder'/prevalence_summary_`local_id'.dta"
		check_for_output, locate_file("`checkfile'") timeout(1) failScript("$prevalence_worker") scriptArguments("`acause' `local_id'") 
	}

// Aggregate files to parent locations
	run "$aggregate_locations" "prevalence" "prevalence_" `output_folder'

// Compile summaries
	clear
	foreach local_id in `modeled_locations' {
		local appendFile = "`output_folder'/prevalence_summary_`local_id'.dta"
		append using "`appendFile'"
	}
	merge m:1 location_id using `location_info', keep(1 3) nogen
	compress
	save "`output_folder'/prevalence_summary.dta", replace

// close log		
	capture log close

** *************
** END
** *************
