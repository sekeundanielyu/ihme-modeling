// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	Generate excess mortality from SMR estimates

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM STEP CODE (NO NEED TO EDIT THIS SECTION)

	// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	if "`1'"=="" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "01e"
		local 5 SMR_to_excessmort
		local 6 "/share/code/injuries/strUser/inj/gbd2015"
		local 7 89
		local 8 1995
		local 9 1
	}
	// base directory on J 
	local root_j_dir `1'
	// base directory on clustertmp
	local root_tmp_dir `2'
	// timestamp of current run (i.e. 2014_01_17)
	local date `3'
	// step number of this step (i.e. 01a)
	local step_num `4'
	// name of current step (i.e. first_step_name)
	local step_name `5'
    // directory where the code lives
    local code_dir `6'
    // iso3
	local location_id `7'
	// year
	local year `8'
	// sex
	local sex `9'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for standard code files
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Settings
	local slots 1
	local debug 0
	
// Filepaths
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local input_dir "`tmp_dir'/02_temp/03_data"
	local output_dir "`tmp_dir'/03_outputs"
	local draw_dir "`output_dir'/01_draws"
	local summ_dir "`output_dir'/02_summary"
	
// Import GBD functions
	adopath + `code_dir'/ado
	run "$prefix/WORK/04_epi/01_database/01_code/00_library/ado/calc_se.ado"


// Where is SMR from metanalysis 
local smr_data "`in_dir'/data/02_formatted/lt_SMR/lt_SMR_by_ncode.csv"

// Pull conversion table for ages to age_group_ids
	insheet using "`code_dir'/convert_to_new_age_ids.csv", comma names clear
		tostring age_start, force format(%12.2f) replace
		destring age_start, replace
		tempfile ages 
		save `ages', replace

// Grab populations 
	get_demographics, gbd_team("epi") 
	get_populations, year_id(`year') location_id(`location_id') sex_id(`sex') age_group_id($age_group_ids) clear
		tempfile pops 
		save `pops', replace

	// Pull location_id for this ihme_loc_id
	quiet run "$prefix/WORK/10_gbd/00_library/functions/create_connection_string.ado"
	create_connection_string, strConnection
	local conn_string = r(conn_string)
	odbc load, exec("SELECT ihme_loc_id, location_id FROM shared.location_hierarchy_history WHERE location_set_version_id = (SELECT location_set_version_id FROM shared.location_set_version WHERE location_set_id = 9 and end_date IS NULL)") `conn_string' clear
		keep if location_id == `location_id'
		local ihme_loc_id = ihme_loc_id

// Bring in mortality envelope by iso3/year/age/sex - TOTAL MORTALITY - create 1000 draws from mean, upper, lower
	import delimited using  "/share/gbd/WORK/02_mortality/03_models/5_lifetables/results/env_loc/with_shock/env_`ihme_loc_id'.csv", delim(",") varnames(1) clear
		keep if sex_id == `sex' & year_id == `year'
		gen ihme_loc_id = "`ihme_loc_id'"
		gen location_id = `location_id'
		drop if age_group_id > 21 | age_group_id == 1 
		keep ihme_loc_id location_id sex_id age_group_id year_id draw_*
		merge 1:1 age_group_id using `pops', assert(match) nogen
		levelsof ihme_loc_id, l(ihme_loc_ids)
		rename draw* env*
		tempfile totalmort
		save `totalmort', replace
	
// Bring in SMR mortality dataset - create 1000 draws
	import delimited using "`smr_data'", delim(",") varnames(1) clear asdouble
	rename age age_start 
	tostring age_start, force format(%12.2f) replace
	destring age_start, replace 
	merge m:1 age_start using `ages', assert(match) nogen

	** only generate draws once for each mean/upper/lower combo
	tempfile allncodes
	save `allncodes', replace
	keep ncode smr ll ul
	duplicates drop
	calc_se ll ul, newvar(smr_sd)
	forvalues i = 0/999 {
		gen smr_`i' = rnormal(smr, smr_sd)
	}
	merge 1:m ncode smr ll ul using `allncodes', assert(match) nogen
	keep ncode age_group_id smr_*
	save `allncodes', replace

// Loop over N-codes and generate excess mortality 
	levelsof ncode, local(ncodes) clean
	foreach ncode of local ncodes {
		use `allncodes', clear
		keep if ncode == "`ncode'"
		merge 1:m age_group_id using `totalmort', assert(match) nogen
		forvalues i = 0/999 {
			replace env_`i' = (env_`i' / pop) * (smr_`i' - 1)
			rename env_`i' draw_`i'
		}
		merge m:1 age_group_id using `ages', assert(match) nogen
		drop age_group_id
		rename age_start age
		keep location_id year_id age sex_id draw_*
		order location_id year_id sex_id age, first
		tempfile emr_`ncode'
		save `emr_`ncode'', replace
	}	

	if `sex' == 1 {
		local sex_string male
	}
	if `sex' == 2 {
		local sex_string female
	}

	tempfile appended
	foreach n of local ncodes {
		cap mkdir "`draw_dir'/`n'"
		
	// Select the part of data we want to save
		use `emr_`n'', clear
		keep age draw*
		
	// Save draws
		local filename "f_`ihme_loc_id'_`year'_`sex_string'.csv"
		format draw_* %16.0g
		order age, first
		sort age
		export delimited "`draw_dir'/`n'/`filename'", delim(",") replace

	// Append to later save appended summary stats
		gen ncode = "`n'"
		cap confirm file `appended'
		if !_rc append using `appended'
		save `appended', replace
	}
	
// Save summary files
	fastrowmean draw_*, mean_var_name("mean")
	fastpctile draw_*, pct(2.5 97.5) names(ll ul)
	drop draw_*
	sort_by_ncode ncode, other_sort(age)
	format mean ul ll %16.0g
	export delimited "`summ_dir'/`filename'", delim(",") replace


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

