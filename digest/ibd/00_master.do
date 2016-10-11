// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:	Apply scalar to IBD sequelae to account for undiagnosed


// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	cap log close
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	
// ****************************************************************************
// Manually defined macros
	** Steps to run (0/1)
	local apply_scalar 1
	local upload 1

	local grouping "colitis crohns"

	local meid_colitis_adjusted 3103
	local meid_crohns_adjusted 3104
	
// ****************************************************************************
// Automated macros
	// code directory
	local prog_dir "/ihme/code/epi/emgold2/ibd"
	// define the date of the run in format YYYY_MM_DD: 2014_01_09
	local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
	local date = subinstr(`"`date'"'," ","_",.)
	// temporary date so I don't have to run 02-03
	// local date = "2016_05_14"
	
	local tmp_dir "/ihme/scratch/users/emgold2/test_steps/ibd/03_steps"
	capture mkdir "`tmp_dir'/`date'"
	capture mkdir "`tmp_dir'/`date'/00_logs"
	capture mkdir "`tmp_dir'/`date'/01_draws"
	capture mkdir "`tmp_dir'/`date'/01_draws/colitis"
	capture mkdir "`tmp_dir'/`date'/01_draws/crohns"
	
	// directory for standard code files and functions
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	// shell file
	local shell_file "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh"
	
// ****************************************************************************
// Get country list
	get_location_metadata, location_set_id(9) clear
	keep if most_detailed == 1 & is_estimate == 1
	levelsof location_id, local(locations)
	clear

// ****************************************************************************
// set log for parent code
	cap log using "`tmp_dir'/`date'/00_logs/scalar_parent.smcl", replace
	if !_rc local close_log 1
	else local close_log 0
	
// ****************************************************************************
// Modify draws to apply undiagnosed scalar?

	// set up check system
	local c = 0
	// erase and make directory for finished checks
	! mkdir "`tmp_dir'/`date'/checks"
	local datafiles: dir "`tmp_dir'/`date'/checks" files "finished_loc*.txt"
	foreach datafile of local datafiles {
		rm "`tmp_dir'/`date'/checks/`datafile'"
	}

	if `apply_scalar' == 1 {
		clear
		local M = 1.070 
		local L = 1.054
		local U = 1.086
		local SE = (`U'-`L')/(2*1.96)
		drawnorm prop_, n(1000) means(`M') sds(`SE')
		gen num = _n
		replace num = num-1
		gen mvar = 1
		reshape wide prop_, i(mvar) j(num)
		save "`tmp_dir'/`date'/prop_draws.dta", replace
		local slots 4
		local mem = `slots' * 2
		foreach location of local locations {
			!qsub -P proj_custom_models -pe multi_slot `slots' -l mem_free=`mem' -N "loc`location'_IBD_scalar" "`shell_file'" ///
			"`prog_dir'/01_apply_scalar.do" "`tmp_dir' `location' `date'"

			local ++ c
			sleep 100
		}
	}

	sleep 60000

	// wait for jobs to finish before passing save_results argument
	local i = 0
	while `i' == 0 {
		local checks : dir "`tmp_dir'/`date'/checks" file "finished_loc*.txt", respectcase
		local count : word count `checks'
		di "checking `c(current_time)': `count' of `c' jobs finished"
		if (`count' == `c') continue, break
		else sleep 60000
	}

	di "All files adjusted and saved"

// ****************************************************************************
// Save results?

// CHANGED TO INCIDENCE

	if `upload' == 1 {
		run "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
		foreach group of local grouping {
			save_results, modelable_entity_id(`meid_`group'_adjusted') metrics(prevalence incidence) description(emgold2: custom upload of adjusted `group' `date' both incidence and prevalence) ///
			mark_best(yes) in_dir(`tmp_dir'/`date'/01_draws/`group')
		}
	}
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Finished?

	file open finished using "`tmp_dir'/`date'/finished.txt", replace write
	file close finished

	// close log if open
	if `close_log' log close
	clear all
