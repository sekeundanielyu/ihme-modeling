// submit prevalence extraction jobs

if c(os) == "Unix" {
	local prefix "/home/j"
	global prefix "/home/j"
	set more off
	set odbcmgr unixodbc
}
else if c(os) == "Windows" {
	local prefix "J:"
	global prefix "J:"
}
set more off
clear all
cap restore, not
cap set maxvar 20000
set seed 12345
adopath + "`prefix'/FILEPATH"
adopath + "`prefix'/FILEPATH"
local root "`prefix'/FILEPATH"

if "`1'" == "" {
local 1 137
local 2 test_march_21_2017
local 3 incidence
local 4 inc
local 5 1
}

local bundle_id `1'
local date `2'
local measure `3'
local short_measure `4'
local inp_only `5'

cap mkdir "$prefix/FILEPATH`date'"

quiet run "$prefix/FILEPATH"

local ms_vers = "v3"
local write_date = YYY_MM_DD


import delimited "$prefix/FILEPATH", delim(",") varn(1) case(preserve) clear
	rename bundle_acause_rei acause
keep if bundle_id == `bundle_id'
local acause = acause

use "FILEPATH", clear
rename cf_final mean
rename variance standard_error
replace standard_error = sqrt(standard_error)
split acause, p("#")
rename acause2 bundle_id
drop acause1
destring bundle_id, replace
keep if bundle_id == `bundle_id'
keep NID location_id year age sex mean standard_error bundle_id
	rename NID nid
	rename age age_start
	rename year year_start
	tostring sex, replace
	replace sex = "Male" if sex == "1"
	replace sex = "Female" if sex == "2"
tempfile all_nr
save `all_nr', replace

if `inp_only' == 0 {
	use "FILEPATH", clear
}
if `inp_only' == 1 {
	use "FILEPATH", clear
}
if `inp_only' == 2 {
	use "FILEPATH", clear
}
if `inp_only' == 3 {
	use "FILEPATH", clear
}
if `inp_only' == 4 {
	use "FILEPATH", clear
}
drop mean standard_error
merge 1:1 nid location_id year_start age_start sex bundle_id using `all_nr', keep(3) nogen

// Drop data outside of age restrictons by cause
preserve
	quiet run "$prefix/FILEPATH"
	create_connection_string, server("SERVER") database(SERVER)
	local conn_string = r(conn_string)
	odbc load, exec("QUERY") `conn_string' clear
		tempfile acauses
		save `acauses', replace
	odbc load, exec("QUERY") `conn_string' clear
		tempfile meta_ids
		save `meta_ids', replace
	odbc load, exec("QUERY") `conn_string' clear
		merge m:1 cause_metadata_type_id using `meta_ids', keep(3) nogen
	keep if cause_metadata_type == "yld_age_end" | cause_metadata_type == "yld_age_start"
	merge m:1 cause_id using `acauses', keep(3) nogen
	drop cause_metadata_type_id
	rename cause_metadata_value value
	reshape wide value, i(cause_id acause) j(cause_metadata_type, string)
	rename value* *
	destring yld*, replace
	keep if acause == "`acause'"
	local age_end = yld_age_end
	local age_start = yld_age_start
	if "`acause'" == "gyne_other" {
		local age_start = 15
		local age_end = 80
	}
	if "`acause'" == "imp_or_env" {
		local age_end = 80
		local age_start = 0
	}
restore
// Drop restricted ages groups
drop if age_start < `age_start'
if `age_end' != 80 {
	drop if age_start > `age_end' + 4
}

// Final formatting
	cap replace recall_type = "Period: years"
	cap replace urbanicity_type = "Mixed/both"
	// cap drop design_effect uncertainty_type
	cap drop uncertainty_type_value uncertainty_type
	gen uncertainty_type_value = .
	gen uncertainty_type = "Standard error"
	replace upper = .
	replace lower = .
	drop cv_
	// gen cv_marketscan = 1

// Final correcting for noise-reduced means going over 1
	replace cases = sample_size * mean
	if "`short_measure'" == "prev" {
		replace cases = sample_size if cases > sample_size
		replace mean = 1 if mean > 1
	}

// Save US aggregate rows
preserve
	set seed 12345
	local vars_to_collapse = ""
	drop egeoloc
	foreach var of varlist * {
		if "`var'" != "location_id" & "`var'" != "location_name" & "`var'" != "cases" & "`var'" != "sample_size" & "`var'" != "mean" & "`var'" != "standard_error" {
			local vars_to_collapse = "`vars_to_collapse'" + " `var'"
		}
	}

	fastcollapse cases sample_size, type(sum) by(`vars_to_collapse')
	gen mean = cases / sample_size
	gen standard_error = sqrt(cases) / sample_size
	gen location_id = 102
	gen location_name = "United States"
	tempfile us_aggregate
	save `us_aggregate', replace
restore
append using `us_aggregate'

// add cols for 2016 elmo reqs
gen seq = .

// Adjust rates for maternal MEs using live birth events
if `bundle_id' == 79 | `bundle_id' == 646 | `bundle_id' == 74 | `bundle_id' == 75 | `bundle_id' == 423 | `bundle_id' == 77 | `bundle_id' == 422 | `bundle_id' == 667 | `bundle_id' == 76 {
	preserve
		quiet run "$prefix/FILEPATH"
			create_connection_string, server("SERVER") database("SERVER")
			local conn_string = r(conn_string)
			odbc load, exec("QUERY") `conn_string' clear
			rename age_group_years_start age_start
			tempfile age_ids
			save `age_ids', replace
		quiet run "$prefix/FILEPATH"

		get_covariate_estimates, covariate_name_short(asfr) clear

			keep location_id year_id age_group_id sex_id mean_value
			rename year_id year_start
			merge m:1 age_group_id using `age_ids', nogen keep(3)
			rename sex_id sex
			tostring sex, replace
			replace sex = "Male" if sex == "1"
			replace sex = "Female" if sex == "2"
			tempfile asfr
			save `asfr', replace
	restore
	merge 1:1 location_id year_start age_start sex using `asfr', keep(3) nogen
	replace sample_size = sample_size * mean_value
	replace mean = cases / sample_size
}

