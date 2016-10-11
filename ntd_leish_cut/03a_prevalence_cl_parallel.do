// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global
// Description: Generate prevalence of VL cases, based on incidence as predicted by DisMod and duration from literature
// Location: /home/j/WORK/04_epi/01_database/02_data/ntd_leish/1458_1459_1460_1461/04_models/gbd2015/01_code/dev/03a_prevalence_cl_parallel.do

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

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
		local save_dir `3'
	}
	else if "`1'" == "" {
		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
		local date = subinstr("`date'"," ","_",.)
		local location_id 43911
		local tmp_in_dir "/ihme/gbd/WORK/04_epi/02_models/02_results/ntd_leish_cut/1461/04_models/gbd2015/03_steps/`date'/03a_prevalence_cl/02_inputs"
		local save_dir "/ihme/gbd/WORK/04_epi/02_models/02_results/ntd_leish_cut/1461/04_models/gbd2015/03_steps/`date'/03a_prevalence_cl/03_outputs/01_draws"
	}

// *********************************************************************************************************************************************************************
// Import functions
	run "$prefix/WORK/10_gbd/00_library/functions/get_draws.ado"
	run "$prefix/WORK/10_gbd/00_library/functions/get_demographics.ado"
	run "$prefix/WORK/10_gbd/00_library/functions/fastcollapse.ado"
	
// *********************************************************************************************************************************************************************
	
	// Get ages, sexes, and years
	get_demographics , gbd_team(epi) clear
	
   // Check whether country is considered as ever having leishmaniasis (CL or VL).
      use "`tmp_in_dir'/leish_presence.dta" if location_id == `location_id', replace
      local zero_leish = 1 - leish_presence
	  
	// Get reported case indicator
	use "`tmp_in_dir'/cl_case.dta" if location_id == `location_id', clear
	count
	assert `r(N)' == 1
	levelsof cl_case, local(has_case) c
      
  // loop through ages and sexes
    foreach year_id of global year_ids {
    foreach sex_id of global sex_ids {
      
      di "`location_id' `year_id' `sex_id'"
      
      use "`tmp_in_dir'/hsa.dta", clear
      quietly keep if location_id == `location_id' & year_id == `year_id'
      quietly summ hsa_norm
      local hsa_norm = `r(mean)'
   
      get_draws, gbd_id_field(modelable_entity_id) gbd_id(1461) source(epi) measure_ids(6) location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') clear

      quietly keep if age_group_id <= 21

    // If the country does not have leishmaniasis according to the leish_presence covariate, set inc to 0. If it does have
    // leishmaniasis, scale up figures by underreporting factor.
      if `zero_leish' == 1 {
        forvalues x = 0/999 {
          quietly replace draw_`x' = 0
        }
      }
      else if `zero_leish' != 1 & `has_case' == 1 {
        quietly merge m:1 location_id using "`tmp_in_dir'/isomap.dta", assert(2 3) keep(3) nogen
        quietly merge m:1 iso3 using "`tmp_in_dir'/underreporting.dta", assert(2 3) keep(3) keepusing(uf*) nogen
        forvalues x = 0/999 {
          quietly replace draw_`x' = draw_`x' * uf_`x'
        }        
        drop iso3 uf*
      }

      quietly outsheet using "`save_dir'/6_`location_id'_`year_id'_`sex_id'.csv", comma replace
	  replace measure_id = 5
      
    // Compute total prevalence, combining longterm and acute 
      if `zero_leish' == 1 {
		quietly outsheet using "`save_dir'/5_`location_id'_`year_id'_`sex_id'.csv", comma replace
      }
      else {
		quietly merge m:1 age_group_id using "`tmp_in_dir'/ages.dta", assert(3) nogen
        forvalues x = 0/999 {
		
          // Prevalence of longterm sequelae at start of each age category
			sort age_group_id
            quietly generate double inc_long_`x' = draw_`x' * (1 - `hsa_norm') * 0.476
            quietly generate double prev_start_`x' = 0 if age_group_years_start == 0 
            quietly replace prev_start_`x' = prev_start_`x'[_n-1] + (1 - prev_start_`x'[_n-1]) * (1 - exp(-(age_group_years_end[_n-1] - age_group_years_start[_n-1]) * inc_long_`x'[_n-1])) if age_group_years_start > 0
            
          // Prevalence of longterm sequelae in each age category (half-year correction)
            quietly replace prev_start_`x' = prev_start_`x' + (1 - prev_start_`x') * (1 - exp(-(age_group_years_end - age_group_years_start)/2 * inc_long_`x')) if age_group_years_start < 80
            quietly replace prev_start_`x' = prev_start_`x' + (1 - prev_start_`x') * (1 - exp(-(85 - age_group_years_start)/2 * inc_long_`x')) if age_group_years_start ==  80
            quietly rename prev_start_`x' prev_`x'
            
          // Add cases with acute sequelae (ie all cases but long-term cases), assuming 6 month duration
            quietly replace prev_`x' = prev_`x' + (draw_`x' - inc_long_`x') / 2
            
			quietly drop draw_`x' inc_long_`x'
            quietly rename prev_`x' draw_`x'
        }
        
        keep measure_id location_id year_id age_group_id sex_id modelable_entity_id draw_*
		quietly outsheet using "`save_dir'/5_`location_id'_`year_id'_`sex_id'.csv", comma replace
      }
	}
	}
	
// *********************************************************************************************************************************************************************
