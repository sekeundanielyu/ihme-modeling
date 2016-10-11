// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global

// Description:	transferring to COMO
// 				Number of output files: 
// 				When uploading to DisMod, use
//				save_results, sequela_id(ID) subnational(yes) description(TEXT DESCRIPTION) in_dir(/clustertmp/WORK/04_epi/01_database/02_data/FUNCTIONAL/04_models/gbd2013/03_steps/DATE/REST...)
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
//Running interactively on cluster 
** do "/ihme/code/epi/struser/id/09_save_results.do"
	local cluster_check 0
	if `cluster_check' == 1 {
		local 1		"/home/j/struser/zrankin/imp_id"
		local 2		"/clustertmp/struser/id/tmp_dir"
		local 3		"2015_12_29"
		local 4		"09"
		local 5		"save_results"
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
		local step_num "09"
		local step_name "save_results"
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
// WRITE CODE HERE
		
 	//Clear previous check files
		cap mkdir "`tmp_dir'/02_temp/01_code/checks"
		local checks: dir "`tmp_dir'/02_temp/01_code/checks" files "*.txt"
		foreach check of local checks {
			rm "`tmp_dir'/02_temp/01_code/checks/`check'"
			}

	//Custom outputs: 
		local meids "9423 9424 9425 9426 9427 9428"
		* 9423	Borderline intellectual disability impairment envelope
		* 9424	Mild intellectual disability impairment envelope
		* 9425	Moderate intellectual disability impairment envelope
		* 9426	Severe intellectual disability impairment envelope
		* 9427	Profound intellectual disability impairment envelope
		* 9428	Proportion of intellectual disability due to cretinism (profound & severe) that is profound

	//Submit save_results job for each meid (note: this is where I normally would loop over location_ids for parallelization)

		//Diagnostics only 
		//local meids "9423"
		local errors_outputs `"-o "/share/temp/sgeoutput/zrankin/output" -e "/share/temp/sgeoutput/struser/errors""'
	

		//Submit jobs for each meid 
		local n 0
		quietly {
			foreach meid in `meids' {
							
							noisily di "submitting `meid'"
							
							//qsub settings (or consistency, the argument structure is the same as model_custom, with meid added and hold_steps last_steps deleted)
							local jobname "step_`step_num'_meid`meid'"
							local project "proj_custom_models"
							local shell "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell"
							local slots = 20
							local mem = `slots' * 2
							local code = "`code_dir'/`step_num'_`step_name'_parallel"
							di `"`errors_outputs'"' //will only create errors and outputs if running in diagnostic mode 
						
						! qsub -N "`jobname'" -P "`project'" `errors_outputs' -pe multi_slot `slots' -l mem_free=`mem' "`shell'.sh" "`code'.do" ///
							"`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `meid'"
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
