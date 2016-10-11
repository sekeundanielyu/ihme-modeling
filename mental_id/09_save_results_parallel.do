// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This sub-step template is for parallelized jobs submitted from main step code

// Description:	Parallelization of 09_save_results

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

//Running interactively on cluster 
** do "/ihme/code/epi/struser/id/09_save_results_parallel.do"
	local cluster_check 0
	if `cluster_check' == 1 {
		local 1		"/home/j/temp/struser/imp_id"
		local 2		"/clustertmp/struser/id/tmp_dir"
		local 3		"2015_12_31"
		local 4		"09"
		local 5		"save_results"
		local 6		"/ihme/code/epi/struser/id"
		local 7		"1999"
		}
	
// LOAD SETTINGS FROM STEP CODE (NO NEED TO EDIT THIS SECTION)
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	set type double, perm
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
		local cluster 1 
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local cluster 0
	}
	// directory for standard code files
		adopath + "$prefix/WORK/10_gbd/00_library/functions"
		adopath +  "$prefix/WORK/10_gbd/00_library/functions/get_outputs_helpers"


	//If running locally, manually set locals (zrankin: I deleted or commented out ones I think will be unnecessary for running locally...if needed refer to full list below)
	if `cluster' == 0 {

		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
        local date = subinstr("`date'", " " , "_", .)
		local step_num "09"
		local step_name "save_results"
		local code_dir "C:/Users/struser/Documents/Git/id"
		local in_dir "$prefix/WORK/04_epi/01_database/02_data/imp_id/04_models/02_inputs"
		local root_j_dir "$prefix/temp/struser/imp_id"
		local root_tmp_dir "$prefix/temp/struser/imp_id/tmp_dir"
		local meid "1999"

		}


	//If running on cluster, use locals passed in by model_custom's qsub
	else if `cluster' == 1 {
		// base directory on J 
		local root_j_dir `1'
		// base directory on clustertmp
		local root_tmp_dir `2'
		// timestamp of current run (i.e. 2014_01_17) 
		local date `3'
		// step number of this step (i.e. 01a)
		local step_num `4'
		// name of current step (i.e. first_step_name)
		local step_name `5'
		// directory for steps code
		local code_dir `6'
		local meid `7'

		}
	
	**Define directories 
		// directory for external inputs 
		local in_dir "$prefix/WORK/04_epi/01_database/02_data/imp_id/04_models/02_inputs"
		// directory for output on the J drive
		local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
		// directory for output on clustertmp
		local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	
		/*
		// write log if running in parallel and log is not already open
		cap log using "`out_dir'/02_temp/02_logs/`step_num'_`meid'.smcl", replace
		if !_rc local close_log 1
		else local close_log 0
		*/

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE
do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"

	// Cretinism (Proportion) 	
	* 9428	Proportion of intellectual disability due to cretinism (profound & severe) that is profound
	if `meid' == 9428 save_results, modelable_entity_id(`meid') mark_best(yes) description(struser id cret prop meid `meid' on `date') in_dir("`root_j_dir'/03_steps/`date'/03_split_sev_env/03_outputs/01_draws/`meid'") metrics(proportion)
	
	// Severity Envelopes (Prevalence) 
	* 9423	Borderline intellectual disability impairment envelope
	* 9424	Mild intellectual disability impairment envelope
	* 9425	Moderate intellectual disability impairment envelope
	* 9426	Severe intellectual disability impairment envelope
	* 9427	Profound intellectual disability impairment envelope
	else save_results, modelable_entity_id(`meid') mark_best(yes) description(struser id env meid `meid' on `date') in_dir("`root_j_dir'/03_steps/`date'/03_split_sev_env/03_outputs/01_draws/`meid'") metrics(prevalence)

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// CHECK FILES (NO NEED TO EDIT THIS SECTION)

cap log close

	// write check file to indicate sub-step has finished
		file open finished using "`tmp_dir'/02_temp/01_code/checks/finished_meid`meid'.txt", replace write
		file close finished
