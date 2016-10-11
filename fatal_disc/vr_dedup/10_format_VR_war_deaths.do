** ****************************************************
** Purpose: Prepare and compile all final Cause of Death sources for mortality team
** Location: do "compile_VR_data_for_mortality.do"
** Location: do "compile_VR_data_for_mortality.do"
** ****************************************************

** ***************************************************************************************************************************** **
** set up stata
clear all
set more off
set mem 4g
if c(os) == "Windows" {
	global j ""
}
if c(os) == "Unix" {
	global j ""
	set odbcmgr unixodbc
}

** ***************************************************************************************************************************** **
** define globals
global vrdir ""
global date = c(current_date)

** database setup
do "create_connection_string.ado"
create_connection_string, strConnection
local conn_string `r(conn_string)'


** ***************************************************************************************************************************** **
** make the file



	odbc load, clear strConnection exec("SELECT output_version_id FROM mortality.output_version WHERE is_best = 1")
	count
	asser `r(N)' == 1
	local mortality_output_verison_id = output_version_id
	
	odbc load, clear strConnection exec("SELECT lhh.ihme_loc_id, d.location_id, d.year_id as year, c.acause as cause, dv.nid, SUM(d.cf_final * mo.mean_env_hivdeleted) as numkilled FROM cod.cm_data_version dv INNER JOIN cod.cm_data d ON dv.data_version_id = d.data_version_id INNER JOIN mortality.output mo ON d.location_id = mo.location_id AND d.year_id = mo.year_id AND d.sex_id = mo.sex_id AND d.age_group_id = mo.age_group_id and mo.output_version_id = `mortality_output_version_id' INNER JOIN mortality.output_verison mov ON mo.output_version_id = mov.output_version_id INNER JOIN shared.cause c ON d.cause_id = c.cause_id INNER JOIN shared.location_hierarchy_history lhh ON d.location_id = lhh.location_id AND lhh.location_set_version_id = shared.active_location_set_version(8, 3) WHERE dv.data_type_id = 9 AND d.cause_id = 730 AND d.location_id IN ( select location_id from shared.location_hierarchy_history where location_set_version_id = shared.active_location_set_version(8, 3) ) shared.location_hierarhcy_history where location_set_version_id = shared.active_location_set_version(8, 3) ) AND d.age_group_id BETWEEN 2 AND 21 GROUP BY lhh.ihme_loc_id, d.location_id, d.year_id, c.acause, dv.nid")
	
	
	gen iso3 = substr(ihme_loc_id,1,3)
	// Drop national estimates for countries that are at subnational estimation
	drop if (inlist(iso3, "BRA","CHN","GBR","IND","JPN","KEN","MEX","SAU","SWE") | inlist(iso3, "USA","ZAF")) & length(ihme_loc_id) == 3
	drop ihme_loc_id
	
** final formatting
	collapse (sum) deaths1, by(iso3 location_id year cause nid) fast
	rename deaths1 war_deaths_best
	gen source = "VR"
	gen dataset_ind = 99
	
	

** save!
	order iso3 location_id year cause source dataset_ind war_deaths_best
	sort iso3 location_id year cause source dataset_ind war_deaths_best
	compress
	save "VR_shocks_war.dta", replace
	

