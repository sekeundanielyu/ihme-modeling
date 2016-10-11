// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global
// Description: Generate prevalence of VL cases, based on incidence as predicted by DisMod and duration from literature
// Location: /home/j/WORK/04_epi/01_database/02_data/ntd_leish/1458_1459_1460_1461/04_models/gbd2015/01_code/dev/03b_prevalence_vl_parallel.do

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
		local save_dir_1458 `3'
		local save_dir_1459 `4' 
		local save_dir_1460 `5'
	}
	else if "`1'" == "" {
		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
		local date = subinstr("`date'"," ","_",.)
		local location_id 44539
		local tmp_in_dir "/ihme/gbd/WORK/04_epi/02_models/02_results/ntd_leish_visc/1458/04_models/gbd2015/03_steps/`date'/03b_prevalence_vl/02_inputs"
		local save_dir_1458 "/ihme/gbd/WORK/04_epi/02_models/02_results/ntd_leish_visc/1458/04_models/gbd2015/03_steps/`date'/03b_prevalence_vl/03_outputs/01_draws"
		local save_dir_1459 "/ihme/gbd/WORK/04_epi/02_models/02_results/ntd_leish_visc/1459/04_models/gbd2015/03_steps/`date'/03b_prevalence_vl/03_outputs/01_draws"
		local save_dir_1460 "/ihme/gbd/WORK/04_epi/02_models/02_results/ntd_leish_visc/1460/04_models/gbd2015/03_steps/`date'/03b_prevalence_vl/03_outputs/01_draws"
	}

// *********************************************************************************************************************************************************************
// Import functions
	run "$prefix/WORK/10_gbd/00_library/functions/get_draws.ado"
	run "$prefix/WORK/10_gbd/00_library/functions/get_demographics.ado"
	run "$prefix/WORK/10_gbd/00_library/functions/fastcollapse.ado"
	
