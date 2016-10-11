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
	args rate_id resubmission

// set list of data_types
	local data_types = "prevalence incidence"

** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/get_mod_proc_`data_type'_`rate_id'"
	capture mkdir "`log_folder'"
 
// Start Logs	
	capture log close _all
	capture log using "`log_folder'/`rate_id'.log", text replace

** **************************************************************************
** Submit Jobs, Check For Completion, Aggregate, and Save
** **************************************************************************
// Submit jobs
if !`resubmission' {
	foreach data_type in `data_types' {
			$qsub -pe multi_slot 3 -l mem_free=6g -N "gmpW_`rate_id'_`data_type'" "$shell" "$get_modeled_procedures_worker" "`rate_id' `data_type'"
	}	
}

// Check for completion
	noisily di "Finding outputs... "
	foreach data_type in `data_types' {
		local checkfile = "$modeled_procedures_folder/`rate_id'/modeled_`data_type'_`rate_id'.dta"
		if !`resubmission' check_for_output, locate_file("`checkfile'") timeout(30) failScript("$get_modeled_procedures_worker") scriptArguments("`rate_id' `data_type' 1") 
		else check_for_output, locate_file("`checkfile'") timeout(0) failScript("$get_modeled_procedures_worker") scriptArguments("`rate_id' `data_type' 1") 
	}

// Save verification file
	clear
	set obs 1 
	gen modeled_procedures = "obtained"
	save "$modeled_procedures_folder/`rate_id'_obtained.dta", replace

// close log		
	capture log close

** *************
** END
** *************
