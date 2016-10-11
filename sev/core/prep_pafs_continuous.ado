cap program drop prep_pafs_continuous
program define prep_pafs_continuous
    args tmrel_file risks_w_tmrel_draws

    adopath + "$functions_dir"

    if $risk_id == 109 {
        //bmd pafs saved before before compiling with hip/non-hip causes for merging with rrs
        local file_list : dir "/ihme/epi/risk/paf/metab_bmd_interm/" files "paf_*.dta"
        clear
        tempfile pafs
        save `pafs', replace emptyok
        foreach file of local file_list {
            use "/ihme/epi/risk/paf/metab_bmd_interm/`file'"
            gen file = "`file'"
            append using `pafs'
            save `pafs', replace           
        }
        split file, p(_)
        destring file3, replace
        replace year_id = file3
        gen cause_id = 9999
        replace cause_id = 8888 if acause == "non-hip"
        rename paf_* draw_*
        keep location_id year_id sex_id age_group_id cause_id rei_id draw_*

    }
    else {

        // go to /share/central_comp/pafs/[risk_version] and read in all YLL pafs for given risk
        local paf_dir = "/share/central_comp/pafs/$paf_version_id/tmp_sev"

        // tmp just read a few locations while testing
        if $testing {
            local files = "`paf_dir'/101.h5 `paf_dir'/105.h5 `paf_dir'/208.h5"
        }
        else {
            local files = "`paf_dir'/*.h5"
        }

        fast_read, input_files("`files'") where("rei_id == $risk_id") num_slots(2) clear

    }
       
    rename rei_id risk_id

    // confirm that all locations, years, and sexes are represented. and if not,
    // generate demographic with 0 for draws all 0 pafs are dropped
    levelsof sex_id, local(sexes) sep(,)
    levelsof age_group_id, local(ages) sep(,)
    preserve

        //pull all possible/needed demographics that should be present
        get_demographics, gbd_team(epi) make_template clear
        keep if inlist(year_id,1990,1995,2000,2005,2010,2015)
        keep location_id year_id age_group_id sex_id
        tempfile demo
        save `demo',replace
        keep if inlist(sex_id,`sexes')
        keep if inlist(age_group_id,`ages')
        if $testing {
            keep if inlist(location_id,101,105,208)
        }
        save `demo', replace

    restore
    merge m:1 location_id year_id sex_id age_group_id using `demo', assert(2 3) keep(2 3) nogen
    replace risk_id = $risk_id if risk_id == .

    //make sure causes are present for all locations
    fillin location_id year_id sex_id age_group_id cause_id risk_id
    drop _fillin
    drop if cause_id == .
    forvalues i = 0/999 {
        qui replace draw_`i' = 0 if draw_`i' == . 
    }

    merge 1:1 risk_id cause_id sex_id age_group_id year_id location_id using `tmrel_file', keep(3) nogen

    // these columns are from tmrel_file, generated in prep_exposure_draws
    rename median_expsd exp_sd
    rename median_expmean exp_mean
    
    ** scale everything by rr_scalar to units are units of exposure
    replace tmrel_mid = tmrel_mid/rr_scalar if inlist($risk_id, `risks_w_tmrel_draws')
    replace exp_mean = exp_mean/rr_scalar
    replace exp_sd = exp_sd/rr_scalar
    forvalues i = 0/999 {
        replace min_1_exp_`i' = min_1_exp_`i'/rr_scalar
        replace max_99_exp_`i' = max_99_exp_`i'/rr_scalar
    }

end
// END