// Covariates and save
foreach year in 2000 2010 2012 {
	gen cv_marketscan_all_`year' = 0
	gen cv_marketscan_inp_`year' = 0
}

// set age end to .999 where age start is 0 to improve dismod models
replace age_end = 0.999 if age_start == 0
// drop US level data
drop if location_id == 102


if `inp_only' == 1 {
	// Fix 0s
	preserve
		use "$prefix/FILEPATH", clear
		sum cf_final if cf_final != 0
		local min_value = r(min)
	restore
	replace mean = 0 if mean < `min_value'
	replace cases = mean * sample_size

	// WRITE TO THE BUNDLE DIRECTORY FOR MODELERS
	cap mkdir "$prefix/FILEPATH"
	local out_dir "$prefix/FILEPATH"
	cap mkdir "`out_dir'"

	replace cv_marketscan_inp_2000 = 1 if year_start == 2000
	replace cv_marketscan_inp_2010 = 1 if year_start == 2010
	replace cv_marketscan_inp_2012 = 1 if year_start == 2012

	export excel "FILEPATH", firstrow(var) sheet("extraction") replace

	cap mkdir "$prefix/FILEPATH"
	saveold "$prefix/FILEPATH", replace
}

if `inp_only' == 0 {
	// Fix 0s
	preserve
		use "$prefix/FILEPATH", clear
		sum cf_final if cf_final != 0
		local min_value = r(min)
	restore
	gen min_value = `min_value'
	replace mean = 0 if mean < min_value
	replace cases = mean * sample_size

	// WRITE TO THE BUNDLE DIRECTORY FOR MODELERS
	cap mkdir "$prefix/FILEPATH"
	local out_dir "$prefix/FILEPATH"
	cap mkdir "`out_dir'"

	replace cv_marketscan_all_2000 = 1 if year_start == 2000
	replace cv_marketscan_all_2010 = 1 if year_start == 2010
	replace cv_marketscan_all_2012 = 1 if year_start == 2012
	export excel "FILEPATH", firstrow(var) sheet("extraction") replace
	cap mkdir "$prefix/FILEPATH"
	saveold "$prefix/FILEPATH", replace
}

if `inp_only' == 3 {
	// Fix 0s
	preserve
		use "$prefix/FILEPATH", clear
		sum cf_final if cf_final != 0
		local min_value = r(min)
	restore
	gen min_value = `min_value'
	replace mean = 0 if mean < min_value
	replace cases = mean * sample_size

	// WRITE TO THE BUNDLE DIRECTORY FOR MODELERS
	cap mkdir "$prefix/FILEPATH"
	local out_dir "$prefix/FILEPATH"
	cap mkdir "`out_dir'"

	replace cv_marketscan_all_2000 = 1 if year_start == 2000
	replace cv_marketscan_all_2010 = 1 if year_start == 2010
	replace cv_marketscan_all_2012 = 1 if year_start == 2012
	export excel "FILEPATH", firstrow(var) sheet("extraction") replace
	cap mkdir "$prefix/FILEPATH"
	saveold "$prefix/FILEPATH", replace
}

if `inp_only' == 4 {
	// Fix 0s
	preserve
		use "$prefix/FILEPATH", clear
		sum cf_final if cf_final != 0
		local min_value = r(min)
	restore
	gen min_value = `min_value'
	replace mean = 0 if mean < min_value
	replace cases = mean * sample_size

	// WRITE TO THE BUNDLE DIRECTORY FOR MODELERS
	cap mkdir "$prefix/FILEPATH"
	local out_dir "$prefix/FILEPATH"
	cap mkdir "`out_dir'"

	replace cv_marketscan_all_2000 = 1 if year_start == 2000
	replace cv_marketscan_all_2010 = 1 if year_start == 2010
	replace cv_marketscan_all_2012 = 1 if year_start == 2012
	export excel "FILEPATH", firstrow(var) sheet("extraction") replace
	cap mkdir "$prefix/FILEPATH"
	saveold "$prefix/FILEPATH", replace
}

if `inp_only' == 2 {
	// Fix 0s
	preserve
		use "$prefix/FILEPATH", clear
		sum cf_final if cf_final != 0
		local min_value = r(min)
	restore
	replace mean = 0 if mean < `min_value'
	replace cases = mean * sample_size

	replace cv_marketscan_all_2000 = 1 if year_start == 2000
	replace cv_marketscan_all_2010 = 1 if year_start == 2010
	replace cv_marketscan_all_2012 = 1 if year_start == 2012
	cap mkdir "$prefix/FILEPATH"
	saveold "$prefix/FILEPATH", replace
}


// END
