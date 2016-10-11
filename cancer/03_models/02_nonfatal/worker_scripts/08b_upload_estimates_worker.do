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
	args me_id

// get cause
	use "$parameters_folder/modelable_entity_ids.dta", clear
	levelsof(acause) if modelable_entity_id == `me_id', local(acause) clean
	levelsof stage if modelable_entity_id == `me_id', clean local(stage)

// input folder
	local output_file = "$upload_estimates_folder/`acause'/`acause'_`me_id'_uploaded.dta"

** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/upload"
	cap mkdir "`log_folder'"

// Start Logs
	capture log close _all	
	capture log using "`log_folder'/upload_`acause'_`me_id'.txt", text replace

** ****************************************************************
** GET GBD RESOURCES
** ****************************************************************
// get measure_ids
	use "$parameters_folder/constants.dta", clear
	local incidence_measure = incidence_measure_id[1]
	local prevalence_measure = prevalence_measure_id[1]

** **************************************************************************
** RUN PROGRAGM
** **************************************************************************	
// Load timestamp and save_results function
	run $generate_timestamp
	run $save_results

// upload data, then verify. upload incidence with the primary stage
	if "`stage'" == "primary" {
		local diagnosis_description = "`acause' `me_id' incidence and prevalence"
		save_results, modelable_entity_id(`me_id') description("`diagnosis_description'") in_dir("$finalize_estimates_folder/`acause'/`me_id'") metrics("`incidence_measure' `prevalence_measure'") mark_best(yes) file_pattern("{measure_id}_{location_id}.csv")
		do $check_save_results "$timestamp" "`me_id'" "`diagnosis_description'" "`output_file'"
	}
	else {
		local prevalence_description = "`acause' `me_id' prevalence"
		save_results, modelable_entity_id(`me_id') description("`prevalence_description'") in_dir("$finalize_estimates_folder/`acause'/`me_id'") metrics(`prevalence_measure') mark_best(yes) file_pattern("{measure_id}_{location_id}.csv")
		do $check_save_results "$timestamp" "`me_id'" "`prevalence_description'" "`output_file'"
	}

// close log
	capture log close

** ************
** END
** ************
