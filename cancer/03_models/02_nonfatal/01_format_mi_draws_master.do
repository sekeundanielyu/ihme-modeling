// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Submit incidence jobs

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
// Accept or default arguments	
	args mi_cause resubmission 
	// set arguments if not sent
	if "`mi_cause'" == "" local mi_cause neo_melanoma
	if "`resubmission'" == "" local resubmission = 0
		
// Set output folder and folder to be used after file adjusted by prevalence
	local output_folder "$formatted_mi_folder/`mi_cause'"
	capture make_directory_tree, path("`output_folder'")

** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
if !`resubmission'{
// Log folder
	local log_folder "$log_folder_root/format_mi_`mi_cause'"
	make_directory_tree, path("`log_folder'")

// Start Logs	
	capture log close _all
	capture log using "`log_folder'/_master.log", text replace
}

** ****************************************************************
** GET RESOURCES
** ****************************************************************	
// Get list of location ids
	use "$parameters_folder/locations.dta", clear
	capture levelsof location_id if model == 1, local(modeled_locations) clean
	capture levelsof location_id, clean local(all_locations)
	
	// FOR GBD2015 ONLY: make list of exceptions for which to use the previous mi ratios
		#delim ;
		if "`mi_cause'" != "neo_melanoma" local exceptions = "";
		else local exceptions = "67 35424 35425 35426 35427 35428 35429 35430
		 35431 35432 35433 35434 35435 35436 35437 35438 35439 35440 35441 
		 35442 35443 35444 35445 35446 35447 35448 35449 35450 35451 35452 
		 35453 35454 35455 35456 35457 35458 35459 35460 35461 35462 35463 
		 35464 35465 35466 35467 35468 35469 35470";	
		#delim cr

** **************************************************************************
** Submit Jobs, Check For Completion, Aggregate, and Save
** **************************************************************************
// Submit jobs
if !`resubmission' {
	local submission_cause = substr("`mi_cause'", 5, .)
	foreach local_id in `modeled_locations' {
		// if exception, send option to use old mi ratios
		local is_exception = 0
		foreach exception of local exceptions {
			if "`local_id'" == "`exception'" local is_exception = 1
			di "location `local_id' is an exception"
		}	
		$qsub -pe multi_slot 3 -l mem_free=6g -N "CRfmiW_`submission_cause'_`local_id'" "$shell" "$format_mi_worker" "`mi_cause' `local_id' `is_exception'"
	}
}

// Check for completion
	noisily di "Finding outputs... "
	clear
	foreach local_id in `modeled_locations' {
		//
		local checkfile = "`output_folder'/formatted_mi_draws_`local_id'.dta"
		
		// if exception, send option to use old mi ratios
		foreach exception of local exceptions {
			if "`local_id'" == "`exception'" local is_exception = 1
			di "location `local_id' is an exception"
		}	
		if `is_exception' check_for_output, locate_file("`checkfile'") sleepInterval(10) timeout(.5) failScript("$format_mi_worker") scriptArguments("`mi_cause' `local_id' 1")
		else check_for_output, locate_file("`checkfile'") sleepInterval(10) timeout(.5) failScript("$format_mi_worker") scriptArguments("`mi_cause' `local_id'")
			
		//
		append using "`checkfile'"	
	}
	compress
	save "`output_folder'/compiled_mi.dta", replace

// close log
	capture log close

** *******
** END
** *******
