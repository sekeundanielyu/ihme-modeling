// Purpose: GBD 2015 Cystic Echinococcosis Estimates
// Description:	Regression of Cystic echinococcosis mortality (cause fraction)

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
  tempfile country_codes
  save `country_codes', replace
    
    egen region = group(region_name), label
    egen superregion = group(super_region_name), label
    keep ihme_loc_id location_id location_name region region_id superregion
    
		tempfile geo_data
		save `geo_data', replace
// Create draw file with zeroes for countries without data (i.e. assuming no burden in those countries)
  clear
  quietly set obs 17
  quietly generate double age = .
  quietly format age %16.0g
  quietly replace age = _n * 5
  quietly replace age = 1 if age == 85
  sort age

  generate double age_group_id = .
  format %16.0g age_group_id
  replace age_group_id = _n + 4


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
   
  keep if year >= 1980 & age > 0.9 & age < 80.1 & sex != 3 
  sort ihme_loc_id year sex age
  tempfile pop_env
  save `pop_env', replace

  // Load COD data
    get_data, cause_ids(353) clear
    tempfile cod_data
    save `cod_data', replace	
    
    drop if sample_size == 0
    
	generate double age = .
	format %16.0g age
	replace age = 0.1 if age_group_id == 4 //PN
	replace age = 1 if age_group_id == 5 //1to4
	replace age = (age_group_id - 5)*5 if age_group_id > 5
	
    // Drop observations for ages < 1 (zero deaths)
      drop if age < 1
   
  // Merge in data on  geographical names
    merge m:1 location_id using `geo_data', keepusing(location_name region superregion) keep(matched) nogen
    
    tempfile nbreg_data
    save `nbreg_data', replace
    
  // Prepare covariates
    // Sheep per capita
	  get_covariate_estimates, covariate_id(144) clear
	  rename year_id year
	  rename sex_id sex	  
      tempfile sheep_cov
      save `sheep_cov', replace
    // Sanitation
	  get_covariate_estimates, covariate_id(142) clear
	  rename year_id year
	  rename sex_id sex	 	  
      tempfile sanitation_cov
      save `sanitation_cov', replace
	  
    // Creating endemicity covariate (categorical and binary)
	  /*
	  //For the covariate database, expand covariate to include country-year-age(all)-sex(both) info. For each country, same value applied for all years
	  
	  insheet using "`in_dir'/cyst_echino_endemicity_2015.csv", clear comma double
	  tempfile endemicity_cov
	  save `endemicity_cov', replace
	  
	  use `pop_env', clear
	  keep location_id year age_group_id sex
	  keep if age_group_id == 10 & sex == 1
	  replace age_group_id = 22
	  replace sex = 3
	  joinby location_id using "`endemicity_cov'", unmatched(master)
	  
	  //generate categorical covariate
	  preserve
	  gen covariate_name_short = "echino_endemicity"
	  keep covariate location_id year age_group_id sex echino_endem
	  rename echino_endem mean_value
	  rename year year_id
	  rename sex sex_id
	  order covariate_name_short location_id year_id age_group_id sex_id mean_value
		tempfile echino_cat
		save `echino_cat', replace
	  quietly outsheet using "C:\Users\wangav\Documents\NTDs\Echino\1484\04_models\gbd2015\02_inputs\echino_endem_categorical.csv", comma replace
	  restore
	  
	  //generate binary covariate
	  preserve
	  gen covariate_name_short = "echino_presence"
	  keep covariate location_id year age_group_id sex endemicity_bin2
	  rename endemicity_bin2 mean_value
	  rename year year_id
	  rename sex sex_id
	  order covariate_name_short location_id year_id age_group_id sex_id mean_value
		tempfile echino_binary
		save `echino_binary', replace
	  quietly outsheet using "C:\Users\wangav\Documents\NTDs\Echino\1484\04_models\gbd2015\02_inputs\echino_endem_binary.csv", comma replace
	  restore
	  */
	  insheet using "`in_dir'/echino_endem_categorical.csv", clear comma double
	  rename mean_value echino_endem
	  rename year_id year
	  rename sex_id sex	
	  tempfile endemicity_cov
	  save `endemicity_cov', replace
	  
    use `nbreg_data', replace
    merge m:1 year location_id using `sheep_cov', keep(matched) keepusing(mean_value) nogen
    rename mean_value sheep_pc
    merge m:1 year location_id using `sanitation_cov', keep(matched) keepusing(mean_value) nogen
    rename mean_value sanitation_prop
    merge m:1 year location_id using `endemicity_cov', keep(matched) keepusing(echino_endem) nogen
    
  // Merge endemicity covariate for countries designated as non-endemic or with sporadic cases
    replace echino_endem = 0 if echino_endem == 1
  
  // Perform regression
    egen age_cat = group(age), label
    
    generate sheep_sanit = sheep_pc * sanitation_prop
    
    // Create separate sex pattern in Eastern Europe and Central Asia for cause fraction model (relatively many men die there)
      generate sex_east = 0 
        replace sex_east = 1 if inlist(region, 4, 9)
    
    poisson study_deaths i.age_cat i.sex sex_east year sheep_pc sanitation_prop i.echino_endem, exposure(sample_size)
    estat ic
 
  // Visualize pattern by year
    ** preserve
      ** clear
      ** set obs 34
      ** generate year = 1980 + _n - 1
      ** generate sheep_pc = 1
      ** generate sanitation_prop = 0.01
      ** generate sheep_sanit = sheep_pc * sanitation_prop
      ** generate sex = 2
      ** generate sample_size = 1
      ** generate echino_endem = 2
      ** generate age_cat = 1
      ** generate age = 1
      ** predict mortrate, nooffset
      ** predict mortrate_sd, stdp nooffset
      ** generate mortrate_up = ln(mortrate) + 1.96 * mortrate_sd
      ** generate mortrate_lo = ln(mortrate) - 1.96 * mortrate_sd
      ** replace mortrate_up = exp(mortrate_up)
      ** replace mortrate_lo = exp(mortrate_lo)
      
      ** twoway (rarea mortrate_up mortrate_lo year) (line mortrate year)
    ** restore
    
  // Visualize pattern by age^(-2 3)
    ** preserve
      ** clear
      ** set obs 100
      ** generate age = _n
        ** generate age1p = age + 1
        ** fp generate age1p^(-2 3)
      ** generate year = 1980
      ** generate sheep_pc = 1
      ** generate sanitation_prop = 0.01
      ** generate sheep_sanit = sheep_pc * sanitation_prop
      ** generate sex = 2
      ** generate sample_size = 1
      ** generate echino_endem = 2
      ** predict mortrate, nooffset
      ** predict mortrate_sd, stdp nooffset
      ** generate mortrate_up = ln(mortrate) + 1.96 * mortrate_sd
      ** generate mortrate_lo = ln(mortrate) - 1.96 * mortrate_sd
      ** replace mortrate_up = exp(mortrate_up)
      ** replace mortrate_lo = exp(mortrate_lo)
      
      ** twoway (rarea mortrate_up mortrate_lo age) (line mortrate age)
    ** restore
    
  // Produce draws of predicted mortality counts per country-year-age-sex
	use `pop_env', clear
	sort ihme_loc_id location_type location_id year age sex
	
    merge m:1 location_id using `geo_data', keepusing(superregion) keep(match) nogen
     
    merge m:1 year location_id using `sheep_cov', keep(matched) keepusing(mean_value) nogen
    rename mean_value sheep_pc
    merge m:1 year location_id using `sanitation_cov', keep(matched) keepusing(mean_value) nogen
    rename mean_value sanitation_prop
    generate sheep_sanit = sheep_pc * sanitation_prop
    merge m:1 year location_id using `endemicity_cov', keep(matched) keepusing(echino_endem) nogen	
    replace echino_endem = 0 if echino_endem == 1
    
    generate sex_east = 0 
      replace sex_east = 1 if inlist(region_name, "Central Asia", "Eastern Europe")
		
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
			local betas `betas' b_`covar_rename'
		}
    
	// store the covariance matrix
	matrix C = e(V)
	
	// use the "drawnorm" function to create draws using the mean and standard deviations from your covariance matrix
		drawnorm `betas', means(m) cov(C)
	// you should now have as many new variables in your dataset as betas
	// they will be filled in, with diff value from range of possibilities of coefficients, in every row of your dataset

	// Generate draws of the prediction
    egen age_cat = group(age) if age >= 1, label
		levelsof age_cat, local(ages)
    levelsof superregion, local(superregion)
		    
		local counter=0
		compress
        
		forvalues j = 1/1000 {
			display in red `counter'
			quietly generate double xb_d`j' = 0
			quietly replace xb_d`j' = xb_d`j' + b__cons[`j']
		// add in any addtional covariates here in the form:
			** quietly replace xb_d`j'=xb_d`j'+covariate*b_covariate[`j']

      // continuous variables gbd2015
        foreach var in sheep_pc sanitation_prop year sex_east {
          quietly replace xb_d`j' = xb_d`j' + `var' * b_`var'[`j']
        }
		
      // sex
         quietly replace xb_d`j' = xb_d`j' + b_2sex[`j'] if sex == 2
      
      // endemicity
        quietly replace xb_d`j' = xb_d`j' + b_2echino_endem[`j'] if echino_endem == 2
				quietly replace xb_d`j' = xb_d`j' + b_3echino_endem[`j'] if echino_endem == 3    
      
      // age
        foreach a of local ages {
          quietly replace xb_d`j' = xb_d`j' + b_`a'age_cat[`j'] if age_cat==`a'
        }			
	
	// rename
        quietly rename xb_d`j' draw_`counter'
		
      // Poisson model predicts ln_cf, so we multiply the exponent by mortality envelope to get deaths		
        quietly replace draw_`counter' = exp(draw_`counter') * envelope
  
      quietly replace draw_`counter' = 0 if missing(draw_`counter')
      quietly replace draw_`counter' = 0 if age < 1
      
      local counter = `counter' + 1
		}
  
  egen mean  = rowmean(draw*)
  tabstat mean, by(year) stat(sum)
  
  tempfile echino_mort_draws
  save `echino_mort_draws', replace
  
  // Upload draws /ihme/gbd
    // Format a la codem output
	  keep ihme_loc_id location_id year sex age_group_id draw_* 
      
      sort location_id year sex age_group_id
      order location_id year sex age_group_id draw_*
      
  // Specify path for saving draws
    cap mkdir "`tmp_dir'/deaths"
     local death_dir "`tmp_dir'/deaths"
	 
      save "`death_dir'/ntd_echino_death_draws.dta", replace
     
    // Save draws by country-year-sex
	  use `pop_env', clear
	  levelsof location_id, local(isos)
	  
      foreach i of local isos {
        
		use "`death_dir'/ntd_echino_death_draws.dta", clear        
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
	save_results, cause_id(353) description("Cystic echino custom Poisson model for cause fraction. Predictors: age, sex, sex_east year, endemicity, sanitation_prop, sheep_pc") in_dir("`death_dir'") mark_best(yes)

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