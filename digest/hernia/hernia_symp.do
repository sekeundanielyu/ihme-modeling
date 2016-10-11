// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:	parallel code to hernia calculations, calculating symptomatic and asymptomatic from chronic and primary diagnosis correction

// PREP STATA
	clear
	set more off
	set maxvar 3200
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	
// locals from the qsub
	local date  	`1'
	local tmp_dir 	`2'
	local location	`3'


	// write log
	cap log using "`tmp_dir'/`date'/00_logs/asymptomatic_`cause'.smcl", replace
	if !_rc local close 1
	else local close 0

	// directory for standard code files and functions
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	// get locals from demographics
	get_demographics, gbd_team(epi) clear
	local years = "$year_ids"
	local sexes = "$sex_ids"
	clear	

	// get demographics
    get_location_metadata, location_set_id(9) clear
    keep if most_detailed == 1 & is_estimate == 1
    levelsof(location_id), local(locations)

   	// MEIDs
	local hernia_chronic 9794
	local hernia_symp 1934
	local hernia_asymp 9542
	local correction_factor_male 4.1424856185913
	local correction_factor_female 4.79122304916381

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE

	get_draws, gbd_id_field(modelable_entity_id) gbd_id(`hernia_chronic') status(best) measure_ids(5) source(epi) location_ids (`location') clear
	drop if age_group_id >= 22
	drop model_version_id
	tempfile chronic
	save `chronic', replace

	forvalues i = 0/999 {
		replace draw_`i' = draw_`i' / `correction_factor_male' if sex_id == 1
		replace draw_`i' = draw_`i' / `correction_factor_female' if sex_id == 2
	}

	foreach year of local years {
		foreach sex of local sexes {
			preserve
			keep if year_id == `year'
			keep if sex_id == `sex'
			outsheet using "`tmp_dir'/`date'/hernia/01_draws/`hernia_symp'/5_`location'_`year'_`sex'.csv", comma replace
			restore
		}
	}

	forvalues i = 0/999 {
		rename draw_`i' symp_`i'
	}
	
	merge 1:1 location_id year_id age_group_id sex_id using `chronic', nogen
	forvalues i = 0/999 {
		replace draw_`i' = draw_`i' - symp_`i'
	}
	drop symp_*

	foreach year of local years {
		foreach sex of local sexes {
			preserve
			keep if year_id == `year'
			keep if sex_id == `sex'
			outsheet using "`tmp_dir'/`date'/hernia/01_draws/`hernia_asymp'/5_`location'_`year'_`sex'.csv", comma replace
			restore
		}
	}

