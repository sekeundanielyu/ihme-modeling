
// Purpose:		Launch scripts to calculate incremental survival for the desired causes, sexes, and locations in conjunction with cancer nonfatal modeling

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
	
// Ensure Presence of subfolders
	local output_folder "$survival_folder/`acause'"
	make_directory_tree, path("`output_folder'")

** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/survival_`acause'"
	capture mkdir "`log_folder'"
 
// Start Logs	
	capture log close _all
	capture log using "`log_folder'/_master.log", text replace

** ****************************************************************
** GET RESOURCES
** ****************************************************************	
// Get list of location ids
	use "$parameters_folder/locations.dta", clear
	capture levelsof(location_id) if model == 1, local(modeled_locations) clean
	keep location_id location_type
	tempfile locations
	save `locations', replace	

** **************************************************************************
** Submit Jobs, Check For Completion, Aggregate, and Save
** **************************************************************************
// Submit jobs
if !`resubmission' {
	local submission_cause = substr("`acause'", 5, .)
	foreach local_id in `modeled_locations' {
			$qsub -pe multi_slot 3 -l mem_free=6g -N "srvW_`submission_cause'_`local_id'" "$shell" "$survival_worker" "`acause' `local_id'"
	}	
} 

// Check for completion, compile and save
	clear
	noisily di "Finding and appending outputs... "
	foreach local_id in `modeled_locations' {
		local checkfile = "`output_folder'/survival_summary_`local_id'.dta"
		check_for_output, locate_file("`checkfile'") timeout(1) failScript("$survival_worker") scriptArguments("`acause' `local_id'") 
		append using "`checkfile'"
	}
	compress
	save "`output_folder'/survival_summary.dta", replace

// close log		
	capture log close

** *************
** END
** *************
