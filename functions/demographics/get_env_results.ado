/*
Purpose:	Get Envelope Results from the most recent run
How To:		get_env_results
Arguments:
			pop_only (T/F): If true, it basically works as a get_populations type of thing. Default is false
			version_id: Numeric, corresponds to the output_version_id of the envelope (1 is gbd2010, 12 is gbd2013, 46 is gbd2015 (for now?)
				If version_id is not specified, it defaults to pulling the best version from the database
*/

cap program drop get_env_results
program define get_env_results
	version 12
	syntax , [type(string)] [pop_only]

// prep stata
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	
	clear
	local get_best = 0
	if "`version_id'" == "" local get_best = 1
	
// Get connection settings
	// Load create_connection_string
	adopath + "strPath" 
	create_connection_string, server(strDB) user(strUser) password(strPass)
	local conn_string = r(conn_string)
	
	// First, get appropriate location_set_version_id
	odbc load, exec("SELECT location_set_version_id FROM shared.location_set_version_active WHERE location_set_id = 21 AND gbd_round_id = 3") `conn_string' clear
	
	local loc_version_id = location_set_version_id[1]
	
	if `get_best' == 1 {
		odbc load, exec("SELECT output_version_id FROM mortality.output_version WHERE is_best = 1") `conn_string' clear
		local version_id = output_version_id[1]
	}
	
	if "`pop_only'" == "" {
		#delimit ;
		local select_command = "SELECT output_version_id, year_id, location_id, location.ihme_loc_id, 
			sex_id, sex, age_group_id, ages.age_group_name, 
			mean_pop, mean_env_whiv, upper_env_whiv, lower_env_whiv,
			mean_env_hivdeleted, upper_env_hivdeleted, lower_env_hivdeleted ";
		#delimit cr
	}
	else {
		#delimit ;
		local select_command = "SELECT output_version_id, year_id, location_id, location.ihme_loc_id, 
			sex_id, sex, age_group_id, ages.age_group_name, 
			mean_pop ";
		#delimit cr
	}
	
	#delimit ;
	local join_command = "FROM (SELECT * FROM mortality.output WHERE output_version_id = `version_id') as output 
			LEFT JOIN (SELECT ihme_loc_id, location_set_version_id, location_id FROM shared.location_hierarchy_history 
				WHERE location_set_version_id = `loc_version_id') as location using(location_id) 
			LEFT JOIN (SELECT * FROM 
					(SELECT age_group_name, age_group_id from shared.age_group 
						INNER JOIN (SELECT DISTINCT age_group_id FROM shared.age_group_set_list 
						WHERE age_group_set_id = 1 OR age_group_set_id = 2 OR age_group_set_id = 5) as age_ids using(age_group_id)) 
					as age_ids2) 
				as ages using(age_group_id) 
			LEFT JOIN shared.sex using(sex_id) ";
	#delimit cr
	

	#delimit ;
	odbc load, exec("`select_command' `join_command'") `conn_string' clear;
	#delimit cr

	
	// end program
	end
	