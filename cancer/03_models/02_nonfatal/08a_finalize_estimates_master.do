// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Submits scripts to reformat final incidence and prevalence estimates, then convert to rate space (#events/population) for upload into Epi

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
** Accept Arguments or Set Defaults
** ****************************************************************
// accept or set arguments	
	args acause resubmission

** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/finalize_`acause'"
	capture mkdir "`log_folder'"

// Start Logs	
	log using "`log_folder'/_master.txt", replace

** ****************************************************************
** 
** ****************************************************************
// Set measure ids 
	local incidence_measure = 6
	local prevalence_measure = 5
	local types = "prevalence incidence" 

// output folder
	local output_folder = "$finalize_estimates_folder/`acause'"
	make_directory_tree, path("`output_folder'")

** ****************************************************************
** GET RESOURCES
** ****************************************************************
// get list of modelable entity ids
noisily di "`acause' $parameters_folder/modelable_entity_ids.dta"
	use "$parameters_folder/modelable_entity_ids.dta", clear
	keep if acause == "`acause'" & inlist(stage, "primary", "in_remission", "ectomy_adjustment", "disseminated", "terminal")
	levelsof modelable_entity_id, clean local(me_ids)
	tempfile m_ids
	save `m_ids', replace

// get list of locations that  expected in the upload
	use "$parameters_folder/locations.dta", clear
	capture levelsof location_id if model == 1 | regexm(ihme_loc_id, "_4"), clean local(modeled_locations)

** **************************************************************************
** RUN PROGRAGM
** **************************************************************************
// submit format script for each location
if !`resubmission' {
	local submission_cause = substr("`acause'", 5, .)
	foreach local_id in `modeled_locations'{
		$qsub -pe multi_slot 3 -l mem_free=6g -N "CRfn_`submission_cause'_`local_id'" "$shell" "$finalize_worker" "`acause' `local_id'"
	}
}
	
// Check for completion
noisily di "Finding outputs... "
foreach type in `types'{
	foreach m in `me_ids' {
		foreach local_id in `modeled_locations' {
			local checkfile = "`output_folder'/`m'/``type'_measure'_`local_id'.csv"
			check_for_output, locate_file("`checkfile'") timeout(1) failScript("$finalize_worker") scriptArguments("`acause' `local_id'") 
		}
	}
}

// save file indicating completion
	clear
	set obs 1
	generate str var1 = "done"
	save "`output_folder'/`acause'_finalized.dta", replace

// close log
capture log close

** ************
** END
** ************
