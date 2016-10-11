/* **************************************************************************
For some parameters, we run a hierarchical mixed-effects regression to generate 
country-year specific estimates of the parameter of interest for these neonatal 
models.  There are two circumstances when we are not comfortable running a single-parameter
regression:
1. There is too little data to come up with a reliable estimate (usually, when we have only 
	one or two datapoints). Sepsis mild_imp and sepsis modsev_imp, for example.
2. For encephalopathy mild_imp and mosev_imp, and mild_imp and modsev_imp for each of the preterm
	gestational ages. These are now calculated in a single regression by cause, as per Chris' suggestion
	on 6/7/2016 (please see 01_dataprep.do for further documentation.)

When the first condition holds, we instead run a meta-analysis.  Meta-analysis 
outputs are effectively a weighted average of all the study results available, with 
weights determined by the sample size of the study (studies with more people are 
considered more reliable).  See the documentation for the 'metan' command for more.

This is the code for the meta-analysis. 
*****************************************************************************/

************************************************************
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

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE



clear all
set more off
set maxvar 32000
ssc install estout, replace 
ssc install metan, replace

/*  //////////////////////////////////////////////
		WORKING DIRECTORY
////////////////////////////////////////////// */

		//root dir
	if c(os) == "Windows" {
		local j "J:"
		// Load the PDF appending application
		quietly do "`j'/Usable/Tools/ADO/pdfmaker_acrobat11.do"
	}
	if c(os) == "Unix" {
		local j "/home/j"
		
	} 
	
	di in red "J drive is `j'"

/* /////////////////////////
///Prep: Pass , parameters,
/// set up logs, etc.
///////////////////////// */

// test arguments
/*local acause "neonatal_preterm"
local gest_age "2"
local grouping "long_modsev_ga2"
local standard_grouping "modsev_prop"
local parent_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data"
local in_dir "`parent_dir'/01_prep/`acause'/`acause'_`grouping'_prepped.dta"
local timestamp "08_10_14" 
*/

// arguments
local acause "`1'"
local grouping "`2'"
local parent_dir "`3'"
local in_dir "`4'"
local timestamp "`5'" 

di in red "acause is `acause'"
di in red "grouping is `grouping'"
di in red "parent_dir is `parent_dir'"
di in red "in_dir is `in_dir'"
di in red "timestamp is `timestamp'"

// logging
local out_dir "`parent_dir'/02_analysis/`acause'"
capture mkdir "`out_dir'"
local log_dir "/ihme/scratch/users/User/neonatal/logs/`acause'/`acause'_`grouping'_meta_`timestamp'.smcl"

capture log close
log using "`log_dir'", replace


/* /////////////////////////
/// Import data prepared in 
/// step 01_dataprep
///////////////////////// */
di in red "importing data"
use "`in_dir'", clear

rename mean data_val
//make sure every study has a mean, lower, and upper in the proper domain [0,1]
keep location_id year location_name super_region_id data_val cases sample_size
gen data_val_se = (data_val * (1-data_val)/sample_size)^0.5
gen data_val_lower = data_val - 1.96*data_val_se
gen data_val_upper = data_val + 1.96*data_val_se
replace data_val_lower=0 if data_val_lower<0
replace data_val_upper=1 if (data_val_upper>1 & data_val_upper!=.)

/* /////////////////////////////////////////////////////////////////////
/// Run meta-analysis,transform outputs from locals to actual variables 
/// in the dataset
///////////////////////////////////////////////////////////////////// */
di in red "performing meta-analysis"
metan data_val data_val_lower data_val_upper, random

//TODO: LOG RESULTS OF META-REGRESSION SOMEWHERE

//by default, the outputs of 'metan' are saved in the 'r' vector.  
// Take them out and put them into the dataset.
gen mean = r(ES)
gen lower = r(ci_low)
gen upper = r(ci_upp)
gen se = (mean - lower)/1.96
//this is all done with sex==3.  Expand to both sexes.
expand 2, gen(iscopy)
gen sex=2
replace sex=1 if iscopy==1 

/* /////////////////////////
///Save these summary stats.
/// Also take a thousand draws
/// and save those as well.
///////////////////////// */


//summary stats
preserve
keep location_id year sex location_name super_region_id mean lower upper data_val 
di in red "saving summary stats!"
local summ_out_dir "`out_dir'/summary"
local summ_archive_dir "`summ_out_dir'/_archive"
capture mkdir "`summ_out_dir'"
capture mkdir "`summ_archive_dir'"
local summ_fname "`acause'_`grouping'_summary"

save "`summ_out_dir'/`summ_fname'.dta", replace
export delimited using "`summ_out_dir'/`summ_fname'.csv", replace
export delimited using "`summ_archive_dir'/`summ_fname'_`timestamp'.csv", replace
restore

keep location_id year sex mean se 

//draws
di in red "generating draws"
forvalues i=1/1000{
	gen draw_`i' = rnormal(mean, se)
}


di in red "saving all draws"
drop mean se
local draw_out_dir = "`out_dir'/draws"
local archive_dir = "`draw_out_dir'/_archive"
capture mkdir "`draw_out_dir'"
capture mkdir "`archive_dir'"
local fname "`acause'_`grouping'_draws"

save "`draw_out_dir'/`fname'.dta", replace
export delimited using "`draw_out_dir'/`fname'.csv", replace
export delimited using "`archive_dir'/`fname'_`timestamp'.csv", replace
	

	
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
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	

