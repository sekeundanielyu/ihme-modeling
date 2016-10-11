// Put injury cause_ids and me_ids into globals. Contingent on file with me_ and cause_ names in file in injuries repo.

capture program drop get_injury_ids
program define get_injury_ids
	version 13
	syntax , repo(string)

// Define J drive for cluster (UNIX) and Windows (Windows)
				if c(os) == "Unix" {
					global prefix "/home/j"
					global hprefix "/snfs2/HOME/strUser"
					set odbcmgr unixodbc
				}
				else if c(os) == "Windows" {
					global prefix "J:"
					global hprefix "H:"
				}

quietly {
// Master function library
adopath + "$prefix/WORK/10_gbd/00_library/functions"

// ME_IDS
insheet using "`repo'/data_modelable_entity_names.csv", comma names clear
levelsof modelable_entity_name_raw, local(me_names)

// Get me_ids of injuries using modelable entity names
quiet run "$prefix/WORK/10_gbd/00_library/functions/create_connection_string.ado"
create_connection_string, strConnection
local conn_string = r(conn_string)
odbc load, exec("SELECT modelable_entity_id, modelable_entity_name FROM epi.modelable_entity") `conn_string' clear
gen keep = 0
foreach me_name of local me_names {
	replace keep = 1 if modelable_entity_name == "`me_name'"
}
keep if keep == 1
levelsof modelable_entity_id, local(me_ids)
global me_ids = "`me_ids'"

// CAUSE_IDS
insheet using "`repo'/ecode_names.csv", comma names clear
levelsof e_code, local(ecodes)

// Get cause_ids of injuries using modelable entity names
quiet run "$prefix/WORK/10_gbd/00_library/functions/create_connection_string.ado"
create_connection_string, strConnection
local conn_string = r(conn_string)
odbc load, exec("SELECT cause_id, cause_name, acause FROM shared.cause") `conn_string' clear
gen keep = 0
foreach ecode of local ecodes {
	replace keep = 1 if acause == "`ecode'"
}
keep if keep == 1
levelsof cause_id, local(cause_ids)
global cause_ids = "`cause_ids'"
}

end

