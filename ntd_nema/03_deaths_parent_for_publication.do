// Purpose: GBD 2015 STH Estimates
// Description:	Regression of STH mortality (cause fraction)

// LOAD SETTINGS FROM MASTER CODE

	// prep stata
	clear all
	set more off
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

	// base directory on J 
	local root_j_dir `1'
	// base directory on ihme/gbd (formerly clustertmp)
	local root_tmp_dir `2'
	// timestamp of current run (i.e. 2015_11_23)
	local date `3'
	// step number of this step (i.e. 01a)
	local step `4'
	// name of current step (i.e. first_step_name)
	local step_name `5'
	// step numbers of immediately anterior parent step (i.e. first_step_name)
	local hold_steps `6'
	// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
	local last_steps `7'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step'_`step_name'"
	// directory for output on ihme/gbd (formerly clustertmp)
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step'_`step_name'/03_outputs/01_draws"
	// directory for standard code files
	adopath + $prefix/WORK/10_gbd/00_library/functions
	run "$prefix/WORK/10_gbd/00_library/functions/get_data.ado"
	quietly do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
	
	di "`out_dir'/02_temp/02_logs/`step'.smcl"
	cap log using "`out_dir'/02_temp/02_logs/`step'.smcl", replace
	if !_rc local close_log 1
	else local close_log 0
	
	// check for finished.txt produced by previous step
	if "`hold_steps'" != "" {
		foreach step of local hold_steps {
			local dir: dir "`root_j_dir'/03_steps/`date'" dirs "`step'_*", respectcase
			// remove extra quotation marks
			local dir = subinstr(`"`dir'"',`"""',"",.)
			capture confirm file "`root_j_dir'/03_steps/`date'/`dir'/finished.txt"
			if _rc {
				di "`dir' failed"
				BREAK
			}
		}
	}	

// Load and save geographical names
  //CoD and Outputs 2015
  clear
  get_location_metadata, location_set_id(35)
 
// Prep country codes file
  duplicates drop location_id, force
  //duplicates drop location_name, force
  tempfile country_codes
  save `country_codes', replace
    
    egen region = group(region_name), label
    egen superregion = group(super_region_name), label
    keep ihme_loc_id location_id location_name region region_id superregion
    
		tempfile geo_data
		save `geo_data', replace
		
