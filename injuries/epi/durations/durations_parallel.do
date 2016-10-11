// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Purpose:		Multiply treated and untreated durations by country-year-specific %-treated to get country-year-specific durations of short-term outcomes

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
		local 4 "01d"
		local 5 durations
		local 6 "/share/code/injuries/ngraetz/inj/gbd2015"
		local 7 178
		local 8 2000
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
// WRITE CODE HERE

// Settings
	set type double, perm

	local pct_file "`out_dir'/01_inputs/pct_treated.dta"
	local dur_file "`out_dir'/01_inputs/durs.dta"

// update adopath
	adopath + "`code_dir'/ado"

// Load injury parameters
	load_params
	
// Merge on pct treated
	use "`dur_file'", clear
	gen location_id = `location_id'
	gen year_id = `year'
	merge m:1 location_id year_id using "`pct_file'", keep(match) nogen
	
// Generate final durations
	forvalues x = 0/$drawmax {
		replace treat_`x' = pct_treated * treat_`x' + (1-pct_treated) * untreat_`x'
		drop untreat_`x'
	}
	rename treat_* draw*
	
// Save draws
	drop location_id year pct_treated
	sort_by_ncode ncode, other_sort(inpatient)
	export delimited "`tmp_dir'/03_outputs/01_draws/durations_`location_id'_`year'.csv", replace
	
// Save summary
	fastrowmean draw*, mean_var_name("mean")
	fastpctile draw*, pct(2.5 97.5) names(ul ll)
	drop draw*
	export delimited "`tmp_dir'/03_outputs/02_summary/durations_`location_id'_`year'.csv", replace
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

