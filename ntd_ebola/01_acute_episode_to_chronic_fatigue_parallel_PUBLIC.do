// **********************************************************************
// Purpose:        This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global

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
		local tmp_dir `2'	
	}
	else if "`1'" == "" {
		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
		local date = subinstr("`date'"," ","_",.)
		local location_id 210
		local tmp_dir "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_ebola/9668/04_models/gbd2015/03_steps/`date'/01_acute_episode_to_chronic_fatigue"
	}

// *********************************************************************************************************************************************************************
// Load universal needs
	run "$prefix/WORK/10_gbd/00_library/functions/get_demographics.ado"
	get_demographics, gbd_team(cod) clear
	use "`tmp_dir'/locs.dta" if location_id == `location_id', clear
	levelsof location_name, local(loc_nm) c
	use "`tmp_dir'/pops.dta" if location_id == `location_id', clear
	tempfile pops
	save `pops', replace
	
// Produce zero function
	cap program drop save_template
	program define save_template
		version 13
		syntax , modelable_entity_id(string) location_id(string) year_id(string) sex_id(string) measure_id(string) tmp_dir(string)
		clear
		set obs 20
		gen modelable_entity_id = `modelable_entity_id'
		gen location_id = `location_id'
		gen year_id = `year_id'
		gen age_group_id = _n + 1
		gen sex_id = `sex_id'
		gen measure_id = `measure_id'
		forval x = 0/999 {
			gen draw_`x' = 0
		}
		outsheet using "`tmp_dir'/final/`modelable_entity_id'/`measure_id'_`location_id'_`year_id'_`sex_id'.csv", comma names replace
	end
	
// Produce formatting function
	cap program drop save_values
	program define save_values
		version 13
		syntax , in_fil(string) pops(string) modelable_entity_id(string) loc_nm(string) location_id(string) year_id(string) sex_id(string) measure_id(string) tmp_dir(string)
		use "`in_fil'" if location_name == "`loc_nm'" & year_id ==`year_id' & sex_id == `sex_id', clear
		count
		assert `r(N)' == 18
		expand 3 if age_group_id == 4, gen(nn)
		bysort age_group_id nn : replace age_group_id = _n + 1 if nn == 1
		drop nn
		sort age_group_id
		gen location_id = `location_id'
		gen modelable_entity_id = `modelable_entity_id'
		merge m:1 location_id year_id age_group_id sex_id using `pops', assert(2 3) keep(3) nogen
		foreach var of varlist draw* {
			replace `var' = `var' / pop_scaled
			replace `var' = 0 if age_group_id < 4
		}
		keep modelable_entity_id location_id year_id age_group_id sex_id measure_id draw*
		outsheet using "`tmp_dir'/final/`modelable_entity_id'/`measure_id'_`location_id'_`year_id'_`sex_id'.csv", comma names replace
	end
	
// ******************************************************************************************************************************************************************************************************************************************************************************************************************************************
// Iterate through years
	foreach year_id of global year_ids {
	if `year_id' >= 1990 {
		use "`tmp_dir'/endemic_location_years.dta" if location_name == "`loc_nm'" & year_id == `year_id', clear
		count
		if `r(N)' > 0 local endem 1
		else if `r(N)' == 0 local endem 0
		foreach sex_id of global sex_ids {
			// Save template
			if `endem' == 0 {
				save_template, modelable_entity_id(9668) location_id(`location_id') year_id(`year_id') sex_id(`sex_id') measure_id(5) tmp_dir(`tmp_dir')
				save_template, modelable_entity_id(9668) location_id(`location_id') year_id(`year_id') sex_id(`sex_id') measure_id(6) tmp_dir(`tmp_dir')
				**
				save_template, modelable_entity_id(9669) location_id(`location_id') year_id(`year_id') sex_id(`sex_id') measure_id(5) tmp_dir(`tmp_dir')
				save_template, modelable_entity_id(9669) location_id(`location_id') year_id(`year_id') sex_id(`sex_id') measure_id(6) tmp_dir(`tmp_dir')
			}
			// Read data, format, and convert to rates
			if `endem' == 1 {
				// Acute incidence
				save_values, in_fil(`tmp_dir'/acute_episode_incidence.dta) pops(`pops') modelable_entity_id(9668) loc_nm(`loc_nm') location_id(`location_id') year_id(`year_id') sex_id(`sex_id') measure_id(6) tmp_dir(`tmp_dir')
				// Acute prevalence
				save_values, in_fil(`tmp_dir'/acute_episode_prevalence.dta) pops(`pops') modelable_entity_id(9668) loc_nm(`loc_nm') location_id(`location_id') year_id(`year_id') sex_id(`sex_id') measure_id(5) tmp_dir(`tmp_dir')
				** 
				// Acute incidence
				save_values, in_fil(`tmp_dir'/post_episode_chronic_fatigue_incidence.dta) pops(`pops') modelable_entity_id(9669) loc_nm(`loc_nm') location_id(`location_id') year_id(`year_id') sex_id(`sex_id') measure_id(6) tmp_dir(`tmp_dir')
				// Acute prevalence
				save_values, in_fil(`tmp_dir'/post_episode_chronic_fatigue_prevalence.dta) pops(`pops') modelable_entity_id(9669) loc_nm(`loc_nm') location_id(`location_id') year_id(`year_id') sex_id(`sex_id') measure_id(5) tmp_dir(`tmp_dir')
			}
		}
	}
	}


// ******************************************************************************************************************************************************************************************************************************************************************************************************************************************