// Create draw file with zeroes for countries without data (i.e. assuming no burden in those countries)
  clear
  quietly set obs 18
  quietly generate double age = .
  quietly format age %16.0g
  quietly replace age = _n * 5
  quietly replace age = 0.1 if age == 85
  quietly replace age = 1 if age == 90
  sort age

  generate double age_group_id = .
  format %16.0g age_group_id
  replace age_group_id = _n + 3

  forvalues i = 0/999 {
    quietly generate draw_`i' = 0
  }

  quietly format draw* %16.0g

  tempfile zeroes
  save `zeroes', replace  
		
// Prepare envelope and population data
// Get connection string
create_connection_string, server(modeling-mortality-db) database(mortality) 
local conn_string = r(conn_string)

  //gbd2015 version:
 odbc load, exec("SELECT a.age_group_id, a.age_group_name_short AS age, a.age_group_name, o.sex_id AS sex, o.year_id AS year, o.location_id, o.mean_env_hivdeleted AS envelope, o.pop_scaled AS pop FROM output o JOIN output_version USING (output_version_id) JOIN shared.age_group a USING (age_group_id) WHERE is_best=1") `conn_string' clear
  
  tempfile demo
  save `demo', replace
  
  use "`country_codes'", clear
  merge 1:m location_id using "`demo'", nogen
  keep age age_group_id sex year ihme_loc_id parent location_name location_id location_type region_name envelope pop
  keep if inlist(location_type, "admin0","admin1","admin2","nonsovereign", "subnational", "urbanicity")

   replace age = "0" if age=="EN"
   replace age = "0.01" if age=="LN"
   replace age = "0.1" if age=="PN"
   drop if age=="All" | age == "<5"
   keep if age_group_id <= 22
   destring age, replace
   
  keep if year >= 1980 & age >= 0.1 & age < 80.1 & sex != 3 
  sort ihme_loc_id year sex age
  tempfile pop_env
  save `pop_env', replace

  // Load STANDARDIZED PREVALENCES of infection from current best epi models in database
    // Ascariasis
      get_best_model_versions, gbd_team(epi) id_list(2999) clear
	  local mvid = model_version_id
	  get_estimates, gbd_team(epi) model_version_id(`mvid') clear
	  //drop duplicated data
	  sort location_id year_id age_group_id sex_id measure
	  quietly by location_id year_id age_group_id sex_id measure: gen dup = cond(_N==1,0,_n)
	  drop if dup > 1
	  drop dup
	  keep if age_group_id == 27
	  tempfile ascar_prev
	  save `ascar_prev', replace

	  use `ascar_prev', replace
	  keep location_id year_id sex_id mean
      rename year_id year
      rename sex_id sex
      rename mean p_ascar_
		
      // Interpolate years 1990-2015
        levelsof(year), local(years)
        tokenize "`years'"
        
        reshape wide p_ascar, i(sex location_id) j(year)
        
        while "`2'" != "" {  // as long as the second token is not empty, do:
          forvalues y = `=`1'+1' / `=`2'-1'  {
            local year_gap = `y' - `1'
            generate exponent_`y' = ln(p_ascar_`2'/p_ascar_`1') * `year_gap' / (`2'-`1')
            generate double p_ascar_`y' = p_ascar_`1' * exp(exponent_`y')
            drop exponent_`y'
          }
          macro shift  // Discard first token and renames others starting at `1'
        }
          
        // Constant backward extrapolation (assuming stable prevalence equal to 1990.
          forvalues y = 1980/1989 {
            generate p_ascar_`y' = p_ascar_1990
          }
          
        reshape long p_ascar_, i(sex location_id) j(year)
        rename p_ascar_ p_ascar
        replace p_ascar = 0 if missing(p_ascar)
      
	  destring location_id, replace
	  destring sex, replace
      tempfile p_ascar
      save `p_ascar', replace
     
 // Trichuriasis
      get_best_model_versions, gbd_team(epi) id_list(3001) clear
	  local mvid = model_version_id
	  
	  get_estimates, gbd_team(epi) model_version_id(`mvid') clear
	  //drop duplicated data
	  sort location_id year_id age_group_id sex_id measure
	  quietly by location_id year_id age_group_id sex_id measure: gen dup = cond(_N==1,0,_n)
	  drop if dup > 1
	  drop dup
	  keep if age_group_id == 27
	  tempfile trich_prev
	  save `trich_prev', replace
	  
	  use `trich_prev', replace
	  keep location_id year_id sex_id mean
      rename year_id year
      rename sex_id sex
      rename mean p_trich_
		
      // Interpolate years 1990-2015
        levelsof(year), local(years)
        tokenize "`years'"
        
        reshape wide p_trich, i(sex location_id) j(year)
        
        while "`2'" != "" {  // as long as the second token is not empty, do:
          forvalues y = `=`1'+1' / `=`2'-1'  {
            local year_gap = `y' - `1'
            generate exponent_`y' = ln(p_trich_`2'/p_trich_`1') * `year_gap' / (`2'-`1')
            generate double p_trich_`y' = p_trich_`1' * exp(exponent_`y')
            drop exponent_`y'
          }
          macro shift  // Discard first token and renames others starting at `1'
        }          
        // Constant backward extrapolation (assuming stable prevalence equal to 1990.
          forvalues y = 1980/1989 {
            generate p_trich_`y' = p_trich_1990
          }
          
        reshape long p_trich_, i(sex location_id) j(year)
        rename p_trich_ p_trich
        replace p_trich = 0 if missing(p_trich)
      
	  destring location_id, replace
	  destring sex, replace
      tempfile p_trich
      save `p_trich', replace

 // Hookworm
      get_best_model_versions, gbd_team(epi) id_list(3000) clear
	  local mvid = model_version_id
	  
	  get_estimates, gbd_team(epi) model_version_id(`mvid') clear
	  //drop duplicated data
	  sort location_id year_id age_group_id sex_id measure
	  quietly by location_id year_id age_group_id sex_id measure: gen dup = cond(_N==1,0,_n)
	  drop if dup > 1
	  drop dup
	  keep if age_group_id == 27
	  tempfile hook_prev
	  save `hook_prev', replace
	 
	  use `hook_prev', replace
	  keep location_id year_id sex_id mean
      rename year_id year
      rename sex_id sex
      rename mean p_hook_
		
      // Interpolate years 1990-2015
        levelsof(year), local(years)
        tokenize "`years'"
        
        reshape wide p_hook, i(sex location_id) j(year)
        
        while "`2'" != "" {  // as long as the second token is not empty, do:
          forvalues y = `=`1'+1' / `=`2'-1'  {
            local year_gap = `y' - `1'
            generate exponent_`y' = ln(p_hook_`2'/p_hook_`1') * `year_gap' / (`2'-`1')
            generate double p_hook_`y' = p_hook_`1' * exp(exponent_`y')
            drop exponent_`y'
          }
          macro shift  // Discard first token and renames others starting at `1'
        }
        // Constant backward extrapolation (assuming stable prevalence equal to 1990.
          forvalues y = 1980/1989 {
            generate p_hook_`y' = p_hook_1990
          }
          
        reshape long p_hook_, i(sex location_id) j(year)
        rename p_hook_ p_hook
        replace p_hook = 0 if missing(p_hook)
      
	  destring location_id, replace
	  destring sex, replace
      tempfile p_hook
      save `p_hook', replace
 
  // Load COD data
    get_data, cause_ids(360) clear
	
    // Drop national aggregate data for countries where we have subnational data
	  //drop if inlist(iso3,"BRA", "CHN", "GBR", "IND", "JPN") | inlist(iso3,"KEN", "MEX", "SAU","SWE", "USA", "ZAF")
	  drop if inlist(location_id, 135, 6, 95, 163, 67) | inlist(location_id, 180, 130, 152, 93, 102, 196)
    
    drop if sample_size == 0
 	tempfile cod_data
    save `cod_data', replace
    
  // Merge in data on geographical names
    merge m:1 location_id using `geo_data', keepusing(location_name region region_id superregion ihme_loc_id) keep(matched) nogen
    
	drop if sample_size == 0
	
    // Drop national aggregate data for countries where we have subnational data
	  drop if inlist(ihme_loc_id,"BRA", "CHN", "GBR", "IND", "JPN") | inlist(ihme_loc_id,"KEN", "MEX", "SAU","SWE", "USA", "ZAF")
	 // drop if inlist(location_id, 135, 6, 95, 163, 67) | inlist(location_id, 180, 130, 152, 93, 102, 196)
  
    tempfile nbreg_data
    save `nbreg_data', replace

 // Merge in data on prevalence of infection     
  // Prepare covariates
    // Sanitation  
	  get_covariate_estimates, covariate_id(142) clear
	  rename year_id year
	  rename sex_id sex
      tempfile sanitation_cov
      save `sanitation_cov', replace
    // Health system access (capped)  
	  get_covariate_estimates, covariate_id(208) clear
	  rename year_id year
	  rename sex_id sex
      tempfile hsa_cov
      save `hsa_cov', replace
    // Proportion of land with population density > 1000 / km^2 (proxy for urbanicity)
	  get_covariate_estimates, covariate_id(118) clear
	  rename year_id year
	  rename sex_id sex
      tempfile urban_cov
      save `urban_cov', replace
     // Proportion of the population living above 1500m of elevation (2.5 arc mins)
	  get_covariate_estimates, covariate_id(109) clear
	  rename year_id year
	  rename sex_id sex
      tempfile altitude_cov
      save `altitude_cov', replace
      

    use `nbreg_data', replace
    merge m:1 year location_id using `sanitation_cov', keep(matched) keepusing(mean_value) nogen
    rename mean_value sanitation_prop
    merge m:1 year location_id using `hsa_cov', keep(matched) keepusing(mean_value) nogen
    rename mean_value hsa
    merge m:1 year location_id using `urban_cov', keep(matched) keepusing(mean_value) nogen
    rename mean_value urban
    merge m:1 year location_id using `altitude_cov', keep(matched) keepusing(mean_value) nogen
    rename mean_value altitude
	merge m:1 year location_id sex using `p_ascar', keep(matched) keepusing(p_ascar) nogen
    merge m:1 year location_id sex using `p_trich', keep(matched) keepusing(p_trich) nogen
    merge m:1 year location_id sex using `p_hook', keep(matched) keepusing(p_hook) nogen
	
  // Perform negative binomial regression
    generate double age = .
	format %16.0g age
	replace age = 0.1 if age_group_id == 4 //PN
	replace age = 1 if age_group_id == 5 //1to4
	replace age = (age_group_id - 5)*5 if age_group_id > 5
	
    drop if age < 0.1 | age_group_id < 4
    replace study_deaths = 0 if study_deaths < 0.5
      
    generate year_center = year - 1979
    egen age_cat = group(age), label
	
    generate philipp = ihme_loc_id == "PHL"
    generate brazil = regexm(ihme_loc_id, "BRA")	//no subnational location with higher mean than the other locations(range: 0.07-0.57), but model fits better when included (smaller AIC than if excluded)
    generate colomb = ihme_loc_id == "COL"
    generate venezu = ihme_loc_id == "VEN"
    generate guatem = ihme_loc_id == "GTM"
    generate iran = ihme_loc_id == "IRN"
	 
    // vw: use prevalence data - ultimately will only use ascar prev data - hook and trichur are just for visualizations
    generate p_inf_zero = (p_ascar == 0 & p_trich == 0 & p_hook == 0)
    drop if p_inf_zero == 1
    
    generate p_inf_total = p_ascar + p_trich + p_hook
    
    generate ln_p_ascar = ln(p_ascar)
    generate ln_p_trich = ln(p_trich)
    generate ln_p_hook = ln(p_hook)
    generate ln_p_inf_total = ln(p_inf_total)
    
    generate ln_p_ascar_urban = ln_p_ascar * urban

 //GBD 2013: NB model with predictors: age sex urban_prop ln_prev_ascariasis and country-indicators for PHL BRA COL and VEN (higher deaths than expected based on other predictors). Sanitation and hsa_capped correlated poorly or in the wrong direction. Also, the age-sex-standardized ascariasis prevalence (from the non-fatal model) correlated only very weakly with the cause-fraction of deaths.
	 
 //GBD 2015: NB model with predictors: age sex urban_prop ln_prev_ascariasis and country-indicators for PHL COL VEN and IRN (higher deaths than expected based on other predictors). Brazil modeled only at subnational level and the number of deaths for each subnational location are not higher than other locations. Sanitation and hsa_capped correlated poorly or in the wrong direction. Also, the age-sex-standardized ascariasis prevalence (from the non-fatal model) correlated only

	//run model to include brazil subnational - checked subnationals and none with unusually high deaths; included PHL, COL, VEN, GMT, IRN; model now converges if GTM is added)
	nbreg study_deaths i.age_cat i.sex urban ln_p_ascar philipp brazil colomb venezu guatem iran, exposure(sample_size) dispersion(constant) vce(robust)
    estat ic

  // Produce draws of predicted mortality counts per country-year-age-sex
	use `pop_env', clear
	sort ihme_loc_id location_type location_id year age sex

  
  // Create covariates to predict deaths with
    merge m:1 location_id using `geo_data', keepusing(superregion) keep(match) nogen
    
    merge m:1 year location_id sex using `p_ascar', keep(matched) keepusing(p_ascar) nogen
    merge m:1 year location_id using `urban_cov', keep(matched) keepusing(mean_value) nogen
    rename mean_value urban
   
    generate philipp = ihme_loc_id == "PHL"
    generate brazil = regexm(ihme_loc_id, "BRA")	//no subnational location with higher mean than the other locations(range: 0.07-0.57), but model fits better when included (smaller AIC than if excluded)
    generate colomb = ihme_loc_id == "COL"
    generate venezu = ihme_loc_id == "VEN"
    generate guatem = ihme_loc_id == "GTM"
    generate iran = ihme_loc_id == "IRN"
    
    generate ln_p_ascar = ln(p_ascar)
    
    generate ln_p_ascar_urban = ln_p_ascar * urban
    
    egen age_cat = group(age) if age >= 0.1, label
    
  // create a columnar matrix (rather than default, which is row) by using the apostrophe
		matrix m = e(b)'
    
	// create a local that corresponds to the variable name for each parameter
		local covars: rownames m
    
	// create a local that corresponds to total number of parameters
		local num_covars: word count `covars'
    
	// create an empty local that you will fill with the name of each beta (for each parameter)
		local betas
    
	// fill in this local
		forvalues j = 1/`num_covars' {
			local this_covar: word `j' of `covars'
			local covar_fix=subinstr("`this_covar'","b.","",.)
			local covar_rename=subinstr("`covar_fix'",".","",.)
      if `j' == `num_covars' {
      // Rename dispersion coefficient (is also called _const, like intercept)  
        local covar_rename = "alpha"
      }
			local betas `betas' b_`covar_rename'
		}
    
	// store the covariance matrix
	matrix C = e(V)
	
	// use the "drawnorm" function to create draws using the mean and standard deviations from your covariance matrix
		drawnorm `betas', means(m) cov(C)
	// you should now have as many new variables in your dataset as betas
	// they will be filled in, with diff value from range of possibilities of coefficients, in every row of your dataset

	// Generate draws of the prediction
		levelsof age_cat, local(ages)
		levelsof superregion, local(superregion)
    levelsof year, local(year)
    
		local counter=0
		compress
 
    quietly generate alpha = exp(b_alpha)
    
		forvalues j = 1/1000 {
			display in red `counter'
			quietly generate double xb_d`j' = 0
			quietly replace xb_d`j' = xb_d`j' + b__cons[`j']
		// add in any addtional covariates here in the form:
			** quietly replace xb_d`j'=xb_d`j'+covariate*b_covariate[`j']
			
      // continuous variables
		foreach var in ln_p_ascar urban {
          quietly replace xb_d`j' = xb_d`j' + `var' * b_`var'[`j']
        }
      
      // sex
         quietly replace xb_d`j' = xb_d`j' + b_2sex[`j'] if sex == 2
      
      // age
        foreach a of local ages {
          quietly replace xb_d`j' = xb_d`j' + b_`a'age_cat[`j'] if age_cat==`a'
        }
        
      // specific countries
        quietly replace xb_d`j' = xb_d`j' + b_philipp[`j'] if ihme_loc_id == "PHL"
        quietly replace xb_d`j' = xb_d`j' + b_brazil[`j'] if ihme_loc_id == "BRA"	
        quietly replace xb_d`j' = xb_d`j' + b_colomb[`j'] if ihme_loc_id == "COL"
        quietly replace xb_d`j' = xb_d`j' + b_venezu[`j'] if ihme_loc_id == "VEN"
        quietly replace xb_d`j' = xb_d`j' + b_venezu[`j'] if ihme_loc_id == "GTM"
        quietly replace xb_d`j' = xb_d`j' + b_venezu[`j'] if ihme_loc_id == "IRN"
      
			// rename
        quietly rename xb_d`j' draw_`counter'
			
		
      // NB model predicts ln_cf, so we multiply the exponent by mortality envelope to get deaths		
        quietly replace draw_`counter' = exp(draw_`counter') * envelope
        
      
      // Add negative binomial uncertainty, using gamma-poisson mixture
        // If dispersion is modeled as a constant (dispersion(constant) option in nbreg; NB1);
        // although Stata calls this parameter "delta", here it is still called "alpha"):
          quietly replace draw_`counter' = rgamma(draw_`counter'/alpha[`j'],alpha[`j'])
          ** quietly replace draw_`counter' = rpoisson(draw_`counter')
        
        // If dispersion is modeled as function of mean (default in Stata nbreg; NB2):
          ** quietly replace draw_`counter' = rgamma(1/alpha[`j'],alpha[`j']*draw_`counter')
          ** quietly replace draw_`counter' = rpoisson(draw_`counter')
          
      quietly replace draw_`counter' = 0 if missing(draw_`counter')
      quietly replace draw_`counter' = 0 if age < 0.1
      
      local counter = `counter' + 1
		}

	egen mean  = rowmean(draw*)
	tabstat mean, by(ihme_loc_id) stat(sum)	
	tabstat mean, by(year) stat(sum)
	tabstat mean, by(age) stat(sum)
	tabstat mean, by(sex) stat(sum)
	
    tempfile sth_mort_draws
    save `sth_mort_draws', replace
  
  // Upload draws /ihme/gbd
    // Format for codem output
	  keep ihme_loc_id location_id year sex age_group_id draw_* 
      
      sort location_id year sex age_group_id
      order location_id year sex age_group_id draw_* 
      
  // Specify path for saving draws
    cap mkdir "`tmp_dir'/deaths"
     local death_dir "`tmp_dir'/deaths"
	 
      save "`death_dir'/ntd_nema_death_draws.dta", replace 
   
    // Save draws by country-year-sex
	  use `pop_env', clear
	  levelsof location_id, local(isos)
	  
      foreach i of local isos {
        
        use "`death_dir'/ntd_nema_death_draws.dta", clear
        quietly keep if location_id == `i'
        
        forvalues yr = 1980/2015 {
          foreach s in 1 2 {
            display in red "`i' `yr' sex `s'"
            preserve
            quietly {
            
            keep if sex == `s' & year == `yr'
			count
			if r(N) > 0 {
			quietly keep age_group_id draw*
          }
          else {
            use `zeroes', clear
          }
            quietly keep age_group_id draw*
			sort age_group_id
            format draw* %16.0g
            
            if `s' == 1 outsheet using "`death_dir'/death_`i'_`yr'_1.csv", comma replace
            else outsheet using "`death_dir'/death_`i'_`yr'_2.csv", comma replace
			
            }
            restore
          }
        }
      }

