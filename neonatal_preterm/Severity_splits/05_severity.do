*********************************************
** Description: This .do file deletes the results of previous runs
** of this step in the modeling process, submits a python script 
** that does the actual computation, and then checks for completed 
** results files. 
*********************************************

** inputs


** outputs



**********************************************

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM MASTER CODE (NO NEED TO EDIT THIS SECTION)

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
	local working_dir = "H:/neo_model"
}
if c(os) == "Unix" {
	local j "/home/j"
	local working_dir = "/homes/User/neo_model" 
} 


// directories
local out_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/temp_outputs"

// locals
local acause_list " "neonatal_preterm" "neonatal_enceph" "neonatal_sepsis" "
****************************************************************

// first, remove all previous files 
foreach acause of local acause_list {

	di "get me_id_list"
	if "`acause'" == "neonatal_preterm" {
		local me_id_list 1557 1558 1559 
	}
	if "`acause'" == "neonatal_enceph" {
		local me_id_list 2525
	}
	if "`acause'" == "neonatal_sepsis" {
		local me_id_list 9793
	}

	foreach me_id of local me_id_list {
		di "removing old files"
		cd "`out_dir'/`acause'/`me_id'/parallel_no_sub"
		local files: dir . files "*.csv"
		foreach file of local files {
			erase `file'
		}
	}
} 

// qsub the upper-level severity script (and custom shell)
!qsub -pe multi_slot 5 -l mem_free=10g -N severity_split -P proj_custom_models -e /share/temp/sgeoutput/User/errors -o /share/temp/sgeoutput/User/output "`working_dir'/enceph_preterm_sepsis/model_custom/severity/start_neonatal.sh"  



// wait until results files have been generated
foreach acause of local acause_list {

	di "get me_id_list"
	if "`acause'" == "neonatal_preterm" {
		local me_id_list 1557 1558 1559 
	}
	if "`acause'" == "neonatal_enceph" {
		local me_id_list 2525
	}
	if "`acause'" == "neonatal_sepsis" {
		local me_id_list 9793
	}

	foreach me_id of local me_id_list {
		di "checking for mild_prev_final_prev"
		capture noisily confirm file "`out_dir'/`acause'/`me_id'/parallel_no_sub/mild_prev_final_prev.csv"
		while _rc!=0 {
			di "File mild_prev_final_prev.csv for `acause' not found :["
			sleep 60000
			capture noisily confirm file "`out_dir'/`acause'/`me_id'/parallel_no_sub/mild_prev_final_prev.csv"
		}
		if _rc==0 {
			di "File mild_prev_final_prev.csv for `acause' found!"
		}

		di "checking for mild_count_scaled_check"
		capture noisily confirm file "`out_dir'/`acause'/`me_id'/parallel_no_sub/mild_count_scaled_check.csv"
		while _rc!=0 {
			di "File mild_count_scaled_check.csv for `acause' not found :["
			sleep 60000
			capture noisily confirm file "`out_dir'/`acause'/`me_id'/parallel_no_sub/mild_count_scaled_check.csv"
		}
		if _rc==0 {
			di "File mild_count_scaled_check.csv for `acause' found!"
		}

		di "checking for modsev_prev_final_prev"
		capture noisily confirm file "`out_dir'/`acause'/`me_id'/parallel_no_sub/modsev_prev_final_prev.csv"
		while _rc!=0 {
			di "File modsev_count_final_prev.csv for `acause' not found :["
			sleep 60000
			capture noisily confirm file "`out_dir'/`acause'/`me_id'/parallel_no_sub/modsev_prev_final_prev.csv"
		}
		if _rc==0 {
			di "File modsev_prev_final_prev.csv for `acause' found!"
		}

		di "checking for modsev_count_scaled_check"
		capture noisily confirm file "`out_dir'/`acause'/`me_id'/parallel_no_sub/modsev_count_scaled_check.csv"
		while _rc!=0 {
			di "File modsev_count_scaled_check.csv for `acause' not found :["
			sleep 60000
			capture noisily confirm file "`out_dir'/`acause'/`me_id'/parallel_no_sub/modsev_count_scaled_check.csv"
		}
		if _rc==0 {
			di "File modsev_count_scaled_check.csv for `acause' found!"
		}	
		
		di "checking for asymp_prev_final_prev"
		capture noisily confirm file "`out_dir'/`acause'/`me_id'/parallel_no_sub/asymp_prev_final_prev.csv"
		while _rc!=0 {
			di "File asymp_prev_final_prev.csv for `acause' not found :["
			sleep 60000
			capture noisily confirm file "`out_dir'/`acause'/`me_id'/parallel_no_sub/asymp_prev_final_prev.csv"
		}
		if _rc==0 {
			di "File asymp_prev_final_prev.csv for `acause' found!"
		}
	}
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
	
