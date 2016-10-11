// *********************************************************
// Purpose:	Calculate bacterial vs viral meningitis ratio
// *********************************************************

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

// set locals
	// file path for inputs
	local in_dir "$prefix/temp/strUser/meningitis/04_models/gbd2015/02_inputs"

	// file for viral hospital data
	local viral_hosp "$prefix/WORK/04_epi/01_database/02_data/meningitis_other/1418/01_input_data/01_nonlit/01_hospital/meningitis_other_1418_apr_5_16.xlsx"
	// file for viral marketscan data
	local viral_ms "$prefix/WORK/04_epi/01_database/02_data/meningitis_other/1418/01_input_data/01_nonlit/marketscan/ALL_meningitis_other_1418_nr_inc_apr_15_2016.xlsx"

	// file for bacterial hospital data
	local bacterial_hosp "$prefix/WORK/04_epi/01_database/02_data/meningitis/1296/01_input_data/01_nonlit/01_hospital/meningitis_1296_apr_5_16.xlsx"
	// file for bacterial ms data
	local bacterial_ms "$prefix/WORK/04_epi/01_database/02_data/meningitis/1296/01_input_data/01_nonlit/marketscan/INP_ONLY_meningitis_1296_nr_inc_apr_15_2016.xlsx"

	// make bacterial hospital data inpatient only
	import excel "`bacterial_hosp'", firstrow clear
	drop if source_type == "Facility - outpatient"
	collapse(sum) cases sample_size, by(sex age_start age_end) fast
	gen type = "hospital"
	preserve

	// load bacterial marketscan data
	import excel "`bacterial_ms'", firstrow clear
	collapse(sum) cases sample_size, by(sex age_start age_end) fast
	gen type = "ms"
	tempfile ms_b
	save `ms_b'
	restore

	// append bacterial data
	append using `ms_b'
	collapse(sum) cases sample_size, by(sex age_start age_end) fast
	if age_start >= 80 {
		collapse(sum) cases sample_size, by(sex)
	}
	drop if age_end == 84 | age_end == 89 | age_end == 94 | age_start == 95
	gen inc_bacterial = cases / sample_size
	drop cases sample_size
	tempfile bacterial
	save `bacterial'

	// import viral hospital data (both inpatient and outpatient)
	import excel "`viral_hosp'", firstrow clear
	collapse(sum) cases sample_size, by(sex age_start age_end) fast
	gen type = "hospital"
	preserve

	// load viral marketscan
	import excel "`viral_ms'", firstrow clear
	collapse(sum) cases sample_size, by(sex age_start age_end) fast
	gen type = "ms"
	tempfile ms_v
	save `ms_v'
	restore

	// append viral data
	append using `ms_v'
	collapse(sum) cases sample_size, by(sex age_start age_end) fast
	if age_start >= 80 {
		collapse(sum) cases sample_size, by(sex)
	}
	drop if age_end == 84 | age_end == 89 | age_end == 94 | age_start == 95
	gen inc_viral = cases / sample_size
	drop cases sample_size

	// merge with bacterial
	merge 1:1 sex age_start age_end using `bacterial', nogen keep(1 3)
	gen ratio = inc_viral / inc_bacterial
	drop if age_start == 0 & age_end == 4

	foreach num of numlist 1/2 {
		count
		gen row = r(N)
		expand 2 if age_start == 0
		gene seqnum = _n
		replace age_start = .01 if row < seqnum & `num' == 1
		replace age_start = .1 if row < seqnum & `num' == 2
		drop row seqnum
	}
	sort sex age_start

	lowess ratio age_start if sex == "Male", gen(ratio_male) nograph
	lowess ratio age_start if sex == "Female", gen(ratio_female) nograph

	replace ratio = ratio_male if ratio_female == .
	replace ratio = ratio_female if ratio_male == .
	drop ratio_*

	gen age_group_id = _n + 1
	replace age_group_id = age_group_id - 20 if sex == "Male"
	gen sex_id = 2
	replace sex_id = 1 if sex == "Male"
	drop sex age_start age_end inc_*

	save "`in_dir'/bac_vir_ratio_2015.dta", replace
	
	clear
	