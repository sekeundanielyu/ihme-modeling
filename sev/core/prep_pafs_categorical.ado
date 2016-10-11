cap program drop prep_pafs_categorical
program define prep_pafs_categorical
    syntax, rrs(string) location_ids(numlist) age_group_ids(numlist)

    adopath + "$functions_dir"

        // go to /share/central_comp/pafs/[risk_version] and read in all YLL pafs for given risk
        local paf_dir = "/share/central_comp/pafs/$paf_version_id/tmp_sev"

        // unless occ_backpain or hearing -- in that case use YLD pafs
        if inlist($risk_id, $yld_risks) {
            local paf_dir = "`paf_dir'" + "/yld"
        }

        // if we're testing, just read a few files instead of everything
        if $testing {
            local files = "`paf_dir'/101.h5 `paf_dir'/105.h5 `paf_dir'/208.h5"
        }
        else {
            local files = "`paf_dir'/*.h5"
        }

        // read the pafs
        if $risk_id == 134 {
            // read both male and female pafs for CSA
            fast_read, input_files("`files'") where("rei_id in [244,245]") num_slots(4) clear
            replace rei_id = $risk_id
        }
        else if $risk_id == 99 {
            // read both SIR and prev pafs for smoking
            fast_read, input_files("`files'") where("rei_id in [165,166]") num_slots(4) clear
            replace rei_id = $risk_id
        }
        else {
            fast_read, input_files("`files'") where("rei_id == $risk_id") num_slots(2) clear
        }
        rename rei_id risk_id

        if $risk_id == 102 {
            //drop diabetes from alcohol
            drop if cause_id == 587
        }

        // confirm that all locations, years, and sexes are represented. and if not,
        // replace with 0 as all pafs of 0 are dropped
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
        merge m:1 location_id year_id sex_id age_group_id using `demo', keep(2 3) nogen
        replace risk_id = $risk_id if risk_id == .

        //make sure causes are present for all locations
        fillin location_id year_id sex_id age_group_id cause_id risk_id
        drop _fillin
        drop if cause_id == .
        forvalues i = 0/999 {
            qui replace draw_`i' = 0 if draw_`i' == . 
        }

    merge m:1 risk_id cause_id sex_id age_group_id using `rrs', keep(3) nogen

end
// END
