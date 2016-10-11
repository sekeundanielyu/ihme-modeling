// Purpose: GBD 2015 Onchocerciasis Estimates
// Description:	Estimate Asymptomatic prevalence for onchocerciasis

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
  cap mkdir "`tmp_dir'/oncho_asymptomatic"
  cap mkdir "`tmp_dir'/2957_prev"
  cap mkdir "`tmp_dir'/2958_prev"
  cap mkdir "`tmp_dir'/3611_prev"

/*meids:
********
//oncho=1494, mild skin disease=1495, mod skin disease=1496, severe skin disease=2515, mod vision squeezed=2957, severe vision squeezed=2958, blindness super squeezed=3611, mild skin dis without itch=2620, severe skin dis without itch=2621
//mod vision unsqueezed=1497, severe vision unsqueezed=1498, blindness unsqueezed=1499
*/

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
  keep if inlist(year, 1990, 1995, 2000, 2005, 2010, 2015)
  keep if sex !=3
  sort location_id year age sex
  tempfile pop_env
  save `pop_env', replace

  // Append all oncho (and sequelae) draw files for all six Dismod years and save
  use `pop_env', clear
  keep if inlist(year, 1990, 1995, 2000, 2005, 2010, 2015)
  levelsof location_id, local(isos)
  levelsof year, local(years)

