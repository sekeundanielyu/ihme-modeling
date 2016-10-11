// Cleaning NLD data

	clear
	set more off, perm

local check = 0
if `check' == 1 {
local 1 "J:"
local 2 "/clustertmp/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/03b_EN_matrices/02_temp/03_data/00_cleaned"
}	
	
	** import macros
global prefix `1'
local output_data_dir `2'

// Insheet codebook
	use "$prefix/LIMITED_USE/PROJECT_FOLDERS/NLD/INJURY_SURVEILLANCE_SYSTEM/NLD_ISS_1998_2012_ECODE_ACAUSE_MAPPING.DTA", clear
	rename ecode ecode_num
	rename acause ecode
	drop sequela
	drop if ecode_num == . | ecode_num == 99
	tempfile ecodes
	save `ecodes'
	
// Insheet raw data
	import delimited using "$prefix/LIMITED_USE/PROJECT_FOLDERS/NLD/INJURY_SURVEILLANCE_SYSTEM/NLD_ISS_1998_2012_HOSP_INJ_Y2014M02D10.CSV", delim(";") clear
	rename ecode ecode_num
	merge m:1 ecode_num using `ecodes'
		drop if _merge != 3
		drop _merge
	// Reformat n-codes
	tostring ncode, replace
	gen final_ncode_1 = "N" + ncode
	rename ecode final_ecode_1
	gen iso3 = "NLD"
	rename hospitalized inpatient
	keep iso3 year age sex final_ecode_1 final_ncode_1 inpatient
	order iso3 year age sex final_ecode_1 final_ncode_1 inpatient


// Drop inpatients - new NLD data (HDR) has almost total coverage, so that will probably capture all the inpatients from this dataset
	drop if inpatient == 1

// Save cleaned data
	export delimited using "`output_data_dir'/cleaned_nld_iss.csv", delim(",") replace
	