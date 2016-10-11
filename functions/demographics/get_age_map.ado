/*
Purpose:	Grab all possible GBD age mappings
How To:		get_age_map // will get you GBD 2015 age groups
Options:  type: mort, gbd, all 
                mort: Mortality standard age groups (plus all ages)
				lifetable: Pulls lifetable standard age_group_ids
                gbd: Standard GBD age groups
                all: Pulls all age groups in shared.age_group
*/

cap program drop get_age_map
program define get_age_map
	version 12
	syntax , [type(string)] 

// prep stata
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	
	clear
	
	if "`type'" == "" local type = "mort"
	

// Grab age_group_id identifiers
	adopath + "strPath" // Load create_connection_string
	create_connection_string
	local conn_string = r(conn_string)
	
	if "`type'" == "mort" {
		// Select age group names etc. for Mortality 2015 age groups

		clear
		set obs 1
		gen age_group_set_id = 5
		gen age_group_id = 22
		gen age_group_name = "All Ages"
		gen age_group_name_short = "All Ages"
		gen age_group_alternative_name = "All Ages"
		gen age_group_years_start = 0
		gen age_group_years_end = 125
		gen is_aggregate = 1
		tempfile tempage
		save `tempage'

		#delimit ;
		odbc load, exec("
		SELECT age_group_set_id, age_group_id, age_group_name, age_group_name_short, age_group_alternative_name, is_aggregate, age_group_years_start, age_group_years_end
		FROM shared.age_group_set_list 
		JOIN shared.age_group_set using(age_group_set_id) 
		JOIN shared.age_group using(age_group_id) 
		WHERE age_group_set_id = 5
		") `conn_string' clear;
		#delimit cr
		append using `tempage'
	}
	if "`type'" == "lifetable" {
		#delimit ;
		odbc load, exec("
		SELECT age_group_id, age_group_name, age_group_name_short, age_group_alternative_name, is_aggregate, age_group_years_start, age_group_years_end
		FROM shared.age_group
		WHERE (age_group_id >= 5 AND age_group_id <= 20) OR age_group_id = 28 OR (age_group_id >= 30 AND age_group_id <= 33) 
		OR (age_group_id >= 44 AND age_group_id <= 45) OR age_group_id = 148
		") `conn_string' clear;
		#delimit cr
		gen age_group_set_id = . // To match with the mort and GBD variables
	}
	if "`type'" == "gbd" {
		// Select age group names etc. for GBD 2015 age groups
		#delimit ;
		odbc load, exec("
		SELECT age_group_set_id, age_group_id, age_group_name, age_group_name_short, age_group_alternative_name, is_aggregate, age_group_years_start, age_group_years_end
		FROM shared.age_group_set_list 
		JOIN shared.age_group_set using(age_group_set_id) 
		JOIN shared.age_group using(age_group_id) 
		WHERE age_group_set_id = 1
		") `conn_string' clear;
		#delimit cr
	}
	if "`type'" == "all" {
		#delimit ;
		odbc load, exec("
		SELECT age_group_id, age_group_name, age_group_name_short, age_group_alternative_name, is_aggregate, age_group_years_start, age_group_years_end
		FROM shared.age_group
		") `conn_string' clear;
		#delimit cr
		gen age_group_set_id = . // To match with the mort and GBD variables
	}	
	
	replace age_group_name_short = "enn" if age_group_name == "Early Neonatal"
	replace age_group_name_short = "lnn" if age_group_name == "Late Neonatal"
	replace age_group_name_short = "pnn" if age_group_name == "Post Neonatal"
	replace age_group_name_short = "nn" if age_group_name == "Neonatal"
	replace age_group_name_short = "0" if age_group_name == "<1 year"
	replace age_group_name_short = "100" if age_group_name == "100 to 104"
	replace age_group_name_short = "105" if age_group_name == "105 to 109"
	
	sort age_group_id
		
	// end program
	end
	