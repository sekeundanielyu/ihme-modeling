// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Author: 		Lily Alexander
// Date: 		May 10, 2016
// Project:		RISK
// Purpose:		Clean bone mineral density extractions for 2015 and save in epi format for upload to DisMod
** **************************************************************************
** RUNTIME CONFIGURATION
** **************************************************************************
// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		set mem 12g
		set maxvar 32000
	// Set to run all selected code without pausing
		set more off
	// Set graph output color scheme
		set scheme s1color
	// Remove previous restores
		cap restore, not
	// Reset timer (?)
		timer clear	
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

// Set up locals 
	local data_dir "J:/WORK/05_risk/risks/metab_bmd/data/exp/BMD_search"
	local dismod_dir "J:/WORK/05_risk/risks/metab_bmd/data/exp/2443/input_data" 

// Bring in country codes 
	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & inlist(level, 3, 4)

	keep ihme_loc_id location_id 
	
	rename ihme_loc_id iso3 

	tempfile country_codes
	save `country_codes', replace

// Bring in data 
	import excel using "`data_dir'/GBD2015_BMD_extraction.xlsx", firstrow clear 

// Clean up extraction 
	renvars, lower 
	drop if nid == . // these were empty rows that were inserted between extractions in order to make distinctions between studies 

	// For studies that apply to multiple locations, duplicate that row 
	levelsof iso3, local(countries)

	foreach iso3 of local countries { 
		di "`iso3'"
		if regexm("`iso3'", ",") { 
			expand 2 if iso3 == "`iso3'", gen(dup)
		}

		else {
			di in red "no duplicates"
		}
	}

	replace iso3 = "BEL" if regexm(iso3, "BEL") & dup == 1 
	replace country = "Belgium" if iso3 == "BEL"
	replace iso3 = "GBR_4619" if regexm(iso3, "GBR_4619") & dup == 0 
	replace country = "North West England" if iso3 == "GBR_4619"

	drop dup 

	// Need to duplicates observations for Indian states because we only report by urban/rural
	replace iso3 = "IND_43908" if iso3 == "IND_4841" // study was conducted in Andhra Pradesh villages so code as rural 
	replace iso3 = "IND_43891" if iso3 == "IND_4860" // study was conducted in affluent areas of Pune, India so code as urban 

	// Merge on location_ids for iso3s where we don't have them 
	merge m:1 iso3 using `country_codes', keep(3) nogen 

	// Rename variables for template 
	rename bmd_value_gr_cm2_standardized mean 
	rename standard_deviation_standardized standard_deviation

	gen standard_error = standard_deviation / sqrt(effective_sample_size)

// Replace missing age_start and age_end using mean age and sd of age 
	replace age_start = mean_age - 1.96 * sd_mean_age if age_start == . 
	replace age_end = mean_age + 1.96 * sd_mean_age if age_end == . 

	drop if age_start == . & age_end == . 

	replace age_start = round(age_start)
	replace age_end = round(age_end)
// Validation check 
	drop if mean < 0 

// Create necessary variables for epi uploader template 

	gen modelable_entity_id = 2443
	gen modelable_entity_name = "Low bone mineral density mean"
	gen representative_name = "Nationally representative only"
	gen urbanicity_type = "Mixed/both"
	replace urbanicity_type = "Urban" if inlist(location_id, 43880, 43891) 
	replace urbanicity_type = "Rural" if location_id == 43908

	replace sex = strproper(sex)

	gen uncertainty_type = "Effective sample size" if standard_error == . 
	replace uncertainty_type = "Standard error" if standard_error != . 
	gen uncertainty_type_value = . 
	gen lower = . 
	gen upper = . 

	destring location_id, replace
	rename zotero_citation field_citation_value 

	gen unit_value_as_published = 1 
	gen unit_type = "Person"
	gen measure = "continuous"	
	gen recall_type = "Lifetime" 
	gen source_type = "Survey - cohort"
	gen description = "" 
	gen case_definition = "" 
	gen case_name = "" 
	gen is_outlier = 0 
	gen underlying_nid = . 
	gen sampling_type = . 
	gen recall_type_value = . 
	gen input_type = "" 
	gen sample_size = . 
	gen cases = . 
	gen design_effect = . 
	gen case_diagnostics = . 
	gen note_SR = "" 
	gen note_modeler = "" 
	gen row_num = . 
	gen parent_id = . 
	gen response_rate = . 
	gen data_sheet_file_path = "" 

	destring nid, replace 
	rename country location_name 

// Keep only necessary variables 
	local variables row_num modelable_entity_id modelable_entity_name description field_citation_value measure	nid	file location_name	location_id	location_name	/// 
	sex	year_start	year_end	age_start	age_end	measure	mean	lower	upper	standard_error	effective_sample_size	/// 
	uncertainty_type uncertainty_type_value	representative_name	urbanicity_type	case_definition	extractor ///
	unit_value_as_published source_type is_outlier underlying_nid /// 
	sampling_type recall_type recall_type_value unit_type input_type sample_size cases design_effect site_memo case_name /// 
	case_diagnostics note_SR note_modeler data_sheet_file_path parent_id case_name response_rate

	keep `variables'

// Save in dismod folder so that we can upload!
	export excel using "`dismod_dir'/compiled_2015_bmd_estimates.xlsx", firstrow(variables) sheet("extraction") replace