// save the results to the database
	quietly do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
	save_results, cause_id(360) description("STH deaths custom NB model (robust SEs), + NB uncertainty added using a gamma-poisson mixture. Predictors: age_group, sex, urbanicity, ln_p_ascar, country-indic for PHL, BRA, COL, VEN, GTM, IRN") in_dir("`death_dir'") mark_best(yes)

	// save same results for ascariasis
	save_results, cause_id(361) description("Ascariasis = STH deaths custom NB model (robust SEs) + NB uncertainty using a gamma-poisson mixture. Predictors: age_group,sex,urbanicity,ln_p_ascar,country-indic for PHL, BRA, COL, VEN, GTM, IRN") in_dir("`death_dir'") mark_best(yes)

// **********************************************************************
// CHECK FILES

	// write check file to indicate step has finished
		file open finished using "`out_dir'/finished.txt", replace write
		file close finished
		
	// if step is last step, write finished.txt file
		local i_last_step 0
		foreach i of local last_steps {
			if "`i'" == "`this_step'" local i_last_step 1
		}
		
		// only write this file if this is one of the last steps
		if `i_last_step' {
		
			// account for the fact that last steps may be parallel and don't want to write file before all steps are done
			local num_last_steps = wordcount("`last_steps'")
			
			// if only one last step
			local write_file 1
			
			// if parallel last steps
			if `num_last_steps' > 1 {
				foreach i of local last_steps {
					local dir: dir "root_j_dir/03_steps/`date'" dirs "`i'_*", respectcase
					local dir = subinstr(`"`dir'"',`"""',"",.)
					cap confirm file "root_j_dir/03_steps/`date'/`dir'/finished.txt"
					if _rc local write_file 0
				}
			}
			
			// write file if all steps finished
			if `write_file' {
				file open all_finished using "root_j_dir/03_steps/`date'/finished.txt", replace write
				file close all_finished
			}
		}
		
	// close log if open
		if `close_log' log close