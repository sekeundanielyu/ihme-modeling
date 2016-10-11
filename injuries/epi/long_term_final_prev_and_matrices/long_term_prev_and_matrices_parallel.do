// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	This step cycles through n-codes, sums long term prevalence across e-codes for input into COMO and also saves the distributions of E-codes for each n-code for post-como redistribution

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
		local 4 "07"
		local 5 long_term_final_prev_and_matrices
		local 6 "/share/code/injuries/ngraetz/inj/gbd2015"
		local 7 165
		local 8 2010
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
    // iso3
	local location_id `7'
	// year
	local year `8'
	// sex
	local sex `9'
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

// SETTINGS
	set type double, perm
	** how many slots is this script being run on?
	local slots 1
	** debugging?
	local debug 1

// Filepaths
	//ocal gbd_ado "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	local como_dir = "/share/injuries/04_COMO_input"
	cap mkdir "`como_dir'"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local rundir "`root_tmp_dir'/03_steps/`date'"
	local draw_dir "`tmp_dir'/03_outputs/01_draws"
	local summ_dir "`tmp_dir'/03_outputs/02_summary"
	local ncode_draw_out "`como_dir'/00_long_term_ncode_plat_prev"
	local NEmatrix_draw_out "`como_dir'/01_NE_matrix"
	local NEmatrix_summ_out "`summ_dir'/NEmatrix"
	cap mkdir "`ncode_draw_out'"
	cap mkdir "`NEmatrix_draw_out'"
	cap mkdir "`NEmatrix_summ_out'"
	cap mkdir "`summ_dir'"
	cap mkdir "`draw_dir'"

// Import functions
	adopath + "`code_dir'/ado"

// Load injuries parameters
	get_demographics, gbd_team("epi")

// get the step number of the step you're pulling output from
	** global is too long for get_step_num function
	local step_name long_term_final_prev_by_platform
	import excel "`code_dir'/_inj_steps.xlsx", sheet("steps") firstrow clear
	keep if name == "`step_name'"
	local prev_step = step[1] + "_`step_name'"

// Import long-term prev by E-N
	use "`rundir'/`prev_step'/03_outputs/01_draws/`location_id'/prevalence_`location_id'_`year'_`sex'.dta", clear
	cap drop mean
	
	drop if regexm(ncode, "N") != 1
	
	// Get age groups (not ids)
	preserve
	insheet using "`code_dir'/convert_to_new_age_ids.csv", comma names clear
	levelsof age_start, l(ages)
	restore

// Create prevalence NE matrices and collapse to N and E-code long-term prevalences
	collapse_to_n_and_e, code_dir("`code_dir'") prefix("$prefix") n_draw_outdir("`ncode_draw_out'") e_draw_outdir("`draw_dir'") summ_outdir("`summ_dir'") output_name("5_`location_id'_`year'_`sex'") ages("`ages'") longterm matrix_draw_outfile("`NEmatrix_draw_out'/NEmatrix_`location_id'_`year'_`sex'.csv") matrix_summ_outfile("`NEmatrix_summ_out'/NEmatrix_`location_id'_`year'_`sex'.csv")
	
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

	