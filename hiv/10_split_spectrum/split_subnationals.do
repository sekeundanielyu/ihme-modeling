// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Parallelization to split Spectrum national-level results into child subnationals
//					using CoD death data and populations


// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
		local country = "`1'"
		local spec_dir = "`2'"
		di "`country'"
		di "`spec_dir'"
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local country = "KEN_35626"
		local spec_dir = "strPath"
	}

	if !regexm("`country'","CHN") local parent_country = substr("`country'",1,3)
	else if inlist("`country'","CHN_354","CHN_361","CHN_44533") local parent_country = "CHN"
	else local parent_country = "CHN_44533"

** ***************************************************************************
** Set settings
	local prop_out_dir = "/ihme/gbd/WORK/02_mortality/03_models/hiv/spectrum_draws/subnat_props"

	// Identify the variables to split by cod props, population, and non-cod
	local cod_vars = "hiv_deaths new_hiv hiv_births pop_lt200 pop_200to350 pop_gt350 pop_art"
	local pop_vars = "suscept_pop pop_neg total_births"
	local hivfree_vars = "non_hiv_deaths" // Split these HIV-deleted numbers, at summary level

** ***************************************************************************
** Grab country-level proportions from split_gen_props.do
	cd "`prop_out_dir'"
	use props_`parent_country'.dta if ihme_loc_id == "`country'", clear
	if "`parent_country'" == "CHN_44533" replace parent_loc_id = "CHN"
	levelsof parent_loc_id, local(step_parent) c
	tempfile props
	save `props'

** ***************************************************************************
** Rescale Spectrum data by subnational splits
	cap insheet using "`spec_dir'/best/`step_parent'_ART_data.csv", comma clear
	if _rc {
		cap insheet using "`spec_dir'/stage_2/`step_parent'_ART_data.csv", comma clear
        if _rc {
            insheet using "`spec_dir'/stage_1/`step_parent'_ART_data.csv", comma clear
            local type = "stage_1"
        }
        else local type = "stage_2"
	}
	else local type = "best"
	gen ihme_loc_id = "`country'"

	merge m:1 ihme_loc_id year sex age using `props'
	
	foreach vvv in ihme_loc_id year sex age {
		levelsof `vvv' if _m == 1 | _m == 2
	}
	keep if _m == 3
	drop _m
		
	// Rescale vars by CoD hiv props
		foreach var in `cod_vars' {
			replace `var' = `var' * cod_prop
		}
		drop cod_prop

	// Rescale vars by pop props
		foreach var in `pop_vars' {
			replace `var' = `var' * pop_prop
		}
		drop pop_prop

	// Rescale vars by HIV-free props
		foreach var in `hivfree_vars' {
			replace `var' = `var' * hivfree_prop
		}
		drop hivfree_prop


** ***************************************************************************
** Output data
	cd "`spec_dir'/`type'"
	drop ihme_loc_id parent_loc_id
	outsheet using `country'_ART_data.csv, comma replace

