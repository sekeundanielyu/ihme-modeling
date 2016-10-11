// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 		04 August 2016
// Purpose:	Apply pregnagncy adjustment to parent PMS model


// PREP STATA
	clear all
	set more off
	set maxvar 3200
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
		set mem 2g
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		set mem 2g
	}

	// make connection string
	run "$prefix/WORK/10_gbd/00_library/functions/create_connection_string.ado"
	create_connection_string, database(epi) server(modeling-epi-db)
	local epi_str = r(conn_string)

// ****************************************************************************
// Manually defined macros
	** User
	local username USER

	** Steps to run (0/1)
	local apply_proportion 0
	local upload 1
	local sweep 0

	** Where is your local repo for this code?
	local prog_dir "/homes/`username'/pms_custom_code"

// ****************************************************************************
// Automated macros

	local tmp_dir "/ihme/centralcomp/custom_models/pms"
	capture mkdir "`tmp_dir'"
	capture mkdir "`tmp_dir'/00_logs"
	capture mkdir "`tmp_dir'/01_draws"

// ****************************************************************************
// Load original parent models
	local pms_id 2079
	local prop_id 2080
	local final_pms_id 3133
	odbc load, exec("SELECT model_version_id, modelable_entity_id from epi.model_version where modelable_entity_id IN(`pms_id', `prop_id') and is_best = 1") `epi_str' clear
	levelsof model_version_id if modelable_entity_id == `pms_id', local(cases_model)
	levelsof model_version_id if modelable_entity_id == `prop_id', local(prop_model)

// ****************************************************************************
// Get country list
	odbc load, exec("SELECT lhh.location_id FROM shared.location_hierarchy_history lhh WHERE lhh.location_set_version_id = (SELECT location_set_version_id FROM shared.location_set_version lsv WHERE lsv.location_set_id = 35 AND lsv.gbd_round = 2015 AND lsv.end_date IS NULL) AND most_detailed = 1 ORDER BY sort_order") `epi_str' clear
	levelsof location_id, local(locations)

// ****************************************************************************
// Modify draws to apply pregnancy proportion?
	if `apply_proportion' == 1 {
		foreach loc of local locations {
			!qsub -P proj_custom_models -pe multi_slot 4 -l mem_free=8g -N "PMS_proportion_`loc'" "`prog_dir'/stata_shell.sh" "`prog_dir'/01_apply_proportion.do" "`tmp_dir' `loc' `pms_id' `prop_id'"
		}
	}

// ****************************************************************************
// Upload?
	if `upload' == 1 {
	    if `apply_proportion' == 1 {
	        sleep 6000000
	        }
		quietly {
			run $prefix/WORK/10_gbd/00_library/functions/save_results.do
			save_results, modelable_entity_id(`final_pms_id') metrics(incidence prevalence) description("model `case_model' reduced by model `prop_model'") in_dir("`tmp_dir'/01_draws") mark_best("yes")
			noisily di "UPLOADED -> " c(current_time)
		}
	}

// ****************************************************************************
// Clear draws?
	if `sweep' == 1 {
		!rm -rf "`tmp_dir'"
	}

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
