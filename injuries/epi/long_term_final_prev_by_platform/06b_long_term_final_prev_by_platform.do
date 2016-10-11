// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	Submit jobs to subtract acute prevalence from total prevalence to get just long-term prevalence

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM MASTER CODE (NO NEED TO EDIT THIS SECTION)

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
	if "`1'" == "" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "06b"
		local 5 long_term_final_prev_by_platform

		local 8 "/share/code/injuries/ngraetz/inj/gbd2015"
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
	// directory for standard code files
	adopath + "$prefix/WORK/10_gbd/00_library/functions"

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Settings
	local debug 1
	set type double, perm

// If no check global passed from master, assume not a test run
	if missing("$check") global check 0
	
// Filepaths
	local gbd_ado "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local summ_dir "`tmp_dir'/03_outputs/02_summary"
	local rundir "`code_dir'/03_steps/`date'"
	local stepfile "`code_dir'/_inj_steps.xlsx"
	
	cap mkdir "`out_dir'"
	cap mkdir "`out_dir'/02_temp"
	cap mkdir "`diag_dir'"
	cap mkdir "`tmp_dir'"
	cap mkdir "`summ_dir'"
	
// Import functions
	adopath + "`code_dir'/ado"
	adopath + `gbd_ado'

// set memory (gb) for each job
	local mem 2
// set type for pulling different years (cod/epi); this is used for what parellel jobs to submit based on cod/epi estimation demographics, not necessarily what inputs/outputs you use
	local type "epi"
// set subnational=no (drops subnationals) or subnational=yes (drops national CHN/IND/MEX/GBR)
	local subnational "yes"
// set code file from 01_code to run in parallel (change from template; just "name.do" no file path since it should be in same directory)
	local code "`step_name'/long_term_final_prev_by_platform_parallel.do"
		
// parallelize by location/year/sex

	// PARALLELIZE BY ISO3/YEAR/SEX
	get_demographics, gbd_team("epi")
	foreach location_id of global location_ids {
		foreach year of global year_ids {
			foreach sex of global sex_ids {
				! qsub -e /share/temp/sgeoutput/ngraetz/errors -o /share/temp/sgeoutput/ngraetz/output -P proj_injuries	-N _`step_num'_`location_id'_`year'_`sex' -pe multi_slot 4 -l mem_free=8 "`code_dir'/stata_shell.sh" "`code_dir'/`code'" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `location_id' `year' `sex'"
			}
		}
	}

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
