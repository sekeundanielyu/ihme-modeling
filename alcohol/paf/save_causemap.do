

clear all
set more off

** Set directories
	if c(os) == "Windows" {
		global j "J:"
		global prefix "J:"
	}
	if c(os) == "Unix" {
		global j "/home/j"
		global prefix "/home/j"
		set odbcmgr unixodbc
	}


run "$j/WORK/10_gbd/00_library/functions/create_connection_string.ado"

create_connection_string
local conn_string = r(conn_string)


// now we just return the id column and the col_name column (ie, age_group_id and age_group_name)
# delim ;
local query = "
	SELECT
	cause_id,
	acause
	FROM
	cause
	WHERE
	last_updated_action != 'DELETE'
";
odbc load, exec(`"`query'"') `conn_string' clear;
# delim cr

**  "
** save file that maps acause to cause_id to use Stan's mapping to lowest level causes
saveold "$j/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/acause_causeid_map.dta", replace


