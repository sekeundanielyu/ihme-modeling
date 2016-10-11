// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global
// Description: Generate prevalence of VL cases, based on incidence as predicted by DisMod and duration from literature
// Location: /home/j/WORK/04_epi/01_database/02_data/ntd_leish/1458_1459_1460_1461/04_models/gbd2015/01_code/dev/03b_prevalence_vl.do
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM MASTER CODE (NO NEED TO EDIT THIS SECTION)

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
	if "`1'" != "" {
		// base directory on J 
		local root_j_dir `1'
		// base directory on share
		local root_tmp_dir `2'
		// timestamp of current run (i.e. 2014_01_17)
		local date `3'
		// step number of this step (i.e. 01a)
		local step_num `4'
		// name of current step (i.e. first_step_name)
		local step_name `5'
		// step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
		local hold_steps `6'
		// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
		local last_steps `7'
		// directory where the code lives
		local code_dir `8'
	}
	else if "`1'" == "" {
		// base directory on J 
		local root_j_dir "$prefix/WORK/04_epi/01_database/02_data/ntd_leish/1458_1459_1460_1461/04_models/gbd2015"
		// base directory on share
		local root_tmp_dir "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_leish/1458_1459_1460_1461/04_models/gbd2015"
		// timestamp of current run (i.e. 2014_01_17)
		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
		local date = subinstr("`date'"," ","_",.)
		// step number of this step (i.e. 01a)
		local step_num "03b"
		// name of current step (i.e. first_step_name)
		local step_name "prevalence_vl"
		// step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
		local hold_steps ""
		// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
		local last_steps ""
		// directory where the code lives
		local code_dir "$prefix/WORK/04_epi/01_database/02_data/ntd_leish/1458_1459_1460_1461/04_models/gbd2015/01_code/dev"
	}
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on share
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	
	// write log if running in parallel and log is not already open
	cap log using "`out_dir'/02_temp/02_logs/`step_num'.smcl", replace
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

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
 // Import functions
	run "$prefix/WORK/10_gbd/00_library/functions/get_demographics.ado"
    run "$prefix/WORK/10_gbd/00_library/functions/get_covariate_estimates.ado"
    run "$prefix/WORK/10_gbd/00_library/functions/get_best_model_versions.ado"
	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
	do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"

  // Set the model number and saving parameters
	  get_best_model_versions, gbd_team(epi) id_list(1458) clear
	  local mod_num = model_version_id
  // Set directory for saving best model
	foreach meid in 1458 1459 1460 {
		local root_tmp_dir_`meid' "/ihme/gbd/WORK/04_epi/02_models/02_results/ntd_leish_visc/`meid'/04_models/gbd2015"
		capture mkdir "`root_tmp_dir_`meid''/03_steps/"
		capture mkdir "`root_tmp_dir_`meid''/03_steps/`date'"
		capture mkdir "`root_tmp_dir_`meid''/03_steps/`date'/`step_num'_`step_name'"
		capture mkdir "`root_tmp_dir_`meid''/03_steps/`date'/`step_num'_`step_name'/03_outputs"
		capture mkdir "`root_tmp_dir_`meid''/03_steps/`date'/`step_num'_`step_name'/03_outputs/01_draws"
		local save_dir_`meid' "`root_tmp_dir_`meid''/03_steps/`date'/`step_num'_`step_name'/03_outputs/01_draws"
    }
    local tmp_in_dir "`root_tmp_dir_1458'/03_steps/`date'/`step_num'_`step_name'/02_inputs"
	capture mkdir "`tmp_in_dir'"

  
  // Bring in country codes to ensure that we capture all needed countries
  // Create globals $iso3 $years $ages $sexes for epi analyses
    get_demographics , gbd_team(epi) clear
  
  // Bring in country-specific underreporting factors as assigned by Alvar et al (PLoS Negl Trop Dis 2012).
    clear
    tempfile shape
    save `shape', emptyok
    
    import excel using "`in_dir'/underreporting_factors_alvar_2012.xlsx", firstrow clear
    keep iso3 gbd_analytical_region_name vl*
    
    // Generate shape parameters for a beta distributions with 2.5 and 97.5 percentiles equal to one divided
    // by upper and lower underreporting factors for
      include "`code_dir'/estimate_beta_shape.do"
      
      foreach var of varlist vl* {
        quietly replace `var' = 1 / `var'
      }
      
      rename vl_underreporting_lo prop_hi
      rename vl_underreporting_hi prop_lo
      
      replace prop_lo = . if prop_lo == 1
      replace prop_hi = . if prop_hi == 1
      
      tempfile uf_temp
      save `uf_temp', replace      
      
      quietly duplicates drop prop*, force
      keep prop*
      sort *lo *hi
      drop if missing(prop_lo) | missing(prop_hi)
      
      quietly count
      local n_bounds = r(N)
      
      generate double alpha = .
      generate double beta = .
      
      preserve
      forvalues i = 1/`n_bounds' {
        restore, preserve
          keep if _n == `i'
          expand 2
          generate y = 0
          replace y = 1 in 1
          
          nl faq @ y, parameters(alpha beta) initial(alpha 2 beta 2)

          replace alpha = [alpha]_b[_cons]
          replace beta = [beta]_b[_cons]
          
          quietly duplicates drop alpha beta, force
          drop y
          append using `shape'
          save `shape', replace
      }
      restore, not
      
      use `uf_temp', clear
      merge m:1 prop_lo prop_hi using `shape', keepusing(alpha beta) nogen
      
      keep iso3 gbd_analytical_region_name alpha beta
      sort iso3
      
      forvalues i = 0/999 {
        quietly generate uf_`i' = 1 / rbeta(alpha,beta)
        quietly replace uf_`i' = 1 if missing(uf_`i')
      }
      
    save "`tmp_in_dir'/underreporting.dta", replace
  
  // Get national iso3s to merge on for underreporting 
	get_location_metadata, location_set_id(35) clear
	keep if most_detailed == 1 | location_id == 163
	save "`tmp_in_dir'/location_metadata.dta", replace
	gen iso3 = substr(ihme_loc_id,1,3)
	keep iso3 location_id
	save "`tmp_in_dir'/isomap.dta", replace
	
	// Save endemicity to limit scale-up
		insheet using "`in_dir'/gbd2015_locations_leish.csv", clear
		keep location_id vl_case
		save "`tmp_in_dir'/vl_case.dta", replace
	
	// Get populations
	  get_populations , year_id($year_ids) location_id($location_ids 163) sex_id($sex_ids) age_group_id($age_group_ids) clear
	  save "`tmp_in_dir'/pops.dta", replace
    
  // Pull covariate for endemicity
    get_covariate_estimates, covariate_id(211) clear
	replace mean_value = 1 if mean_value >= 1
	replace mean_value = 0 if mean_value < 1
    duplicates drop location_id location_name, force
    rename mean_value leish_presence
    keep location_id leish_presence
	save "`tmp_in_dir'/leish_presence.dta", replace
	
