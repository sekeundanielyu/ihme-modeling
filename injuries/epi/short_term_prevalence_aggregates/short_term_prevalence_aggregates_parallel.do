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
		local 4 "05a"
		local 5 scaled_short_term_en_prev_yld_by_platform
		local 6 "/share/code/injuries/ngraetz/inj/gbd2015"
		local 7 165
		local 8 2010
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
	adopath + "`code_dir'/ado"

// Load file of zero draws to copy where missing location/year/sex
insheet using "`in_dir'/parameters/zero_draws.csv", comma names clear
	tempfile zero_draws
	save `zero_draws', replace

// Load all short-term prevalence
	use "/share/injuries/03_steps/`date'/05a_scaled_short_term_en_prev_yld_by_platform/03_outputs/01_draws/prev/`location_id'/prevalence_`year'_`sex'.dta", clear

// Aggregate to E-code
	fastcollapse draw_*, type(sum) by(ecode inpatient age)

// Convert to age_group_id
	preserve
		insheet using "`code_dir'/convert_to_new_age_ids.csv", comma names clear
		rename age_start age
		tempfile age_ids 
		save `age_ids', replace
	restore
	merge m:1 age using `age_ids', keep(3) nogen
	drop age 

// Loop over all E-code/platforms and save in upload folders (make a zero prevalence file if missing E-code/platform)
load_params
tempfile all_prev
save `all_prev', replace
levelsof ecode, l(ecodes)
foreach ecode of global modeled_e_codes {
	forvalues platform = 0/1 {
		if `platform' == 0 {
			local save_dir = "/share/injuries/04_COMO_input/03_st_prev/outpatient/`ecode'"
			cap mkdir "`save_dir'"
		}
		if `platform' == 1 {
			local save_dir = "/share/injuries/04_COMO_input/03_st_prev/inpatient/`ecode'"
			cap mkdir "`save_dir'"
		}
		use `all_prev', clear
		keep if ecode == "`ecode'" & inpatient == `platform'
		count
		if _N == 0 {
			use `zero_draws', clear
			outsheet using "`save_dir'/5_`location_id'_`year'_`sex'.csv", comma names replace
		}
		if _N != 0 {
			keep age_group_id draw_*
			outsheet using "`save_dir'/5_`location_id'_`year'_`sex'.csv", comma names replace
		}
	}
}

// Load all long-term prevalence
	use "/share/injuries/03_steps/`date'/06b_long_term_final_prev_by_platform/03_outputs/01_draws/`location_id'/prevalence_`location_id'_`year'_`sex'.dta", clear

// Aggregate to E-code
	fastcollapse draw_*, type(sum) by(ecode inpatient age)

// Convert to age_group_id
	merge m:1 age using `age_ids', keep(3) nogen
	drop age 

// Loop over all E-code/platforms and save in upload folders (make a zero prevalence file if missing E-code/platform)
load_params
tempfile all_lt_prev
save `all_lt_prev', replace
levelsof ecode, l(ecodes)
foreach ecode of global modeled_e_codes {
	forvalues platform = 0/1 {
		if `platform' == 0 {
			local save_dir = "/share/injuries/04_COMO_input/03_lt_prev/outpatient/`ecode'"
			cap mkdir "`save_dir'"
		}
		if `platform' == 1 {
			local save_dir = "/share/injuries/04_COMO_input/03_lt_prev/inpatient/`ecode'"
			cap mkdir "`save_dir'"
		}
		use `all_lt_prev', clear
		keep if ecode == "`ecode'" & inpatient == `platform'
		count
		if _N == 0 {
			use `zero_draws', clear
			outsheet using "`save_dir'/5_`location_id'_`year'_`sex'.csv", comma names replace
		}
		if _N != 0 {
			keep age_group_id draw_*
			outsheet using "`save_dir'/5_`location_id'_`year'_`sex'.csv", comma names replace
		}
	}
}

// Load all non-shock short-term incidence
	use "/share/injuries/03_steps/`date'/04b_scaled_short_term_en_inc_by_platform/03_outputs/01_draws/nonshocks/collapsed/incidence_`location_id'_`year'_`sex'.dta", clear

// Aggregate to E-code
	fastcollapse draw_*, type(sum) by(ecode inpatient age)

// Convert to age_group_id
	preserve
		insheet using "`code_dir'/convert_to_new_age_ids.csv", comma names clear
		rename age_start age
		tempfile age_ids 
		save `age_ids', replace
	restore
	merge m:1 age using `age_ids', keep(3) nogen
	drop age 

// Loop over all E-code/platforms and save in upload folders (make a zero prevalence file if missing E-code/platform)
load_params
tempfile all_prev
save `all_prev', replace
levelsof ecode, l(ecodes)
foreach ecode of global nonshock_e_codes {
	forvalues platform = 0/1 {
		if `platform' == 0 {
			local save_dir = "/share/injuries/04_COMO_input/03_st_prev/outpatient/`ecode'"
			cap mkdir "`save_dir'"
		}
		if `platform' == 1 {
			local save_dir = "/share/injuries/04_COMO_input/03_st_prev/inpatient/`ecode'"
			cap mkdir "`save_dir'"
		}
		use `all_prev', clear
		keep if ecode == "`ecode'" & inpatient == `platform'
		count
		if _N == 0 {
			use `zero_draws', clear
			outsheet using "`save_dir'/6_`location_id'_`year'_`sex'.csv", comma names replace
		}
		if _N != 0 {
			keep age_group_id draw_*
			outsheet using "`save_dir'/6_`location_id'_`year'_`sex'.csv", comma names replace
		}
	}
}

// END

