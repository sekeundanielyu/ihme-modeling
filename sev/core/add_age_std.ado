cap program drop add_age_std
program define add_age_std, rclass

    run "$functions_dir/create_connection_string.ado"
    create_connection_string, database(shared)
    local con = r(conn_string)
    
    preserve
    local query = "select age_group_id, age_group_weight_value as weight from shared.age_group_weight where gbd_round_id = 3" 
    odbc load, exec("`query'") `con' clear
    tempfile age_weights
    save `age_weights'
    restore
    
    merge m:1 age_group_id using `age_weights', assert(2 3) keep(3) nogen
    bysort risk_id year_id location_id sex_id: egen wt_scaled = pc(weight), prop // rescale to 1
    replace age_group_id = 27
    forvalues i = 0/999 {
        qui replace sev_`i' = sev_`i' * wt_scaled
    }

    fastcollapse sev* if age_group_id == 27, type(sum) by(sex_id age_group_id location_id risk_id year_id)
    keep if age_group_id == 27

    local f = "$tmp_dir/asr_results_$risk_id.dta"
    save `f', replace
    return local asr_file_path `f'
end
// END
