// Cleaning NLD HDR data
	
	clear
	set more off, perm
	pause on

local check = 0
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
	local input_dir "$prefix/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2013/02_inputs/data/01_raw/EN_data"
	
	import delimited using "$prefix/LIMITED_USE/PROJECT_FOLDERS/NLD/NATIONAL_MEDICAL_REGISTRY_LMR/NLD_LMR_1998_2012_INJURIES_Y2014M02D20.CSV", delimiter(";")

// Assert that data is clean
	** sex
	assert inlist(sex,1,2)
	
	** age
	assert age < 120	
	
	** the code below is a faster way of doing what the loop above was doing
	expand number_raw

// Add an E to front of E-codes
	tostring ecode_icd, replace
	replace ecode_icd = "E" + ecode_icd
	
// Bring in ICD mapping ado
	adopath + "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	
// Map ICD-codes
	map_icd diagnosis_icd, icd_version(9) prefix($prefix) mapping(yld)
		rename yld_cause final_ncode_1
	map_icd ecode_icd, icd_version(9) prefix($prefix) mapping(yld)
		rename yld_cause final_ecode_1
		
// Add characteristics of dataset
	gen iso3 = "NLD"
	gen inpatient = 1
	rename diagnosis_icd icd9_ncode
	rename ecode_icd icd9_ecode
	keep iso3 year age sex final_ecode_1 final_ncode_1 inpatient icd9_ncode icd9_ecode
	order iso3 year age sex final_ecode_1 final_ncode_1 inpatient

// Drop garbage codes, N-codes that are coded as E-codes, E-codes that are coded as N-codes -- only keep obs with an N-code and E-code
	keep if final_ecode_1 != "" & final_ncode_1 != ""
		drop if final_ecode_1 == "_gc"
		drop if final_ncode_1 == "_gc"
	drop if regexm( final_ecode_1, "N")
	gen keep = substr( final_ncode_1, 4, 1)
	keep if keep == ""
	drop keep
	
// Save cleaned data
	export delimited using "`output_data_dir'/cleaned_hdr.csv", delim(",") replace
	