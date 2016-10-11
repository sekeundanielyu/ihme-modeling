// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global

// Description:	Subtract ID due to each causes from the envelope

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

//Running interactively on cluster 
** do "/ihme/code/epi/struser/id/03_envelope_subtract.do"
	local cluster_check 0
	if `cluster_check' == 1 {
		local 1		"/home/j/temp/struser/imp_id"
		local 2		"/share/scratch/users/struser/id/tmp_dir"
		local 3		"2015_12_29"
		local 4		"03"
		local 5		"split_sev_env"
		local 6		""
		local 7		""
		local 8		"/ihme/code/epi/struser/id"
		}

// LOAD SETTINGS FROM MASTER CODE (NO NEED TO EDIT THIS SECTION)

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


	//If running locally, manually set locals
	if `cluster' == 0 {

		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
        local date = subinstr("`date'", " " , "_", .)
		local step_num "03"
		local step_name "split_sev_env"
		local hold_steps ""
		local code_dir "C:/Users/struser/Documents/Git/id"
		local in_dir "$prefix/WORK/04_epi/01_database/02_data/imp_id/04_models/02_inputs"
		local root_j_dir "$prefix/temp/struser/imp_id"
		local root_tmp_dir "$prefix/temp/struser/imp_id/tmp_dir"
		
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
		// step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
		local hold_steps `6'
		// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
		local last_steps `7'
		// directory for steps code
		local code_dir `8'
		}
	
	**Define directories 
		// directory for external inputs 
		local in_dir "$prefix/WORK/04_epi/01_database/02_data/imp_id/04_models/02_inputs"
		// directory for output on the J drive
		local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
		// directory for output on clustertmp
		local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"


		

	// write log if running in parallel and log is not already open
	cap log using "`out_dir'/02_temp/02_logs/`step_num'.smcl", replace
	if !_rc local close_log 1
	else local close_log 0
	
	// check for finished.txt produced by previous step
	if "`hold_steps'" != "" {
		foreach step of local hold_steps {
			local dir: dir "`root_j_dir'/03_steps/`date'" dirs "`step'_*", respectcase
			// remove extra quotation marks
			local dir = subinstr(`"`dir'"',`"""',"",.)
			capture confirm file "`root_j_dir'/03_steps/`date'/`dir'/finished.txt"
			if _rc {
				di "`dir' failed"
				BREAK
			}
		}
	}	

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE


//Clear previous check files
		cap mkdir "`tmp_dir'/02_temp/01_code/checks"
		local checks: dir "`tmp_dir'/02_temp/01_code/checks" files "*.txt"
		foreach check of local checks {
			rm "`tmp_dir'/02_temp/01_code/checks/`check'"
			}


		// PARALLELIZE BY LOCATION 
			//Set locals of location to loop over 
			get_location_metadata, location_set_id(9) clear
                keep if most_detailed == 1 & is_estimate == 1
				levelsof location_id, local(location_ids)
					

			//Diagnostics only 
				//local location_ids "58"
				local errors_outputs `"-o "/share/temp/sgeoutput/struser/output" -e "/share/temp/sgeoutput/struser/errors""'

			//Submit jobs for each location  
			local n 0
			quietly {
				foreach location_id in `location_ids' {
								
								noisily di "submitting `location_id'"
								
								//qsub settings (for consistency, the argument structure is the same as model_custom, with location added and hold_steps last_steps deleted)
								local jobname "step_`step_num'_loc`location_id'"
								local project "proj_custom_models"
								local shell "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell"
								local slots = 4
								local mem = `slots' * 2
								local code = "`code_dir'/`step_num'_`step_name'_parallel"
								di `"`errors_outputs'"' //will only create errors and outputs if running in diagnostic mode 
							
							! qsub -N "`jobname'" -P "`project'" `errors_outputs' -pe multi_slot `slots' -l mem_free=`mem' "`shell'.sh" "`code'.do" ///
								"`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `location_id'"
							local ++ n 
							}
						}
		

	// wait for parallel jobs to finish before passing execution back to main step file
	local i = 0
	while `i' == 0 {
		local checks : dir "`tmp_dir'/02_temp/01_code/checks" files "finished_*.txt", respectcase
		local count : word count `checks'
		di "checking `c(current_time)': `count' of `n' jobs finished"
		if (`count' == `n') continue, break
		else sleep 60000
	}


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// CHECK FILES (NO NEED TO EDIT THIS SECTION)

	// write check file to indicate step has finished
		file open finished using "`out_dir'/finished.txt", replace write
		file close finished
		
	// if step is last step, write finished.txt file
		local i_last_step 0
		foreach i of local last_steps {
			if "`i'" == "`this_step'" local i_last_step 1
		}
		
		// only write this file if this is one of the last steps
		if `i_last_step' {
		
			// account for the fact that last steps may be parallel and don't want to write file before all steps are done
			local num_last_steps = wordcount("`last_steps'")
			
			// if only one last step
			local write_file 1
			
			// if parallel last steps
			if `num_last_steps' > 1 {
				foreach i of local last_steps {
					local dir: dir "`root_j_dir'/03_steps/`date'" dirs "`i'_*", respectcase
					local dir = subinstr(`"`dir'"',`"""',"",.)
					cap confirm file "`root_j_dir'/03_steps/`date'/`dir'/finished.txt"
					if _rc local write_file 0
				}
			}
			
			// write file if all steps finished
			if `write_file' {
				file open all_finished using "`root_j_dir'/03_steps/`date'/finished.txt", replace write
				file close all_finished
			}
		}
		
	// close log if open
		if `close_log' log close

