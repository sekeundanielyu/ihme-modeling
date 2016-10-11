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
	
// Sequela_id
	local parent_me `3'
	
// Limit applied equela_id
	local limit_me `4'
	
// Model
	local model `5'
	
** ** TEST **
** local prog_dir "$prefix/WORK/04_epi/02_models/01_code/06_custom/ntd_foodborne"
** local tmp_dir "/clustertmp/User/FBT_model_prep"
** capture mkdir "`tmp_dir'"
** local grouping clonorchiasis
** local parent_seq 1525
** local limit_seq 3078
** local model 22035
	
// ****************************************************************************
// Use get_draws
	run $prefix/WORK/10_gbd/00_library/functions/get_demographics.ado
	run $prefix/WORK/10_gbd/00_library/functions/get_draws.ado
	
// Make sequela-specific director
	capture mkdir "`tmp_dir'/`limit_me'"
	capture mkdir "`tmp_dir'/`limit_me'/00_logs"
	capture mkdir "`tmp_dir'/`limit_me'/01_country_limit"
	
// Log work
	//capture log close
	//log using "`tmp_dir'/`limit_me'/00_logs/01_country_limit.smcl", replace
	
// Load country list
	get_demographics, gbd_team("epi") make_template clear
	keep location_id location_name
	duplicates drop
	duplicates drop location_name, force
	tempfile locdf
	save `locdf'
	insheet using "`prog_dir'/fbt_sequela_country_list.csv", comma names clear
	di "`parent_me'"
	keep me_id_`parent_me'
	rename me_id_`parent_me' location_name
	drop if location_name == ""
	duplicates drop
	** Merge on location_name codes
	merge 1:1 location_name using `locdf', assert(2 3) keep(3) keepusing(location_id) nogen
	keep location_id
	gen keep_location_id = 1
	tempfile location_id_list
	save `location_id_list', replace
	
// Get final country list
	get_demographics, gbd_team("epi") make_template clear
	keep location_id
	duplicates drop
	merge 1:1 location_id using `location_id_list', assert(1 3) nogen
	replace keep_location_id = 0 if keep_location_id == .
	levelsof location_id, local(locations)
	foreach location of local locations {
		quietly levelsof keep_location_id if location_id == `location', local(keep_id) c
		if `keep_id' == 1 di "Keeping `location' data"
		if `keep_id' == 0 di "Removing `location' data"
		preserve
		foreach year_id in 1990 1995 2000 2005 2010 2015 {
			foreach sex_id in 1 2 {
				if `keep_id' != 1 {
					di "`parent_me' `location' `year_id' `sex_id'"
					get_draws, gbd_id_field("modelable_entity_id") gbd_id(`parent_me') source("epi") measure_ids(5) location_ids(`location') year_ids(`year_id') sex_ids(`sex_id') clear
					foreach var of varlist draw* {
						quietly replace `var' = 0
					}
					quietly replace measure_id = 5
					quietly replace modelable_entity_id = `limit_me'
					quietly replace model_version_id = `model'
					quietly outsheet using "`tmp_dir'/`limit_me'/01_country_limit/6_`location'_`year_id'_`sex_id'.csv", comma names replace
				}
				else if `keep_id' == 1 {
					di "`parent_me' `location' `year_id' `sex_id'"
					get_draws, gbd_id_field("modelable_entity_id") gbd_id(`parent_me') source("epi") measure_ids(5) location_ids(`location') year_ids(`year_id') sex_ids(`sex_id') clear
					quietly replace measure_id = 5
					quietly replace modelable_entity_id = `limit_me'
					quietly replace model_version_id = `model'
					quietly outsheet using "`tmp_dir'/`limit_me'/01_country_limit/6_`location'_`year_id'_`sex_id'.csv", comma names replace
				}
			}
		}
		restore
	}
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
