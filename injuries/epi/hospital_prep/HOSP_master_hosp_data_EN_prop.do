// Generate file with adjustment factor for E/N reporting proportion by iso3/year/age/sex 
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

	local function _inj
	local out_dir "`prefix'/WORK/04_epi/01_database/02_data/`function'/02_nonlit"
	local tmp_dir "`clustertmp'/WORK/04_epi/01_database/02_data/`function'/02_nonlit"

** ADJUSTING NUMERATOR BY E-N FACTOR		
** **************************************************************************************
	local cutoff 0.45
	cap mkdir "`out_dir'/03_temp/EN_prop"
	
	// load hospital data and save in temporary folder
		use "`prefix'/WORK/06_hospital/02_database/data/hospital_epi.dta", clear
		gen cause_icd10 = cause_primary if icd_vers == "ICD10"
		gen cause_icd9 = cause_primary if icd_vers == "ICD9_detail"
		global prefix J:
		map_icd cause_icd10, icd_version(10) prefix($prefix) mapping(yld) detail
			rename yld_cause final_icd10
		map_icd cause_icd9, icd_version(9) prefix($prefix) mapping(yld) detail
			rename yld_cause final_icd9		
		gen final_cause = final_icd10 if icd_vers == "ICD10"
			replace final_cause = final_icd9 if icd_vers == "ICD9_detail"
		gen cause = regexm(final_cause, "inj_") | regexm(final_cause, "N")
		keep if cause == 1
		replace cause = 0
		replace cause = regexm(final_cause, "N")
		gen code = "Ncode" if cause == 1
		replace code = "Ecode" if cause == 0
		drop cause
		rename cases numerator
		keep location_id platform year_start year_end age_start age_end sex code numerator
		save "`out_dir'/03_temp/EN_prop/EN_hosp_inj.dta", replace
		cap restore, not
		
	// diagnose if the Ecode proportion meets the minimum requirement, and if not, drop data
		fastcollapse numerator, type(sum) by(location_id platform year_start year_end code)
		egen total = sum(numerator), by(location_id platform year_start year_end)
		gen prop = numerator / total
		drop if code == "Ncode" & prop != 1
		keep if prop < `cutoff' | (code == "Ncode" & prop == 1) // Keep if the proportion coded with E-codes is less than our cut-off OR 100% of patients are coded to N-code (that source will be missing an E-code proportion row, in that case)
		keep location_id platform year_start
		gen remove = 1
		tempfile remove
		save `remove', replace
		save "`out_dir'/03_temp/EN_prop/ineligible_country_years.dta", replace
		
		use "`out_dir'/03_temp/EN_prop/EN_hosp_inj.dta", clear
		merge m:1 location_id platform year_start using `remove'
		preserve
			keep location_id platform year_start remove
			duplicates drop
			export delimited "`out_dir'/03_temp/EN_prop/ineligible_country_years.csv", delim(",") replace
		restore
		keep if _merge == 1
		drop remove _merge
		save "`out_dir'/03_temp/EN_prop/EN_hosp_inj_eligible.dta", replace	
		
	// collapse to get country/year/sex/age-specific EN proportion	 (aggregate young and old people)
		replace age_start = 0 if age_start < 20
		replace age_end = 19 if age_end < 20
		replace age_start = 60 if age_start >= 60
		replace age_end = 99 if age_end >= 60

		fastcollapse numerator, type(sum) by(location_id platform year_start year_end age_start age_end sex code)
		egen total = sum(numerator), by(location_id platform year_start year_end age_start age_end sex)
		gen prop = numerator / total
		gen factor = 1 / prop
		drop if code == "Ncode"
		drop code numerator total prop
		
	// disaggregate the aggregated ages back in place
		count if age_start == 0
		gen age_0 = r(N)
		sum age_0
		local zero = r(mean)
		local row = r(N)
		expand 5 if age_start == 0
		foreach c of numlist 1/`zero' {
			foreach r of numlist 1/4 {
				local row_new = `row'+ (4 * `c' - 4) + `r'
				replace age_start = 1 in `row_new' if `r' == 1
				replace age_start = 5 in `row_new' if `r' == 2
				replace age_start = 10 in `row_new' if `r' == 3
				replace age_start = 15 in `row_new' if `r' == 4
				replace age_end = 5 in `row_new' if `r' == 1
				replace age_end = 9 in `row_new' if `r' == 2
				replace age_end = 14 in `row_new' if `r' == 3
				replace age_end = 19 in `row_new' if `r' == 4
			}
		}
		replace age_0 = 1 if age_start == 0 & age_end == 19
		replace age_end = 1 if age_0 == 1
		drop age_0
		
		count if age_start == 60
		gen age_60 = r(N)
		sum age_60
		local zero = r(mean)
		local row = r(N)
		expand 5 if age_start == 60
		foreach c of numlist 1/`zero' {
			foreach r of numlist 1/4 {
				local row_new = `row'+ (4 * `c' - 4) + `r'
				replace age_start = 65 in `row_new' if `r' == 1
				replace age_start = 70 in `row_new' if `r' == 2
				replace age_start = 75 in `row_new' if `r' == 3
				replace age_start = 80 in `row_new' if `r' == 4
				replace age_end = 69 in `row_new' if `r' == 1
				replace age_end = 74 in `row_new' if `r' == 2
				replace age_end = 79 in `row_new' if `r' == 3
				replace age_end = 99 in `row_new' if `r' == 4
			}
		}
		replace age_60 = 1 if age_start == 60 & age_end == 99
		replace age_end = 64 if age_60 == 1
		drop age_60
		
		rename platform notes
		sort location_id notes year_start year_end age_start age_end sex
		
		save "`out_dir'/03_temp/EN_prop/adjustment_factors.dta", replace