// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global
// Description:	Correct dismod output for pre-control prevalence of infection and morbidity for the effect of mass treatment, and scale
// 				to the national level (dismod model is at level of population at risk).
// include "/home/j/WORK/04_epi/01_database/02_data/ntd_lf/1491/04_models/gbd2015/01_code/dev/01_prev_sequela_parallel.do"

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
	
	// Define arguments
	if "`1'" != "" {
		local location_id `1' 
		local tmp_in_dir `2' 
		local out_dir `3'
		local out_dir_infection `4' 
		local out_dir_lymphedema `5' 
		local out_dir_hydrocele `6'
	}
	else if "`1'" == "" {
		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
		local date = subinstr("`date'"," ","_",.)
		local location_id 522
		local tmp_in_dir "/ihme/gbd/WORK//04_epi/01_database/02_data/ntd_lf/1491/04_models/gbd2015/03_steps/`date'/01_prev_sequela/02_inputs"
		local out_dir "$prefix/WORK/04_epi/01_database/02_data/ntd_lf/1491/04_models/gbd2015/03_steps/`date'/01_prev_sequela"
		local out_dir_infection "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_lf/1491/04_models/gbd2015/03_steps/`date'/01_prev_sequela/03_outputs/01_draws/cases"
		local out_dir_lymphedema "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_lf/1492/04_models/gbd2015/03_steps/`date'/01_prev_sequela/03_outputs/01_draws/cases"
		local out_dir_hydrocele "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_lf/1493/04_models/gbd2015/03_steps/`date'/01_prev_sequela/03_outputs/01_draws/cases"
	}

// *********************************************************************************************************************************************************************
// Import functions
	run "$prefix/WORK/10_gbd/00_library/functions/get_draws.ado"
	run "$prefix/WORK/10_gbd/00_library/functions/get_demographics.ado"
	run "$prefix/WORK/10_gbd/00_library/functions/fastcollapse.ado"
	
// *********************************************************************************************************************************************************************
    