// Submit jobs by location to scale for underreporting
	foreach location_id of global location_ids {
		capture confirm file "`save_dir_1460'/5_`location_id'_2015_2.csv"
		if _rc {
			!qsub -N "VL_custom_model_lid_`location_id'" -P proj_custom_models -pe multi_slot 2 -l mem_free=4g "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh" "`code_dir'/`step_num'_`step_name'_parallel.do" "`location_id' `tmp_in_dir' `save_dir_1458' `save_dir_1459' `save_dir_1460'"
		}
	}
// Wait for results (check for the last file saved)
	use "`tmp_in_dir'/isomap.dta", clear
    foreach location_id of global location_ids {
		quietly levelsof iso3 if location_id == `location_id', local(iso3) c
		capture confirm file "`save_dir_1460'/5_`location_id'_2015_2.csv"
		if _rc == 601 noisily display "Searching for `location_id' (`iso3') -- `c(current_time)'"
		while _rc == 601 {
			capture confirm file "`save_dir_1460'/5_`location_id'_2015_2.csv"
			sleep 1000
		}
		if _rc == 0 {
			noisily display "`iso3' FOUND!"
		}
    }
	
    
  // Save result
  	save_results, modelable_entity_id(1458) metrics(incidence prevalence) in_dir("`save_dir_1458'") move(yes) ///
				  description("VL  prevalence and incidence draws based on dismod model `mod_num' scaled by underreporting factor (non-endemic countries zeroed)")
    
	 sleep 2000
	
	save_results, modelable_entity_id(1459) metrics(incidence prevalence) in_dir("`save_dir_1459'") move(yes) ///
				  description("VL moderate infection prevalence draws based on dismod model `mod_num' scaled by underreporting factor (non-endemic countries zeroed)")
    
    sleep 2000
    
	save_results, modelable_entity_id(1460) metrics(prevalence) in_dir("`save_dir_1460'") move(yes) ///
				  description("VL severe infection prevalence draws based on dismod model `mod_num' scaled by underreporting factor (non-endemic countries zeroed)")


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// CHECK FILES (NO NEED TO EDIT THIS SECTION)

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
					local dir: dir "`root_j_dir'/03_steps/`date'" dirs "`i'_*", respectcase
					local dir = subinstr(`"`dir'"',`"""',"",.)
					cap confirm file "`root_j_dir'/03_steps/`date'/`dir'/finished.txt"
					if _rc local write_file 0
				}
			}
			
			// write file if all steps finished
			if `write_file' {
				file open all_finished using "`root_j_dir'/03_steps/`date'/finished.txt", replace write
				file close all_finished
			}
		}
		
	// close log if open
		if `close_log' log close
	

	