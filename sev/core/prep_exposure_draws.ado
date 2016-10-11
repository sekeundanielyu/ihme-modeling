cap program drop prep_exposure_draws
program define prep_exposure_draws, rclass
    syntax, location_ids(numlist) year_ids(numlist) age_group_ids(numlist)
    /*
    for given risk, check to see if exposure draws of mean/sd exist
    if they do
        grab all exposure draws of mean and sd
        find the median of the draws
    otherwise
        if bmi
            calculate mean/variance from alpha & beta
        otherwise
            grab all exposure draws
            calculate sd from the coefficient of variance
            reshape wide on parameter and me
            find the median of the draws mean/sd
    merge on pop_scaled
    */
    
    run "$experimental_dir/risk_utils/risk_info.ado"
    adopath + "$functions_dir"
    create_connection_string, server(modeling-epi-db)  // for querying shared
    local con = r(conn_string)

    //pull risk_short_name to reference folder
    risk_info, risk_id($risk_id) draw_type(exposure) clear
    levelsof risk, local(risk) c

     //if bmi, need to calculate mean and variance from alpha and beta
    //currently using compiled version from /ihme/covariates/ubcov/04_model/beta_parameters/4/
    if $risk_id == 108 {
        clear
        tempfile exp
        save `exp', replace emptyok
        local file_list : dir "/ihme/covariates/ubcov/04_model/beta_parameters/4/" files "exp_*.csv"
        foreach file of local file_list {
            insheet using "/ihme/covariates/ubcov/04_model/beta_parameters/4/`file'", clear
            qui append using `exp'
            qui save `exp', replace          
        }
    }
    else if $risk_id == 95 { // if iron, pull files directly
        clear
        tempfile exp
        save `exp', replace emptyok
        local file_list : dir "/ihme/gbd/WORK/05_risk/02_models/02_results/nutrition_iron/exp/5/" files "exp_*.csv"
        foreach file of local file_list {
            insheet using "/ihme/gbd/WORK/05_risk/02_models/02_results/nutrition_iron/exp/5/`file'", clear
            gen file = "`file'"
            qui append using `exp'
            save `exp', replace          
        }
        gen risk_id = $risk_id
        rename gbd_age_start age_group_id
        egen loc_id = ends(file), tail p(_)
        egen location_id = ends(loc_id), head p(.)
        destring location_id, replace

        // take median of draws
        fastpctile exp_*, pct(50) names(median_exp) 
        keep year_id location_id age_group_id sex_id parameter median_exp 
        gen risk_id = $risk_id 

        // reshape wide on parameter
        reshape wide median_exp, i(year_id risk_id location_id age_group_id sex_id) j(parameter) string
    }
    else {
        //check to see if exposure draws exist
        capture confirm file "/ihme/epi/risk/paf/`risk'_interm/exp_101_1990_1.dta" 

        //if they do, grab all exposure draws of mean and sd and take the median
        if _rc == 0 {
            
            //read in files for each location/year/sex
            di "reading exposure mean/sd draw files instead of using get_draws"
            local file_list : dir "/ihme/epi/risk/paf/`risk'_interm/" files "exp_*.dta"
            clear
            tempfile exp_sd
            save `exp_sd', replace emptyok
            foreach file of local file_list {
                append using "/ihme/epi/risk/paf/`risk'_interm/`file'"             
            }
            keep if inlist(age_group_id,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21)
            save `exp_sd', replace
            
            // take median of exp_mean and exp_sd draws
            fastpctile exp_mean_*, pct(50) names(median_expmean) 
            fastpctile exp_sd_*, pct(50) names(median_expsd) 

            //keep only needed columns
            keep year_id location_id age_group_id sex_id median_expmean median_expsd
            gen risk_id = $risk_id 

        }

        // otherwise, grab all exposure draws, calculate sd from the coefficient of variance,
        // reshape wide on parameter and modelable_entity_id, find the median of the draws
        else {
                
            //pull CV file
            import excel "/ihme/epi/risk/paf/`risk'_interm/CV.xlsx", firstrow clear
            tempfile cv
            save `cv', replace 

            // Grab all exposure draws
            get_draws, /// 
                source(risk) gbd_id_field(risk_id) gbd_id($risk_id) location_ids(`location_ids') ///
                year_ids(`year_ids') age_group_ids(`age_group_ids') kwargs(draw_type:exposure) clear

            // parameter from draws is continuous, rename to mean for purposes of reshapes etc
            replace parameter = "mean" if parameter == "continuous"

            // generate sd based off of coeffient of variation 
            // standard deviation = draws * coefficent of variation
            merge m:1 location_id using `cv', keep(1 3) nogen
            expand = 2, generate(expanded)
            replace parameter = "sd" if expanded
            forvalues i = 0/999 {
                qui replace draw_`i' = draw_`i' * coeff_var if parameter == "sd"
            }
            drop expanded coeff_var

             // take median of draws
            fastpctile draw*, pct(50) names(median_exp) 

            keep year_id location_id age_group_id sex_id parameter median_exp 
            gen risk_id = $risk_id 

            // reshape wide on parameter
            reshape wide median_exp, i(year_id risk_id location_id age_group_id sex_id) j(parameter) string
        }

    }

    // merge on pop_scaled, for use in population weighted pctile calc later
    preserve
        levelsof age_group_id, local(age_group_ids)
        levelsof sex_id, local(sex_ids) c
        get_populations, location_id(`location_ids') year_id(`year_ids') sex_id("`sex_ids'") ///
            age_group_id("`age_group_ids'") clear
        tempfile pops
        save `pops'
    restore
    merge 1:1 location_id year_id age_group_id sex_id ///
        using `pops', keep(3) assert(2 3) nogen keepusing(pop_scaled)
    
    // later, population weighting will occur by using expand on pop_scaled.
    // since that creates N-1 copies where N is the value of pop_scaled at that row,
    // lets divide pop_scaled so dataset doesn't get too huge.
    replace pop_scaled = pop_scaled/1000 
    replace pop_scaled = round(pop_scaled)

    local f = "$tmp_dir/exp_$risk_id.dta"
    save `f', replace
    return local file_path `f'
    
end
// END