// Create draw file with zeroes for non-endemic countries
  clear
  set obs 20
  gen age_group_id = _n + 1
  gen measure_id = 5
  forvalue i = 0/999 {
    quietly gen draw_`i' = 0
  }
  tempfile zeroes
  quietly save `zeroes', replace

// By country-year-sex, pull draw files and correct prevalence of infection and morbidity for effect of mass treatment and scale to national level
  // Get demographics
	get_demographics , gbd_team(epi) clear
	
  // Mf prevalence
	use "`tmp_in_dir'/loc_met.dta" if location_id == `location_id', clear
	levelsof ihme_loc_id, local(iso3) c
    foreach sex_id of global sex_ids {
    foreach year_id of global year_ids {
      
      display "`iso3' `year_id' `sex_id' mf prevalence" 
      
    // Pull draw file (measure_id for prevalence is 5)
	  get_draws, gbd_id_field(modelable_entity_id) gbd_id(1491) measure_ids(5) location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') source(epi) clear
      
      keep *_id draw_*
      
      quietly keep if age_group_id >= 2 & age_group_id <= 21
      
      quietly merge m:1 year_id location_id using "`tmp_in_dir'/prop_at_risk.dta", keepusing(prop_at_risk) keep(master match) nogen
      
    // Check if there is population at risk. If not, output zeroes; otherwise, correct for effect of mass treatment
      quietly summarize prop_at_risk
      if r(mean) == 0 {
        use `zeroes', clear
		gen sex_id = `sex_id'
		gen year_id = `year_id'
		gen location_id = `location_id'
		gen modelable_entity_id = 1491
		order location_id year_id age_group_id sex_id modelable_entity_id measure_id draw*
        quietly outsheet using "`out_dir_infection'/5_`location_id'_`year_id'_`sex_id'.csv", comma replace
      }
      else {
        
      // If post/during control, correct prevalence for effect of mass treatment (if any).
        if `year_id' > 2000 {
          quietly merge m:1 year_id location_id using "`tmp_in_dir'/coverage.dta", keepusing(effect_inf_*) keep(master match) nogen
          forvalues i = 0/999 {
            quietly replace draw_`i' = draw_`i' * effect_inf_`i'
          }
        }
        
      // Scale prevalence to national level and set to zero for age < 1
        forvalues i = 0/999 {
          quietly replace draw_`i' = draw_`i' * prop_at_risk
          quietly replace draw_`i' = 0 if age_group_id < 5
        }
		capture gen modelable_entity_id = 1491
		capture gen measure_id = 5
        quietly keep location_id year_id age_group_id sex_id modelable_entity_id measure_id draw*
		order location_id year_id age_group_id sex_id modelable_entity_id measure_id draw*
        quietly outsheet using "`out_dir_infection'/5_`location_id'_`year_id'_`sex_id'.csv", comma replace
      }
    }
    }
    
  // Prevalence of hydrocele
    foreach sex_id of global sex_ids {
    foreach year_id of global year_ids {
  
      display "`iso3' `year_id' `sex_id' prevalence of hydrocele"
    
    // Check sex; if female, output zeroes; if male, continue.
      if `sex_id' == 2 {
        use `zeroes', clear
		gen sex_id = `sex_id'
		gen year_id = `year_id'
		gen location_id = `location_id'
		gen modelable_entity_id = 1493
        quietly keep location_id year_id age_group_id sex_id modelable_entity_id measure_id draw*
		order location_id year_id age_group_id sex_id modelable_entity_id measure_id draw*
        quietly outsheet using "`out_dir_hydrocele'/5_`location_id'_`year_id'_`sex_id'.csv", comma replace
      }
      else {
      
      // Pull and prep mf draw files for both sexes to calculate total crude mf prevalence (used for calculating hydrocele envelope)
        foreach s of global sex_ids {
        
        // Pull and prep mf draw file
		  get_draws, gbd_id_field(modelable_entity_id) gbd_id(1491) measure_ids(5) location_ids(`location_id') year_ids(`year_id') sex_ids(`s') source(epi) clear
        
		  keep *_id draw_*
		  
		  quietly keep if age_group_id >= 2 & age_group_id <= 21
          
        // Calculate crude mf prevalence in general population, assuming that blood surveys include only ages >= 1.
          quietly merge 1:1 location_id age_group_id year_id sex_id using "`tmp_in_dir'/pops.dta", keepusing(pop_scaled) keep(master match) nogen
          forvalues i = 0/999 {
            quietly replace draw_`i' = draw_`i' * pop_scaled
            quietly replace draw_`i' = 0 if age_group_id < 5
          }
          
          quietly replace pop_scaled = 0 if age_group_id < 5
          
          quietly fastcollapse pop_scaled draw*, type(sum) by(sex_id)
          
          local pop_all_`s' = pop_scaled
          drop sex_id pop_scaled
          
          xpose, clear promote
          format %16.0g *
          rename v1 mf_cases_`s'
          generate pop_`s' = `pop_all_`s''
          generate index = _n
          
          tempfile temp_mf_`s'
          quietly save `temp_mf_`s'', replace
        }
        
      // Calculate total prevalence of hydrocele in population
        use `temp_mf_1', clear
        quietly merge 1:1 index using `temp_mf_2', nogen
        
        generate pop_all = pop_1 + pop_2
        generate mf_cases_all = mf_cases_1 + mf_cases_2
        generate double mf_prev = mf_cases_all / pop_all
        
        local pop_all = pop_all
        
        quietly merge 1:1 index using "`tmp_in_dir'/hyd_regression.dta", nogen
        
        quietly replace mf_prev = (a + b * mf_prev ^ c) / (1 + b * mf_prev ^ c)
        rename mf_prev prev_envelope
        
        drop a b c
        
        tempfile hyd_envelope_draws
        quietly save `hyd_envelope_draws', replace
        
      // Squeeze dismod age pattern draws into envelope draws
		get_draws, gbd_id_field(modelable_entity_id) gbd_id(1493) measure_ids(5) location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') source(epi) clear
        
		keep *_id draw_*
		  
		quietly keep if age_group_id >= 2 & age_group_id <= 21
        
        quietly merge 1:1 location_id age_group_id year_id sex_id using "`tmp_in_dir'/pops.dta", keepusing(pop_scaled) keep(master match) nogen
        quietly merge m:1 year_id location_id using "`tmp_in_dir'/prop_at_risk.dta", keepusing(prop_at_risk) keep(master match) nogen
    
        quietly set obs 1000
        generate int index = _n
        quietly merge 1:1 index using `hyd_envelope_draws', nogen
    
        forvalues i = 0/999 {
          // Calculate unscaled number of hydrocele cases by age, according to dismod (assume zero hydrocele under age 5)
            quietly replace draw_`i' = draw_`i' * pop_scaled
            quietly replace draw_`i' = 0 if age_group_id < 6
            
          // Create r(sum) containing total unscaled cases, according to dismod
            quietly summarize draw_`i', detail
          
          // Calculate prevalence scaled to population at risk, using scaling factor [envelope draw ] / [unscaled dismod cases draw]
            quietly replace draw_`i' = (draw_`i' / pop_scaled) * (prev_envelope[`i'+1] * `pop_all_`sex_id'') / r(sum)
            quietly replace draw_`i' = 1 if draw_`i' > 1
        }
        
        quietly drop if missing(age_group_id) |  age_group_id > 21 |  age_group_id < 2
     
      // Temporarily store draw file if next iteration of this loop is going to be a post-control year.
      // This file contains hydrocele prevalence draws scaled to the hydrocele envelope at the level
      // of population at risk.
        if `year_id' == 2000 {
          tempfile hyd_draws_`location_id'_2000_1
          quietly save `hyd_draws_`location_id'_2000_1', replace
        }
        if `year_id' > 2000 {
          
        // Pull hydrocele prevalence at level of population at risk in 2000, and correct for effect of mass treatment
          quietly use `hyd_draws_`location_id'_2000_1', clear 
          
          drop prop_at_risk
          quietly replace year_id = `year_id'
          
          quietly merge m:1 year_id location_id using "`tmp_in_dir'/prop_at_risk.dta", keepusing(prop_at_risk) keep(master match) nogen
          quietly merge m:1 year_id location_id using "`tmp_in_dir'/coverage.dta", keepusing(effect_hyd*) keep(master match) nogen
          
          forvalues i = 0/999 {
            quietly replace draw_`i' = draw_`i' * effect_hyd_`i'
          }
          
        }
        
      // Scale prevalence to national level and set to zero for age < 1
        forvalues i = 0/999 {
          quietly replace draw_`i' = draw_`i' * prop_at_risk
          quietly replace draw_`i' = 0 if age_group_id < 5
        }
        
		capture gen modelable_entity_id = 1491
		capture gen measure_id = 5
        quietly keep location_id year_id age_group_id sex_id modelable_entity_id measure_id draw*
		order location_id year_id age_group_id sex_id modelable_entity_id measure_id draw*
        quietly outsheet using "`out_dir_hydrocele'/5_`location_id'_`year_id'_`sex_id'.csv", comma replace
        
      }
      
    }
    }

  // Prevalence of lymphedema
    foreach year_id of global year_ids {
  
      display "`iso3' `year_id' prevalence of lymphedema"
      
    // If this is a pre-control year (<2000, or <1995 for China), predict pre-control lymphedema prevalence from mf prevalence
      if (`year_id' <= 2000 & !regexm("`iso3'", "CHN")) | (`year_id' == 1990 & regexm("`iso3'", "CHN")) {
      // Calculate lymphedema envelope as function of pre-control mf prevalence draws
        foreach sex_id of global sex_ids {
        
        // Pull and prep mf draw file
		  get_draws, gbd_id_field(modelable_entity_id) gbd_id(1491) measure_ids(5) location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') source(epi) clear
        
		  keep *_id draw_*
		  
		  quietly keep if age_group_id >= 2 & age_group_id <= 21
          
        // Calculate crude mf prevalence in general population, assuming that blood surveys include only ages >= 1.
          quietly merge 1:1 location_id age_group_id year_id sex_id using "`tmp_in_dir'/pops.dta", keepusing(pop_scaled) keep(master match) nogen
          
          forvalues i = 0/999 {
            quietly replace draw_`i' = draw_`i' * pop_scaled
            quietly replace draw_`i' = 0 if age_group_id < 5
          }
          
          quietly replace pop_scaled = 0 if age_group_id < 5
          
          quietly fastcollapse pop_scaled draw*, type(sum) by(sex)
          
          local pop_all_`sex_id' = pop_scaled
          drop sex pop_scaled
          
          xpose, clear promote
          format %16.0g *
          rename v1 mf_cases_`sex_id'
          generate pop_`sex_id' = `pop_all_`sex_id''
          generate index = _n
          
          tempfile temp_mf_`sex_id'
          quietly save `temp_mf_`sex_id'', replace
        }
        
        // Calculate total prevalence of lymphedema in population
          use `temp_mf_1', clear
          quietly merge 1:1 index using `temp_mf_2', nogen
          
          generate pop_all = pop_1 + pop_2
          generate mf_cases_all = mf_cases_1 + mf_cases_2
          generate double mf_prev = mf_cases_all / pop_all
          
          local pop_all = pop_all
          
          quietly merge 1:1 index using "`tmp_in_dir'/oed_regression.dta", nogen
          
          quietly replace mf_prev =  (a + b * mf_prev ^ c) / (1 + b * mf_prev ^ c)
          rename mf_prev prev_envelope
          
          keep index prev_envelope
          
          tempfile oed_envelope_draws
          quietly save `oed_envelope_draws', replace
        
      // Squeeze dismod age pattern draws into envelope draws
        foreach sex_id of global sex_ids {
        
		  get_draws, gbd_id_field(modelable_entity_id) gbd_id(1492) measure_ids(5) location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') source(epi) clear
        
		  keep *_id draw_*
		  
		  quietly keep if age_group_id >= 2 & age_group_id <= 21
          
          quietly merge 1:1 location_id age_group_id year_id sex_id using "`tmp_in_dir'/pops.dta", keepusing(pop_scaled) keep(master match) nogen
          quietly merge m:1 year_id location_id using "`tmp_in_dir'/prop_at_risk.dta", keepusing(prop_at_risk) keep(master match) nogen
          
          tempfile temp_dismod_`sex_id'
          quietly save `temp_dismod_`sex_id'', replace
          
        }
        
        use `temp_dismod_1', clear
        append using `temp_dismod_2'
        
        quietly set obs 1000
        generate int index = _n
        quietly merge 1:1 index using `oed_envelope_draws', nogen
        
        forvalues i = 0/999 {
          // Calculate unscaled number of lymphedema cases by age and sex, according to dismod (assume zero lymphedema in age <5)
            quietly replace draw_`i' = draw_`i' * pop_scaled
            quietly replace draw_`i' = 0 if age_group_id < 6
            
          // Create r(sum) containing total unscaled cases, according to dismod
            quietly summarize draw_`i', detail
          
          // Calculate prevalence scaled to population at risk, using scaling factor [envelope draw ] / [unscaled dismod cases draw]
            quietly replace draw_`i' = (draw_`i' / pop_scaled) * (prev_envelope[`i'+1] * `pop_all') / r(sum)
            quietly replace draw_`i' = 1 if draw_`i' > 1
        }
        
        quietly drop if missing(age_group_id) | age_group_id > 21 | age_group_id < 2
        quietly keep sex_id age_group_id location_id year_id draw* prop_at_risk
        
      // Temporarily store draw file if next iteration of this loop is going to be a post-control year.
      // This file contains lymphedema prevalence draws scaled to the envelope at the level of
      // population at risk.
        if `year_id' == 1990 & regexm("`iso3'", "CHN") {
          tempfile oed_draws_`location_id'_1990
          quietly save `oed_draws_`location_id'_1990', replace
        }
        if `year_id' == 2000 & !regexm("`iso3'", "CHN") {
          tempfile oed_draws_`location_id'_2000
          quietly save `oed_draws_`location_id'_2000', replace
        }
        
      }
      else {
      // I.e. if this is a post-control year, correct for affect of mass treatment, assuming zero excess mortality in general 
      // and zero incidence of lymphedema among the treated proportion of the population (average coverage over last 5 years).
        if `year_id' == 1995 & regexm("`iso3'", "CHN") {
          use  `oed_draws_`location_id'_1990', clear
        }
        if `year_id' == 2000 & regexm("`iso3'", "CHN") {
          use  `oed_draws_`location_id'_1995', clear
        }
        if `year_id' == 2005 {
          use  `oed_draws_`location_id'_2000', clear
        }
        if `year_id' == 2010 {
          use  `oed_draws_`location_id'_2005', clear
        }
        if `year_id' == 2015 {
          use  `oed_draws_`location_id'_2010', clear
        }
        
        drop prop_at_risk
        
        if !regexm("`iso3'", "CHN") {
          quietly replace year_id = `year_id'
          quietly merge m:1 year_id location_id using "`tmp_in_dir'/coverage.dta", keepusing(cov_avg5) keep(master match) nogen
          quietly merge m:1 year_id location_id using "`tmp_in_dir'/prop_at_risk.dta", keepusing(prop_at_risk) keep(master match) nogen
        }
        else {
          quietly replace year_id = `year_id'
          quietly merge m:1 year_id location_id using "`tmp_in_dir'/coverage.dta", keepusing(cov_avg5) keep(master match) nogen
          quietly replace cov_avg5 = 1  // Implies no active transmission (China has eliminated LF infection by 1995, but
                                        // there will still be cases of lymphedema after 1995, as this is a chronic condition.
          quietly replace year_id = 1990           // Otherwise the proportion will be zero, and the final number will be zero!
          quietly merge m:1 year_id location_id using "`tmp_in_dir'/prop_at_risk.dta", keepusing(prop_at_risk) keep(master match) nogen
        }
        
        gsort sex_id -age_group_id
        forvalues i = 0/999 {
          quietly bysort sex_id: replace draw_`i' = (1 - cov_avg5) * draw_`i' + cov_avg5 * draw_`i'[_n+1] if _n < _N
          quietly bysort sex_id: replace draw_`i' = (1 - cov_avg5) * draw_`i' if _n == _N
        }
        sort sex_id age_group_id
        quietly keep sex_id age_group_id location_id year_id draw* prop_at_risk
        
      // Store draws in tempfiles, so that calculations for next post-control years can take off from there
        if `year_id' == 1995 & regexm("`iso3'", "CHN") {
          tempfile oed_draws_`location_id'_1995
          quietly save `oed_draws_`location_id'_1995', replace
        }
        if `year_id' == 2000 & regexm("`iso3'", "CHN") {
          tempfile oed_draws_`location_id'_2000
          quietly save `oed_draws_`location_id'_2000', replace
        }
        if `year_id' == 2005 {
          tempfile oed_draws_`location_id'_2005
          quietly save `oed_draws_`location_id'_2005', replace
        }
        if `year_id' == 2010 {
          tempfile oed_draws_`location_id'_2010
          quietly save `oed_draws_`location_id'_2010', replace
        }
      }

      // Scale prevalence to national level and set to zero for age < 1
        forvalues i = 0/999 {
          quietly replace draw_`i' = draw_`i' * prop_at_risk
          quietly replace draw_`i' = 0 if age_group_id < 5
        }
        
      // Write draw files to clustertmp
        foreach sex_id of global sex_ids {
            preserve
              quietly keep if sex_id == `sex_id'
			  quietly keep age_group_id sex_id draw*
			  gen modelable_entity_id = 1492
			  gen measure_id = 5
			  gen year_id = `year_id'
			  gen location_id = `location_id'
			  order location_id year_id age_group_id sex_id modelable_entity_id measure_id draw*
			  quietly outsheet using "`out_dir_lymphedema'/5_`location_id'_`year_id'_`sex_id'.csv", comma replace
            restore
        }
	}

// *********************************************************************************************************************************************************************
