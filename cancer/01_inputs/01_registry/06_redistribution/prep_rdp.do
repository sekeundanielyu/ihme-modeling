
// Purpose:	called by submit_rdp to create a file that can be submitted to redistribution

** ****************************************************************
** Get additional information
** ****************************************************************
// Get cause restricitons
	use "$j/WORK/00_dimensions/03_causes/gbd2015_causes_all.dta", clear
	keep if substr(acause, 1, 4) == "neo_"
	keep acause *_age_* male female
	tempfile cause_restrictions
	save `cause_restrictions', replace

// Get garbage code remap (for ICD9 coding systems with codes that are mapped to ICD10)
	import delim "$j/WORK/07_registry/cancer/01_inputs/programs/redistribution/data/ICD10_to_ICD9_garbage_remap.csv", clear varnames(1) case(preserve)
	keep if inlist(data_type, "both", "$data_type")
	keep ICD10 ICD9_detail
	rename (ICD10 ICD9_detail) (acause new_cause)
	gen coding_system = "ICD9_detail"
	tempfile garbage_recode
	save `garbage_recode', replace

** ************************
** format file for redistribution
** ************************
// GET DATA
	use "$input_folder/05_acause_disaggregated_$data_type.dta", clear

// Keep only relevant data
	keep $metric_name* iso3 subdiv location_id national source NID registry gbd_iteration year_start year_end sex coding_system acause cause
	drop if regexm(acause, "hiv")

// Replace garbage codes with causes
	replace acause = cause if acause == "_gc"

// Set all coding systems to ICD10 and ICD9_detail, since these are the only ones processed by RDP 
	gen has_9 = 1 if coding_system == "ICD9_detail"
	bysort location_id iso3 subdiv registry sex year*: egen uid_has_9 = total(has_9)
	replace coding_system = "ICD9_detail" if uid_has_9 > 0  
	replace coding_system = "ICD10" if coding_system != "ICD9_detail"
	drop *has_9

	// Recode ICD9_detail coding systems that contain ICD10 codes
	count if coding_system == "ICD9_detail"
	if r(N) {
		merge m:1 coding_system acause using `garbage_recode', keep(1 3) nogen
		replace acause = new_cause if new_cause != ""
	}

	// Collapse
	collapse (sum) $metric_name*, by(iso3 subdiv location_id national source NID registry gbd_iteration year_start year_end sex coding_system acause) fast

// Rename deaths to cases so that it can go through cancer redistribution without a lot of fuss
	if "$data_type" == "mor" {
		quietly foreach var of varlist deaths* {
			local nn = subinstr("`var'","deaths","cases",.)
			rename `var' `nn'
		}
	}

// Apply restrictions
	// Reshape everything long
		egen obs = group(location_id iso3 subdiv national source registry NID gbd_iteration year_start year_end coding_system sex), missing
		preserve
			keep obs location_id iso3 subdiv national source registry NID gbd_iteration year_start year_end
			duplicates drop
			tempfile UIDs
			save `UIDs', replace
		restore
		drop location_id iso3 subdiv national source registry NID gbd_iteration year_start year_end
		foreach i of numlist 1/26 {
			capture gen cases`i' = 0
			replace cases`i' = 0 if cases`i' == .
		}
		aorder
		drop cases1 cases4-cases6 cases26
		reshape long cases@, i(obs sex coding_system acause) j(gbd_age)
		gen age = (gbd_age - 6)*5
		replace age = 0 if gbd_age == 2
		replace age = 1 if gbd_age == 3
	
	// Merge with restrictions
		merge m:1 acause using `cause_restrictions', keep(1 3) nogen
		quietly foreach var of varlist *_age_start {
			replace `var' = 0 if `var' == .
		}
		quietly foreach var of varlist *_age_end {
			replace `var' = 99 if `var' == . | `var' == 80
		}
		quietly foreach var of varlist male female {
			replace `var' = 1 if `var' == .
		}
		drop if sex == 1 & male == 0
		drop if sex == 2 & female == 0
		
	// Apply restrictions
		local yl = "$yll_or_yld"
		replace acause = "ZZZ" if (sex == 1 & male == 0) | (sex == 2 & female == 0)
		replace acause = "ZZZ" if age < `yl'_age_start & age > `yl'_age_end
		replace acause = "C80" if coding_system == "ICD10" & (acause == "ZZZ" | acause == "195")
		replace acause = "195" if coding_system == "ICD9_detail" & (acause == "ZZZ" | acause == "C80")
		collapse (sum) cases*, by(obs sex coding_system acause gbd_age) fast
		
	// Reshape wide
		capture drop age male female *_age_start *_age_end
		reshape wide cases, i(obs sex coding_system acause) j(gbd_age)
		egen cases1 = rowtotal(cases*)
		foreach i of numlist 1/26 {
			capture gen cases`i' = 0
			replace cases`i' = 0 if cases`i' == .
		}
		merge m:1 obs using `UIDs', keep(1 3) assert(3) nogen

// SAVE
	compress
	aorder
	save "$output_folder/06_pre_rdp_$data_type.dta", replace
	save "$output_folder/_archive/06_pre_rdp_$data_type_$today.dta", replace
	capture saveold "$output_folder/_archive/06_pre_rdp_$data_type_$today.dta", replace	

** ************************
** End Prep-RDP
** ************************
