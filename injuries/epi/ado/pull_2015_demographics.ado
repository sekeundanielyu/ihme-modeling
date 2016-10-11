// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This ado file runs the steps involved in cod/epi custom modeling for a functional group submitted from 00_master.do file; do not make edits here

cap program drop pull_2015_demographics
program define pull_2015_demographics
	version 12
	syntax , [dem_dir(string) pops_dir(string) age_weights_dir(string)]

	if c(os) == "Unix" {
		local prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		local prefix "J:"
	}
	
// Save age weights
if "`age_weights_dir'" != "" {
	use "`prefix'/WORK/02_mortality/04_outputs/02_results/age_weights.dta", clear
	save "`age_weights_dir'/age_weights.dta", replace
	}
	
// Make all demographic globals
clear
	odbc load, exec("SELECT ihme_loc_id, location_name, location_id, location_type FROM shared.location_hierarchy_history WHERE (location_type = 'admin0' OR location_type = 'admin1' OR location_type = 'admin2') AND location_set_version_id = (SELECT location_set_version_id FROM shared.location_set_version WHERE location_set_id = 9 and end_date IS NULL)") dsn(strDSN)
	drop if inlist(ihme_loc_id,"BRA","CHN","GBR","IND")
	drop if inlist(ihme_loc_id,"JPN","KEN","MEX","SAU","SWE","USA","ZAF")
	levelsof ihme_loc_id, local(iso3s)
	global iso3s = "`iso3s'"			
	levelsof location_id, local(loc_ids)
	global loc_ids = "`loc_ids'"
	global years "1990 1995 2000 2005 2010 2013 2015"
	global sexes "1 2"
	if "`dem_dir'" != "" {
		save "`dem_dir'/dem.dta", replace
		}
	
// Save populations
clear
	odbc load, exec("SELECT output_version_id, year_id, location_id, location_hierarchy_history.ihme_loc_id, sex_id, sex, age_group_id, age_group.age_group_name, location_hierarchy_history.location_set_version_id, mean_pop, pop_scaled, mean_env, upper_env, lower_env, output_version.is_best FROM mortality.output LEFT JOIN mortality.output_version using(output_version_id) LEFT JOIN shared.location_hierarchy_history using(location_id) LEFT JOIN shared.age_group using(age_group_id) LEFT JOIN shared.sex using(sex_id) WHERE location_hierarchy_history.location_set_version_id = 39 AND output_version.is_best = 1") dsn(mortality) 
	drop location_set_version_id sex_id is_best
	if "`pops_dir'" != "" {
		save "`pops_dir'/pops.dta", replace
		}
	levelsof age_group_id, local(age_ids)
	global age_ids = "`age_ids'"

end


