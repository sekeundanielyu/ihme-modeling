// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 		04 August 2014
// Purpose:	Apply proportion


// PREP STATA
	clear
	set more off
	set maxvar 3200
	if c(os) == "Unix" {
		global prefix "/home/j/"
		set odbcmgr unixodbc
		set mem 2g
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		set mem 2g
	}

// Temp directory
	local tmp_dir "`1'"

// location id
	local loc `2'

// Parent pms me_id
	local pms_id `3'

// Proportion me_id
  local prop_id `4'
/*
** ** TEST **
 local tmp_dir "/ihme/centralcomp/custom_models/pms"
 local loc 11
 local pms_id 2079
 local prop_id 2080
**
*/

// ****************************************************************************
// Log work
	capture log close
	log using "`tmp_dir'/00_logs/`loc'_preg_proportion.smcl", replace

	// Load in necessary function
    run "$prefix/WORK/10_gbd/00_library/functions/get_draws.ado"

// Produce symptomatic
	foreach year in 1990 1995 2000 2005 2010 2015 {
		foreach sex in 1 2 {
			// do the stuff for incidence
			get_draws, gbd_id_field(modelable_entity_id) gbd_id(`pms_id') source("epi")measure_ids(6) location_ids(`loc') year_ids(`year') sex_ids(`sex') age_group_ids(2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21) status(best) clear
			renpfix draw case
			tempfile cases
			save `cases', replace
			get_draws, gbd_id_field(modelable_entity_id) gbd_id(`prop_id') source("epi") measure_ids(18) location_ids(`loc') year_ids(`year') sex_ids(`sex') age_group_ids(2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21) status(best) clear
			renpfix draw prop
			merge 1:1 age_group_id using `cases', assert(3) nogen
			forval t = 0/999 {
				gen draw_`t' = case_`t'*(1-prop_`t')
			}
			keep draw* age_group_id
			outsheet using "`tmp_dir'/01_draws/6_`loc'_`year'_`sex'.csv", comma names replace
			// do the stuff for prevalence
			get_draws, gbd_id_field(modelable_entity_id) gbd_id(`pms_id') source("epi")measure_ids(5) location_ids(`loc') year_ids(`year') sex_ids(`sex') age_group_ids(2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21) status(best) clear
			renpfix draw case
			tempfile cases
			save `cases', replace
			get_draws, gbd_id_field(modelable_entity_id) gbd_id(`prop_id') source("epi") measure_ids(18) location_ids(`loc') year_ids(`year') sex_ids(`sex') age_group_ids(2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21) status(best) clear
			renpfix draw prop
			merge 1:1 age_group_id using `cases', assert(3) nogen
			forval t = 0/999 {
				gen draw_`t' = case_`t'*(1-prop_`t')
			}
			keep draw* age_group_id
			outsheet using "`tmp_dir'/01_draws/5_`loc'_`year'_`sex'.csv", comma names replace
		}
	}

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
