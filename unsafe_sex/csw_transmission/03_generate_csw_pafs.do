// apply csw proportions to squeezed hiv models to generate proportion of hiv attributable to csw transmission

 
// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		macro drop _all
		set mem 700m
		set maxvar 32000
	// Set to run all selected code without pausing
		set more off
	// Set to enable export of large excel files
		set excelxlsxlargefile on
	// Set graph output color scheme
		set scheme s1color
	// Remove previous restores
		cap restore, not
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}
// Close previous logs
	cap log close
	
// Load the PDF appending application
	//do "$prefix/Usable/Tools/ADO/pdfmaker_acrobat11.do"

// create locals
local version			2
local data				"$prefix/WORK/05_risk/risks/unsafe_sex/products/pafs/scaled_paf/`version'"
local output			"$prefix/WORK/05_risk/risks/unsafe_sex/products/pafs"

//local archived_data		"$prefix/WORK/05_risk/risks/unsafe_sex/data/exp/raw/compiled_squeeze_models_9717_9714_9716.dta" // Old results of squeeze.

run "$prefix/WORK/10_gbd/00_library/functions/get_draws.ado"
run "$prefix/WORK/10_gbd/00_library/functions/get_outputs.ado"

// location_ids
	
	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & inlist(level, 3, 4)

	keep ihme_loc_id location_id location_ascii_name super_region_name super_region_id region_name region_id
	
	rename ihme_loc_id iso3 
	tempfile country_codes
	save `country_codes', replace

	qui: levelsof location_id, local(locations)
	


*** * ***************************************************************************************
*** LOAD CODCORRECT RESULTS 
*** * ***************************************************************************************

clear

// run "get output" functions
	adopath + "$j/WORK/10_gbd/00_library/functions"


// call results for HIV deaths in years of interest by age and sex
	
	local ages 8 9 10 11 12 13 14 15 16 17 18 19 20 21
	local measures 1 4 // for deaths and YLLs 

	local count = 0

foreach meas of local measures { 
	foreach age of local ages { 
		get_outputs, topic(cause) cause_id(298) measure_id(`meas') gbd_round(2015) year_id(all) age_group_id(`age') sex_id(2) location_id("all") clear

		tempfile deaths 
		save `deaths', replace 

		tempfile data_`count'
		save `data_`count'', replace

		local count = `count' + 1 
	}
}  

	// Append together 
	local terminal = `count' - 1
	
	clear
	forvalues x = 0/`terminal' {
		di `x'
		qui: cap append using `data_`x'', force
	}

// Reshape 
	drop measure_id
	reshape wide val upper lower, i(location_id year_id age_group_id) j(measure, string)

	rename valdeath mean_abs_death 
	rename valyll mean_abs_yll

	tempfile hiv_cod
	save `hiv_cod', replace
	

*** * ********************************************************************************************
*** LOAD PROPORTION DUE TO CSW RESULTS
*** * ********************************************************************************************
  /*
   run "$prefix/WORK/10_gbd/00_library/functions/get_estimates.ado"
   get_estimates, gbd_team(epi) gbd_id(2636) status("best") clear
   save "$prefix/WORK/05_risk/risks/unsafe_sex/products/pafs/csw_dismod_results.dta", replace 
*/

	use "J:/WORK/05_risk/risks/unsafe_sex/products/pafs/csw_dismod_results.dta", clear 
	rename mean prop_sex_due_to_csw

	keep if inrange(age_group_id, 1, 21) & sex_id == 2

	tempfile csw_results
	save `csw_results', replace

*** * ******************************************************************************************
*** COMPILE SQUEEZED DISMOD RESULTS INTO A SINGLE FILE
*** * ******************************************************************************************

// Here we need to bring in the 3 models: Proportion HIV due to IDU, proportion HIV due to other and proportion HIV due to sex 

