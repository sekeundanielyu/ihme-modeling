// Purpose: GBD 2015 Schistosomiasis Estimates
// Description:	Custom model for schistosomiasis mortality

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


  // Load national prevalence data and prep such that it can be merged onto the COD data.
	use "`in_dir'/schisto_morb_total_prev_draws.dta", replace

    rename p_tot_draw p_inf
    collapse (mean) p_inf p_hep p_hem p_asc p_dys p_hyd, by(ihme_loc_id)
    
    drop if p_inf ==0 | missing(p_inf)	//IRN dropped
    
    merg m:1 ihme_loc_id using `geo_data', keep(matched) nogen
    
    tempfile nat_prev_data
    save `nat_prev_data', replace
	
  //merge with pop_env data to fill in subnational geographies with national figures where necessary (KEN, SAU, ZAF)
  preserve
  use `pop_env', clear
  keep ihme_loc_id location_id year sex age age_group_id
  keep if year==2010 & sex==1 & age_group_id==5
  drop age_group_id - year
  replace ihme_loc_id = substr(ihme_loc_id, 1, 3)
  keep if inlist(ihme_loc_id, "KEN", "SAU", "ZAF")
  joinby ihme_loc_id using "`nat_prev_data'", unmatched(none)
  drop if inlist(location_id, 180, 152, 196)
  tempfile ksz
  save `ksz', replace
  restore
  
  append using `ksz'

  tempfile nat_prev_data_filled
  save `nat_prev_data_filled', replace 
  
  // Load COD data
    get_data, cause_ids(351) clear
    tempfile cod_data
    save `cod_data', replace	
    
	generate double age = .
	format %16.0g age
	replace age = 0.1 if age_group_id == 4 //PN
	replace age = 1 if age_group_id == 5 //1to4
	replace age = (age_group_id - 5)*5 if age_group_id > 5
	
    drop if sample_size == 0
    drop if age < 0.1
	
  // Merge in data on prevalence of infection and geographical names
    merge m:1 location_id using `nat_prev_data_filled', keepusing(p_inf p_hep p_hem p_asc p_dys p_hyd location_name region superregion) keep(matched) nogen
   
    tempfile nbreg_data
    save `nbreg_data', replace

 //merge with pop data to get ihme_loc_ids   
   use `pop_env', clear
   keep if year == 2010 & sex == 1 & age_group_id == 5
   keep ihme_loc_id location_id
   joinby location_id using "`nbreg_data'", unmatched(none)	

    drop if p_inf ==0 | missing(p_inf) //zero obs deleted    
    save `nbreg_data', replace   
	
    
  // Prepare covariates
    // Health services access (capped)
	  get_covariate_estimates, covariate_id(208) clear
	  rename year_id year
	  rename sex_id sex	  	  
      tempfile hsa_cov
      save `hsa_cov', replace
    // Access to improved water sources
	  get_covariate_estimates, covariate_id(160) clear
	  rename year_id year
	  rename sex_id sex	  	  
      tempfile impr_water
      save `impr_water', replace
          
    use `nbreg_data', replace
    merge m:1 year location_id using `hsa_cov', keep(matched) keepusing(mean_value) nogen
    rename mean_value hsa
    merge m:1 year location_id using `impr_water', keep(matched) keepusing(mean_value) nogen
    rename mean_value impr_water
    
    generate ln_p_inf = ln(p_inf)
    generate ln_p_inf0 = ln(p_inf)*p_inf
    
    generate logit_impr_water = ln(impr_water/(1-impr_water))
    generate hsa_impr_water = hsa * impr_water

    generate year_egypt = 0
      replace year_egypt = (year - 1979)/10 if ihme_loc_id == "EGY"
    
    generate year_china = 0
      replace year_china = (year - 1979) / 10 if year > 1991 & regexm(ihme_loc_id,"CHN")
      replace year_china = (1991 - 1979) / 10 if year <= 1991 & regexm(ihme_loc_id,"CHN")
      
    egen age_cat = group(age), label
    
  // GBD 2013: Work with data from countries with extensive and reasonably plausible mortality data
    //keep if inlist(ihme_loc_id, "EGY", "PHL") | regexm(ihme_loc_id, "CHN") | regexm(ihme_loc_id, "BRA") //GBD 2015: run model with all data
    
  // Perform negative binomial regression
  // Multivariate fractional polynomial for prevalence of infection and time trends in Egypt and China.
    fp generate year_egypt^(2 3), zero replace
    fp generate year_china^(0 .5), zero replace

	//run model with robust standard errors:
	nbreg study_deaths year_egypt_1 year_egypt_2 year_china_1 year_china_2 ln_p_inf i.age_cat i.sex year, exposure(sample_size) vce(robust)
	estat ic
    
  // Visualize pattern with time, global or in Egypt or China
    preserve
      clear
      set obs 36
      generate year = 1980 + _n -1
      generate year_egypt = 0
      generate year_china = 0
        ** replace year_egypt = (year - 1979)/10  // uncomment for trend in egypt
        ** replace year_china = (year - 1979) / 10 if year > 1991  //uncomment for trend in china
        ** replace year_china = (1991 - 1979) / 10 if year <= 1991  //uncomment for trend in china
        fp generate year_egypt^(2 3), zero
        fp generate year_china^(0 .5), zero
      generate p_inf = 0.5
      generate ln_p_inf = ln(p_inf)
      generate age = 80
        generate age1p = age + 1
        fp generate age1p^(-.5 3)
        generate age_cat = 6
      generate impr_water = 1
      generate hsa = 1
      generate hsa_impr_water = 1
      generate superregion = 7
      generate sex = 2
      generate sample_size = 1
      
      predict mortrate, nooffset
      predict mortrate_sd, stdp nooffset
      generate mortrate_up = exp(ln(mortrate) + 1.96 * mortrate_sd)
      generate mortrate_lo = exp(ln(mortrate) - 1.96 * mortrate_sd)
      
      twoway (rarea mortrate_up mortrate_lo year) (line mortrate year)
    restore
  
  // Visualize pattern with infection
    preserve
      clear
      set obs 10000
      generate p_inf = _n/10000
      generate ln_p_inf = ln(p_inf)
      generate age = 80
        generate age1p = age + 1
        fp generate age1p^(-.5 3)
        generate age_cat = 6
      generate impr_water = 0
      generate superregion = 7
      generate year = 2010
      generate year_egypt = 0
      generate year_china = 0
        ** replace year_egypt = (year - 1979)/10
        ** replace year_china = (year - 1990) / 10 if year > 1991
        fp generate year_egypt^(2 3), zero
        fp generate year_china^(0 .5), zero
      generate sex = 2
      generate sample_size = 1
      
      predict mortrate, nooffset
      predict mortrate_sd, stdp nooffset
      generate mortrate_up = exp(ln(mortrate) + 1.96 * mortrate_sd)
      generate mortrate_lo = exp(ln(mortrate) - 1.96 * mortrate_sd)
      
      twoway (rarea mortrate_up mortrate_lo p_inf) (line mortrate p_inf)
    restore
    
  // Visualize pattern with age.cat
    preserve
      clear
      set obs 18
      generate p_inf = 0.5
      generate ln_p_inf = ln(p_inf)
      generate age = 5*(_n - 1)
        replace age = 0.1 if age == 0
        replace age = 1 if age == 85
        sort age
        egen age_cat = group(age), label
      generate impr_water = 0
      generate superregion = 7
      generate year = 2000
      generate sex = 2
      generate year_egypt_1  = 0
      generate year_egypt_2 = 0
      generate year_china_1 = 0
      generate year_china_2 = 0
      generate sample_size = 1
      
      predict mortrate, nooffset
      predict mortrate_sd, stdp nooffset
      generate mortrate_up = exp(ln(mortrate) + 1.96 * mortrate_sd)
      generate mortrate_lo = exp(ln(mortrate) - 1.96 * mortrate_sd)
      
      twoway (rarea mortrate_up mortrate_lo age) (line mortrate age)
    restore
    
    
  // Produce draws of predicted mortality counts per country-year-age-sex for each country
  // where schistosomiasis is present (i.e. countries in the data with national prevalence data). Assume zero deaths for all other countries.
	use `pop_env', clear
	sort ihme_loc_id location_type location_id year age sex
         
    merge m:1 location_id using `geo_data', keepusing(superregion) keep(match) nogen
    
    egen age_cat = group(age) if age >= 0.1, label
     
    merge m:1 location_id using `nat_prev_data_filled', keepusing(p_inf p_hem) keep(1 3) nogen
    generate ln_p_inf = ln(p_inf)

     generate year_egypt = 0
      replace year_egypt = (year - 1979)/10 if ihme_loc_id == "EGY"
    
    generate year_china = 0
      replace year_china = (year - 1979) / 10 if year > 1991 & regexm(ihme_loc_id,"CHN")
      replace year_china = (1991 - 1979) / 10 if year <= 1991 & regexm(ihme_loc_id,"CHN")

    fp generate year_egypt^(2 3), zero replace
    fp generate year_china^(0 .5), zero replace
     
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
        foreach var in ln_p_inf year year_egypt_1 year_egypt_2 year_china_1 year_china_2 {
          quietly replace xb_d`j' = xb_d`j' + `var' * b_`var'[`j']
        }
      
      // sex
         quietly replace xb_d`j' = xb_d`j' + b_2sex[`j'] if sex == 2

      // age category
        foreach a of local ages {
          quietly replace xb_d`j' = xb_d`j' + b_`a'age_cat[`j'] if age_cat == `a'
        }

			// rename
        quietly rename xb_d`j' draw_`counter'
			
		
      // NB model predicts ln_cf, so we multiply the exponent by mortality envelope to get deaths		
        quietly replace draw_`counter' = exp(draw_`counter') * envelope
        

      // Add negative binomial uncertainty, using gamma-poisson mixture
        // If dispersion is modeled as a constant (dispersion(constant) option in nbreg; NB1);
        // although Stata calls this parameter "delta", here it is still called "alpha").
          ** quietly replace draw_`counter' = rgamma(draw_`counter'/alpha[`j'],alpha[`j'])
          ** quietly replace draw_`counter' = rpoisson(draw_`counter')
        
        // If dispersion is modeled as function of mean (default in Stata nbreg; NB2):
          quietly replace draw_`counter' = rgamma(1/alpha[`j'],alpha[`j']*draw_`counter')
          ** quietly replace draw_`counter' = rpoisson(draw_`counter')
          
      quietly replace draw_`counter' = 0 if missing(p_inf) | age < 0.1
      
      local counter = `counter' + 1
		}
  
	egen mean  = rowmean(draw*)
	tabstat mean, by(ihme_loc_id) stat(sum)	
	tabstat mean, by(year) stat(sum)
	tabstat mean, by(age) stat(sum)
	tabstat mean, by(sex) stat(sum) 
  
  tempfile schisto_mort_draws
  save `schisto_mort_draws', replace
  
  
  // Upload draws ihme/gbd
    // Format a la codem output
	  keep ihme_loc_id location_id year sex age_group_id draw_* 
      
      sort location_id year sex age_group_id
      order location_id year sex age_group_id draw_* 

  // Specify path for saving draws
    cap mkdir "`tmp_dir'/deaths"
	    
     local death_dir "`tmp_dir'/deaths"
     save "`death_dir'/ntd_schisto_death_draws.dta", replace	
      

    // Save draws by country-year-sex
	  use `pop_env', clear
	  levelsof location_id, local(isos)
	  
      foreach i of local isos {
        
        use "`death_dir'/ntd_schisto_death_draws.dta", clear
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

// Export results to cod viz
	quietly do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"	
	save_results, cause_id(351) description("Schisto deaths custom NB2 model(robust SEs) + NB uncertainty added using a gamma-poisson mixture. Covs: pre-control ln_p_inf,age,sex,year. Model based on all data. Time trend: Global=all; CHN,EGY=FP") in_dir("`death_dir'") mark_best(yes)

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
		