// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This template takes prevalence of symptomatic episodes from prevalence of chronic disease for digestive disorders
// Description:	Pull in prevalence of chronic disease and symptomatic episodes, subtract, and save results for asymptomatic MEIDs and sequelae	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
	// This must be done on the cluster because of get_draws

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

	// set locals
	// define the date of the run in format YYYY_MM_DD: 2014_01_09
	local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
	local date = subinstr(`"`date'"'," ","_",.)
	// directory for standard code files
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	// code directory
	local code_dir "/ihme/code/epi/strUser/digestive"
	// directory
	local tmp_dir "/ihme/scratch/users/strUser/test_steps/digestive/03_steps"
	capture mkdir "`tmp_dir'/`date'"
	capture mkdir "`tmp_dir'/`date'/01_draws"
	capture mkdir "`tmp_dir'/`date'/00_logs"

	// Which causes do I want to do?
	local pud 0
	local gastritis 0
	local bile 1

	// get locals from demographics
	get_demographics, gbd_team(epi) clear
	local years = "$year_ids"
	local sexes = "$sex_ids"
	clear

	// get demographics
    get_location_metadata, location_set_id(9) clear
    keep if most_detailed == 1 & is_estimate == 1
    levelsof(location_id), local(locations)

	//MEIDs
	local pud_symp 1924
	local pud_chronic 9759
	local pud_asymp 9314
	local gastritis_symp 1928
	local gastritis_chronic 9761
	local gastritis_asymp 9528
	local bile_symp 1940
	local bile_chronic 9760
	local bile_asymp 9535

	// shell file
	local shell_file "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh"

	// write log
	cap log using "`tmp_dir'/`date'/00_logs/asymptomatic_parent.smcl", replace
	if !_rc local close 1
	else local close 0

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE
	// set up local of causes
	local causes ""
	if `pud' == 1 local causes = "pud"
	if `gastritis' == 1 local causes = "`causes' gastritis" 
	if `bile' == 1 local causes = "`causes' bile"

	// set up check system
	foreach cause of local causes {
		local count_`cause' 0

		local datafiles: dir "`tmp_dir'/`date'/checks/`cause'" files "finished_`cause'*.txt"
		foreach datafile of local datafiles {
			rm "`tmp_dir'/`date'/checks/`cause'/`datafile'"
		}

		capture mkdir "`tmp_dir'/`date'/01_draws/`cause'"
		capture mkdir "`tmp_dir'/`date'/checks/`cause'"
	}

	foreach cause of local causes {
		foreach location of local locations {
			local slots = 4
			local mem = 2 * `slots'

			!qsub -P proj_custom_models -pe multi_slot `slots' -l mem_free=`mem' -N "asymptomatic_`cause'_`location'" "`shell_file'" ///
			"`code_dir'/chronic_adjustment_parallel.do" "`tmp_dir' `cause' `date' `location'"

			di "`cause' job submitted"
			local ++ count_`cause'
			sleep 100
		}
	}

	sleep 60000

	// wait for jobs to finish before passing save_results argument
	foreach cause of local causes {
		local i_`cause' = 0
		while `i_`cause'' == 0
		local checks : dir "`tmp_dir'/`date'/checks/`cause'" file "finished_`cause'*.txt", respectcase
		local count : word count `checks'
		di "checking `c(current_time)': `count' of `count_`cause'' jobs finished"
		if (`count' == `count_`cause'') continue, break
		else sleep 60000
	}

	run "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
	foreach cause of local causes {
		save_results, modelable_entity_id(``cause'_asymp') metrics(prevalence) description(emgold2: custom upload of adjusted `cause' `date') mark_best(yes) in_dir(`tmp_dir'/`date'/01_draws/`cause')
	}

	di "All models saved"

// close logs
	if `close' log close
	clear
	