/*
	odbc load, exec("SELECT modelable_entity_id, modelable_entity_name FROM epi.modelable_entity WHERE modelable_entity_name IN ('Proportion HIV due to intravenous drug use','Proportion HIV due to other','Proportion HIV due to sex')") dsn(epi) clear
	levelsof modelable_entity_id, local(MEs) c

	local MEs 2637 2638 2639

	local x=0
	foreach me of local MEs { 
		get_draws, gbd_id_field(modelable_entity_id) gbd_id(`me') sex_ids(2) status(best) source(epi) clear
		
		local x = `x' + 1
		tempfile `x'
		save ``x'', replace
	 
	}

	clear
	forvalues i = 1/`x' {
		append using ``i''
	}

	** re-scale HIV models and apply as direct PAF for unsafe sex and IV drug use
	forvalues draw = 0/999 {
		bysort location_id year_id age_group_id sex_id: egen scalar = total(draw_`draw')
		replace draw_`draw' = draw_`draw' / scalar
		rename draw_`draw' paf_yll_`draw'
		gen double paf_yld_`draw' = paf_yll_`draw'
		drop scalar
	}

	egen paf_mean = rowmean(paf_yll_*)
	egen paf_upper = rowpctile(paf_yll_*), p(97.5)
	egen paf_lower = rowpctile(paf_yll_*), p(2.5)


	drop paf_yll_* paf_yld_* 

	export excel using "$prefix/WORK/05_risk/risks/unsafe_sex/products/pafs/scaled_paf/squeezed_dismod_models.xlsx", firstrow(variables) replace 

	*/

*** * ******************************************************************************************
*** MERGE DISMOD AND CODCORRECT RESULTS
*** * ******************************************************************************************

import excel using "$prefix\WORK\05_risk\risks\unsafe_sex\products\pafs\scaled_paf\squeezed_dismod_models.xlsx", firstrow clear

// keep only relevant observations. female and healthstate == hiv_sex
	//keep if sex == 2
	keep if modelable_entity_id == 2638 // HIV due to sex 

// merge in outcome data
	merge m:1 location_id year_id age_group_id sex_id using `hiv_cod', keep(3) nogen

// merge in csw data
	merge m:1 location_id year_id age_group_id sex_id using `csw_results', keep(3) nogen

// only want to apply CSW proportions for those age 15-45. Set proportion csw for other ages = 0
	replace prop_sex_due_to_csw = 0 if inlist(age_group_id, 1, 2, 3, 4, 5, 6, 7, 14, 15, 16, 17, 18, 19, 20, 21)

// create non-csw scalar. this will be the proportion of sexually transmitted hiv not attributable to csw = 1 - prop(csw)
	gen prop_non_csw = 1 - prop_sex_due_to_csw

// create attributable deaths for each age, sex, risk entry
	gen att_deaths_all_sex = paf_mean * mean_abs_death
	gen att_ylls_all_sex = paf_mean * mean_abs_yll
	
	gen att_deaths_non_csw = paf_mean * mean_abs_death * prop_non_csw
	gen att_ylls_non_csw = paf_mean * mean_abs_yll * prop_non_csw
	
// gen variables with proportion of hiv deaths/ylls attributable to non_csw sexual transmission for each age group
	gen paf_deaths_non_csw = att_deaths_non_csw / mean_abs_death
	gen paf_ylls_non_csw = att_ylls_non_csw / mean_abs_yll 
	
// variable with overall proportion attributable to non-CSW sexual transmission
	gen prop_sexual_non_csw = paf_mean * prop_non_csw
	
// rename for clarity
	rename paf_mean prop_sexual_all
 
// keep only relevant data:  healthstate = hiv_sex
	keep if modelable_entity_id == 2638
	keep if sex_id == 2

	tempfile all 
	save `all', replace

// Merge on age groups 
	insheet using "`output'/convert_to_new_age_ids.csv", comma names clear 
	merge 1:m age_group_id using `all', keep(3) nogen

	merge m:1 location_id using `country_codes', keep(3) nogen

	rename age_start age 

// keep only relevant vars
	keep age iso3 year sex prop_sexual_all mean_abs_death mean_abs_yll prop_sex_due_to_csw prop_non_csw att_deaths_all_sex att_ylls_all_sex att_deaths_non_csw att_ylls_non_csw paf_deaths_non_csw paf_ylls_non_csw prop_sexual_non_csw

// save
	save "`output'/csw_pafs.dta", replace
	export excel using "`output'/csw_pafs.xlsx", firstrow(var) replace



	
	
	