//Start with the me's that are in the folder, "~/cases":
    foreach var in "_parent" "disfigure_pain_1" "disfigure_1" "disfigure_pain_2" "disfigure_pain_3" "disfigure_3" {

      local n = 0
      
      foreach iso of local isos {
        
        display in red "`var' `iso'"
        
      foreach sex in 1 2 {
      foreach year in 1990 1995 2000 2005 2010 2015 {
      
        local res_dir "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_oncho/04_models/gbd2015/03_steps/2016_05_13/01_draws/03_outputs/01_draws/cases"
		quietly insheet using "`res_dir'/`var'/5_`iso'_`year'_`sex'.csv", clear double
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
      
      save "`out_dir'/`var'_prevalence_draws_dismodyears.dta", replace     
    }

//Then get draws for vision and append:
//mod vision squeezed=2957, severe vision squeezed=2958, blindness super squeezed=3611
//mod vision unsqueezed=1497, severe vision unsqueezed=1498, blindness unsqueezed=1499
/*
//Without parallelization of get_draws()
	foreach var in 2957 2958 3611 {	 //squeezed
      local n = 0
      
      foreach iso of local isos {
        
        display in red "`var' `iso'"
        
      foreach sex in 1 2 {
      foreach year in 1990 1995 2000 2005 2010 2015 {
		get_draws, gbd_id_field(modelable_entity_id) gbd_id(`var') measure_ids(5) location_ids(`iso') year_ids(`year') sex_ids(`sex') source(epi) status(best) clear		
        quietly drop if age_group_id > 21
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
      
      save "`out_dir'/`var'_prevalence_draws_dismodyears.dta", replace
      
    }
*/

//With parallelization of get_draws()
  foreach iso of local isos {
  foreach sex in 1 2 {
  foreach year of local years {
  foreach var in 2957 2958 3611 {
    ! qsub -N int_`var'_`iso'_`sex'_`year' -pe multi_slot 2 -l mem_free=4 -P proj_custom_models "$prefix/WORK/10_gbd/00_library/functions/utils/stata_shell.sh" "$prefix/WORK/04_epi/01_database/02_data/ntd_oncho/04_models/gbd2015/01_code/asymptomatic_parallel.do" "`tmp_dir' `var' `iso' `sex' `year'"	
  }
	sleep 500
  }
  }
  }

  use `pop_env', clear
  levelsof location_id, local(isos)
  
    foreach var in 2957 2958 3611 {	 //squeezed

      local n = 0
      
      foreach iso of local isos {
	  //foreach iso in 435 {          
        display in red "`var' `iso'"
        
      foreach sex in 1 2 {
      foreach year in 1990 1995 2000 2005 2010 2015 {
      
		//local res_dir "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_oncho/04_models/gbd2015/03_steps/2016_05_13/01_draws/03_outputs/01_draws/cases"
		quietly insheet using "`tmp_dir'/`var'_prev/5_`iso'_`year'_`sex'.csv", clear double
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
      
      save "`out_dir'/`var'_prevalence_draws_dismodyears.dta", replace
      
    }

////////////////////////////////////////////////////////////////////
//read in draw files and multiply by pop to get prevalent cases:
foreach var in "_parent" "disfigure_pain_1" "disfigure_1" "disfigure_pain_2" "disfigure_pain_3" "disfigure_3" 2957 2958 3611 {
		use "/home/j/WORK/04_epi/01_database/02_data/ntd_oncho/04_models/gbd2015/03_steps/2016_05_20/03_asymptomatic/`var'_prevalence_draws_dismodyears.dta", replace
		destring location_id, replace
		destring sex, replace
		
		joinby location_id year age_group_id sex using "`pop_env'", unmatched(none)
		forvalues x=0/999 {
			quietly replace draw_`x' = draw_`x' * pop
		}		
		
		tempfile `var'_draws
		save ``var'_draws', replace
}
//multiply all draws to be subtracted by (-1)
foreach var in "disfigure_pain_1" "disfigure_1" "disfigure_pain_2" "disfigure_pain_3" "disfigure_3" 2957 2958 3611 {
	use ``var'_draws', replace
	forvalues x=0/999 {
		quietly replace draw_`x' = -1 * draw_`x'
	}
	save ``var'_draws', replace
}

//scale vision loss estimates: ask Daniel Dicker where 8/33 came from
foreach var in 2957 2958 3611 {
	use ``var'_draws', replace
	forvalues x=0/999 {
		quietly replace draw_`x' = draw_`x' * 8/33
	}
	save ``var'_draws', replace
}

	use "`_parent_draws'", replace
	append using "`disfigure_pain_1_draws'"
	append using "`disfigure_1_draws'"
	append using "`disfigure_pain_2_draws'"
	append using "`disfigure_pain_3_draws'"
	append using "`disfigure_3_draws'"
	append using "`2957_draws'"
	append using "`2958_draws'"
	append using "`3611_draws'"
	
	fastcollapse draw_*, by(location_id year age_group_id sex) type(sum)
	joinby location_id year age_group_id sex using "`pop_env'", unmatched(none)
	//divide by pop to get prevalence (rates)
	forvalues x=0/999 {
			quietly replace draw_`x' = draw_`x'/pop
			quietly replace draw_`x' = 0 if draw_`x' < 0
			quietly replace draw_`x' = 1 if draw_`x' > 1
		}

	save "`tmp_dir'/oncho_asymptomatic/oncho_asympt_draws.dta", replace
	
// Prep data for looping
  //local asympt_dir "`tmp_dir'/oncho_asymptomatic"
  local asympt_dir "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_oncho/04_models/gbd2015/03_steps/2016_05_20/03_asymptomatic/03_outputs/01_draws/oncho_asymptomatic"
  
  use "`asympt_dir'/oncho_asympt_draws.dta", replace
  levelsof location_id, local(isos)
   
// Loop through sex, location_id, and year, keep only the relevant data, and outsheet the .csv of interest: prevalence (measue id 5)
	  foreach iso of local isos {
		use "`asympt_dir'/oncho_asympt_draws.dta", replace
		quietly keep if location_id == `iso'
		display in red `iso'
		
		foreach sex in 1 2 {
		  foreach y in 1990 1995 2000 2005 2010 2015 {
		  
		  preserve
          quietly keep if sex == `sex' & year == `y'
		  keep age_group_id draw*
		  sort age_group_id
		  format %16.0g draw_*
          quietly outsheet using "`asympt_dir'/5_`iso'_`y'_`sex'.csv", comma replace
          
		  restore		  
		  }
	    }
		
	  }	

// Send results to central database
  quietly do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
  save_results, modelable_entity_id(3107) description("Asymptomatic Oncho = mf_cases - (all disfigurement + squeezed vision*8/33)") in_dir("`asympt_dir'") metrics(prevalence) mark_best(yes)

 *********************************************************************************************************************************************************************
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