cap program drop get_demographic_variables
program define get_demographic_variables, rclass

    /*
    We need GBD estimation years and the location_ids the current dalynator used.
    These are used when grabbing draw files.
    */
    
    run "$functions_dir/get_demographics.ado"
    ** Going to query gbd outputs db for best dalynator location_set
    run "$functions_dir/create_connection_string.ado"
    create_connection_string, server(modeling-gbd-db) database(gbd)
    local con = r(conn_string)
    create_connection_string  
    local cod_con = r(conn_string)

    // get location_set_version_id for current best dalynator for gbd 2015
    #delim ;
    local query = "
            SELECT
            location_set_version_id
            FROM
            gbd.compare_version
            JOIN
            gbd.compare_version_output USING (compare_version_id)
            JOIN
            gbd.gbd_process_version_set_version USING (gbd_process_version_id)
            WHERE
            gbd_round_id = 3
            AND
            compare_version_status_id = 1
            GROUP BY location_set_version_id
    ";
    #delim cr
    odbc load, exec("`query'") `con' clear

    ** Should only have 1 location set version per dalynator
    count
    assert r(N) == 1
    levelsof location_set_version_id, local(lsvid) c
    
    ** use lsvid to grab loc_ids
    # delim ;
    local query = "
        call shared.view_location_hierarchy_history(`lsvid')
    ";
    # delim cr
    odbc load, exec("`query'") `cod_con' clear
    levelsof location_id, local(loc_ids) c

    ** Return gbd 2015 estimation years
    get_demographics, gbd_team(epi)
    local yids = r(year_ids)

    // temp for testing
    if $testing {
        return local location_ids 101 105 208
    }
    else {
        return local location_ids `loc_ids'
    }

    return local year_ids `yids'
    return local age_group_ids 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21
    
end
// END OF FILE
