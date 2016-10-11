// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This code takes prevalence of all hernia, and divides it by 1 + primary correction factor to get symptomatic hernia
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
	capture mkdir "`tmp_dir'/`date'/hernia"
	capture mkdir "`tmp_dir'/`date'/hernia/01_draws"
	capture mkdir "`tmp_dir'/`date'/hernia/00_logs"

	// MEIDs
	local hernia_chronic 9794
	local hernia_symp 1934
	local hernia_asymp 9542
	local correction_factor_male 4.1424856185913
	local correction_factor_female 4.79122304916381

	// code directory
	local code_dir "/ihme/code/epi/emgold2/digestive"

	// shell file
	local shell_file "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh"

	// get demographics
    get_location_metadata, location_set_id(9) clear
    keep if most_detailed == 1 & is_estimate == 1
    levelsof(location_id), local(locations)

    get_demographics, gbd_team(epi) clear
    local years = "$year_ids"
    local sexes = "$sex_ids"
    //local locations 102

	//make more files for save results
	capture mkdir "`tmp_dir'/`date'/hernia/01_draws/`hernia_symp'"
	capture mkdir "`tmp_dir'/`date'/hernia/01_draws/`hernia_asymp'"

	// write log
	cap log using "`tmp_dir'/`date'/hernia/00_logs/hernia_adjustment.smcl", replace
	if !_rc local close 1
	else local close 0

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE


	local a 0
	foreach location of local locations {

		di "submitting hernia_`location'"
		!qsub -P proj_custom_models -N "hernia_`location'" -pe multi_slot 4 -l mem_free=8 "`shell_file'" "`code_dir'/hernia_symp.do" ///
		"`date' `tmp_dir' `location'"

		foreach year of local years {
			foreach sex of local sexes {
				local ++ a
			}
		}
		sleep 100
	}

	sleep 120000

	local b = 0
	while `b' == 0 {
		local checks : dir "`tmp_dir'/`date'/hernia/01_draws/`hernia_symp'" files "5_*.csv", respectcase
		local count : word count `checks'
		di "checking `c(current_time)': `count' of `a' jobs finished"
		if (`count' == `a') continue, break
		else sleep 60000
	}


	run "$prefix/WORK/10_gbd/00_library/functions/save_results.do"

	save_results, modelable_entity_id(`hernia_symp') metrics(prevalence) description(emgold2: custom upload of adjusted symptomatic hernias `date') mark_best(yes) in_dir(`tmp_dir'/`date'/hernia/01_draws/`hernia_symp')
	save_results, modelable_entity_id(`hernia_asymp') metrics(prevalence) description(emgold2: custom upload of asymptomatic hernias `date') mark_best(yes) in_dir(`tmp_dir'/`date'/hernia/01_draws/`hernia_asymp')


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// close logs
	if `close' log close
	clear

