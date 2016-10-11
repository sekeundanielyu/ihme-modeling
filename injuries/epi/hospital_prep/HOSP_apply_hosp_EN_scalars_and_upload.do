// Apply EN proportion scalars to cases by cause/iso3/year/age/sex
// Add study-level covariates, save for upload
if c(os) == "Unix" {
	local prefix "/home/j"
	set more off
	set odbcmgr unixodbc
}
else if c(os) == "Windows" {
	local prefix "J:"
}
set more off
clear all
cap restore, not
cap set maxvar 20000
set seed 80085
adopath + "`prefix'/WORK/10_gbd/00_library/functions"
adopath + "`prefix'/WORK/04_epi/01_database/01_code/00_library/ado"
local repo = "H:/local/inj/gbd2015"
local me_id_file = "UPDATE_master_injury_me_ids.csv"
local function _inj
local scalar_dir "`prefix'/WORK/04_epi/01_database/02_data/`function'/02_nonlit"
local hosp_dir "`prefix'/WORK/04_epi/01_database/02_data"

local hosp_version = "mar_18_16"

// Load ME ids 
import delimited "`repo'/`me_id_file'", delim(",") varn(1) clear
	keep if injury_metric == "Adjusted data"
	keep modelable_entity_name modelable_entity_id
	tempfile me_ids
	save `me_ids', replace
// Load E-code names to merge on to ME ids 
insheet using "H:/local/inj/gbd2015/ecode_names.csv", comma names clear
	keep e_code e_code_name
	rename e_code_name modelable_entity_name
	merge 1:1 modelable_entity_name using `me_ids', keep(3) nogen
	save `me_ids', replace
	drop if e_code == "inj_war" | e_code == "inj_disaster" // No need to upload hospital data because we don't model these shock causes in Dismod.
	levelsof e_code, l(ecodes)
**// Load iso3:location_id map to apply to scalars file 
**	quiet run "`prefix'/WORK/10_gbd/00_library/functions/create_connection_string.ado"
**	create_connection_string, strConnection
**	local conn_string = r(conn_string)
**	odbc load, exec("SELECT ihme_loc_id as iso3, location_id, location_name FROM shared.location_hierarchy_history WHERE location_set_version_id = (SELECT location_set_version_id FROM shared.location_set_version WHERE location_set_id = 9 and **end_date IS NULL)") `conn_string' clear
**	duplicates drop
**	tempfile iso3s 
**	save `iso3s', replace
// Load EN proportion scalars
use "`scalar_dir'/03_temp/EN_prop/adjustment_factors.dta", clear
	gen cv_outpatient = 0 if notes == 1
	replace cv_outpatient = 1 if notes == 2
	drop notes
	// merge m:1 iso3 using `iso3s', keep(3) nogen
	// drop iso3
	tostring sex, replace force
	replace sex = "Male" if sex == "1"
	replace sex = "Female" if sex == "2"
	replace factor = 1 if location_id == 4645 & year_start == 2000 & age_start == 20
	replace factor = 1 if location_id == 4665 & year_start == 2000 & age_start == 55
	tempfile scalars 
	save `scalars', replace
// Load file that marks ineligible country/years in hospital data based on EN proportion
use "`scalar_dir'/03_temp/EN_prop/ineligible_country_years.dta", clear
	// merge m:1 iso3 using `iso3s', keep(3) nogen
	gen cv_outpatient = 0 if platform == 1
	replace cv_outpatient = 1 if platform == 2
	drop platform
	tempfile remove
	save `remove', replace

// Loop over raw hospital data, adjust with scalars, save for upload
foreach ecode of local ecodes {
	use `me_ids' if e_code == "`ecode'", clear
		levelsof modelable_entity_id, l(me_id)
		local me_name = modelable_entity_name
	import excel "`hosp_dir'/`ecode'/`me_id'/01_input_data/01_nonlit/01_hospital/`ecode'_`me_id'_`hosp_version'.xlsx", firstrow sheet("extraction") clear
		tostring modelable_entity_name, replace 
		replace modelable_entity_name = "`me_name'"
		tostring measure, replace
		replace measure = "incidence"
		gen cv_outpatient = 1 if regexm(source_type, "outpatient") == 1
		replace cv_outpatient = 0 if regexm(source_type, "inpatient") == 1
		cap assert cv_outpatient != .
			if _rc != 0 {
				di in red "Platforms missing for `ecode'"
				BREAK
			}
		merge m:1 location_id year_start cv_outpatient using `remove', keep(1) nogen
		merge m:1 location_id cv_outpatient year_start year_end age_start sex using `scalars', keep(3) assert(2 3) nogen // Only merging on age_start because data for young kids is saved as 0-4 and 0-1. Use same scalar for both (age_start == 0)
		** inflate numerator by factor
		replace factor = 0 if cases == 0 // Rows with 0 cases caused factor to be missing. Need to replace with 0 so that when we multiply we get 0*0=0 instead of 0*.=.
		count if factor == .
		cap assert r(N) == 0 // Assert that the only rows where we are missing a scalar are rows with 0 cases
			if _rc != 0 {
				di in red "Scalars missing for `ecode'"
				BREAK
			}
		replace factor = 1 if factor == .
		replace cases = cases * factor
		replace mean = cases / sample_size
		replace mean = 1 if mean > 1
		drop factor remove inp_all_correction_factor
		gen cv_medcare = 0
	export excel "`hosp_dir'/`ecode'/`me_id'/01_input_data/`ecode'_`me_id'_adjusted.xlsx", firstrow(var) sheet("extraction") replace 
}