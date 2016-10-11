// Purpose: GBD 2015 Soil Transmitted Helminthiasis (STH) Estimates
// Description:	Estimate Asymptomatic prevalence for each STH

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

// Specify paths for saving draws
    cap mkdir "`tmp_dir'/ascar_asymptomatic"
    cap mkdir "`tmp_dir'/hook_asymptomatic"
    cap mkdir "`tmp_dir'/trich_asymptomatic"

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
  keep age age_group_id sex year ihme_loc_id parent location_name location_id location_type region_name envelope pop
  keep if inlist(location_type, "admin0","admin1","admin2","nonsovereign", "subnational", "urbanicity")

   replace age = "0" if age=="EN"
   replace age = "0.01" if age=="LN"
   replace age = "0.1" if age=="PN"
   drop if age=="All" | age == "<5"
   keep if age_group_id <= 22
   destring age, replace
  
  keep location_id year age_group_id sex pop
  sort location_id year age sex
  tempfile pop_env
  save `pop_env', replace
 

  // Append all STH draw files for all six Dismod years and save
  use `pop_env', clear
  levelsof location_id, local(isos)
  
    foreach cause in ascar hook trich {
    foreach intensity in inf_all inf_heavy inf_med {
    
      local n = 0
      
      foreach iso of local isos {
        
        display in red "`cause' `intensity' `iso'"
        
      foreach sex in 1 2 {
      foreach year in 1990 1995 2000 2005 2010 2015 {
      
        local res_dir "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_nema/04_models/gbd2015/03_steps/2016_05_12/01_prev_extrap_gbd_2010/03_outputs/01_draws"
		quietly insheet using "`res_dir'/`cause'_`intensity'/5_`iso'_`year'_`sex'.csv", clear double
        quietly keep age_group_id draw*
        
        generate location_id = "`iso'"
        generate sex = "`sex'"
        generate year = `year'
        
        local ++n
        tempfile `n'
        quietly save ``n'', replace
        
      }
      }
      }
      
      clear
      forvalues i = 1/`n' {
        append using ``i''
      }
      
      save "`in_dir'/`cause'_`intensity'_prevalence_draws_dismodyears.dta", replace
      
    }
    }

//////////////////////////////////////////////////////////////////
foreach cause in ascar hook trich {
	foreach intensity in inf_all inf_heavy inf_med {
		use "`in_dir'/`cause'_`intensity'_prevalence_draws_dismodyears.dta", replace
		destring location_id, replace
		destring sex, replace
		joinby location_id year age_group_id sex using "`pop_env'", unmatched(none)
		forvalues x=0/999 {
			quietly replace draw_`x' = draw_`x' * pop	//to get prevalent cases
		}		
		tempfile `cause'_`intensity'_draws
		save ``cause'_`intensity'_draws', replace
	}
}	


foreach cause in ascar hook trich {
	foreach intensity in inf_heavy inf_med {
		use ``cause'_`intensity'_draws', replace
		forvalues x=0/999 {
			quietly replace draw_`x' = -1 * draw_`x'
		}
		save ``cause'_`intensity'_draws', replace
	}
}


foreach cause in ascar hook trich {
	use ``cause'_inf_all_draws', replace
	append using ``cause'_inf_heavy_draws'
	append using ``cause'_inf_med_draws'
	
	fastcollapse draw_*, by(location_id year age_group_id sex) type(sum)
	joinby location_id year age_group_id sex using "`pop_env'", unmatched(none)
	forvalues x=0/999 {
			quietly replace draw_`x' = draw_`x'/pop	//to get prevalence (proportions)
			quietly replace draw_`x' = 0 if draw_`x' < 0
			quietly replace draw_`x' = 1 if draw_`x' > 1
		}
	save "`tmp_dir'/`cause'_asymptomatic/`cause'_asympt_draws.dta", replace 
	}
	
// Prep data for looping
  local asympt_dir "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_nema/04_models/gbd2015/03_steps/2016_05_19/05_asymptomatic/03_outputs/01_draws"

  use "`asympt_dir'/ascar_asymptomatic/ascar_asympt_draws.dta", replace
  levelsof location_id, local(isos)
   
// Loop through sex, location_id, and year, keep only the relevant data, and outsheet the .csv of interest: prevalence (measue id 5)	
    foreach cause in ascar trich {
	  
    // Set location where draws are saved
      local save_dir "`asympt_dir'/`cause'_asymptomatic"

	  foreach iso of local isos {
		use "`asympt_dir'/`cause'_asymptomatic/`cause'_asympt_draws.dta", replace
		quietly keep if location_id == `iso'
		display in red `iso'
		
		foreach sex in 1 2 {
		  foreach y in 1990 1995 2000 2005 2010 2015 {
		  
		  preserve
          quietly keep if sex == `sex' & year == `y'
		  keep age_group_id draw*
		  sort age_group_id
		  format %16.0g draw_*
          quietly outsheet using "`save_dir'/5_`iso'_`y'_`sex'.csv", comma replace
          
		  restore		  
		  }
	    }
		
	  }
	}	

// Send results to central database
  quietly do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
  save_results, modelable_entity_id(3109) description("Asymptomatic Ascariasis = ascar_all - (ascar_heavy + ascar_med)") in_dir("`asympt_dir'/ascar_asymptomatic") metrics(prevalence) mark_best(yes)
  
  save_results, modelable_entity_id(3110) description("Asymptomatic Trichuriasis = trich_all - (trich_heavy + trich_med)") in_dir("`asympt_dir'/trich_asymptomatic") metrics(prevalence) mark_best(yes)
 
  save_results, modelable_entity_id(3111) description("Asymptomatic Hookworm = hook_all - (hook_heavy + hook_med)") in_dir("`tmp_dir'/hook_asymptomatic") metrics(prevalence) mark_best(yes)

//
 *********************************************************************************************************************************************************************
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