// **********************************************************************
// Purpose:		This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global
// Description:	Calculate mortality rate from incidence for DisMod years, and interpolate for non-DisMod years 
// Location: /home/j/WORK/04_epi/01_database/02_data/ntd_leish/1458_1459_1460_1461/04_models/gbd2015/01_code/dev/03c_mi_death_vl_parallel.do

// **********************************************************************
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
		local save_dir `3'
		local epi_model  `4'
	}
	else if "`1'" == "" {
		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
		local date = subinstr("`date'"," ","_",.)
		local location_id 48
		local tmp_in_dir "/ihme/gbd/WORK/04_epi/02_models/02_results/ntd_leish_visc/1458/04_models/gbd2015/03_steps/`date'/03c_mi_death_vl/02_inputs"
		local save_dir "/ihme/gbd/WORK/04_epi/02_models/02_results/ntd_leish_visc/1458/04_models/gbd2015/03_steps/`date'/03c_mi_death_vl/03_outputs/01_dismod_year_draws"
		run "$prefix/WORK/10_gbd/00_library/functions/get_best_model_versions.ado"
		get_best_model_versions, gbd_team(epi) id_list(1458) clear
		local epi_model = model_version_id
	}

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
 // Import functions
	run "$prefix/WORK/10_gbd/00_library/functions/get_draws.ado"
	run "$prefix/WORK/10_gbd/00_library/functions/get_demographics.ado"

//**********************************************************************  
// Calculate mortality cases from incidence predictions for VL.
  // Check whether country is considered as ever having leishmaniasis (CL or VL).
	use "`tmp_in_dir'/leish_presence.dta" if location_id == `location_id', replace
	local zero_leish = round(1 - leish_presence,1)
  
  // Create globals $year_ids $age_group_ids $sex_ids for epi analyses
    get_demographics, gbd_team(epi) clear
    
	// Now pull in incidence files by country-year-sex
	quietly {
	foreach sex_id of global sex_ids {
		foreach year_id of global year_ids {
		display in red "`location_id' : `year_id' `sex_id'"
			
		// Pull in Dismod incidence predictions
		  get_draws, gbd_id_field(modelable_entity_id) gbd_id(1458) measure_ids(6) source(epi) location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') clear
		  drop model_version_id
		  keep if age_group_id >= 2 & age_group_id <= 21
		  
		  count
		  if `r(N)' == 0 {
			set obs 20
			replace modelable_entity_id = 1458
			replace measure_id = 6
			replace location_id = `location_id'
			replace year_id = `year_id'
			replace age_group_id = _n + 1
			replace sex_id = `sex_id'
			foreach var of varlist draw* {
				replace `var' = 0
			}
		  }
			
			if `zero_leish' == 1 {
			  forvalues n = 0/999 {
				replace draw_`n' = 0
			  }
			}
			else {
			  
			  
			// merge in population and MI
			  merge 1:1 location_id age_group_id year_id sex_id using "`tmp_in_dir'/pops.dta", assert(2 3) keep(3) nogen
			  merge 1:1 location_id age_group_id year_id sex_id using "`tmp_in_dir'/mi_ratios/mi_ratio_`location_id'.dta", assert(2 3) keep(3) nogen
			  
			// Calculate mortality cases
			  forvalues j = 0/999 {
				quietly replace draw_`j' = draw_`j' * pop_scaled * mi_ratio_`j'
				quietly replace draw_`j' = 0 if age_group_id < 4
			  }
			  
			}
			
			replace measure_id = 1
			gen cause_id = 348
			keep cause_id measure_id location_id year_id age_group_id sex_id draw*
			order cause_id measure_id location_id year_id age_group_id sex_id draw*
			
			quietly outsheet using "`save_dir'/death_`location_id'_`year_id'_`sex_id'.csv", comma replace
			
		}
	} 
	}
    
// **********************************************************************
	