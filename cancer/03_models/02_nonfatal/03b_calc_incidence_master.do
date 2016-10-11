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
	args acause resubmission 

	// set arguments if not sent
	if "`acause'" == "" local acause neo_nmsc_scc
	if "`resubmission'" == "" local resubmission = 0

// Set worker script
	if !regexm("`acause'", "neo_nmsc") local worker_script = "$incidence_worker"
	else local worker_script = "$incidence_worker_nmsc"

// Set output folder and folder to be used after file adjusted by prevalence (later step)
	local output_folder "$incidence_folder/`acause'"
	make_directory_tree, path("`output_folder'")

** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
if !`resubmission'{
// Log folder
	local log_folder "$log_folder_root/total_incidence_`acause'"
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
	capture levelsof(location_id) if model == 1, local(modeled_locations) clean
	capture levelsof(location_id) if location_id != 1, clean local(all_locations)
	keep location_id location_type
	tempfile location_info
	save `location_info', replace

// get measure_ids
	use "$parameters_folder/constants.dta", clear
	local incidence_measure = incidence_measure_id[1]
	local prevalence_measure = prevalence_measure_id[1]

// get modelable entity id
	use "$parameters_folder/modelable_entity_ids.dta", clear
	levelsof modelable_entity_id if stage == "primary" & acause == "neo_nmsc_scc", clean local(me_id)

** **************************************************************************
** Submit Jobs, Check For Completion, Aggregate, and Save
** **************************************************************************
if regexm("`acause'", "neo_nmsc"){
	noisily di "`acause'"

	// Import function to retrieve epi estimates 
		run "$get_draws"
		get_draws, gbd_id_field(modelable_entity_id) source(dismod) measure_ids(`incidence_measure') gbd_id(`me_id') clear

	// Save data for script
		// Rename variables and keep variables of interest
			rename (year_id sex_id) (year sex)
			keep location_id year age sex draw_*
		 	rename draw_* incidence_*

		// Reformat Age
			convert_from_age_group
			tostring(age), replace format("%12.2f") force
			destring(age), replace
	
		// keep and sort relevant data
			keep location_id year sex age incidence_*
			order location_id year sex age incidence_*
			sort location_id year sex age

		// save
			save "`output_folder'/incidence_download.dta", replace
}

// Submit jobs
if !`resubmission' {
	local submission_cause = substr("`acause'", 5, .)
	local submission_cause = "`acause'"
	foreach local_id in `modeled_locations' {
		$qsub -pe multi_slot 3 -l mem_free=6g -N "incW_`submission_cause'_`local_id'" "$shell" "`worker_script'" "`acause' `local_id'"
	}
}

// Check for completion
	noisily di "Finding outputs... "
	foreach local_id in `modeled_locations' {
		local checkfile = "`output_folder'/incidence_summary_`local_id'.dta"
		check_for_output, locate_file("`checkfile'") sleepInterval(10) timeout(1) failScript("`worker_script'") scriptArguments("`acause' `local_id'")	
	}

// Aggregate files to parent locations
	run "$aggregate_locations" "incidence" "incidence_" `output_folder'


// Compile summaries
	clear
	foreach local_id in `all_locations' {
		local appendFile = "`output_folder'/incidence_summary_`local_id'.dta"
		capture append using "`appendFile'"
	}
	merge m:1 location_id using `location_info', keep(1 3) nogen
	compress
	save "`output_folder'/incidence_summary.dta", replace

// close log
	capture log close

** *******
** END
** *******
