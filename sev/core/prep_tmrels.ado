cap program drop prep_tmrels
program define prep_tmrels, rclass
    syntax, rr_file(string) exp_file(string) location_ids(numlist) year_ids(numlist) age_group_ids(numlist)

    // most risks need tmrels generated on the fly, except for nutrition_iron, pufa, and bmd
    // for those, grab draws
    local risks_w_tmrel_draws = "95, 109, 122"
    return local risks_w_tmrel_draws "`risks_w_tmrel_draws'"

    adopath + "$functions_dir"
    run "$experimental_dir/risk_utils/risk_info.ado"


    if !inlist($risk_id, `risks_w_tmrel_draws') {

        // first get risk from risk_id, for use with risk_variables
        if $risk_id == 120 {
            risk_info, risk_id(147) clear
        }
        else {
            risk_info, risk_id($risk_id) clear 
        }
        levelsof risk, local(risk)

        // gen tmrel_mid for risks without tmrel draws
        // also get rr scalar, inv_exp, and min_val
        gen_tmrel_mid `risk' $risk_id

        merge 1:m risk_id using `rr_file', keep(3) nogen
    }

    else {

        //custom code for diet_pufa from Stan
        if $risk_id == 122 {
            get_draws, gbd_id_field(modelable_entity_id) gbd_id(2436) location_ids(`location_ids') ///
                year_ids(`year_ids') sex_ids(1 2) age_group_ids(`age_group_ids') status(best) source(epi) clear
            tempfile PUFA
            save `PUFA', replace
            get_draws, gbd_id_field(modelable_entity_id) gbd_id(2439) location_ids(`location_ids')  ///
                year_ids(`year_ids') sex_ids(1 2) age_group_ids(`age_group_ids') status(best) source(epi) clear
            forvalues i = 0/999 {
                gen shift_`i' = draw_`i' - .07
                drop draw_`i'
            }
            merge 1:1 age_group_id location_id year_id sex_id measure_id using `PUFA', keep(3) nogen
            forvalues i = 0/999 {
                qui replace draw_`i' = .12 - shift_`i' if shift_`i'>=0 & shift_`i'!=.
                rename draw_`i' tmred_mean_`i'
            }
            drop shift*
            gen risk_id = $risk_id
        }

        //custom for iron
        else if $risk_id == 95 {
            clear
            tempfile tmred
            save `tmred', replace emptyok
            local file_list : dir "/ihme/gbd/WORK/05_risk/02_models/02_results/nutrition_iron/tmred/8/" files "tmred_*.csv"
            foreach file of local file_list {
                insheet using "/ihme/gbd/WORK/05_risk/02_models/02_results/nutrition_iron/tmred/8/`file'", clear
                qui append using `tmred'
                save `tmred', replace          
            }
            drop if parameter == "sd"
            gen risk_id = $risk_id
            rename gbd_age_start age_group_id
        }

        //custom for bmd
        else if $risk_id == 109 {
            clear
            insheet using "/ihme/gbd/WORK/05_risk/02_models/02_results/metab_bmd/tmred/4/tmred_G.csv", clear
            drop if parameter == "sd"
            rename sex sex_id
            gen risk_id = $risk_id
            gen age_group_id = .
            replace age_group_id = 11 if gbd_age_start == 30
            replace age_group_id = 12 if gbd_age_start == 35
            replace age_group_id = 13 if gbd_age_start == 40
            replace age_group_id = 14 if gbd_age_start == 45
            replace age_group_id = 15 if gbd_age_start == 50
            replace age_group_id = 16 if gbd_age_start == 55
            replace age_group_id = 17 if gbd_age_start == 60
            replace age_group_id = 18 if gbd_age_start == 65
            replace age_group_id = 19 if gbd_age_start == 70
            replace age_group_id = 20 if gbd_age_start == 75
            replace age_group_id = 21 if gbd_age_start == 80
        }

        ** collapse TMRED acorss year and location
        fastcollapse tmred*, type(mean) by(risk_id sex_id age_group_id)
        fastrowmean tmred*, mean_var_name(tmrel_mid)
        drop tmred*
        merge 1:m risk_id sex_id age_group_id using `rr_file', keep(3) nogen

        ** generate different rr_scalars depending on which risk it is
        // nutrition_iron
        if $risk_id == 95 {
            gen inv_exp=0
            gen rr_scalar=10
            gen min_val=0
        }
        // diet_pufa
        else if $risk_id == 122 {
            gen inv_exp=1
            gen rr_scalar=0.05
            gen min_val=0
        }
        // metab_bmd
        else if $risk_id == 109 {
            gen inv_exp=1
            gen rr_scalar=0.10
            gen min_val=0
        }
    }

    // now add on exposure percentiles
    joinby risk_id sex_id age_group_id using `exp_file'
    
    local f = "$tmp_dir/tm_$risk_id.dta"
    save `f', replace
    return local file_path `f'
end
// END
