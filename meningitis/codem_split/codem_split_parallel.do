// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
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

// define locals from qsub command
	local date			`1'
	local dir 			`2'
	local cause_id		`3'

	// directory for standard code files	
	adopath + "$prefix/WORK/10_gbd/00_library/functions"

	// set descriptions
	local description "meningitis_pneumo" if `cause_id' == 333
	local description "meningitis_hib" if `cause_id' == 334
	local description "meningitis_meningo" if `cause_id' == 335
	local description "meningitis_other" if `cause_id' == 336

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE

	do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"

	save_results, cause_id(`cause_id') description(Custom `description' model `date') mark_best(yes) in_dir(/share/scratch/users/strUser/cod_split/meningitis/`date'/`cause_id')


// set adopath
	// adopath + "$prefix/WORK/10_gbd/00_library/functions"
	// shell file
	// local shell_file "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh"

		// ! qsub -P proj_custom_models -N "meningitis_hib" -pe multi_slot 4 -l mem_free=8 "`shell_file'" "`code_dir'/codem_split_parallel.do" ///

		// save_results, cause_id(333) description(Custom meningitis_pneumo model 2016_04_03) mark_best(yes) in_dir(/share/scratch/users/strUser/cod_split/meningitis/2016_04_03/333)

		// save_results, cause_id(334) description(Custom meningitis_hib model 2016_04_03) mark_best(yes) in_dir(/share/scratch/users/strUser/cod_split/meningitis/2016_04_03/334)
		
		// save_results, cause_id(335) description(Custom meningitis_meningo model 2016_04_03) mark_best(yes) in_dir(/share/scratch/users/strUser/cod_split/meningitis/2016_04_03/335)
		
		// save_results, cause_id(336) description(Custom meningitis_other model 2016_04_03) mark_best(yes) in_dir(/share/scratch/users/strUser/cod_split/meningitis/2016_04_03/336)
		
