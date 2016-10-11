** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** Purpose:		Autmatially loads yld settings and sets commonly used macros		
** *********************************************************************************************************************************************************************

// Skip this script if paths have already been set
	if "$paths_are_set" != "" exit

// Define load_common function depending on operating system
	do "/ihme/code/cancer/cancer_estimation/00_common/set_common_roots.do"

// YLD folders
	global shell = "$stata_shell"
	global code_folder "$code_prefix/03_models/02_nonfatal"
	global data_folder = "$cancer_storage/03_models/02_yld_estimation/02_data"
	global results_folder = "$cancer_storage/03_models/02_yld_estimation/03_results"

// Long term copies of model controls
	global long_term_copy_parameters = "$data_folder/_parameters"
	global long_term_copy_scalars = "$data_folder/_scalars"

// // scratch folders
	// main folders
		global non_fatal_work_folder 		= "$cancer_workspace/03_models/02_non_fatal/GBD2015"

	// model settings and parameters
		global parameters_folder 		= "$non_fatal_work_folder/_parameters"
		global scalars_folder 			= "$non_fatal_work_folder/_scalars"

	// Temporary Data folders
		global log_folder_root 			= "$non_fatal_work_folder/_logs"
		global previous_output_storage		= "$non_fatal_work_folder/_previous_outputs"
		global mi_ratio_folder			= "/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/06_draws"
		global formatted_mi_folder		= "$non_fatal_work_folder/formatted_mi_draws"
		global mortality_folder 		= "$non_fatal_work_folder/mortality"
		global incidence_folder 		= "$non_fatal_work_folder/total_incidence"
		
		global ectomy_folder 			= "$non_fatal_work_folder/_ectomy_proportions"		
		global procedure_proportion_folder  	= "$ectomy_folder/02_procedure_proportions"
		global procedure_rate_folder		= "$ectomy_folder/03_procedure_rates"
		global modeled_procedures_folder 	= "$ectomy_folder/04_modeled_procedures"

		global atc_folder 			= "$non_fatal_work_folder/access_to_care"
		global survival_folder 			= "$non_fatal_work_folder/survival"
		global prevalence_folder 		= "$non_fatal_work_folder/prevalence"
		global split_incidence_folder 		= "$non_fatal_work_folder/split_incidence"
		global incremental_prevalence_folder = "$non_fatal_work_folder/incremental_prevalence"

		global finalize_estimates_folder	 = "$non_fatal_work_folder/finalize_estimates"
		global upload_estimates_folder 		= "$non_fatal_work_folder/upload_estimates"
		global sequelae_adjustment_folder 	= "$non_fatal_work_folder/sequelae_adjustment"

// // Data
	global population_data 				= "$parameters_folder/populations.dta"
	global script_control				= "$data_folder/_script_control.dta"

// // Scripts
	// Worker scripts and subroutines
		global generate_parameters 		= "$code_folder/worker_scripts/00_generate_parameters.do"
		global mi_model_process			= "$cancer_folder/03_models/01_mi_ratio/01_code/03_st_gpr/spacetimeGPR/run_st_gpr/call_processes.py"
		global format_mi_worker 		= "$code_folder/worker_scripts/01_format_mi_draws_worker.do"
		global mortality_worker 		= "$code_folder/worker_scripts/03a_death_draws_worker.do"
		global incidence_worker 		= "$code_folder/worker_scripts/03b_calc_incidence_worker.do"
		global incidence_worker_nmsc 		= "$code_folder/worker_scripts/03b_calc_incidence_worker_nmsc.do"
		global ectomy_prop_worker 		= "$code_folder/worker_scripts/04b_calc_ectomy_proportions_worker.do"
		global ectomy_rate_worker		= "$code_folder/worker_scripts/05_calc_ectomy_rates_worker.do"
		global survival_worker 			= "$code_folder/worker_scripts/05_calc_survival_worker.do"
		global sequelae_worker			= "$code_folder/worker_scripts/06b_sequelae_calculation_worker.do"
		global prevalence_worker 		= "$code_folder/worker_scripts/07_calc_prevalence_worker.do"
		global finalize_worker 			= "$code_folder/worker_scripts/08a_finalize_estimates_worker.do"
		global upload_estimates_worker 		= "$code_folder/worker_scripts/08b_upload_estimates_worker.do"

	// Master scripts
		global format_bcc_master		= "$code_folder/01_format_bcc_data_for_epi.do"
		global format_mi_master 		= "$code_folder/01_format_mi_draws_master.do"
		global procedure_prop_master 		= "$code_folder/02_generate_ectomy_rates.do"
		global survival_curves_master 		= "$code_folder/02_generate_survival_curves.do"
		global generate_lambda_master		= "$code_folder/02_generate_lambda_values.do"
		global regional_scalars_master		= "$code_folder/02_generate_regional_scalars.do"
		global sequela_duration_master		= "$code_folder/02_generate_sequela_duration_input.do"
		global mortality_master 		= "$code_folder/03a_death_draws_master.do"
		global incidence_master 		= "$code_folder/03b_calc_incidence_master.do" 
		global atc_master 			= "$code_folder/04a_calc_access_to_care.do"
		global upload_ectomy_prop_master 	= "$code_folder/04b_upload_ectomy_proportions_master.do"
		global survival_master 			= "$code_folder/05_calc_survival_master.do"
		global download_modeled_proportions	= "$code_folder/05_download_ectomy_proportions.do"
		global upload_ectomy_rates_master 	= "$code_folder/05_upload_ectomy_rates_master.do"
		global download_ectomy_master		= "$code_folder/06a_get_modeled_procedures.do"
		global sequelae_calc_master		= "$code_folder/06b_sequelae_calculation_master.do" 
		global prevalence_master 		= "$code_folder/07_calc_prevalence_master.do"
		global finalize_master 			= "$code_folder/08a_finalize_estimates_master.do"
		global upload_master 			= "$code_folder/08b_upload_estimates_master.do"

// // Load Functions
	// Define locations of optional yld functions
		global aggregate_locations 		= "$code_folder/subroutines/aggregate_locations.do"
		global adjust_remission			= "$code_folder/subroutines/adjust_remission.do"
		global generate_timestamp		= "$code_folder/subroutines/generate_timestamp.do"
		global check_save_results		= "$code_folder/subroutines/check_save_results.do"
		global convert_andCheck_rates		= "$code_folder/subroutines/convert_to_rate_space_and_check.do"
		global summary_functions		= "$code_folder/subroutines/generate_summary_data.do"

	// Define locations of functions for Epi upload/download
		global save_results				= "$j/WORK/10_gbd/00_library/functions/save_results.do"
		global get_draws				= "$j/WORK/10_gbd/00_library/functions/get_draws.ado"


	// load IHME written mata functions which speed up collapse, pctile, and egen
		run "$j/WORK/10_gbd/00_library/functions/fastcollapse.ado"
		run "$j/WORK/10_gbd/00_library/functions/fastpctile.ado"
		run "$j/WORK/10_gbd/00_library/functions/fastrowmean.ado"
	
	// re-load cancer team functions
		capture drop program better_remove
		capture drop program check_for_output
		capture drop program make_directory_tree
		capture drop program copy_directory_tree
		capture drop program convert_age

		do "$common_cancer_code/better_remove.do"
		do "$common_cancer_code/check_for_output.do"
		do "$common_cancer_code/make_directory_tree.do"
		do "$code_folder/subroutines/convert_age.do"

// declare that directories and functions have already been set
	global paths_are_set = 1

** *****************************************************
** END
** *****************************************************
