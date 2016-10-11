
//sdg
// get locations needed for the sdg paper so i can merge this in the uhc indicator R code

run "J:\WORK\10_gbd\00_library\functions\get_outputs.ado"
run "J:\WORK\10_gbd\00_library\functions\get_ids.ado"

get_ids, table(location) clear 


quiet run "J:/WORK/10_gbd/00_library/functions/create_connection_string.ado"

create_connection_string, database(gbd) server(modeling-gbd-db)
    local gbd_str = r(conn_string)
    create_connection_string, database(epi) server(modeling-epi-db)
    local epi_str = r(conn_string)

    odbc load, exec("SELECT * FROM shared.location_hierarchy_history WHERE location_set_id =1 AND location_set_version_id = (SELECT location_set_version_id FROM shared.location_set_version WHERE location_set_id = 1 and end_date IS NULL)") `gbd_str' clear
    keep if level == 4 | level==3
    keep location_id location_name location_name_short map_id super_region_name region_name local_id ihme_loc_id
    levelsof location_id, local(countries)
	
	export delimited "H:/sdg-capstone-paper-2015/uhc_code/locations_needed_for_sdg.csv", replace