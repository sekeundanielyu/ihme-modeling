// **********************************************************************
// Purpose:        This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global
// Description:   Calculate incidence of leprosy by country-year-age-sex, using cases reported to WHO and
//                      age-patterns from dismod. Produce incidence for every year in 1890-2015, and sweep forward
//                      with ODE to arrive at prevalence predictions.
// /home/j/WORK/04_epi/01_database/02_data/leprosy/1662/04_models/gbd2015/01_code/dev/02_inc_prev_ode_format_parallel.do

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
		local min_year `2'
		local tmp_dir `3'	
	}
	else if "`1'" == "" {
		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
		local date = subinstr("`date'"," ","_",.)
		local location_id 43911
		local min_year 1987
		local tmp_dir "/ihme/gbd/WORK/04_epi/01_database/02_data/leprosy/1662/04_models/gbd2015/03_steps/`date'/02_inc_prev_ode"
	}

// *********************************************************************************************************************************************************************
// Import functions
	run "$prefix/WORK/10_gbd/00_library/functions/get_demographics.ado"
	
// Get IHME loc ID for location
	get_demographics, gbd_team(epi) clear
	use "`tmp_dir'/loc_iso3.dta" if location_id == `location_id', clear
	levelsof iso3, local(iso) c
	local sex_1 "male"
	local sex_2 "female"
	
// Make function for fixing ages
	cap program drop age_to_age_group_id
	program define age_to_age_group_id
		version 13
		syntax , tmp_dir(string)
		recast double age
		replace age = 0.01 if age > 0.009 & age < 0.011
	    replace age = 0.1 if age > 0.09 & age < 0.11
	    merge m:1 age using "`tmp_dir'/age_map.dta", assert(3) nogen
		drop age
	end
	
// *********************************************************************************************************************************************************************
    foreach year_id of global year_ids {
		foreach sex_id of global sex_ids {
		// Parent sequelae
			// Incidence
				insheet using "`tmp_dir'/draws/cases/inc_annual/incidence_`iso'_`year_id'_`sex_`sex_id''.csv", comma names clear
				gen sex_id = `sex_id'
				gen year_id = `year_id'
				gen location_id = `location_id'
				gen measure_id = 6
				gen modelable_entity_id = 1662
				age_to_age_group_id, tmp_dir(`tmp_dir')
				keep modelable_entity_id location_id year_id age_group_id sex_id measure_id draw*
				order modelable_entity_id location_id year_id age_group_id sex_id measure_id draw*
				outsheet using "`tmp_dir'/draws/upload/1662/6_`location_id'_`year_id'_`sex_id'.csv", comma names replace
			
			// Prevalence
				insheet using "`tmp_dir'/draws/cases/final/prevalence_`iso'_`year_id'_`sex_`sex_id''.csv", comma names clear
				gen sex_id = `sex_id'
				gen year_id = `year_id'
				gen location_id = `location_id'
				gen measure_id = 5
				gen modelable_entity_id = 1662
				age_to_age_group_id, tmp_dir(`tmp_dir')
				keep modelable_entity_id location_id year_id age_group_id sex_id measure_id draw*
				order modelable_entity_id location_id year_id age_group_id sex_id measure_id draw*
				outsheet using "`tmp_dir'/draws/upload/1662/5_`location_id'_`year_id'_`sex_id'.csv", comma names replace
				
		// Disfigurement 1
			// Incidence
				insheet using "`tmp_dir'/draws/disfigure_1/final/incidence_`iso'_`year_id'_`sex_`sex_id''.csv", comma names clear
				gen sex_id = `sex_id'
				gen year_id = `year_id'
				gen location_id = `location_id'
				gen measure_id = 6
				gen modelable_entity_id = 1663
				age_to_age_group_id, tmp_dir(`tmp_dir')
				keep modelable_entity_id location_id year_id age_group_id sex_id measure_id draw*
				order modelable_entity_id location_id year_id age_group_id sex_id measure_id draw*
				outsheet using "`tmp_dir'/draws/upload/1663/6_`location_id'_`year_id'_`sex_id'.csv", comma names replace
			
			// Prevalence
				insheet using "`tmp_dir'/draws/disfigure_1/final/prevalence_`iso'_`year_id'_`sex_`sex_id''.csv", comma names clear
				gen sex_id = `sex_id'
				gen year_id = `year_id'
				gen location_id = `location_id'
				gen measure_id = 5
				gen modelable_entity_id = 1663
				age_to_age_group_id, tmp_dir(`tmp_dir')
				keep modelable_entity_id location_id year_id age_group_id sex_id measure_id draw*
				order modelable_entity_id location_id year_id age_group_id sex_id measure_id draw*
				outsheet using "`tmp_dir'/draws/upload/1663/5_`location_id'_`year_id'_`sex_id'.csv", comma names replace
		
		// Disfugurement 2
			// Incidence
				insheet using "`tmp_dir'/draws/disfigure_2/final/incidence_`iso'_`year_id'_`sex_`sex_id''.csv", comma names clear
				gen sex_id = `sex_id'
				gen year_id = `year_id'
				gen location_id = `location_id'
				gen measure_id = 6
				gen modelable_entity_id = 1664
				age_to_age_group_id, tmp_dir(`tmp_dir')
				keep modelable_entity_id location_id year_id age_group_id sex_id measure_id draw*
				order modelable_entity_id location_id year_id age_group_id sex_id measure_id draw*
				outsheet using "`tmp_dir'/draws/upload/1664/6_`location_id'_`year_id'_`sex_id'.csv", comma names replace
			
			// Prevalence
				insheet using "`tmp_dir'/draws/disfigure_2/final/prevalence_`iso'_`year_id'_`sex_`sex_id''.csv", comma names clear
				gen sex_id = `sex_id'
				gen year_id = `year_id'
				gen location_id = `location_id'
				gen measure_id = 5
				gen modelable_entity_id = 1664
				age_to_age_group_id, tmp_dir(`tmp_dir')
				keep modelable_entity_id location_id year_id age_group_id sex_id measure_id draw*
				order modelable_entity_id location_id year_id age_group_id sex_id measure_id draw*
				outsheet using "`tmp_dir'/draws/upload/1664/5_`location_id'_`year_id'_`sex_id'.csv", comma names replace
		}
    }

// *********************************************************************************************************************************************************************