// *********************************************************************************************************************************************************************
	// Set duration for prevalence calculation
		local duration_parent = .25
		local duration_mild = .1875 // duration of mild form on average is 2.25 months or 2.25/12 years
		local duration_sev = `duration_parent' - `duration_mild'
		
	// Get ages, sexes, and years
	get_demographics , gbd_team(epi) clear
	
	// Get location details
	local draws_loc = `location_id'
	use "`tmp_in_dir'/location_metadata.dta", clear
	keep if location_id == `location_id'
	if regexm(path_to_top_parent,",163,") local draws_loc 163
	
	// Get Indian state distribution
	if `draws_loc' == 163 {
		levelsof parent_id, local(state_location_id) c
		if regexm(location_name,"Rural") local urbanicity "rural"
		else if regexm(location_name,"Urban") local urbanicity "urban"
		assert "`urbanicity'" != ""
		import excel using "$prefix/WORK/04_epi/01_database/02_data/ntd_leish/1458_1459_1460_1461/04_models/gbd2015/02_inputs/IND_state_case_props.xlsx", firstrow clear
		keep if parent_id == `state_location_id'
		if "`urbanicity'" == "rural" gen prop_cases = prop_state * prop_rural
		else if "`urbanicity'" == "urban" gen prop_cases = prop_state * prop_urban
		gen location_id = `location_id'
		keep location_id prop_cases
		tempfile IND_state_case_props
		save `IND_state_case_props', replace
	}
	
	// Get reported case indicator
		use "`tmp_in_dir'/vl_case.dta" if location_id == `location_id', clear
		count
		assert `r(N)' == 1
		levelsof vl_case, local(has_case) c
	
   // Check whether country is considered as ever having leishmaniasis (CL or VL).
      use "`tmp_in_dir'/leish_presence.dta" if location_id == `draws_loc', replace
      local zero_leish = 1 - leish_presence
      
	foreach year_id of global year_ids {
	foreach sex_id of global sex_ids {
	
    // Pull in Dismod incidence predictions
      get_draws, gbd_id_field(modelable_entity_id) gbd_id(1458) source(epi) measure_ids(6) location_ids(`draws_loc') year_ids(`year_id') sex_ids(`sex_id') clear
      drop model_version_id
	  keep if age_group_id >= 2 & age_group_id <= 21
	  
    // If the country does not have leishmaniasis according to the leish_presence covariate, set inc to 0. If it does have
    // leishmaniasis, scale up figures by underreporting factor.
      if `zero_leish' == 1 {
        forvalues x = 0/999 {
          quietly replace draw_`x' = 0
        }
      }
      else {
		quietly merge m:1 location_id using "`tmp_in_dir'/isomap.dta", assert(2 3) keep(3) nogen
        quietly merge m:1 iso3 using "`tmp_in_dir'/underreporting.dta", assert(2 3) keep(3) keepusing(uf*) nogen
		if `has_case' == 1 & `draws_loc' != 163 {
			forvalues x = 0/999 {
			  quietly replace draw_`x' = draw_`x' * uf_`x'
			}
		}
        drop iso3 uf*
		
		// Use state distribution from literature for India
		if `draws_loc' == 163 {
			merge 1:1 location_id age_group_id year_id sex_id using "`tmp_in_dir'/pops.dta", assert(2 3) keep(3) nogen
			forvalues x = 0/999 {
				quietly replace draw_`x' = draw_`x' * pop_scaled
			}
			drop pop_scaled
			replace location_id = `location_id'
			merge m:1 location_id using `IND_state_case_props', assert(3) nogen
			merge 1:1 location_id age_group_id year_id sex_id using "`tmp_in_dir'/pops.dta", assert(2 3) keep(3) nogen
			forvalues x = 0/999 {
				quietly replace draw_`x' = (draw_`x' * prop_cases) / pop_scaled
			}
			drop prop_cases pop_scaled
        }     
		}
	  
    // Save updated incidence draws with non-endemic countries set to zero.
	  aorder
	  order modelable_entity_id measure_id location_id year_id age_group_id sex_id
	  
	// Make SURE there are only the desired 20 observations
	  sort age_group_id
	  gen n = _n
	  drop if n > 20
	  drop n
	  
	// Save incidence
	  count
	  assert `r(N)' == 20
	  foreach var of varlist * {
		quietly capture count if `var' == ""
		if _rc quietly count if `var' == .
		if `r(N)' > 0 {
			di "Missingness found in `var'"
			BREAK
		}
	  }
      
    // Calculate different health states
      preserve
		// Incidence and prevalence of parent
		quietly outsheet using "`save_dir_1458'/6_`location_id'_`year_id'_`sex_id'.csv", comma replace
		replace measure_id = 5
        forvalues x = 0/999 {
          quietly replace draw_`x' = `duration_parent' * draw_`x'
        }
		count
		assert `r(N)' == 20
        quietly outsheet using "`save_dir_1458'/5_`location_id'_`year_id'_`sex_id'.csv", comma replace
      restore
      preserve
		// Incidence and prevalence of moderate
		replace modelable_entity_id = 1459
		quietly outsheet using "`save_dir_1459'/6_`location_id'_`year_id'_`sex_id'.csv", comma replace
		replace measure_id = 5
        forvalues x = 0/999 {
          quietly replace draw_`x' = `duration_mild' * draw_`x'
        }
		count
		assert `r(N)' == 20
        quietly outsheet using "`save_dir_1459'/5_`location_id'_`year_id'_`sex_id'.csv", comma replace
      restore
      preserve
		// Prevalence of severe
		replace modelable_entity_id = 1460
		replace measure_id = 5
        forvalues x = 0/999 {
          quietly replace draw_`x' = `duration_sev' * draw_`x'
        }
		count
		assert `r(N)' == 20
        quietly outsheet using "`save_dir_1460'/5_`location_id'_`year_id'_`sex_id'.csv", comma replace
      restore
    }
	}
	
// *********************************************************************************************************************************************************************
