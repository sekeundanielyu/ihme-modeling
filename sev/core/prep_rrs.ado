cap program drop prep_rrs
program define prep_rrs, rclass
    syntax, location_ids(numlist) age_group_ids(numlist) year_ids(numlist)

    adopath + "$functions_dir"
    create_connection_string
    local con = r(conn_string)

    // temp: read in only a few locations for speed's sake
    if $testing {
        local location_ids = "6 4771"
    }

    // for backpain and hearing, we need to grab morbidity rrs instead of mortality
    global yld_risks = "130, 132"

    ** pull RRs **
    //read in flat files of RR draws for air_pm, air_hap, drugs_alcohol, and bmd
    //calculate RR for drugs_illicit_suicide with custom code 
    //pull in RR flat file of IQ shifts for envir_lead_blood
    if inlist($risk_id,86,87,102,109,140,130) {

        if $risk_id == 140 {
            local n = 0
            foreach me in 1977 1978 1976 {

                clear
                set obs 1
                gen cause_id = 719 in 1
                if `me' == 1977 {
                    gen modelable_entity_id = `me'
                    gen sd = ((ln(16.94)) - (ln(3.93))) / (2*invnormal(.975))
                    forvalues i = 0/999 {
                        gen double rr_`i' = exp(rnormal(ln(8.16), sd))
                    }
                }
                if `me' == 1978 {
                    gen modelable_entity_id = `me'
                    gen sd = ((ln(16.94)) - (ln(3.93))) / (2*invnormal(.975))
                    forvalues i = 0/999 {
                        gen double rr_`i' = exp(rnormal(ln(8.16), sd))
                    }
                }
                if `me' == 1976 {
                    gen modelable_entity_id = `me'
                    gen sd = ((ln(10.53)) - (ln(4.49))) / (2*invnormal(.975))
                    forvalues i = 0/999 {
                        gen double rr_`i' = exp(rnormal(ln(6.85), sd))
                    }
                }

                replace cause_id = 718
                gen parameter = "cat1"

                gen n = 1
                tempfile r
                save `r', replace

                clear
                set obs 50
                gen age_group_id = _n
                keep if age_group_id<=21
                drop if age_group_id==.
                gen n = 1
                joinby n using `r'
                keep cause_id age_group_id modelable_entity_id parameter rr*

                expand 2, gen(dup)
                forvalues i = 0/999 {
                    replace rr_`i' = 1 if dup==1
                }
                replace parameter="cat2" if dup==1 
                drop dup
                gen mortality=1
                gen morbidity=1

                tempfile rr
                save `rr', replace

                local n = `n' + 1
                tempfile `n'
                save ``n'', replace

            } // end me loop

            ** append PAFs and calculate joint for all drug use
            clear
            forvalues i = 1/`n' {
                append using ``i''
            }

            gen risk_id = $risk_id
            keep if mortality == 1
            gen sex_id = 1
            expand 2, gen(dup)
            replace sex_id = 2 if dup == 1
            drop dup
            fastcollapse rr*, type(mean) by(risk_id sex_id age_group_id cause_id parameter)
        }

        //air pm
        if $risk_id == 86 {
            insheet using "/home/j/temp/strUser/sev/rrmax/air_pm_rrmax.csv", clear
            gen sex_id = 1
            expand = 2, generate(expanded)
            replace sex_id = 2 if expanded
            drop expanded
        }

        //air hap
        if $risk_id == 87 {
            insheet using "/home/j/temp/strUser/sev/rrmax/air_hap_rrmax.csv", clear
            gen sex_id = 1
            expand = 2, generate(expanded)
            replace sex_id = 2 if expanded
            drop expanded
            rename rr* draw*
        }

        //alcohol
        if $risk_id == 102 {
            insheet using "/home/j/temp/strUser/sev/rrmax/alcohol_rrmax.csv", clear
            forvalues i = 0/999 {
                gen draw_`i' = mean
            }
            drop mean
        }

        if $risk_id == 130 {
            insheet using "/home/j/temp/strUser/sev/rrmax/occ_hearing_rrmax.csv", clear
            forvalues i = 0/999 {
                gen draw_`i' = mean
            }
            drop mean
        }

        //BMD
        if $risk_id == 109 {
            insheet using "/share/gbd/WORK/05_risk/02_models/02_results/metab_bmd/rr/3/rr_G.csv", clear
            drop risk mor* parameter year *upper *lower *mean *end
            rename rr_* draw_*
            rename sex sex_id
            rename gbd_age_start age 
            gen cause_id = 9999 if acause == "hip"
            replace cause_id = 8888 if acause == "non-hip"
        }

        //format 
        if inlist($risk_id,86,87,102,109,130) {
            preserve
                //pull cause_id and age_group_id from database to merge on
                # delim ;
                odbc load, exec("
                    SELECT cause_id, acause 
                    FROM shared.cause_hierarchy_history 
                    WHERE cause_set_version_id = 97") `con' clear ;
                # delim cr
                tempfile cause_merge
                save `cause_merge', replace

                # delim ;
                odbc load, exec("
                    SELECT age_group_id, age_group_years_start as age 
                    FROM shared.age_group 
                    WHERE age_group_id between 2 and 21") `con' clear ;
                # delim cr
                tempfile age_merge
                replace age = 3 if age_group_id == 3
                replace age = 4 if age_group_id == 4
                save `age_merge', replace
            restore

            rename draw_* rr_*
            gen risk_id = $risk_id

            if inlist($risk_id,102,109) {
                merge m:1 age using `age_merge', keep(3) assert(2 3) nogen
            }
            if inlist($risk_id,86,87) {
                merge m:1 acause using `cause_merge', keep(3) assert(2 3) nogen                
            }
            if inlist($risk_id,102,130,86,87){
                drop acause
            }
            else {
                drop acause age
            }
        }

    }

    //for all other risks, use get_draws
    else {
        
        ** read in all RR draws for the given risk
        if $risk_id == 134 { //for CSA read in both male and female
            get_draws, ///
                source(risk) gbd_id_field(risk_id risk_id) gbd_id(244 245) year_ids(`year_ids') ///
                location_ids(`location_ids') age_group_ids(`age_group_ids') kwargs(draw_type:rr) clear
        }
        else if $risk_id == 99 { //for smoking read in SIR and prevlelance
            get_draws, ///
                source(risk) gbd_id_field(risk_id risk_id) gbd_id(165 166) year_ids(`year_ids')  ///
                location_ids(`location_ids') age_group_ids(`age_group_ids') kwargs(draw_type:rr) clear
        }
        else if $risk_id == 120 { //for calcium read diet low in calcium
            get_draws, ///
                source(risk) gbd_id_field(risk_id) gbd_id(147) year_ids(`year_ids')  ///
                location_ids(`location_ids') age_group_ids(`age_group_ids') kwargs(draw_type:rr) clear
        }
        else {
            get_draws, ///
                source(risk) gbd_id_field(risk_id) gbd_id($risk_id) location_ids(`location_ids') ///
                age_group_ids(`age_group_ids') kwargs(draw_type:rr)  year_ids(`year_ids') clear
        }
        gen risk_id = $risk_id
        drop model_version_id modelable_entity_id
        
        // for backpain and hearing, grab morbidity rrs instead of mortality
        if inlist($risk_id, $yld_risks) {
            keep if morbidity == 1
        }
        else {
            keep if mortality == 1
        }

    }

    ** find max and average across time and space
    if $continuous {
             ** for continuous risks we average across years and locations 
             ** before taking rowise mean. Mean_rr is used in calc_scalars
             fastcollapse rr*, type(mean) by(risk_id sex_id age_group_id cause_id)
    }
    else {
        if !inlist($risk_id,86,87,102,109,130) {
            ** for categorical risks, we need to find the category (usually cat1)
            ** that contains the highest RR draw. We need to do this by outcome, age, and sex.
            ** Another way to phrase this is we're finding the max rr value across space and time
            ** We keep the rr draw columns (unlike continuous)

            ** per unique values of key, we want only rows belonging to the category that has the highest rr draw value
            ** we'll do this by merging on a filtering dataset, that just contains key and parameter (aka category)
            egen key = group(cause_id age_group_id sex_id) 
            preserve
            egen rowwise_max = rowmax(rr*) // top rr draw value per row
            bysort key: egen double max_per_key = max(rowwise_max) // by a/s/c, max rr draw value
            gen top_category = (max_per_key == rowwise_max) // boolean that's 1 if a row contains the top rr draw value in a/s/c
            keep if top_category 
            contract key parameter  // create a filtering dataset that only contains the top category per a/s/c
            drop _freq
            // A possible edge case is if two categories in a a/s/c group both contain the same max draw value
            // We can check for that by asserting there's only 1 category per key
            isid key parameter
            tempfile top_category_per_key
            save `top_category_per_key'
            restore
            // now that we know, for each a/s/c, which category to keep, we can filter using merge
            merge m:1 key parameter using `top_category_per_key',  keep(3) nogen
            drop key
        }

        // same as continuous risks, average rr over time and space
        fastcollapse rr*, type(mean) by(risk_id sex_id age_group_id cause_id)

    }

    local f = "$tmp_dir/rr_$risk_id.dta"
    save `f', replace
    return local file_path `f'
end
// END
