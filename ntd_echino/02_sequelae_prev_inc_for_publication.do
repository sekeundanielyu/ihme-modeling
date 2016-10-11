// Purpose: GBD 2015 Cystic Echinococcosis Estimates
// Description:	split estimated prevalence of clinical echinococcosis parent into specific sequelae, given overall prevalence and 
// literature on the counts or proportions of different sequelae among all echinococcosis cases. Take into account the
// uncertainty due to the limited sample size of the study, and make sure that proportions always add up to one.

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

  cap mkdir "`tmp_dir'/epilepsy_prev"
  cap mkdir "`tmp_dir'/abd_prev"
  cap mkdir "`tmp_dir'/resp_prev"
  
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
	

// **********************************************************************
// Get best model id's
  get_best_model_versions, gbd_team(epi) id_list(1484) clear
	local model_parent = model_version_id
  
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
/*
//without parallelization
// Create thousand draws of proportions for abdominal, respiratory and epileptic symptoms among echinococcosis cases that
//  add up to 1, given the observed sample sizes in Eckert & Deplazes, Clinical Microbiology Reviews 2004; 17(1) 107-135 (Table 3).
// Assume that the observed cases follow a multinomial distribution cat(p1,p2,p3), where (p1,p2,p3)~Dirichlet(a1,a2,a3),
// where the size parameters of the Dirichlet distribution are the number of observations in each category (must be non-zero).
  local n1 = 316+17+15+9+1  // abdominal or pelvic cyst localization
  local n2 = 79+5           // thoracic cyst localization (lungs & mediastinum)
  local n3 = 4              // brain cyst localization
  local n4 = 10+3           // other localization (bones, muscles, and skin; currently not assigning this to a healthstate)

  forvalues i = 0/999 {
    quietly clear
    quietly set obs 1
    
    generate double a1 = rgamma(`n1', 1)
    generate double a2 = rgamma(`n2', 1)
    generate double a3 = rgamma(`n3', 1)
    generate double a4 = rgamma(`n4', 1)
    generate double A = a1 + a2 + a3 + a4
    
    generate double p1 = a1 / A
    generate double p2 = a2 / A
    generate double p3 = a3 / A
    generate double p4 = a4 / A
  
    local p_abd_`i' = p1 + p4  //Added these cases to abdominal (the largest group) so we at least assign some burden
    local p_resp_`i' = p2
    local p_epilepsy_`i' = p3
  
    di "`p_abd_`i''  `p_resp_`i''  `p_epilepsy_`i''"
  }

// Multiply echinococcosis incidence and prevalence among with the proportions of sequelae
	use `pop_env', clear
	levelsof location_id, local(isos)
	levelsof sex, local(sexes)
	levelsof year, local(years)
	  
  foreach iso of local isos {
  foreach sex of local sexes {
  foreach year of local years {
    
    display in red "`iso' `year' `sex'"

  foreach metric in 5 6 {
    
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(1484) measure_ids(`metric') location_ids(`iso') year_ids(`year') sex_ids(`sex') source(epi) status(best) clear
    
	quietly drop if age_group_id > 21 //age > 80 yrs
    quietly keep draw_* age_group_id
    format draw* %16.0g
  
    foreach sequela in abd resp epilepsy {
      preserve
      forvalues i = 0/999 {
        quietly replace draw_`i' = draw_`i' * `p_`sequela'_`i''
      }
      quietly outsheet using "`tmp_dir'/`sequela'_prev/`metric'_`iso'_`year'_`sex'.csv", comma replace
      restore
    }

  } 
  }
  }
  }
*/

// Multiply echinococcosis incidence and prevalence among with the proportions of sequelae  
//With parallelization 
	use `pop_env', clear
	levelsof location_id, local(isos)
	levelsof year, local(years)
	  
  foreach iso of local isos {
  foreach sex in 1 2 {
  foreach year of local years {
  foreach metric in 5 6 {
  foreach sequela in abd resp epilepsy {
    ! qsub -N int_`sequela'_`metric'_`iso'_`sex'_`year' -pe multi_slot 2 -l mem_free=4 -P proj_custom_models "$prefix/WORK/10_gbd/00_library/functions/utils/stata_shell.sh" "$prefix/WORK/04_epi/01_database/02_data/ntd_echino/1484/04_models/gbd2015/01_code/sequelae_prev_inc_parallel.do" "`tmp_dir' `sequela' `metric' `iso' `sex' `year'"	
  }
	sleep 500   
  } 
  }
  }
  }


// save the results to the database
	quietly do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
	save_results, modelable_entity_id(1485) description("Abdominopelvic disease due to echino, derived from estimated clinical cases (dismod#`model_parent') and proportion of people with abdominopelvic localization of cysts (incl other localizations such as bone, skin, and muscle)") in_dir("`tmp_dir'/abd_prev") metrics(prevalence incidence) mark_best(yes)

	save_results, modelable_entity_id(1486) description("Respiratory disease due to echinococcosis, derived from echino envelope (dismod #`model_parent') and proportion of people with thoracic localization of cysts") in_dir("`tmp_dir'/resp_prev") metrics(prevalence incidence) mark_best(yes)

	save_results, modelable_entity_id(2796) description("Epilepsy due to echinococcosis, derived from echino envelope (dismod #`model_parent') and proportion of people with cerebral localization of cysts") in_dir("`tmp_dir'/epilepsy_prev") metrics(prevalence incidence) mark_best(yes)


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
	