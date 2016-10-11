	
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		set odbcmgr unixodbc
	}
	
// Import macros
	local check 99
	if `check' == 1 {
		local 1 /snfs1
		local 2 /snfs3/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/03b_EN_matrices/02_temp/03_data/01_prepped
		local 3 /snfs3/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/03b_EN_matrices/02_temp/03_data
		local 4 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/03b_EN_matrices/02_temp/02_logs
	}
	global prefix `1'
	local prepped_dir `2'
	local appended_dir `3'
	local log_dir `4'
	
adopath + "$prefix/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2013/01_code/dev_IB/ado"
adopath + "$prefix/WORK/04_epi/01_database/01_code/04_models/prod"
// load_params

// Write log
	cap log using "`log_dir'/02_append_en_data.smcl", replace
	if !_rc local close_log 1
	else local close_log 0
	
// Import datasets
	local datasets: dir "`prepped_dir'" files "prepped_*"
	local datasets = subinstr(`"`datasets'"',`"""',"",.)
	
	tempfile appended
	foreach ds of local datasets {
		import delimited `prepped_dir'/`ds', delim(",") clear
		gen ds = "`ds'"
		cap confirm file `appended'
		if !_rc append using `appended'
		save `appended', replace
	}

// Try dropping inp-only n-code cases from China NISS
foreach ncode of global inp_only_ncodes	{
drop if n_code == "`ncode'" & ds == "prepped_chinese_niss.csv"
}
// Also dropping N14 (other dislocations) from inj_fires (PengPeng confirmed this was a coding error in his mapping of their E/N codes to ours)
drop if n_code == "N14" & ds == "prepped_chinese_niss.csv" & e_code == "inj_fires"

	save `appended', replace
	
	// Merge on super region
	** here we want to bring in the GBD super region map from the SQL server to get the super region number for the iso3 codes of all of the data
	clear
	odbc load, exec("SELECT ihme_loc_id, location_name, location_id, location_type, super_region_name FROM shared.location_hierarchy_history WHERE (location_type = 'admin0' OR location_type = 'admin1' OR location_type = 'admin2') AND location_set_version_id = (SELECT location_set_version_id FROM shared.location_set_version WHERE location_set_id = 9 and end_date IS NULL)") dsn(strDSN)
	rename ihme_loc_id iso3
	keep iso3 super_region super_region_name
	gen high_income=0
	replace high_income=1 if super_region_name=="High-income"
	keep iso3 high_income 
	tempfile iso3_to_sr_map
	save `iso3_to_sr_map', replace
	
	** merge this on
	merge 1:m iso3 using `appended', assert(match master)
	keep if _m == 3
	drop _m
	
	** save this dataset to examine which country data we have
	preserve
	keep if e_code == "inj_war" | e_code == "inj_disaster"
	export delimited using "`appended_dir'/../04_diagnostics/country_specific_shocks_data.csv", delim(",") replace
	restore
	
	// For diagnosing countries with high spinal lesions
	// outsheet using "/snfs3/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2013/03_steps/2014_05_30/03b_EN_matrices/03_outputs/03_other/data_by_countries.csv", comma names replace
	
	drop iso3 location_id year ds
	drop if n_code==""
// Group by desired level and pivot so that N-codes are columns
	collapse (sum) cases, by(e_code n_code high_income age sex inpatient)
	
	reshape wide cases, i(e_code high_income age sex inpatient) j(n_code) string
	** missing values after reshape are really 0's
	foreach var of varlist cases* {
		replace `var' = 0 if `var' == .
	}
	rename cases* *
	
// Create e-code totals column
	egen totals = rowtotal(N*)
	
// drop medical misadventure e-codes b/c we will map them 100% to medical misadventure N-code
	drop if e_code == "inj_medical"
	
// Save
	compress
	export delimited using "`appended_dir'/02_appended.csv", delim(",") replace
	
	if `close_log' log close
	