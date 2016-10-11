// Purpose: GBD 2015 Cysticercosis Estimates
// Description:	Calculate prevalence of epilepsy due to cysticercosis (neurocysticercosis or NCC) by multiplying the epilepsy envelope
// with the prevalence of NCC among epileptics, corrected for population at risk (non-muslims without access to sanitation).

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
	adopath + $prefix/WORK/10_gbd/00_library/functions/utils
	
	di "`out_dir'/02_temp/02_logs/`step'.smcl""
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

  // Specify path for saving draws
	cap mkdir "`tmp_dir'/epilepsy_prev"
     local prev_dir "`tmp_dir'/epilepsy_prev"

 // Load and save geographical names
   //DisMod and Epi Data 2015
   clear
   get_location_metadata, location_set_id(9)
 
  // Prep country codes file
  duplicates drop location_id, force
  tempfile country_codes
  save `country_codes', replace
  
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
  keep age age_group_id sex year ihme_loc_id parent location_name location_id location_type envelope pop
  keep if inlist(location_type, "admin0","admin1","admin2","nonsovereign", "subnational", "urbanicity")

   replace age = "0" if age=="EN"
   replace age = "0.01" if age=="LN"
   replace age = "0.1" if age=="PN"
   drop if age=="All" | age == "<5"
   keep if age_group_id <= 22
   destring age, replace
   
  keep if inlist(year, 1990, 1995, 2000, 2005, 2010, 2015) & age > 0.9 & age < 80.1 & sex != 3 
  sort ihme_loc_id year sex age
  tempfile pop_env
  save `pop_env', replace
  
// Get best model id's
  get_best_model_versions, gbd_team(epi) id_list(2403) clear //Epilepsy impairment envelope
	local model_epil_env = model_version_id
  get_best_model_versions, gbd_team(epi) id_list(1479) clear //NCC among epileptics
	local model_ncc_prop = model_version_id
	
// Pull covariates for defining population at risk (proportion non-Muslim without access to sanitation)
    insheet using "`in_dir'/prop_muslim_gbd2015.csv", clear comma double
    drop sourcenotes
    tempfile muslim_cov
    save `muslim_cov', replace
    // Sanitation  
	get_covariate_estimates, covariate_id(142) clear
	rename mean_value sanitation_prop
	rename year_id year
	rename sex_id sex
	keep location_id year sanitation_prop
	keep if inlist(year, 1990, 1995, 2000, 2005, 2010, 2015)
    tempfile sanitation_cov
    save `sanitation_cov', replace
    
    merge m:1 location_id using `muslim_cov', keepusing(prop_muslim) keep(master match) nogen
    generate double not_at_risk = 1 - (1 - prop_muslim) * (1 - sanitation_prop)
    keep location_id year not_at_risk
    tempfile not_at_risk
    save `not_at_risk', replace
	save "`tmp_dir'/not_at_risk.dta", replace 
/*
// Multiply NCC prevalence among all epileptics with epilepsy envelope, correcting for population not at risk
//without parallelization
	  use `pop_env', clear
	  //keep if location_id >= 35648
	  levelsof location_id, local(isos)
	  levelsof sex, local(sexes)
	  levelsof year, local(years)
	  
  foreach iso of local isos {
  foreach sex of local sexes {
  foreach year of local years {
  
    display in red "`iso' `year' `sex'"
    
    // Load and temporarily store the NCC prevalence among epileptics at risk
	  get_draws, gbd_id_field(modelable_entity_id) gbd_id(1479) location_ids(`iso') year_ids(`year') sex_ids(`sex') source(epi) status(best) clear
      
	  quietly drop if age_group_id > 21 //ie age > 80 yrs
      
      format draw* %16.0g
      
      forvalues i = 0/999 {
        quietly rename draw_`i' ncc_prev_`i'
      }
      
      tempfile ncc_prev_`iso'_`sex'_`year'
      quietly save `ncc_prev_`iso'_`sex'_`year'', replace
    
    // Load epilepsy envelope
	  get_draws, gbd_id_field(modelable_entity_id) gbd_id(2403) measure_ids(5) location_ids(`iso') year_ids(`year') sex_ids(`sex') source(epi) status(best) clear
      
	  quietly drop if age_group_id > 21 //ie age > 80 yrs
      
      format draw* %16.0g
      
    // Merge in predicted NCC prevalence among epileptics at risk
      quietly merge m:1 age using `ncc_prev_`iso'_`sex'_`year'', keepusing(ncc_prev*) nogen
	  rename sex_id sex
	  rename year_id year      
      
    // Merge in proportion of population not at risk for NCC (proportion Muslim or with access to sanitation)
      quietly merge m:1 location_id year using `not_at_risk', keepusing(not_at_risk) keep(master match) nogen
      
      
    // Calculate prevalence of epilepsy due to NCC as: P * (NM-N) / (NM-1), where
    // P = prevalence of all-cause epilepsy in total population.
    // N = proportion of NCC among epileptics at risk (non-muslims without access to sanitation).
    // M = proportion of population not at risk of contracting NCC (i.e. muslims and people with access to sanitation).
    // Assumption: prevalence of epilepsy due to causes other than NCC is the same for population at risk and not at risk for NCC.
    // Assumption: muslims and non-muslims have equal access to sanitation.
      forvalues i = 0/999 {
        quietly replace draw_`i' = draw_`i' * (ncc_prev_`i' * not_at_risk - ncc_prev_`i') / (ncc_prev_`i' * not_at_risk - 1)
      }

//replace missing draws with zeros for Greenland (349) and Guam (351)
	forvalues i = 0/999 {
        quietly replace draw_`i' = 0 if missing(draw_`i') & missing(not_at_risk)
      }
	  
    quietly keep draw_* age_group_id
    
    quietly outsheet using "`prev_dir'/5_`iso'_`year'_`sex'.csv", comma replace
    
  } 
  }
  }
  */

// Multiply NCC prevalence among all epileptics with epilepsy envelope, correcting for population not at risk
//With parallelization 
	  use `pop_env', clear
	  levelsof location_id, local(isos)
	  levelsof sex, local(sexes)
	  levelsof year, local(years)
  foreach iso of local isos {
  foreach sex of local sexes {
  foreach year of local years {
	
    ! qsub -N int_`iso'_`sex'_`year' -pe multi_slot 4 -l mem_free=8 -P proj_custom_models "$prefix/WORK/10_gbd/00_library/functions/utils/stata_shell.sh" "$prefix/WORK/04_epi/01_database/02_data/ntd_cysticer/1479/04_models/gbd2015/01_code/multiply_prev_parallel.do" "`tmp_dir' `prev_dir' `iso' `sex' `year'"	
  }
    sleep 500
  }
  }

// save the results to the database
	quietly do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
	save_results, modelable_entity_id(2656) description("Prevalence of epilepsy due to NCC (E_NCC), derived from epilepsy envelope (E, #`model_epil_env') and NCC prev among epileptics at risk (N, #`model_ncc_prop'), corrected for population not at risk for NCC (M). E_NCC = E*(NM-N)/(NM-1)") in_dir("`prev_dir'") metrics(prevalence) mark_best(yes)
		
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