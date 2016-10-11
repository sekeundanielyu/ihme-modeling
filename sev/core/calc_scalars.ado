cap program drop calc_scalars
program define calc_scalars, rclass
    
    adopath + "$functions_dir"

    if $continuous {

        forvalues i = 0/999{
            qui gen diff_`i'=max_99_exp_`i'-tmrel_mid
            // If the exposure type is equal to one, subtract exposure from tmred.
            // because the risk is protective
            qui replace diff_`i'=tmrel_mid-min_1_exp_`i' if inv_exp==1
            
            // max rr can't be below 1, so if diff is negative, this changes it to 0. 
            // Which causes max_rr to be 1. If diff is positive,
            // it does nothing
            qui replace diff_`i'=(abs(diff_`i')+diff_`i')/2
            qui gen max_rr_`i' = rr_`i'^(diff_`i')
      
            /*
            continuous sev is defined as (paf/(1-paf)/(max_rr-1), where max_rr is rowwise mean
            */
            qui replace draw_`i' = 0 if draw_`i' < 0 //no negative pafs
            qui gen double sev_`i' = (draw_`i'/(1-draw_`i'))/(max_rr_`i'-1)
            qui replace sev_`i' = 0 if max_rr_`i' <= 1 
            qui replace sev_`i' = 1 if sev_`i' > 1 //truncate
            
        }

    }
    else {
        
        /*
        Categorical SEV is (paf/1-paf) / (rr_max - 1), where rr_max is defined as
        the rr category with the highest rr draw value for that a/s/c
        */
        forvalues i = 0/999 {
            qui replace draw_`i' = 0 if draw_`i' < 0 //no negative pafs
            qui gen double sev_`i' = (draw_`i'/(1-draw_`i'))/(rr_`i'-1)
            qui replace sev_`i' = 0 if rr_`i' <= 1 
            qui replace sev_`i' = 1 if sev_`i' > 1 //truncate
        }

    }
    
    //save RR max
    preserve
        keep age_group_id sex_id risk_id cause_id rr*
        duplicates drop
        save "$base_dir/$paf_version_id/rrmax/draws/$risk_id.dta", replace
        fastrowmean rr*, mean_var_name(max_rr)
        keep age_group_id sex_id risk_id cause_id max_rr
        save "$base_dir/$paf_version_id/rrmax/summary/$risk_id.dta", replace
    restore

    ** right now results are still cause specific, so these are scalars. 
    ** average across cause to get actual sevs
    fastcollapse sev*, type(mean) by(sex_id age_group_id location_id risk_id year_id)

    local f = "$tmp_dir/results_$risk_id.dta"
    save `f', replace
    return local file_path `f'

end
// END
