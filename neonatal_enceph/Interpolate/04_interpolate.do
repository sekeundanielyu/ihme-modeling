************************************************************
** Description: This script linearlly interpolates prevalence at age 0-6d, 7-27d and 28d (missing value) at the draw level
** for the first DisMod model results for neonatal preterm, enceph and sepsis. The output is prevalence at 28 days. 



** Inputs:

** 

** Outputs:

** 


************************************************************
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


// priming the working environment
clear 
set more off
set maxvar 30000
version 13.0


// discover root 
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
local me_ids 1557 1558 1559 2525 9793  

// functions
run "`j'/WORK/10_gbd/00_library/functions/get_estimates.ado"
run "`j'/WORK/10_gbd/00_library/functions/create_connection_string.ado"
run "`j'/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
run "`j'/WORK/10_gbd/00_library/functions/get_best_model_versions.ado"
run "`j'/WORK/10_gbd/00_library/functions/save_results.do"

// directories
local data_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/02_analysis"

************************************************************

// Submit jobs
foreach me_id of local me_ids {

	// get acause
	if `me_id' == 1557 | `me_id' == 1558 | `me_id' == 1559 {
		di "Me_id is `me_id'"
		local acause "neonatal_preterm"
	}

	if `me_id' == 2525 {
		di "Me_id is `me_id'"
		local acause "neonatal_enceph"
	}

	if `me_id' == 9793 {
		di "Me_id is `me_id'"
		local acause "neonatal_sepsis"
	}

	// delete any old interpolation results
	di "Me_id is `me_id' and acause is `acause'"
	cd "`data_dir'/`acause'/prev_28_days/`me_id'/draws/"
	!ls
	!pwd
	!rm *csv
	!rm *dta
	cd "`data_dir'/`acause'/prev_28_days/`me_id'/draws/birth/"
	!ls
	!pwd
	!rm *csv
	!rm *dta
	cd "`data_dir'/`acause'/prev_28_days/`me_id'/draws/0-6/"
	!ls
	!pwd
	!rm *csv
	!rm *dta
	cd "`data_dir'/`acause'/prev_28_days/`me_id'/draws/7-27/"
	!ls
	!pwd
	!rm *csv
	!rm *dta

	!qsub -pe multi_slot 20 -l mem_free=8g -N get_draws_`me_id' -P proj_custom_models -e /share/temp/sgeoutput/User/errors -o /share/temp/sgeoutput/User/output "`working_dir'/stata_shell.sh" "`working_dir'/enceph_preterm_sepsis/model_custom/interpolate/04_interpolate_parallel.do" "`me_id' `acause'"
}


// wait for final results files to finish 
foreach me_id of local me_ids {

	// get acause
	if `me_id' == 1557 | `me_id' == 1558 | `me_id' == 1559 {
		di "Me_id is `me_id'"
		local acause "neonatal_preterm"
	}

	if `me_id' == 2525 {
		di "Me_id is `me_id'"
		local acause "neonatal_enceph"
	}

	if `me_id' == 9793 {
		di "Me_id is `me_id'"
		local acause "neonatal_sepsis"
	}

	capture noisily confirm file "`data_dir'/`acause'/prev_28_days/`me_id'/draws/all_draws.dta"
	while _rc!=0 {
		di "File all_draws.dta for `acause' `me_id' not found :["
		sleep 60000
		capture noisily confirm file "`data_dir'/`acause'/prev_28_days/`me_id'/draws/all_draws.dta"
	}
	if _rc==0 {
		di "File all_draws.dta for `acause' `me_id' found!"
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
	


