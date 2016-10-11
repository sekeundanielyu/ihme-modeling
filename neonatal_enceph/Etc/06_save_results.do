/*******************************************
Description: 06_save_results.do first clears all previous files generated
by this step. Then, it submits a script parallelized by cause-gestational age. 
This lower-level script does two things: 1) submits another lower-level script (not parallelized)
that formats mild_imp prevalence data and runs save_results (we do not run a second DisMod model for 
mild impairment) and 2) appends and formats modsev prevalence data and saves it to 04_big_data for 
upload into the final DisMod model. 06_save_results.do then checks for the existence of these prevalence
files in 04_big_data. 

*******************************************/

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM MASTER CODE

	// prep stata
	clear all
	set more off
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	// base directory on J 
	local root_j_dir `1'
	// base directory on /ihme
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
    // directory where the code lives
    local code_dir `8'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on /ihme
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


clear all 
set more off
set maxvar 30000
version 13.0

// priming the working environment
if c(os) == "Windows" {
			local j "J:"
			// Load the PDF appending application
			quietly do "`j'/Usable/Tools/ADO/pdfmaker_acrobat11.do"
			local working_dir = "H:/neo_model"
		}
		if c(os) == "Unix" {
			local j "/home/j"
			ssc install estout, replace 
			ssc install metan, replace
			local working_dir = "/homes/User/neo_model" 
		} 

// locals
local acause_list " "neonatal_preterm" "neonatal_enceph" "neonatal_sepsis" "

// directories
local out_dir "`j'/WORK/04_epi/01_database/02_data"

*******************************************************

// first remove all previous files
foreach acause of local acause_list {

	di "finding target me_id"
	if "`acause'" == "neonatal_preterm" {
		local target_me_ids 8621 8622 8623
	}
	if "`acause'" == "neonatal_enceph" {
		local target_me_ids 8653
	}
	if "`acause'" == "neonatal_sepsis" {
		local target_me_ids 8674
	}

	foreach target_me_id of local target_me_ids {
		di "removing old files for `target_me_id'"
		cd "`out_dir'/`acause'/`target_me_id'/04_big_data"
		local files: dir . files "*prevalence.xlsx"
		foreach file of local files {
			erase `file'
		}
	}
}



// submit jobs that format and save_results
foreach acause of local acause_list {

	// find me_ids
	if "`acause'" == "neonatal_preterm" {
		local me_id_list 1557 1558 1559 
	}

	if "`acause'" == "neonatal_enceph" {
		local me_id_list 2525
	}
	
	if "`acause'" == "neonatal_sepsis" {
		local me_id_list 9793
	}

	// submit jobs
	foreach me_id of local me_id_list {
		!qsub -pe multi_slot 20 -l mem_free=8g -N save_results_`me_id' -P proj_custom_models "`working_dir'/stata_shell.sh" "`working_dir'/enceph_preterm_sepsis/model_custom/save_results/06_save_results_parallel.do" "`acause' `me_id'"
	}
}	


// wait until results files have been created
foreach acause of local acause_list {

	di "finding target me_id"
	if "`acause'" == "neonatal_preterm" {
		local target_me_ids 8621 8622 8623
	}
	if "`acause'" == "neonatal_enceph" {
		local target_me_ids 8653
	}
	if "`acause'" == "neonatal_sepsis" {
		local target_me_ids 8674
	}

	foreach target_me_id of local target_me_ids {

		capture noisily confirm file "`out_dir'/`acause'/`target_me_id'/04_big_data/`target_me_id'_prevalence.xlsx"
		while _rc!=0 {
			di "File `target_me_id'_prevalence.xlsx not found :["
			sleep 60000
			capture noisily confirm file  "`out_dir'/`acause'/`target_me_id'/04_big_data/`target_me_id'_prevalence.xlsx"
		}
		if _rc==0 {
			di "File `target_me_id'_prevalence.xlsx found!"
		}	
	}
}
	

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// CHECK FILES

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
	


