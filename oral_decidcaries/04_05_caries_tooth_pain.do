// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:	Split deciduous and permanent caries to make tooth pain child
// do "/home/j/WORK/04_epi/02_models/01_code/06_custom/oral/04_05_caries_tooth_pain.do"

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

// Parent ME_id
	local parent_id `2'

// ME_id of symptomatic results
	local child_id `3'

// ME_id of asymptomatic results
	local asymp_id `4'

// location_id
	local loc `5'

// data-rich or data-poor?
	local dev_stat "`6'"

** ** TEST **
** local tmp_dir "/clustertmp/USER/oral_model_prep"
** local parent_id 2336
** local child_id 2583
** local asymp_id 3092
** local loc 11
** local dev_stat "D0"

// ****************************************************************************
// Log work
	capture log close
	log using "`tmp_dir'/`child_id'/00_logs/`loc'_draws.smcl", replace

	// Load in necessary function
run "$prefix/WORK/10_gbd/00_library/functions/get_draws.ado"

// Get final country list
	foreach year in 1990 1995 2000 2005 2010 2015 {
		foreach sex in 1 2 {
			foreach met in 5 6 {
				get_draws, gbd_id_field(modelable_entity_id) gbd_id(`parent_id') source("epi") measure_ids(`met') location_ids(`loc') year_ids(`year') sex_ids(`sex') age_group_ids(2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21) status(best) clear
				gen metric = "prevalence_incidence"
				merge m:1 metric using "`tmp_dir'/`child_id'/tooth_pain_split_`dev_stat'.dta", assert(3) nogen
				forval y = 0/999 {
					gen symp_`y' = draw_`y'*prop_`y'
				}
				drop prop* metric
				preserve
					forval y = 0/999 {
						replace draw_`y' = draw_`y' - symp_`y'
					}
					drop symp*
					outsheet using "`tmp_dir'/`asymp_id'/01_draws/`met'_`loc'_`year'_`sex'.csv", comma names replace
				restore
				drop draw*
				renpfix symp draw
				outsheet using "`tmp_dir'/`child_id'/01_draws/`met'_`loc'_`year'_`sex'.csv", comma names replace
			}
		}
	}


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
