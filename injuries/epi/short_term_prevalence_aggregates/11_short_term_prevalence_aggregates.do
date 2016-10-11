// LOAD SETTINGS FROM MASTER CODE (NO NEED TO EDIT THIS SECTION)
// Aggregate short-term results to E- and N-code to upload to Epi database 

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

	// Make save dirs 
	cap mkdir "/share/injuries/04_COMO_input/03_lt_prev"
	cap mkdir "/share/injuries/04_COMO_input/03_st_prev"
	cap mkdir "/share/injuries/04_COMO_input/03_st_prev/outpatient"
	cap mkdir "/share/injuries/04_COMO_input/03_st_prev/inpatient"
	cap mkdir "/share/injuries/04_COMO_input/03_lt_prev/outpatient"
	cap mkdir "/share/injuries/04_COMO_input/03_lt_prev/inpatient"
	cap mkdir "/share/injuries/04_COMO_input/03_st_inc"
	cap mkdir "/share/injuries/04_COMO_input/03_st_inc/outpatient"
	cap mkdir "/share/injuries/04_COMO_input/03_st_inc/inpatient"
	
	// set code file from 01_code to run in parallel (change from template; just "name.do" no file path since it should be in same directory)
	local code "`step_name'/short_term_prevalence_aggregates_parallel.do"

	// parallelize by location/year/sex
	get_demographics, gbd_team("epi")
	foreach location_id of global location_ids {
		foreach year of global year_ids {
			foreach sex of global sex_ids {
				! qsub -e /share/temp/sgeoutput/ngraetz/errors -o /share/temp/sgeoutput/ngraetz/output -P proj_injuries	-N _prev_agg_`location_id'_`year'_`sex' -pe multi_slot 4 -l mem_free=8 "`code_dir'/stata_shell.sh" "`code_dir'/`code'" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `location_id' `year' `sex'"
			}
		}
	}

// END

