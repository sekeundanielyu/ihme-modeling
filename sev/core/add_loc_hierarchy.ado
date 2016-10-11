cap program drop add_loc_hierarchy
program define add_loc_hierarchy, rclass
    syntax, location_ids(numlist) year_ids(numlist)

    run "$functions_dir/fastcollapse.ado"
    run "$functions_dir/create_connection_string.ado"
    
    create_connection_string, database(shared)
    local con = r(conn_string)
    create_connection_string, database(cod)
    local cod = r(conn_string)

    preserve

        // Load pop and envelope
        # delim ;
        odbc load, exec("
            SELECT year_id,location_id,sex_id,age_group_id,mean_pop 
            FROM mortality.output JOIN mortality.output_version USING (output_version_id) 
            WHERE is_best=1") `cod' clear ;
        # delim cr
        tempfile envelope
        save `envelope', replace

        // Load location levels
         # delim ;
        odbc load, exec("
            SELECT lhh.level,lhh.location_id,lhh.location_name,lhh.parent_id,lhh.location_type,
            lhh.most_detailed,(SELECT GROUP_CONCAT(location_id) 
                FROM shared.location_hierarchy_history 
                WHERE location_set_version_id = 75 and parent_id = lhh.location_id) AS child_ 
            FROM shared.location_hierarchy_history lhh 
            WHERE lhh.location_set_version_id = 75 
            GROUP BY lhh.location_id, lhh.location_name, lhh.parent_id, lhh.location_type, 
            lhh.most_detailed ORDER BY lhh.sort_order") `con' clear ;
        # delim cr
        keep if child_!=""
        qui summ level
        local max_loc `r(max)'
        tempfile loc_level
        save `loc_level', replace

        // Load location levels for SDI
        # delim ;
        odbc load, exec("
            SELECT lhh.level,lhh.location_id,lhh.location_name,lhh.parent_id,lhh.location_type,
            lhh.most_detailed,(SELECT GROUP_CONCAT(location_id) 
                FROM shared.location_hierarchy_history WHERE location_set_version_id = 91 
                and parent_id = lhh.location_id) AS child_ 
            FROM shared.location_hierarchy_history lhh 
            WHERE lhh.location_set_version_id = 91 GROUP BY lhh.location_id, lhh.location_name, 
            lhh.parent_id, lhh.location_type, lhh.most_detailed 
            ORDER BY lhh.sort_order") `con' clear ;
        # delim cr
        keep if child_!=""
        qui summ level
        local max_sdi `r(max)'
        tempfile sdi_level
        save `sdi_level', replace

    restore
    merge m:1 location_id year_id age_group_id sex_id using `envelope', keep(1 3) nogen keepusing(mean_pop)
    tempfile data
    save `data', replace

    //aggregate up normal location hierarchy
    foreach x of numlist `max_loc'(-1)0 {
        use if level==`x' using `loc_level', clear
        count
        if `r(N)'==0 continue
        forvalues i=1/`r(N)' {
            use if level==`x' using `loc_level', clear
            levelsof child_ in `i', local(keep) c
            levelsof location_id in `i', local(parent) c
            use if inlist(location_id,`keep') using `data', clear
            count
            if `r(N)'==0 continue 
            bysort year_id age_group_id sex_id risk_id: egen weight = pc(mean_pop), prop
                foreach sev of varlist sev* {
                    qui replace `sev' = `sev' * weight
                }
            fastcollapse sev*, type(sum) by(year_id age_group_id sex_id risk_id)
            gen location_id=`parent'
            ** merge on pop
            merge m:1 location_id year_id age_group_id sex_id using `envelope', keep(1 3) nogen keepusing(mean_pop)
            append using `data'
            save `data', replace
        }
    }
    drop mean_pop 

    if $testing == 0 {
        merge m:1 location_id year_id age_group_id sex_id using `envelope', keep(1 3) nogen keepusing(mean_pop)
        save `data', replace
        foreach x of numlist `max_sdi'(-1)0 {
            use if level==`x' using `sdi_level', clear
            count
            if `r(N)'==0 continue
            forvalues i=1/`r(N)' {
                use if level==`x' using `sdi_level', clear
                levelsof child_ in `i', local(keep) c
                levelsof location_id in `i', local(parent) c
                use if inlist(location_id,`keep') using `data', clear
                count
                if `r(N)'==0 continue 
                bysort year_id age_group_id sex_id risk_id: egen weight = pc(mean_pop), prop
                    foreach sev of varlist sev* {
                        qui replace `sev' = `sev' * weight
                    }
                fastcollapse sev*, type(sum) by(year_id age_group_id sex_id risk_id)
                gen location_id=`parent'
                ** merge on pop
                merge m:1 location_id year_id age_group_id sex_id using `envelope', keep(1 3) nogen keepusing(mean_pop)
                append using `data'
                save `data', replace
            }
        }
        drop mean_pop 
    }
    

    local f = "$tmp_dir/loc_results_$risk_id.dta"
    save `f', replace
    return local loc_file_path `f'
end
// END

