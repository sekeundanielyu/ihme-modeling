/*************************************************************
Description: This code performs arithmetic on raw cfr data for encephalopathy, preterm and sepsis
and transforms them to emr by: [-ln(1-cfr)/(28/365.25)]. This equation is analogous to the one 
that transforms culumlative incidence (CI) to incidence rate (IR): CI = 1-e^(-IR*T). cfr is the 
"cumulative incidence" here - recall the denominator for emr is person-time of the population with 
the condition. 

This emr data is then saved in the 04_big_data for the appropriate me_id and uploaded into the first 
DisMod model for each cause. 

** Inputs:




** Outputs:




************************************************************/
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
clear all
set more off
set maxvar 30000
version 13.0


// discover root
if c(os) == "Windows" {
		local j "J:"
		// Load the PDF appending application
		quietly do "`j'/Usable/Tools/ADO/pdfmaker_acrobat11.do"
	}
	if c(os) == "Unix" {
		local j "/home/j"
		ssc install estout, replace 
		ssc install metan, replace
	} 
	di in red "J drive is `j'"

// functions
run "`j'/WORK/10_gbd/00_library/functions/get_outputs_helpers/query_table.ado"

** directories
local data_dir "`j'/WORK/04_epi/01_database/02_data"

** locals
local acause_list " "neonatal_preterm" "neonatal_enceph" "neonatal_sepsis" "


************************************************************************

// get modelable_entity data
query_table, table_name(modelable_entity) server(modeling-epi-db) database(epi) clear
tempfile me_metadata
save `me_metadata'

foreach acause of local acause_list {

	// set gestational ages. Assign null value for neonatal_enceph because there are none. 
	di "CFR to EMR transformation for `acause'"

	if "`acause'" == "neonatal_preterm" {
		local me_ids 2571 2572 2573 8676
	}
	if "`acause'" == "neonatal_enceph" {
		local me_ids 2524
	}
	if "`acause'" == "neonatal_sepsis" {
		local me_ids 3964
	}

	// begin gestational age loop
	di "begin me loop"
	foreach me_id of local me_ids {

		di "Me_id is `me_id'"

		// create local that will hold target me_id (ie, corresponding birth prevalence)
		if `me_id' == 2571 {
			local new_me_id = 1557
		}
		if `me_id' == 2572 {
			local new_me_id = 1558
		}
		if `me_id' == 2573 {
			local new_me_id = 1559
		}
		if `me_id' == 8676 {
			local new_me_id = 8675
		}
		if `me_id' == 2524 {
			local new_me_id = 2525
		}
		if `me_id' == 3964 {
			local new_me_id = 1594
		}

		// import data 
		di "retrieving most recent data"
		cd "`data_dir'/`acause'/`me_id'/03_review/01_download"
		local files: dir . files "me_`me_id'*.xlsx"
  		local files: list sort files 
  		import excel using `=word(`"`files'"', wordcount(`"`files'"'))', firstrow clear

  		// clean up
  		replace measure = "crf" if measure == "prevalence"

		// arithmetic
		di "arithmetic"
		replace mean = -ln(1-mean)/(28/365.25)

		// can't calculate an EMR from a cfr of 1 (would be infinite) so drop these rows
		di "dropping cfr=1/infinite EMRs"
		drop if mean == . 

		// format a bit
		replace measure = "mtexcess" 
		replace age_end = 28/365
		replace lower = .
		replace upper = .
		replace uncertainty_type_value = .
		replace standard_error = . 
		tostring note_modeler, replace 
		replace note_modeler = "Transformed from raw cfr data by -ln(1-mean)/(28/365.25)"
		replace row_num = . 


		// format modelable_entity info
		drop modelable_entity_name 
		replace modelable_entity_id = `new_me_id'
		merge m:1 modelable_entity_id using `me_metadata', nogen keep(3)
		drop *date* // drops all the problematic additional vars

		// save
		di "saving"
		export excel "`data_dir'/`acause'/`new_me_id'/01_input_data/raw_cfr_to_emr_`me_id'.xlsx", firstrow(variables) sheet("extraction") replace 
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
	
