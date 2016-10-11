// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	Submit jobs that impute incidence of injury from war & disaster using mortality shocks data base

** *********************************************
// DON'T EDIT - prep stata
** *********************************************

// PREP STATA (DON'T EDIT)
	// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

// Check for parallelizing 
global parallel_check = 0

// Global can't be passed from master when called in parallel
	if "`1'" == "" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "03a"
		local 5 impute_short_term_shock_inc

		local 8 "/homes/ngraetz/local/inj/gbd2015"
	}

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
    // directory where the code lives
    local code_dir `8'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
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

** *********************************************
** WRITE CODE HERE
** *********************************************

// SETTINGS
	** debugging?
	local debug 0
	** how many slots is this script being run on?
	local slots 4
	** What version of cause-list are we currently on? The custom model code should at some point be changed to pass this from the master do-file.
	local cause_version 2
	
// Filepaths
	local gbd_ado "$prefix/WORK/10_gbd/00_library/functions"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local stepfile "`code_dir'/`functional'_steps.xlsx"
	local rundir "/clustertmp/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/03_steps/`date'"
	
// Import functions
	adopath + "`code_dir'/ado"
	adopath + `gbd_ado'

// set memory (gb) for each job
	local mem 8
// set type for pulling different years (cod/epi); this is used for what parellel jobs to submit based on cod/epi estimation demographics, not necessarily what inputs/outputs you use
	local type "epi"
// set subnational=no (drops subnationals) or subnational=yes (drops national CHN/IND/MEX/GBR)
	local subnational "yes"

// parallelize by location/sex
if `mem' < 2 local mem 2
local slots = ceil(`mem'/2)
local mem = `slots' * 2

// submit jobs
! rm -rf "`tmp_dir'/02_temp/01_code/checks"
! mkdir "`tmp_dir'/02_temp/01_code/checks"

get_demographics , gbd_team(epi)
if $parallel_check==1 {
	global location_ids 89
	global sex_ids 1
}

cap mkdir "`root_tmp_dir'/03_steps/`date'/03a_impute_short_term_shock_inc/03_outputs/03_other/mi_ratios"
cap mkdir "`root_tmp_dir'/03_steps/`date'/03a_impute_short_term_shock_inc/03_outputs/03_other/mi_ratios/inj_war"
cap mkdir "`root_tmp_dir'/03_steps/`date'/03a_impute_short_term_shock_inc/03_outputs/03_other/mi_ratios/inj_disaster"

// set code file from 01_code to run in parallel (change from template; just "name.do" no file path since it should be in same directory)
local code "impute_short_term_shock_inc/impute_short_term_shock_inc_parallel.do" 
** submit jobs from here
foreach location_id of global location_ids {
		foreach sex_id of global sex_ids {
			! qsub -e /share/temp/sgeoutput/ngraetz/errors -o /share/temp/sgeoutput/ngraetz/output -P proj_injuries -N _`step_num'_`location_id'_`sex_id' -pe multi_slot 4 -l mem_free=8 "`code_dir'/stata_shell.sh" "`code_dir'/`step_name'/impute_short_term_shock_inc_parallel.do" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `location_id' `sex_id'"
		}
	}

// wait for jobs to finish
	local i = 0
	while `i' == 0 {
		local checks : dir "`tmp_dir'/02_temp/01_code/checks" files "finished_*.txt", respectcase
		local count : word count `checks'
		di "checking `c(current_time)': `count' of `n' checks"
		if (`count' == `n') local i = 1
		else sleep 60000
	}
		
** ***********************************************************
// Write check files
** ***********************************************************

// write check file to indicate step has finished - this is now happening in the jobs that are being submitted above
	file open finished using "`out_dir'/finished.txt", replace write
	file close finished

// Close log if open
	log close worker
