// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:	Calcluate asymptomatic

// PREP STATA
	clear
	set more off
	set maxvar 3200
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	
// locals from the qsub
	local tmp_dir 	`1'
	local cause 	`2'
	local date 		`3'
	local location 	`4'


	// write log
	cap log using "`tmp_dir'/`date'/00_logs/asymptomatic_`cause'.smcl", replace
	if !_rc local close 1
	else local close 0

	// directory for standard code files and functions
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
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

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(``cause'_chronic') status(best) measure_ids(5) location_ids(`location') source(epi) clear
	drop if age_group_id >= 22
	drop model_version_id
	tempfile chronic_`cause'_data
	save `chronic_`cause'_data', replace

	get_draws, gbd_id_field(modelable_entity_id) gbd_id(``cause'_symp') status(best) measure_ids(5) location_ids(`location') source(epi) clear
	drop if age_group_id >= 22
	drop model_version_id
	forvalues i = 0/999 {
		rename draw_`i' symp_`i'
	}

	merge 1:1 location_id year_id age_group_id sex_id using `chronic_`cause'_data', nogen
	forvalues i = 0/999 {
		replace draw_`i' = draw_`i' - symp_`i'
	}
	drop symp*
	

	foreach year of local years {
		foreach sex of local sexes {
			preserve
			keep if location_id == `location' & year_id == `year' & sex_id == `sex'
			outsheet using "`tmp_dir'/`date'/01_draws/`cause'/5_`location'_`year'_`sex'.csv", comma replace
			restore
		}
	}

	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// write check
	file open finished using "`tmp_dir'/`date'/checks/`cause'/finished_`cause'_`location'.txt", replace write
	file close finished

// close logs
	if `close' log close
	clear
