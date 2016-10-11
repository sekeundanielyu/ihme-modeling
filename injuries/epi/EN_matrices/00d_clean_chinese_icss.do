// Cleaning CHN data
	
	clear
	set more off, perm

local check = 99
if `check' == 1 {
local 1 "J:"
local 2 "/snfs2/HOME/ngraetz/local/inj/gbd2015"
local 3 "/clustertmp/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/03b_EN_matrices/02_temp/03_data/00_cleaned"
local 4 "/snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/03b_EN_matrices/02_temp/02_logs"
}	
	
// import macros
global prefix `1'
local code_dir `2'
local output_data_dir `3'
local log_dir `4'

// Settings
	local input_dir "$prefix/LIMITED_USE/PROJECT_FOLDERS/CHN/GBD_COLLABORATORS/INJURY_COMPREHENSIVE_SURVEILLANCE_STUDY"
	

// Append datasets
	local files: dir "`input_dir'" files "*.DTA", respectcase
	local files = subinstr(`"`files'"',`"""',"",.)
	clear
	cap erase `appended'
	tempfile appended
	local ds 0
	foreach f of local files {
	// Import
		use  "`input_dir'/`f'", clear
		cap gen year = year(admissiondate)
		tostring id, replace
		replace id = "ds_`ds'_" + id
		keep if icd10_stcode != "" & icd10_vycode != ""
		cap keep id sex year age icd10*
		if _rc keep id sex age icd10*
		
	// Append
		cap confirm file `appended'
		if !_rc append using `appended'
		save `appended', replace
		
	// go to next dataset
		local ++ds
	}

// Assert that data is clean
	** sex
	assert inlist(sex,1,2)
	
	** age
	assert age < 120

// Bring in ICD mapping ado
	adopath + "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	
// Map ICD-codes
	map_icd icd10_stcode, icd_version(10) prefix($prefix) mapping(yld)
		rename yld_cause final_ncode_1
	map_icd icd10_vycode, icd_version(10) prefix($prefix) mapping(yld)
		rename yld_cause final_ecode_1
		
// Add characteristics of dataset
	gen iso3 = "CHN"
	gen inpatient = 0
	rename icd10_stcode icd10_ncode
	rename icd10_vycode icd10_ecode
	keep iso3 year age sex final_ecode_1 final_ncode_1 inpatient icd10_ncode icd10_ecode
	order iso3 year age sex final_ecode_1 final_ncode_1 inpatient icd10_ncode icd10_ecode

// Drop garbage codes, N-codes that are coded as E-codes, E-codes that are coded as N-codes -- only keep obs with an N-code and E-code
	keep if final_ecode_1 != "" & final_ncode_1 != ""
		drop if final_ecode_1 == "_gc"
		drop if final_ncode_1 == "_gc"
	drop if regexm( final_ecode_1, "N")
	gen keep = substr( final_ncode_1, 4, 1)
	keep if keep == ""
	drop keep
	
// Save cleaned data
	export delimited using "`output_data_dir'/cleaned_chinese_icss.csv", delim(",") replace
	