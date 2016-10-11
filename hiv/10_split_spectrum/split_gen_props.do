// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Generate proportions to split Spectrum results into subnationals


// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
		local country = "`1'"
		// local country = "KEN"
		di "`country'"
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local country = "KEN"
	}

** ***************************************************************************
** Set settings
	local cod_dir = "strPath"
	local pop_dir = "strPath"
	local env_dir = "strPath"
	local prop_out_dir = "/strPath"

	// Get locations of all child subnationals
	adopath + "strPath"
	
	// For Kenya, India, and South Africa, find child-to-parent mappings from Spectrum mapping files
	if inlist("`country'","KEN","IND","ZAF") {
		import delimited using "strPath/GBD_2015_countries.csv", varnames(1) clear
		split ihme_loc_id, parse("_")
		rename ihme_loc_id2 location_id
		destring location_id, replace
		gen parent_loc_id = iso3 + "_" + subnat_id
		keep ihme_loc_id location_id parent_loc_id
		
		if "`country'" == "IND" {
			// Split India minor territories from parent minor, which will be produced by subnat_aggregate.do
			drop if inlist(ihme_loc_id,"IND_44539","IND_44540")
			tempfile map
			save `map'
			clear all
			set obs 2
			gen ihme_loc_id = "IND_44539" in 1
			replace ihme_loc_id = "IND_44540" in 2
			gen location_id = 44539 in 1
			replace location_id = 44540 in 2
			gen parent_loc_id = "IND_minor"
			append using `map'
		}
		
		keep if regexm(ihme_loc_id,"`country'")
	}
	
	// For other countries, use the GBD hierarchy to specify the appropriate mappings, with specific handling for certain countries
	else {
		get_locations
		levelsof location_id if ihme_loc_id == "`country'", local(parent_id) c
		if "`country'" == "GBR" {
			replace parent_id = `parent_id' if parent_id == 4749 // Turn English children into GBR children
			drop if ihme_loc_id == "GBR_4749"
		}
		
		keep if parent_id == `parent_id'
		keep location_id ihme_loc_id
		gen parent_loc_id = "`country'"
	}
	drop if ihme_loc_id == "`country'"
	tempfile map
	save `map'

	// Generate numbered map for merging onto Spectrum output
	gen loc_num = _n
	keep ihme_loc_id loc_num
	local loc_count = _N
	tempfile map_num
	save `map_num'


** ***************************************************************************
** Import and format population data
	cd "`pop_dir'"
	use "population_gbd2015.dta" if year >= 1970 & ihme_loc_id != "`country'" & sex != "both", clear
	keep ihme_loc_id year age_group_name age_group_id sex pop
	merge m:1 ihme_loc_id using `map', keep(3) nogen // Get parent_loc_id

	// Save pops to merge onto CoD data
		preserve
		keep if age_group_id >= 2 & age_group_id <= 21
		replace age_group_name = "0" if age_group_id <= 4
		replace age_group_name = "80" if age_group_name == "80 plus"
		split age_group_name, parse(" to ")
		drop age_group_name age_group_name2
		rename age_group_name1 age
		destring age, replace
		replace age = 0 if age == 1
		keep ihme_loc_id year age_group_id age sex pop
		tempfile cod_pops
		save `cod_pops', replace
		restore

	// Save pops to merge onto compiled HIV-deleted LT for its own collapsing
	// Right now, we are assuming that the 80 to 85 mx  in the LTs is reasonably representative of the between-country proportions of the 80+ age group
		preserve
		keep if (age_group_id >= 5 & age_group_id <= 20) | age_group_id == 28 | age_group_id == 21
		replace age_group_name = "0" if age_group_name == "<1 year"
		replace age_group_name = "80" if age_group_name == "80 plus"
		split age_group_name, parse(" to ")
		drop age_group_name age_group_name2
		rename age_group_name1 age
		destring age, replace
		keep ihme_loc_id year age sex pop
		tempfile merge_pops
		save `merge_pops', replace
		restore

	keep if (age_group_id >= 5 & age_group_id <= 21 | age_group_id == 28)
	
	replace age_group_name = "0" if age_group_name == "<1 year" | age_group_name == "1 to 4"
	replace age_group_name = "80" if age_group_name == "80 plus"
	split age_group_name, parse(" to ")
	destring age_group_name1, replace
	rename age_group_name1 age
	
	collapse (sum) pop, by(ihme_loc_id parent_loc_id year age sex)
	bysort parent_loc_id year age sex: egen pop_prop = pc(pop), prop
	keep ihme_loc_id parent_loc_id year sex age pop_prop
	tempfile pop_props
	save `pop_props'


** ***************************************************************************
** Import and format CoD Data
	cd "`cod_dir'"
	import delimited using gpr_results.csv, delimit(",") clear
	rename gpr_mean deaths
	merge m:1 location_id using `map'
    count if _m == 2
    if _N != 0 & `r(N)' == 0 { // If we have ST GPR results for all subnationals, use those; otherwise, use population instead
        drop _m
		gen sex = "male" if sex_id == 1
		replace sex = "female" if sex_id == 2
		rename year_id year
		
		// Aggregate all neonatal age groups and 1 to 4 age group using population-weighted MX
		merge 1:1 ihme_loc_id sex year age_group_id using `cod_pops', keep(3) nogen // Keep the cod_pops here in case there are no ST-GPR results (KEN)
		drop age_group_id
		replace deaths = deaths * pop
		collapse (sum) deaths pop, by(ihme_loc_id parent_loc_id year age sex)

		bysort parent_loc_id year age sex: egen cod_prop = pc(deaths), prop
		keep ihme_loc_id year age sex cod_prop
		
	}
	else {
		use `cod_pops', clear
		merge m:1 ihme_loc_id using `map', keep(3) nogen
		drop age_group_id
		collapse (sum) pop, by(ihme_loc_id parent_loc_id year age sex)
		bysort parent_loc_id year age sex: egen cod_prop = pc(pop), prop
		keep ihme_loc_id year age sex cod_prop
	}

	tempfile cod_props
	save `cod_props' 


** ***************************************************************************
** Import and format HIV-deleted data
	cd "`env_dir'"
	use "compiled_lt_mx_mean.dta" if ihme_loc_id != "`country'" & age <= 80, clear
	merge m:1 ihme_loc_id using `map', keep(3) nogen
	
	gen sex_new = "male" if sex == 1
	replace sex_new = "female" if sex == 2
	drop sex
	rename sex_new sex

	merge 1:1 ihme_loc_id year age sex using `merge_pops', keep(3) nogen
	replace age = 0 if age < 5
	gen tot_death = mean_mx * pop
	collapse (sum) tot_death pop, by(ihme_loc_id parent_loc_id sex year age)
	
	bysort parent_loc_id year age sex: egen hivfree_prop = pc(tot_death), prop
	keep ihme_loc_id year sex age hivfree_prop
	tempfile hivfree_props
	save `hivfree_props'


** ***************************************************************************
** Merge all props together
	use `pop_props', clear
	// Merge in CoD props
		merge 1:1 ihme_loc_id year sex age using `cod_props'
		
		foreach vvv in year sex age {
			levelsof `vvv' if _m == 1 | _m == 2
		}
		keep if _m == 3
		drop _m

	// Merge in HIV-Free props
		merge 1:1 ihme_loc_id year sex age using `hivfree_props'
		foreach vvv in year sex age {
			levelsof `vvv' if _m == 1 | _m == 2
		}
		keep if _m == 3
		drop _m
		
	local miss_count = 0
	foreach var in hivfree_prop cod_prop pop_prop {
		di "`var'"
		count if `var' == .
		if `r(N)' > 0 local ++miss_count
	}
	if `miss_count' > 0 BREAK

** ***************************************************************************
** Output all proportions
	cd "`prop_out_dir'"
	save props_`country'.dta, replace
