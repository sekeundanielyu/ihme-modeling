cap program drop add_all_age
program define add_all_age, rclass

    run "$functions_dir/fastcollapse.ado"
    run "$functions_dir/create_connection_string.ado"

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
    restore

    merge m:1 location_id year_id age_group_id sex_id using `envelope', keep(1 3) nogen keepusing(mean_pop)   

    replace age_group_id = 22
    forvalues i = 0/999 {
        qui replace sev_`i' = sev_`i' * mean_pop
    }
    fastcollapse sev* mean_pop if age_group_id == 22, type(sum) by(sex_id age_group_id location_id risk_id year_id)
    forvalues i = 0/999 {
        qui replace sev_`i' = sev_`i' / mean_pop
    }
    keep if age_group_id == 22
    drop mean_pop

    local f = "$tmp_dir/all_age_results_$risk_id.dta"
    save `f', replace
    return local all_age_file_path `f'
end
// END

