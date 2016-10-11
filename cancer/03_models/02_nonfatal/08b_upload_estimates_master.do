// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Upload incidence and prevalence rate estimates into Epi for Dismod estimation

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
// accept or set arguments	
	args acause resubmission

// Set output folder and ensure that it exists
	local output_folder = "$upload_estimates_folder/`acause'"
	capture make_directory_tree, path("`output_folder'")

** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/upload"
	make_directory_tree, path("`log_folder'")

// Start Logs	
	capture log close _all
	capture log using "`log_folder'/upload_`acause'.txt", text replace

** ****************************************************************
** GET RESOURCES
** ****************************************************************
// get causes
	use "$parameters_folder/causes.dta", clear
	levelsof(acause) if model == 1, local(causes) clean

// get modelable entity ids
	use "$parameters_folder/modelable_entity_ids.dta", clear
	keep if inlist(stage, "primary", "in_remission", "disseminated", "terminal")
	keep if acause == "`acause'"
	levelsof modelable_entity_id, clean local(me_ids)
	levelsof modelable_entity_id if stage == "primary", clean local(incidence_me_ids)

** **************************************************************************
** RUN PROGRAGM
** **************************************************************************
// upload prevalence
	foreach m in `me_ids' {
		if `resubmission' {
			// if resubmitting, don't submit uploads that have already completed
			local checkfile = "`output_folder'/`acause'_`m'_uploaded.dta"
			capture confirm file "`checkfile'"
			if _rc continue
		}
		$qsub -pe multi_slot 3 -l mem_free=6g -N "CRupF_`m'" "$shell" "$upload_estimates_worker" "`m'"
	}

// check for outputs
	noisily di "Finding outputs... "
	foreach m in `me_ids' `incidence_me_ids' {
		local checkfile = "`output_folder'/`acause'_`m'_uploaded.dta"
		check_for_output, locate_file("`checkfile'") timeout(25) failScript("$upload_estimates_worker") scriptArguments("`m'") 
	}

// save file indicating completion
clear
set obs 1
generate str var1 = "done"
save "`output_folder'/`acause'_uploaded.dta", replace


capture log close

** ************
** END
** ************
