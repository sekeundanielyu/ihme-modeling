
// Purpose:		Launch each step of cancer nonfatal calculation by cause & sex, check for step completion

** **************************************************************************
** Configuration
** 		
** **************************************************************************
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"

// Set preferences
	set more off
	set maxvar 32000
	
// Set common directories, functions, and globals (shell, finalize_worker, finalization_folder...)
	run "$j/WORK/07_registry/cancer/03_models/02_yld_estimation/01_code/subroutines/set_paths.do"

** ****************************************************************
** PARAMETERS 
** ****************************************************************
	// CAUSES: space separated list of causes to run.  Leave blank for all causes
		global cause_list = "neo_breast neo_colorectal neo_larynx"

	// YEARS: year range of data
		global min_year = 1980
		global max_year = 2015

	// SET MAXIMUM NUMBER OF MONTHS (GBD 2010 WAS 60 MONTHS/5 YEARS)
		global max_survival_months = 120

	// SET CODCORRECT VERSION. Leave blank to default to current best version
		global codcorrect_version = ""

	// Declare launch parameters 
		global remove_old_outputs               = 0
		global troubleshooting                  = 0
		global run_dont_submit                  = 0
		global just_check                       = 0

** ****************************************************************
** DECLARE STEPS TO RUN
** ****************************************************************
	// Part 0: Set parameters
		global create_parameter_files       = 0  // sets certain constants, generates map of causes and modelable_entity_ids, checks for available MI models, generates a map of the MI lower bounds
			global refresh_population       = 0  // creates population map. only runs with create_parameter_files.do and only needs to be run if population data have been updated

	// Part 1: Preliminary Formatting
		global format_mi_draws              = 0  // imports draw-level output from MI model and re-sets lower bound. Handles MI model exceptions
		global format_bcc_data              = 0  // formats neo_nmsc_bcc data from 01_inputs for dismod upload

	// Part 2: Prepare Scalars
		global generate_survival_curves 	= 0
		global calculate_lambda_values	 	= 0
		global generate_regional_scalars	= 0 
		global format_sequela_durations		= 0 

	// Part 3: Incidence Data Prep
		global download_deaths              = 0
		global calculate_incidence          = 0

	// Part 4: Calculations with Incidence Data
		global upload_ectomy_proportions	= 0
		global calculate_access_to_care 	= 0
	
	// Part 5: Intermediate Calculations
		global get_final_ectomy_proportions	= 0
		global upload_procedure_rates       = 0
		global calc_survival                = 0

	// Part 6: Get Modeled Procedure Rates
		global get_modeled_procedure_rates 	= 0
		global calculate_special_sequelae	= 0
 
	// Part 7: Calculate Prevalence and Adjust Sequelae
		global calculate_prevalence 		= 0
		global adjust_incidence				= 0

	// Part 8: Upload to epi database
		global finalize_estimates           = 0 
		global upload_estimates	            = 1
		

** ****************************************************************
** START LOG
** ****************************************************************
// LOG FOLDER
	local log_folder "$log_root_folder/launch"
	make_directory_tree, path("`log_folder'")

	capture log close _all
	capture log using "`log_folder'/yld_launch_$today.log", text replace name(launch)

** ****************************************************************
** CALL SCRIPTS
** ****************************************************************
	// run call_scripts
		do "$code_folder/worker_scripts/00_call_scripts.do"
		display "Done!"

	// close log
		capture log close _all

** *************
** END LAUNCH
** *************


