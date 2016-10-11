// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This sub-step template is for parallelized jobs submitted from main step code
// Description:	Parallelization of 04a_dismod_prep_wmort

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM STEP CODE (NO NEED TO EDIT THIS SECTION)

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

// define locals from qsub command
	local date 			`1'
	local step_num 		`2'
	local step_name		`3'
	local location 		`4'
	local code_dir 		`5'
	local in_dir 		`6'
	local out_dir 		`7'
	local tmp_dir 		`8'
	local root_tmp_dir 	`9'
	local root_j_dir 	`10'
	local ihme_loc		`11'

// define other locals
	// directory for standard code files
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	// run save_results
	run "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
	// functional
	local functional "meningitis"
	// etiologies
	local etiologies "meningitis_pneumo meningitis_hib meningitis_meningo meningitis_other"
	// grouping
	local grouping "long_modsev _epilepsy"
	// directory for pulling files from previous step
	local pull_dir_03b "`root_tmp_dir'/03_steps/`date'/03b_outcome_split/03_outputs/01_draws"	

	// get locals from demographics
	get_demographics, gbd_team(epi) clear
	local years = "$year_ids"
	local sexes = "$sex_ids"

	/* // test run
	local years 2000 2005
	local sexes 1 */

	// set locals for etiology meids
	local _epilepsy_meningitis_pneumo = 1311
	local _epilepsy_meningitis_hib = 1341
	local _epilepsy_meningitis_meningo = 1371
	local _epilepsy_meningitis_other = 1401
	local long_modsev_meningitis_pneumo = 1305
	local long_modsev_meningitis_hib = 1335
	local long_modsev_meningitis_meningo = 1365
	local long_modsev_meningitis_other = 1395
	
	// write log if running in parallel and log is not already open
	cap log using "`out_dir'/02_temp/02_logs/`step_num'_`ihme_loc'.smcl", replace
	if !_rc local close 1
	else local close 0
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE
	// get estimates from epilepsy excess mortality model
	di "pulling epilepsy excess mortality estimates"
	get_best_model_versions, gbd_team(epi) id_list(2403) clear
	local dm_epilepsy = model_version_id in 1
	clear

	odbc load, exec("SELECT * FROM model_estimate_final WHERE model_version_id = `dm_epilepsy' AND measure_id = 9 AND location_id = `location'") dsn(EPI) clear
	drop if age_group_id > 21
	drop if sex_id == 3
	drop model_version_id
	gen modelable_entity_id = .
	gen modelable_entity_name = ""
	gen measure = "mtexcess"
	drop measure_id
	preserve

	foreach year of local years {
		foreach sex of local sexes {
			keep if sex_id == `sex' & year_id == `year'
			save "`out_dir'/02_temp/03_data/epilepsy_mtexcess_`location'_`year'_`sex'.dta", replace
			restore, preserve
		}
	}
	restore
	clear

	di in red "pulling mortality deaths data"
	import delimited "/ihme/gbd/WORK/02_mortality/03_models/5_lifetables/results/env_loc/with_shock/env_`location'.csv", delim(",") varnames(1) clear
	tempfile mort
	save `mort'

	// pull in population data and merge
	di "pulling in pop data"
	get_populations, year_id(1990 1995 2000 2005 2010 2015) location_id(`location') sex_id(1 2) age_group_id(5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21) clear
	merge 1:1 year_id sex_id age_group_id using `mort', keep(3) nogen
	
	di "calculate mortality rate"
	forvalues x = 0/999 {
		rename draw_`x' deaths_`x'
		gen mort_`x' = deaths_`x'/pop_scaled
	}
	drop deaths*

	gen age = "old"
	replace age = "young" if age_group_id < 9
	save `mort', replace

	// input code for smr-->excessmortality calculation here
	di "pulling in SMR data"
	// prepare SMR file of neonatal encephalopathy to be attached to all long_modsev iso3/year/sex
	use "`in_dir'/CP Mortality update for GBD2013.dta", clear
	keep if cause == "NE" // neonatal encephalopathy
	// generating SMR draws
	drop cause parameter mean_og
	forvalues x = 0/999 {
		gen smr_`x' = rnormal(mean, se)
	}

	// format and merge SMR to mortality data
	gen age = "young"
	replace age = "old" if age_start == 20

	merge 1:m age using `mort', keep(3) nogen

	// generating EMR draws
	forvalues x = 0/999 {
		gen emr_`x' = mort_`x' * (smr_`x' - 1)
	}

	// regenerate mean and CIs for DisMod
	drop mean
	egen mean = rowmean(emr_*)
	fastpctile emr_*, pct(2.5 97.5) names(lower upper)
	keep location_id sex_id age_group_id year_id mean upper lower
	gen measure = "mtexcess"
	gen etiology = ""
	gen modelable_entity_id = .
	gen modelable_entity_name = ""

	order modelable_entity_name modelable_entity_id location_id year_id sex_id age_group_id mean lower upper
	foreach year of local years {
		foreach sex of local sexes {
			preserve
			keep if year_id == `year' & sex_id == `sex'
			tempfile smr_`location'_`year'_`sex'
			save `smr_`location'_`year'_`sex''
			restore
		}
	}

	clear

// THIS IS NEW
	foreach etiology of local etiologies {
		cap mkdir "`tmp_dir'/03_outputs/01_draws/`etiology'"
		cap mkdir "`tmp_dir'/03_outputs/01_draws/`etiology'/`location'"
	}


	foreach year of local years {
		foreach sex of local sexes {
			foreach etiology of local etiologies {
				foreach group of local grouping {
					use "`pull_dir_03b'/`etiology'_`group'_`location'_`year'_`sex'.dta", clear

					** create DisMod input parameters
					egen mean = rowmean(draw_*)
					egen lower = rowpctile(draw_*), p(2.5)
					egen upper = rowpctile(draw_*), p(97.5)
					drop draw_*
					gen measure = "incidence"
					drop measure_id
					gen modelable_entity_name = "`etiology'"
					order modelable_entity_name modelable_entity_id location_id year_id sex_id age_group_id mean lower upper etiology

					if "`group'" == "_epilepsy" {
						append using "`out_dir'/02_temp/03_data/epilepsy_mtexcess_`location'_`year'_`sex'.dta"
					}
					if "`group'" == "long_modsev" {
						append using `smr_`location'_`year'_`sex''
					}

					gen age_start = 0
					replace age_start = 0 if age_group_id == 2
					replace age_start = 0.01 if age_group_id == 3
					replace age_start = 0.1 if age_group_id == 4
					replace age_start = 1 if age_group_id == 5
					replace age_start = (age_group_id - 5)*5 if age_group_id > 5
					gen age_end = 0.01
					replace age_end = 0.1 if age_group_id == 3
					replace age_end = 1 if age_group_id == 4
					replace age_end = 4 if age_group_id == 5
					replace age_end = age_start + 4 if age_start >= 5
					replace age_end = 100 if age_start == 80
					drop age_group_id

					replace modelable_entity_name = "`etiology'" if modelable_entity_name == ""
					replace location_id = `location' if location_id == .
					replace year_id = `year' if year_id == .
					gen note_modeler = "`group'"

					rename year_id year_start
					gen year_end = year_start
					gen sex = "Female"
					replace sex = "Male" if `sex' == 1

					replace modelable_entity_id = ``group'_`etiology''
					if "`group'" == "_epilepsy" & "`etiology'" == "meningitis_pneumo" {
						replace modelable_entity_name = "Epilepsy due to pneumococcal meningitis"
					}
					else if "`group'" == "_epilepsy" & "`etiology'" == "meningitis_hib" {
						replace modelable_entity_name = "Epilepsy due to H influenzae type B meningitis"
					}
					else if "`group'" == "_epilepsy" & "`etiology'" == "meningitis_meningo" {
						replace modelable_entity_name = "Epilepsy due to meningococcal meningitis"
					}
					else if "`group'" == "_epilepsy" & "`etiology'" == "meningitis_other" {
						replace modelable_entity_name = "Epilepsy due to other meningitis"
					}
					else if "`group'" == "long_modsev" & "`etiology'" == "meningitis_pneumo" {
						replace modelable_entity_name = "Moderate to severe impairment due to pneumococcal meningitis"
					}
					else if "`group'" == "long_modsev" & "`etiology'" == "meningitis_hib" {
						replace modelable_entity_name = "Moderate to severe impairment due to H influenzae type B meningitis"
					}
					else if "`group'" == "long_modsev" & "`etiology'" == "meningitis_meningo" {
						replace modelable_entity_name = "Moderate to severe impairment due to meningococcal meningitis"
					}
					else if "`group'" == "long_modsev" & "`etiology'" == "meningitis_other" {
						replace modelable_entity_name = "Moderate to severe impairment due to other meningitis"
					}

					order modelable_entity_name modelable_entity_id location_id year_start year_end sex age_start age_end mean lower upper
					save "`tmp_dir'/03_outputs/01_draws/`etiology'/`location'/`etiology'_`group'_`location'_`year'_`sex'.dta", replace
				}
			}
		}
	}


// write check here
	file open finished using "`tmp_dir'/02_temp/01_code/checks/finished_loc`location'.txt", replace write
	file close finished

// close logs
	if `close' log close
	clear

	