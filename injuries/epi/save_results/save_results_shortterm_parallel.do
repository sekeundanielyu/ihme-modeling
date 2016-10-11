// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Purpose:		Save_results to Epi database for COMO

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM STEP CODE (NO NEED TO EDIT THIS SECTION)

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
	if "`1'"=="" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "08"
		local 5 upload_summed_prev
		local 6 "/share/code/injuries/ngraetz/inj/gbd2015"
		local 7 ncode
		local 8 N16
		local 9 1
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
    // directory where the code lives
    local code_dir `6'
    // code
	local code_type `7'
	// specific ecode or ncode 
	local code `8'
	// platform
	local platform `9'
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

// Pull me id for this N-code platform
insheet using "`code_dir'/como_st_yld_mes.csv", comma names clear
	if "`code_type'" == "ecode" {
		keep if e_code == "`code'" & inpatient == `platform'
		local results_dir = "/share/injuries/04_COMO_input/02_st_ylds/E/`code'/`platform'"
	}
	if "`code_type'" == "ncode" {
		keep if n_code == "`code'" & inpatient == `platform'
		local results_dir = "/share/injuries/04_COMO_input/02_st_ylds/N/`code'/`platform'"
	}
	local me_id = modelable_entity_id

do /home/j/WORK/10_gbd/00_library/functions/save_results.do
save_results, modelable_entity_id(`me_id') description("YLDs for COMO submission") in_dir("`results_dir'") metrics(3) mark_best("yes")

// END

