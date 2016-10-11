// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:	Apply proportion

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
	local location 	`2'
	local date 		`3'

// set other locals
	// directory for standard code files and functions
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	// get locals from demographics
	get_demographics, gbd_team(epi) clear
	local years = "$year_ids"
	local sexes = "$sex_ids"
	clear
	// grouping
	local grouping "colitis crohns"
	// meids unadjusted
	local meid_colitis 1935
	local meid_crohns 1937
	// meids adjusted
	local meid_colitis_adjusted 3103
	local meid_crohns_adjusted 3104

	// measure_ids
	local metrics 5 6

	get_location_metadata, location_set_id(9) clear
	keep if most_detailed == 1 & is_estimate == 1
	levelsof location_id, local(locations)
	clear
	

	// write log
	cap log using "`tmp_dir'/`date'/00_logs/adjust_`location'.smcl", replace
	if !_rc local close 1
	else local close 0
	
// ****************************************************************************
	
	foreach group of local grouping {
		get_draws, gbd_id_field(modelable_entity_id) measure_ids(5 6) gbd_id(`meid_`group'') location_ids(`location') status(best) source(epi) clear
		drop if age_group_id >= 22
		drop model_version_id
		gen mvar = 1
		merge m:1 mvar using "`tmp_dir'/`date'/prop_draws.dta", keep(3) nogen
		forval t = 0/999 {
			replace draw_`t' = draw_`t' * prop_`t'
		}
		drop prop*
		foreach year of local years {
			foreach sex of local sexes {
				foreach i of local metrics {
					preserve
					keep if year_id == `year' & sex_id == `sex' & measure_id == `i'
					outsheet using "`tmp_dir'/`date'/01_draws/`group'/`i'_`location'_`year'_`sex'.csv", comma replace
					restore
				}

			}
		}
	}
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************


// Do I want to write this check?
	file open finished using "`tmp_dir'/`date'/checks/finished_loc`location'.txt", replace write
	file close finished

// close logs
	if `close' log close
	clear
