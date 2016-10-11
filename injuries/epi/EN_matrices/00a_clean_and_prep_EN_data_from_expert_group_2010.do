
// Prep stata
	clear
	set more off, perm

// Import macros
	global prefix `1'
	local inj_dir `2'
	local prepped_dir `3'
	local ages `4'
	local code_dir `5'

// Set other macros
	local country_codes "$prefix/DATA/IHME_COUNTRY_CODES/IHME_COUNTRY_CODES_ALT_SPELL_Y2013M08D12.DTA"
	local map_dir "`inj_dir'/02_inputs/parameters/maps"
	local en_map "`map_dir'/map_EN_data_from_expert_group_2010.xls"
	
// Import params
	adopath + `code_dir'/ado
	load_params
	
// Set up necessary maps
	// Country name spellings
	use "`country_codes'", clear
	rename name countryname
	keep countryname location_id
	duplicates drop
	tempfile alt_spell
	save `alt_spell'
	
	// Country name to iso3
	// odbc load, exec("SELECT location_id,local_id from v_locations") clear dsn(epi)
	quiet run "/snfs1/WORK/10_gbd/00_library/functions/create_connection_string.ado"
	create_connection_string, strConnection
	local conn_string = r(conn_string)
	odbc load, exec("SELECT ihme_loc_id as iso3, location_id FROM shared.location_hierarchy_history WHERE location_set_version_id = (SELECT location_set_version_id FROM shared.location_set_version WHERE location_set_id = 9 and end_date IS NULL)") `conn_string' clear
	merge 1:m location_id using `alt_spell', keep(match) nogen
	tempfile name_iso3_map
	save `name_iso3_map'
	
	// E/N map for expert group data
	import excel ext_code=D e_code=G using "`en_map'", sheet("e_code") cellrange(A2) clear
	drop if e_code == ""
	tempfile e_map
	save `e_map'
	
	import excel seq_code=A n_code=H using "`en_map'", sheet("n_code") cellrange(A2) clear
	drop if n_code == ""
	tempfile n_map
	save `n_map'

// Import data
	import delimited using "`inj_dir'/02_inputs/data/01_raw/EN_data/EN_data_from_expert_group_2010.csv", delim(",") clear
	keep countryname age sex ext_code seq_code cases outcome
	
	** fix age-group naming
	gen dash_ix = strpos(age,"-")
	replace dash_ix = 3 if age == "85+"
	gen age_num = substr(age,1,dash_ix-1)
	drop dash_ix
	destring age_num, replace
	replace age_num = 0 if age == "<1"
	replace age_num = . if age == "Unknown"
	drop age
	rename age_num age
	local num_ages = wordcount("`ages'") - 1
	forvalues x = 1/`num_ages' {
		local start_age = word("`ages'",`x')
		local end_age = word("`ages'",`x'+1)
		replace age = `start_age' if age >= `start_age' & age < `end_age'
	}
	local final_age = word("`ages'",`num_ages'+1)
	replace age = `final_age' if age >= `final_age'
	
	** encode sex
	rename sex sextext
	gen sex = .
	replace sex = 1 if sextext == "Male"
	replace sex = 2 if sextext == "Female"
	drop sextext
	
// Map to iso3 & clean
	merge m:1 countryname using `name_iso3_map', assert(match using)
	keep if _m == 3
	drop _m
	drop countryname
	
	// Gen inpatient variable
	assert outcome != ""
	gen inpatient = 0
	replace inpatient = 1 if outcome == "inpatient"
	drop outcome
	
// Merge on E/N mapping
	merge m:1 ext_code using `e_map', keep(match) nogen
	merge m:1 seq_code using `n_map', keep(match) nogen
	
// drop any "too aggregated" N-codes
levelsof e_code, l(e_codes) c
foreach e of local e_codes {
	local drop 1
	foreach f of global modeled_e_codes {
		if regexm("`e'","`f'") local drop 0
	}
	if `drop' drop if e_code == "`e'"
}
	
// Save desired variables
	keep iso3 location_id age sex inpatient e_code n_code cases ext_code seq_code
	export delimited using "`prepped_dir'/prepped_expert_group_en_data.csv", delim(",") replace
	