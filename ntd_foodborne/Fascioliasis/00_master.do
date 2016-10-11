// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
{
/*
23284	Clonorchiasis due to food-borne trematodiases all countries (1525)
23272	Fascioliasis due to food-borne trematodiases all countries (1526)
22036	Intestinal fluke infection due to food-borne trematodiases all countries (1527)
22031	Opisthorchiasis due to food-borne trematodiases all countries (1528)
23270	Paragonimiasis due to food-borne trematodiases all countries (1529)
*/
}

// PREP STATA
	clear all
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
	
// ****************************************************************************
// Manually defined macros
	** User
	local username User
	
	** Steps to run (0/1)
	local country_limit 0
	local heavy_infection_cerebral 0
	local upload_parent 1
	local upload_child 1
	local sweep 0
	
// ****************************************************************************
// Automated macros
	run $prefix/WORK/10_gbd/00_library/functions/create_connection_string.ado
	run $prefix/WORK/10_gbd/00_library/functions/get_demographics.ado
	run $prefix/WORK/10_gbd/00_library/functions/save_results.do
    create_connection_string, database(epi) server(modeling-epi-db)
    local epi_str = r(conn_string)
	
	local prog_dir "$prefix/WORK/04_epi/02_models/01_code/06_custom/ntd_foodborne"
	
	local tmp_dir "/share/scratch/users/`username'/FBT_model_prep"
	capture mkdir "`tmp_dir'"
	capture mkdir "`tmp_dir'/_split_logs"
	
	adopath + "$prefix/WORK/04_epi/01_database/01_code/04_models/prod"
	
// ****************************************************************************
// Load original parent models
	odbc load, exec("SELECT modelable_entity_id, modelable_entity_name, cause_id, model_version_id FROM epi.model_version JOIN epi.modelable_entity USING (modelable_entity_id) JOIN epi.modelable_entity_cause USING (modelable_entity_id) WHERE is_best = 1 AND cause_id = 364 AND modelable_entity_name LIKE '% food-borne % countries' OR is_best = 1 AND cause_id = 364 AND modelable_entity_name LIKE 'Symptomatic %'") `epi_str' clear
	tempfile parent_me_list
	save `parent_me_list', replace
	
// ****************************************************************************
// Get country list
	get_demographics, gbd_team("epi") make_template clear
	keep location_id
	duplicates drop
	levelsof location_id, local(locations)
	
// ****************************************************************************
// Save draws with limited country lists?
	if `country_limit' == 1 {
		insheet using "`prog_dir'/parent_map.csv", comma names clear
		tempfile map
		save `map'
		use `parent_me_list', clear
		merge 1:1 modelable_entity_id using `map', assert(3) keep(3) keepusing(grouping) nogen
		levelsof grouping, local(groupings)
		foreach group of local groupings {
			di "`group'"
			levelsof modelable_entity_id if grouping == "`group'" & strmatch(modelable_entity_name, "*countries*"), local(parent_me) c
			di "parent `parent_me'"
			levelsof modelable_entity_id if grouping == "`group'" & strmatch(modelable_entity_name, "Symptomatic*"), local(limit_me) c
			di "limit `limit_me'"
			levelsof model_version_id if grouping == "`group'" & strmatch(modelable_entity_name, "*countries*"), local(model) c
			!qsub -pe multi_slot 4 -l mem_free=8g -P "proj_custom_models" -N "`group'_country_exclusions" "`prog_dir'/_shellstata13.sh" "`username'" "`prog_dir'/01_country_limit.do" "`prog_dir' `tmp_dir' `parent_me' `limit_me' `model'"
		}
	}
	
