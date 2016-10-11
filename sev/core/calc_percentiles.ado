cap program drop calc_percentiles
program define calc_percentiles, rclass
    args prepped_exposures
    /*
    For categorical risks, rr_max is the relative risk found at the highest level of exposure.
    For continuous risks, we simulate individuals  from the exposure distribution and find the
        99th percentile of that -- ie, the worst possible BMI, SBP, etc.

    -- do the math and create 1th and 99th percentile columns --
    expand pop_scaled to weight each row by population for that row
    create sample column
    gen mu and sig columns--log normal distribution
    for each risk,  simulate individuals from the exposure distribution and 
        compute 1th and 99th percentile of sample for that risk and stick them in locals
    go back to 'orig' tempfile
    create max and min percentile cols and fill them in using locals from above
    save as tempfile exp
    */

    run "$experimental_dir/risk_utils/risk_info.ado"

    expand pop_scaled 
    gen sample = .
    // https://en.wikipedia.org/wiki/Log-normal_distribution
    gen mu = ln(median_expmean/(sqrt(1+median_expsd^2/median_expmean^2)))
    gen sig = sqrt(ln(1+median_expsd^2/median_expmean^2))

    ** create locals for 99th and 1st percentile of sample column
    replace sample = exp(mu + sig * invnorm(uniform()))
    
    _pctile sample, p(1 99)
    local min_1 = r(r1)
    di "min_1:`min_1'" 
    local max_99 = r(r2)
    di "max_99:`max_99'"

    ** read in max min values generated in PAF calculation if present
    risk_info, risk_id($risk_id) draw_type(exposure) clear
    levelsof risk, local(risk) c

    capture confirm file "/ihme/epi/risk/paf/`risk'_sampled/global_sampled_200_mean.dta" 
    if _rc == 0 {

        di "reading exposure max/min draw files instead of using calculated value"
        use "/ihme/epi/risk/paf/`risk'_sampled/global_sampled_200_mean.dta", clear
        drop risk
        forvalues i = 0/999 {
            gen min_1_val_draw_`i'=min_1_val_mean
            gen max_99_val_draw_`i'=max_99_val_mean
        }
        drop *mean
        rename (rei_id min_1_val_draw_* max_99_val_draw_*) (risk_id min_1_exp_* max_99_exp_*)
        tempfile maxmin
        save `maxmin', replace

    }

    ** merge on and save
    clear
    use `prepped_exposures'

    capture confirm file "/ihme/epi/risk/paf/`risk'_sampled/global_sampled_200_mean.dta" 
    if _rc == 0 {
        merge m:1 risk_id using `maxmin', keep(3) assert(3) nogen
    }
    else {
        // otherwise use values from simulation
        forvalues i = 0/999 {
            gen max_99_exp_`i' = `max_99'
            gen min_1_exp_`i' = `min_1'
        }
    }



    local f = "$tmp_dir/exp_$risk_id.dta"
    save "`f'", replace
    return local file_path `f'
    
end
// END
