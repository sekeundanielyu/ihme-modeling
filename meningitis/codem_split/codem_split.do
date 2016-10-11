// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This is used to run parallelized split code
// Description:	Does a cod model split according to dismod proportion results, and uploads those results to codem
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

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

	// set date
	local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
	local date = subinstr(`"`date'"'," ","_",.)
	// set directory
	local dir "/ihme/scratch/users/strUser/cod_split/meningitis"
	// set adopath
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	// shell file
	local shell_file "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh"
	// make directory in scratch folder
	cap mkdir `"`dir'/`date'"'
	// set code directory
	local code_dir "/ihme/code/epi/strUser/meningitis"
	// set local for cause_ids
	local cause_ids 333 334 335 336

	// run cod_split, do this before running this code (or else save results won't work)
	split_cod_model, source_cause_id(332) target_cause_ids(333 334 335 336) target_meids(1298 1328 1358 1388) output_dir("`dir'/`date'")

	// run save_results
	do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"	

	foreach id of local cause_ids {
		local job_name "save_results_`id'"
		di "submitting `job_name'"
		local slots = 4
		local mem = `slots' *2
		! qsub -P proj_custom_models -N "`job_name'" -pe multi_slot `slots' -l mem_free=`mem' "`shell_file'" "`code_dir'/codem_split_parallel.do" ///
		"`date' `dir' `id'"
	}

