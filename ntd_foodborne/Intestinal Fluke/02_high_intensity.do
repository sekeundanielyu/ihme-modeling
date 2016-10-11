// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
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
	
// Program directory
	local prog_dir "`1'"
	
// Temp directory
	local tmp_dir "`2'"
	
// Sequela label
	local location "`3'"
	
** ** TEST **
	//local prog_dir "$prefix/WORK/04_epi/02_models/01_code/06_custom/ntd_foodborne"
	//local tmp_dir "/share/scratch/users/User/FBT_model_prep"
** capture mkdir "`tmp_dir'"
	//local location 62
	
// ****************************************************************************
// Use get_draws
	run $prefix/WORK/10_gbd/00_library/functions/get_draws.ado

// Log work
	//capture log close
	//log using "`tmp_dir'/_split_logs/`location'_high_intensity.smcl", replace
	
// Load sequela list and produce symptomatic
	use "`tmp_dir'/me_list.dta", clear
	levelsof child_id, local(me_ids)
	foreach me_id of local me_ids {
		preserve
			levelsof parent_id if child_id == `me_id', local(parent_id) c
			foreach year_id in 1990 1995 2000 2005 2010 2015 {
				foreach sex_id in 1 2 {
					insheet using "`tmp_dir'/`parent_id'/01_country_limit/6_`location'_`year_id'_`sex_id'.csv", comma names clear
					drop if age_group_id > 21 | age_group_id < 2
					recast double age_group_id
					tempfile parent_`parent_id'_`year_id'_`sex_id'
					save `parent_`parent_id'_`year_id'_`sex_id'', replace
					merge 1:1 age_group_id sex_id using "`tmp_dir'/`me_id'/high_intensity_proportions.dta", assert(2 3) keep(3) nogen
					forval t = 0/999 {
						replace draw_`t' = draw_`t'*prop_`t'
					}
					replace modelable_entity_id = `me_id'
					drop prop*
					tempfile child_`me_id'_`year_id'_`sex_id'
					save `child_`me_id'_`year_id'_`sex_id'', replace
					outsheet using "`tmp_dir'/`me_id'/01_child_draws/6_`location'_`year_id'_`sex_id'.csv", comma names replace
				}
			}
		restore
	}
	levelsof asymp_id, local(asymp_ids)
	foreach asymp_id of local asymp_ids {
		preserve
			levelsof parent_id if asymp_id == `asymp_id', local(parent_id) c
			levelsof child_id if asymp_id == `asymp_id', local(child_ids) c
			foreach year_id in 1990 1995 2000 2005 2010 2015 {
				foreach sex_id in 1 2 {
					use `parent_`parent_id'_`year_id'_`sex_id'', clear
					renpfix draw parent
					foreach child_id of local child_ids {
						merge 1:1 age_group_id using `child_`child_id'_`year_id'_`sex_id'', assert(3) nogen
						forval t = 0/999 {
							replace parent_`t' = parent_`t'-draw_`t'
						}
						drop draw*
					}
					replace modelable_entity_id = `asymp_id'
					renpfix parent draw
					outsheet using "`tmp_dir'/`asymp_id'/01_child_draws/6_`location'_`year_id'_`sex_id'.csv", comma names replace
				}
			}
		restore
	}
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
