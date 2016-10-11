// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This sub-step template is for parallelized jobs submitted from main step code
// Description:	Parallelization of 04d_outcome_prev_wmort_woseiz.do

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM STEP CODE (NO NEED TO EDIT THIS SECTION)

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

// define locals from qsub command
	local date 			`1'
	local step_num 		`2'
	local step_name		`3'
	local location 		`4'
	local code_dir 		`5'
	local in_dir 		`6'
	local out_dir 		`7'
	local tmp_dir 		`8'
	local root_tmp_dir 	`9'
	local root_j_dir 	`10'

// define other locals
	// directory for standard code files
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	// grouping
	local grouping "long_modsev"
	// functional
	local functional "encephalitis"

	// get locals from demographics
	get_demographics, gbd_team(epi) clear
	local years = "$year_ids"
	local sexes = "$sex_ids"

	// write log if running in parallel and log is not already open
	cap log using "`out_dir'/02_temp/02_logs/`step_num'_`location'.smcl", replace
	if !_rc local close 1
	else local close 0

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE

	get_draws, gbd_id_field(modelable_entity_id) gbd_id(2815) location_ids(`location') ///
	status(best) source(epi) clear
	drop if age_group_id >= 22
	drop model_version_id	
	foreach year of local years {
		foreach sex of local sexes {
			preserve
			keep if year_id == `year' & sex_id == `sex'
			save "`tmp_dir'/03_outputs/01_draws/`functional'_`grouping'_`location'_`year'_`sex'.dta", replace
			restore
		}
	}


// write check here
	file open finished using "`tmp_dir'/02_temp/01_code/checks/finished_loc`location'.txt", replace write
	file close finished

// close logs
	if `close' log close
	clear