// ****************************************************************************
// Modify draws to contain proportion of cases with heavy infection/cerebral?
	if `heavy_infection_cerebral' == 1 {
		clear
		gen group = . 
		tempfile props
		save `props', replace
		clear
		gen child_id = . 
		tempfile me_list
		save `me_list', replace
		insheet using "`prog_dir'/fbt_high_intensity_infection_proportions.csv", comma names clear
		egen group = group(age_group_id sex_id grouping)
		preserve
			keep age_group_id sex_id grouping group
			tempfile tag
			save `tag', replace
		restore
		keep group mean lower upper
		levelsof group, local(gs)
		foreach g of local gs {
			preserve
				levelsof mean if group == `g', local(M) c
				levelsof lower if group == `g', local(L) c
				levelsof upper if group == `g', local(U) c
				local SE = (`U'-`L')/(2*1.96)
				local N = `M'*(1-`M')/`SE'^2
				local a = `M'*`N'
				local b = (1-`M')*`N'
				clear
				set obs 1000
				gen prop_ = rbeta(`a',`b')
				gen num = _n-1
				gen group = `g'
				append using `props'
				save `props', replace
			restore
		}
		use `props', clear
		merge m:1 group using `tag', assert(3) nogen
		drop group
		** Make draws by sex_id
		reshape wide prop_, i(num age_group_id grouping) j(sex_id)
		replace prop_1 = prop_3 if prop_1 == . & prop_3 != .
		replace prop_2 = prop_3 if prop_2 == . & prop_3 != .
		drop prop_3
		reshape long prop_, i(num age_group_id grouping) j(sex_id)
		** Make age draws
		reshape wide prop_, i(num sex_id grouping) j(age_group_id)
		foreach af of numlist 2(1)21 27 30(1)33 164 {
			capture gen prop_`af' = .
		}
		foreach a in 3 4 5 6 164 {
			replace prop_`a' = prop_2 if prop_`a' == . & prop_2 != .
		}
		foreach ag of numlist 7(2)17 {
			local mid = `ag'+1
			replace prop_`mid' = prop_`ag' if prop_`mid' == . & prop_`ag' != .
		}
		foreach a of numlist 18(1)21 30(1)33 {
			replace prop_`a' = prop_17 if prop_`a' == . & prop_17 != .
		}
		foreach a of numlist 2(1)21 27 30(1)33 164 {
			replace prop_`a' = prop_22 if prop_`a' == . & prop_22 != .
		}
		reshape long prop_, i(num sex_id grouping) j(age_group_id)
		reshape wide prop_, i(age_group_id sex_id grouping) j(num)
		replace grouping = "intestinal fluke" if grouping == "fluke"
		levelsof grouping, local(grouping_names)
		foreach g_name of local grouping_names {
			preserve
				** Heavy
				if "`g_name'" != "cerebral" {
					odbc load, exec("SELECT modelable_entity_id, modelable_entity_name, cause_id, model_version_id FROM epi.model_version JOIN epi.modelable_entity USING (modelable_entity_id) JOIN epi.modelable_entity_cause USING (modelable_entity_id) WHERE is_best = 1 AND cause_id = 364 AND modelable_entity_name LIKE 'Heavy `g_name'%'") `epi_str' clear
				}
				else if "`g_name'" == "cerebral" {
					odbc load, exec("SELECT modelable_entity_id, modelable_entity_name, cause_id, model_version_id FROM epi.model_version JOIN epi.modelable_entity USING (modelable_entity_id) JOIN epi.modelable_entity_cause USING (modelable_entity_id) WHERE is_best = 1 AND cause_id = 364 AND modelable_entity_name LIKE 'Cerebral paragonimiasis'") `epi_str' clear
				}
				levelsof modelable_entity_id, local(id) c
				capture mkdir "`tmp_dir'/`id'"
				capture mkdir "`tmp_dir'/`id'/01_child_draws"
				** Asymp
				if "`g_name'" != "cerebral" {
					odbc load, exec("SELECT modelable_entity_id, modelable_entity_name, cause_id, model_version_id FROM epi.model_version JOIN epi.modelable_entity USING (modelable_entity_id) JOIN epi.modelable_entity_cause USING (modelable_entity_id) WHERE is_best = 1 AND cause_id = 364 AND modelable_entity_name LIKE 'Asymptomatic `g_name'%'") `epi_str' clear
				}
				else if "`g_name'" == "cerebral" {
					odbc load, exec("SELECT modelable_entity_id, modelable_entity_name, cause_id, model_version_id FROM epi.model_version JOIN epi.modelable_entity USING (modelable_entity_id) JOIN epi.modelable_entity_cause USING (modelable_entity_id) WHERE is_best = 1 AND cause_id = 364 AND modelable_entity_name LIKE 'Asymptomatic paragonimiasis%'") `epi_str' clear
				}
				levelsof modelable_entity_id, local(asymp_id) c
				capture mkdir "`tmp_dir'/`asymp_id'"
				capture mkdir "`tmp_dir'/`asymp_id'/01_child_draws"
				** Parent
				if "`g_name'" != "cerebral" {
					odbc load, exec("SELECT modelable_entity_id AS parent_id, modelable_entity_name AS name, model_version_id AS parent_model FROM epi.model_version JOIN epi.modelable_entity USING (modelable_entity_id) JOIN epi.modelable_entity_cause USING (modelable_entity_id) WHERE is_best = 1 AND cause_id = 364 AND modelable_entity_name LIKE 'Symptomatic %`g_name'%'") `epi_str' clear
				}
				else if "`g_name'" == "cerebral" {
					odbc load, exec("SELECT modelable_entity_id AS parent_id, modelable_entity_name AS name, model_version_id AS parent_model FROM epi.model_version JOIN epi.modelable_entity USING (modelable_entity_id) JOIN epi.modelable_entity_cause USING (modelable_entity_id) WHERE is_best = 1 AND cause_id = 364 AND modelable_entity_name LIKE 'Symptomatic respiratory paragonimiasis%'") `epi_str' clear
				}
				gen child_id = `id'
				gen asymp_id = `asymp_id'
				append using `me_list'
				save `me_list', replace
			restore, preserve
				keep if grouping == "`g_name'"
				drop grouping
				saveold "`tmp_dir'/`id'/high_intensity_proportions.dta", replace
			restore
		}
		use `me_list', replace
		order child_id asymp_id
		saveold "`tmp_dir'/me_list.dta", replace
		sleep 5000
		foreach location of local locations {
			!qsub -pe multi_slot 4 -l mem_free=8g -P "proj_custom_models" -N "Heavy_Infection_and_Cerebral_`location'" -hold_jid "*country_exclusions" "`prog_dir'/_shellstata13.sh" "`username'" "`prog_dir'/02_high_intensity.do" "`prog_dir' `tmp_dir' `location'"
		}
	}

// ****************************************************************************
// Upload?
	if `upload_parent' == 1 {
		insheet using "`prog_dir'/parent_map.csv", comma names clear
		tempfile parent_map
		save `parent_map'
		use `parent_me_list', clear
		merge 1:1 modelable_entity_id using `parent_map', assert(3) keep(3) keepusing(grouping) nogen
		levelsof grouping, local(fbt_groups)
		foreach fbt_group of local fbt_groups {
			quietly {
				noisily di "Uploading parent `fbt_group'..."
				levelsof modelable_entity_id if grouping == "`fbt_group'" & strmatch(modelable_entity_name, "Symptomatic*"), local(parent_upload) c
				levelsof model_version_id if grouping == "`fbt_group'" & strmatch(modelable_entity_name, "Symptomatic*"), local(model) c
				preserve
					save_results, modelable_entity_id(`parent_upload') metrics("prevalence") description("country limit applied to model `model'") in_dir("`tmp_dir'/`parent_upload'/01_country_limit") move("yes") mark_best("yes")
				restore
				noisily di "UPLOADED -> " c(current_time)
			}
		}
	}
	if `upload_child' == 1 {
		use "`tmp_dir'/me_list.dta", clear
		levelsof child_id, local(upload_ids)
		foreach me_upload of local upload_ids {
			preserve
				quietly {
					levelsof parent_model if child_id == `me_upload', local(parent_id) c
					noisily di "ID: `me_upload'..."
					save_results, modelable_entity_id(`me_upload') metrics("prevalence") description("high intensity proportion split from model `parent_id'") in_dir("`tmp_dir'/`me_upload'/01_child_draws") move("yes") mark_best("yes")
					noisily di "UPLOADED -> " c(current_time)				
				}
			restore
		}
		levelsof asymp_id, local(upload_ids)
		foreach me_upload of local upload_ids {
			preserve
				quietly {
					levelsof parent_model if asymp_id == `me_upload', local(parent_id) c
					noisily di "ID: `me_upload'..."
					save_results, modelable_entity_id(`me_upload') metrics("prevalence") description("asymptomatic remainder from model `parent_id'") in_dir("`tmp_dir'/`me_upload'/01_child_draws") move("yes") mark_best("yes")
					noisily di "UPLOADED -> " c(current_time)				
				}
			restore
		}
	}
	
// ****************************************************************************
// Clear draws?
	if `sweep' == 1 {
		!rm -rf "`tmp_dir'"
	}
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
