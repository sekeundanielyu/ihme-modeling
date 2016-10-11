// Purpose: GBD 2015 Soil Transmitted Helminthiasis (STH) Estimates
// Description:	Calculate the prevalence of wasting due to STH, and prevalence of protein energy malnutrition (PEM), from the wasting envelope

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

// *************************************************************************************
// *************************************************************************************
// Specify paths for saving wasting draws
  
  cap mkdir "`tmp_dir'/ascar_wast"
  cap mkdir "`tmp_dir'/trich_wast"
  cap mkdir "`tmp_dir'/hook_wast"
  
  cap mkdir "`tmp_dir'/pem_wast"
  

// Path of draws for heavy infestation
  local heavy_dir "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_nema/04_models/gbd2015/03_steps/2016_05_12/01_prev_extrap_gbd_2010/03_outputs/01_draws"

// Path of wasting envelope
  local wast_env "/home/j/WORK/05_risk/risks/nutrition_wasting/01_exposure/PEM_wasting/02_output/wasting_prev_by_age_sex_16Jun2016.dta"
  
// Z-score change in weight size per heavy prevalent case.
// Rashmi calculated this based on the Hall et al paper.
	local effsize = .493826493	
	local effsize_l =	.389863021
	local effsize_u =	.584794532
  
  local effsize_sd = (`effsize_u' - `effsize_l') / (2*invnorm(0.975))
  
  forvalues i = 0/999 {
    local z_change_`i' = `effsize' + rnormal() * `effsize_sd'
  }

// Prep wasting data  
  use "`wast_env'", clear
  forvalues i = 0/999 {
      quietly rename draw_`i'cat1 draw`i'
    }

  recast double draw*
  format %16.0g age_group_id draw*
  rename draw* wast_*
  rename year_id year

  keep ihme_loc_id location_id year sex age* wast_*
  
  // Hardcode developed countries to zero wasting
    generate developed = 0
    foreach iso in ALA AND ARG AUS AUT BEL BRN CAN CHE CHL CYP DEU DNK ESP FIN FLK FRA FRO GBR GGY GIB GRC GRL IMN IRL ISL ISR ITA JEY JPN KOR LIE LUX MCO MLT NLD NOR NZL PRT SGP SJM SMR SPM SWE URY USA VAT GBR_4618 GBR_4619 GBR_4620 GBR_4621 GBR_4622 GBR_4623 GBR_4624 GBR_4625 GBR_4626 GBR_4636 GBR_433 GBR_434 GRL{
      quietly replace developed = 1 if ihme_loc_id == "`iso'"
    }
	
	//For GBD 2015, added the subnationals for developed and GRL
	replace developed = 1 if regexm(ihme_loc_id, "GBR")
	replace developed = 1 if regexm(ihme_loc_id, "JPN")
	replace developed = 1 if regexm(ihme_loc_id, "SWE")
	replace developed = 1 if regexm(ihme_loc_id, "USA")
	
    forvalues i = 0/999 {
      quietly replace wast_`i' = 0 if developed == 1
    }
  
  tempfile wast_draws
  quietly save `wast_draws', replace
  
  levelsof location_id, local(isos)
  foreach i of local isos {
  
    use `wast_draws' if location_id == `i', clear
    //drop iso3
    
    tempfile wast_`i'
    quietly save `wast_`i'', replace
 
  }
  
// Zeroes files for ages 5+ (age_group_id 6+)
  clear
  set obs 16
  generate double age = .
  generate double age_group_id = .
  forvalues i = 0/999 {
    generate double draw_`i' = 0
  }
  format %16.0g age* draw*
  replace age = _n * 5
  replace age_group_id = _n + 5
  
  tempfile zeroes
  save `zeroes', replace
  
// Calculate prevalence of wasting due to heavy worm infestation, based on total heavy worm
// infestation. This loop assumes that wasting draw files contain ages 0, 0.01, 0.1, and 1 (corresp age_group_ids: 2,3,4,5); heavy
// worm infestation files contain ages 0.1 and above; and all draw files contain 1K draws.

  use `wast_draws', replace
  keep if inlist(year,1990,1995,2000,2005,2010,2015)
  levelsof location_id, local(isos)
  levelsof sex, local(sexes)
  levelsof year, local(years)  

  foreach iso of local isos {
  foreach year of local years {
  foreach sex of local sexes { 
    
    display in red "`iso' `year' `sex'"
    
  // Pull heavy infestation files for all worm species
    foreach cause in ascar trich hook {
      quietly insheet using "`heavy_dir'/`cause'_inf_heavy/5_`iso'_`year'_`sex'.csv", double clear
      
	  quietly keep if age_group_id > 3 & age_group_id < 6 // age > 0.09 & age < 1.1
      recast double draw*
      format %16.0g age_group_id draw_*
      generate cause = "`cause'"
      
      tempfile `cause'_temp
      quietly save ``cause'_temp', replace
    }
    
    use `ascar_temp', clear
    append using `trich_temp'
    append using `hook_temp'
    
    tempfile heavy_separate
    quietly save `heavy_separate', replace
    
    
  // Sum up prevalences of individual worm prevalences
    quietly fastcollapse draw*, by(age_group_id) type(sum)
    
    forvalues i = 0/999 {
      quietly replace draw_`i' = 1 if draw_`i' > 1
    }
    
    tempfile heavy_sum
    quietly save `heavy_sum', replace
    
    
  // Create proportions for later split up of total wasting due to heavy infestation
    use `heavy_sum', clear
    rename draw_* total_*
    quietly merge 1:m age_group_id using `heavy_separate', nogen
    
    forvalues i = 0/999 {
      quietly replace draw_`i' = draw_`i' / total_`i'
    }
    
    rename draw_* prop_*
    quietly drop total_*
    
    tempfile prop
    quietly save `prop', replace
    
    
  // Calculate total wasting due to heavy worm infection
    use `heavy_sum', clear
    rename draw_* worm_*
    if `sex' == 1 {
      generate sex = 1
      local s = 1
    }
    else {
      generate sex = 2
      local s = 2
    }
	
    generate year = `year'
    quietly merge 1:1 age_group_id sex year using `wast_`iso'', nogen
    
    quietly keep if year == `year' & sex == `s'

    forvalues i = 0/999 {
    // Prev of wasting due to worms as function of change in z-score
      quietly replace worm_`i' = wast_`i' - normal(invnormal(wast_`i') - `z_change_`i'' * worm_`i') if !missing(worm_`i')
      quietly replace worm_`i' = 0 if missing(worm_`i') | wast_`i' == 0
    // Prev of wasting due to PEM
      quietly replace wast_`i' = wast_`i' - worm_`i' if !missing(worm_`i') & worm_`i' > 0
    }
    
    tempfile wast_split
    quietly save `wast_split', replace
  
  
  // Split off and save wasting due to PEM draws
    keep age_group_id wast_*
    rename wast_* draw_*
    
    append using `zeroes'
    
    quietly outsheet using "`tmp_dir'/pem_wast/5_`iso'_`year'_`sex'.csv", comma replace
    
  // Attribute wasting to different worm species and write draw files
    use `wast_split', clear
    keep age_group_id worm_*
    
    quietly merge 1:m age_group_id using `prop', keep(master match) nogen
    
    forvalues i = 0/999 {
      quietly replace prop_`i' = prop_`i' * worm_`i'
      quietly replace prop_`i' = 0 if missing(prop_`i')
    }
    rename prop_* draw_*
    drop worm_*
    
    foreach cause in ascar trich hook {
      preserve
        quietly keep if cause == "`cause'" | missing(cause)
        quietly append using `zeroes'
		keep age_group_id draw_*
        quietly outsheet using "`tmp_dir'/`cause'_wast/5_`iso'_`year'_`sex'.csv", comma replace
      restore
    }
    
  }
  }
  }

  
*********************************************************************
// Send results to central database
  save_results, modelable_entity_id(1515) description("Wasting due to ascariasis") in_dir("`tmp_dir'/ascar_wast") metrics(prevalence) mark_best(yes)
  
  save_results, modelable_entity_id(1518) description("Wasting due to trichuriasis") in_dir("`tmp_dir'/trich_wast") metrics(prevalence) mark_best(yes)
  
  save_results, modelable_entity_id(1521) description("Wasting due to hookworm") in_dir("`tmp_dir'/hook_wast") metrics(prevalence) mark_best(yes)

  save_results, modelable_entity_id(1608) description("Wasting due to PEM based on updated worm and wasting estimates. Developed countries hardcoded to zero") in_dir("`tmp_dir'/pem_wast") metrics(prevalence) mark_best(yes)

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
