cap program drop add_both_sex
program define add_both_sex, rclass

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
    replace sex_id = 3
    forvalues i = 0/999 {
        qui replace sev_`i' = sev_`i' * mean_pop
    }
    fastcollapse sev* mean_pop if sex_id == 3, type(sum) by(sex_id age_group_id location_id risk_id year_id)
    forvalues i = 0/999 {
        qui replace sev_`i' = sev_`i' / mean_pop
    }
    keep if sex_id == 3
    drop mean_pop

    local f = "$tmp_dir/both_sex_results_$risk_id.dta"
    save `f', replace
    return local both_sex_file_path `f'
end
// END

