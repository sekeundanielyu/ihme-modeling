// DATE: JANUARY 21, 2014
// PURPOSE: FORMAT PHYSICAL ACTIVITY DATA SENT BY GBD COLLABORATORS IN MEXICO

// NOTES: 

// Set up
	clear all
	set more off
	set mem 2g
	capture restore not
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j "J:"
		version 11
	}
	
// Create locals for relevant files and folders
	local outdir "$j/WORK/05_risk/risks/activity/data/exp"
	
// Bring in file and drop all data that is not for physical activity
	insheet using "$j/DATA/MEX/GBD_COLLABORATOR_DATA/MEX_GBD_COLLABORATOR_DATA_1988_2012_NUTRITION_RISK_FACTOR_FINAL_Y2013M11D25.CSV", comma clear 
	keep if regexm(definition, "Proportion at level")
	keep if inlist(region, "Rural", "Urbana", "Nacional", "") // Drops rural/urban by region, but keeps state level data, as well as national
	
// Make variable names and format consistent with other survey extractions and epi template
	gen file = "$j/DATA/MEX/GBD_COLLABORATOR_DATA/MEX_GBD_COLLABORATOR_DATA_1988_2012_NUTRITION_RISK_FACTOR_FINAL_Y2013M11D25.CSV"
	
	rename year year_start
	gen year_end = year_start

	replace sex = "3" if sex == "both"
	replace sex = "2" if sex == "female"
	replace sex = "1" if sex == "male"

	gen age_start = substr(age_category, 1, 2)
	gen age_end = substr(age_category, -8, 2)
	replace age_end = "100" if age_start == ">="
	replace age_start = "25" if age_start == ">="
	destring age_start age_end sex, replace
	
	label define sexlabel 1 "Male" 2 "Female" 3 "Both", replace
	label values sex sexlabel

	rename indic_mean mean
	
	gen variance = standard_error^2

// Get subnational ids for Mexican states
	replace state = "Coahuila" if regexm(state, "Coahuila") // Named differently in database
	rename state location_name
	tempfile data_mex
	save `data_mex'

// Bring in country codes 
	clear
	#delim ;
	odbc load, exec("SELECT ihme_loc_id, location_name, location_id, location_type
	FROM shared.location_hierarchy_history 
	WHERE (location_type = 'admin0' OR location_type = 'admin1' OR location_type = 'admin2')
	AND location_set_version_id = (
	SELECT location_set_version_id FROM shared.location_set_version WHERE 
	location_set_id = 9
	and end_date IS NULL)") dsn(epi) clear;
	#delim cr
	
	keep if regexm(ihme_loc_id, "MEX")
	rename ihme_loc_id iso3
	

	merge 1:m location_name using `data_mex', keep(2 3 4 5) nogen
	replace iso3 = "MEX" if iso3 == ""
	
// Specify representativeness
	// Urban/Rural
		gen urbanicity_type = urban_rural == "na"
		replace urbanicity_type = 2 if urban_rural == "urban"
		replace urbanicity_type = 3 if urban_rural == "rural"
		label define urbanicity 0 "Unknown" 1 "Representative" 2 "Urban" 3 "Rural" 4 "Suburban" 5 "Peri-urban"
		label values urbanicity_type urbanicity
	
	// National/Subnational
		gen national_type = 1 if state_code == "33"  // Nationally representative
		replace national_type = 2 if state_code != "33" // Subnationally representative
		label define national 0 "Unknown" 1 "Nationally representative" 2 "Subnationally representative" 3 "Not representative"
		label values national_type national	
	
// There are Dismod models for physical activity, each with a different MET-min/week threshold so we will sum means across relevant categories
	// Model A: Percent inactive (<600 MET-min/week)
		preserve
		keep if regexm(definition, "<600")
		gen healthstate = "activity_inactive"
		tempfile inactive
		save `inactive'
		restore
	
	// Model B: Percent with low activity level (600 - 4000) MET-min/week
		preserve
		keep if !regexm(definition, "3999")
		local varlist iso3 region year_start year_end sex age_start age_end sample_size national_type urbanicity_type file citation
		collapse (sum) mean variance, by(`varlist')
		gen healthstate = "activity_low"
		tempfile lowactive
		save `lowactive'
		restore
		
	//  Model C: Percent low, moderate or highly active (>=600 MET-min/week)
		preserve
		keep if !regexm(definition, "<600")
		local varlist iso3 region year_start year_end sex age_start age_end sample_size national_type urbanicity_type file citation
		collapse (sum) mean variance, by(`varlist')
		gen healthstate = "activity_lowmodhigh"
		tempfile lowmodhighactive
		save `lowmodhighactive'
		restore
		
	// Model D: Percent moderate or highly active (>=4000 MET-min/week)
		preserve
		keep if regexm(definition, "7999") | regexm(definition, "8000")
		local varlist iso3 region year_start year_end sex age_start age_end sample_size national_type urbanicity_type file citation
		collapse (sum) mean variance, by(`varlist')
		gen healthstate = "activity_modhigh"
		tempfile modhighactive
		save `modhighactive'
		restore
		
	// Model E: Percent moderately active (4000 - 8000 MET-min/week)
		preserve
		keep if regexm(definition, "4000")
		local varlist iso3 region year_start year_end sex age_start age_end sample_size national_type urbanicity_type file citation
		collapse (sum) mean variance, by(`varlist')
		gen healthstate = "activity_mod"
		tempfile modactive
		save `modactive'
		restore
	
	// Model F: Percent highly active (>=8000 MET-min/week)
		preserve
		keep if regexm(definition, "8000")
		local varlist iso3 region year_start year_end sex age_start age_end sample_size national_type urbanicity_type file citation
		collapse (sum) mean variance, by(`varlist')
		gen healthstate = "activity_high"
		tempfile highactive
		save `highactive'
		restore

// Append data for all four models together to make master dataset	
	use `inactive', clear
	foreach dataset in lowactive modactive highactive lowmodhighactive modhighactive {
		append using ``dataset''
	}

// Keep only necessary variables
	keep iso3 year_start year_end sex age_start age_end mean sample_size citation file urbanicity_type national_type healthstate variance
	drop if sex == 3

// Calculate standard error for aggregated categories using variance
	gen standard_error = sqrt(variance)
	drop variance
	
// Format
	order iso3 national_type urbanicity_type year_start year_end sex age_start age_end healthstate mean standard_error sample_size
	sort iso3 national_type urbanicity_type year_start year_end sex age_start age_end
	gen nid = 129886
	gen survey_name = "Mexico GBD Collaborator Data"
	gen orig_uncertainty_type = "ESS"
	gen data_type = "Survey: other"
	gen source_type = "Survey"
	gen questionnaire = "similar to IPAQ"

// Save
	save "`outdir'/prepped/ensanut_formatted.dta", replace
	
