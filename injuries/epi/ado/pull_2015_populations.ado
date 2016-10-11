// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Pull current populations estimates from 2015 mortality database.

cap program drop pull_2015_populations
program define pull_2015_populations
	version 12
	syntax , [pops_dir(string)]

	if c(os) == "Unix" {
		local prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		local prefix "J:"
	}

// Load function to create database connection
quiet run "`prefix'/WORK/10_gbd/00_library/functions/create_connection_string.ado"
create_connection_string, server("modeling-mortality-db") database("mortality") 
local conn_string = r(conn_string)

// Pull populations
clear
	odbc load, exec("SELECT output_version_id, year_id, location_id, location_hierarchy_history.ihme_loc_id, sex_id, sex, age_group_id, age_group.age_group_name, location_hierarchy_history.location_set_version_id, mean_pop, pop_scaled, mean_env, upper_env, lower_env, output_version.is_best FROM mortality.output LEFT JOIN mortality.output_version using(output_version_id) LEFT JOIN shared.location_hierarchy_history using(location_id) LEFT JOIN shared.age_group using(age_group_id) LEFT JOIN shared.sex using(sex_id) WHERE location_hierarchy_history.location_set_version_id = 39 AND output_version.is_best = 1") `conn_string' clear
	if "`pops_dir'" != "" {
		save "`pops_dir'/pops.dta", replace
		}

end


