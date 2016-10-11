// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 		March 7, 2016
// Project:		RISK
// Purpose:		Compile MICS, DHS, and GENACIS data for ever partnered 
** **************************************************************************
// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		set mem 12g
	// Set to run all selected code without pausing
		set more off
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}

** ***********************************************************************************************
// STEP 1: Compile all data extracted from surveys
** ***********************************************************************************************
// Make locals for relevant files and folders
	local data_dir "$prefix/WORK/05_risk/risks/abuse_ipv_exp/data/exp/03_adjust/ever_partnered"
	local files: dir "`data_dir'" files "*.dta"
	local outdir  "$prefix/WORK/05_risk/risks/abuse_ipv_exp/data/exp/03_adjust"
	local dismod_dir "$prefix/WORK/05_risk/risks/abuse_ipv_exp/data/exp/9380/input_data" 


// Prepare location names & demographics for 2015

	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & inlist(level, 3, 4)

	keep ihme_loc_id location_id location_ascii_name super_region_name super_region_id region_name region_id

	tempfile countrycodes
	save `countrycodes', replace


clear
// Append datasets for each extracted microdata survey series/country together (going to take care of DHS separately)
	foreach file of local files {
			di in red "`file'"
			append using "`data_dir'/`file'", force
		
	}

	tempfile master
	save `master', replace


** ***********************************************************************************************
// STEP 2: Standardize datasets
** ***********************************************************************************************

// Means are named differently 

	foreach var in ever_partnered mean { 
		replace parameter_value = `var' if parameter_value == . 
	} 

	drop ever_partnered mean all_one

// Standard error also named differently 
	
	replace standard_error = se if standard_error == . 
	recode standard_error (0 = .) // standard error shouldn't be zero so want to replace this with missing and rely on sample size 

// Sample size 
	replace sample_size = ss if sample_size == . 
	drop sd ss se

// Have age_start; don't need age variable
	drop age 
	replace age_end = age_start + 4 if age_end == . 

// Year 
	split path, p("/") 
	rename path5 year_start_dhs 
	split year_start_dhs, p("_") 
	drop year_start_dhs
	destring year_start_dhs1, replace
	rename year_start_dhs2 year_end_dhs
	destring year_end_dhs, replace 
	replace year_start = year_start_dhs1 if year_start == . 
	replace year_end = year_end_dhs if year_end == . 
	replace year_end = year_start if year_end == . 

	drop path1 path2 path3 path4 path6 path7 year_start_dhs1 year_end_dhs

// locations 
	drop location_type
	replace ihme_loc_id = iso3 if ihme_loc_id == "" 
	drop iso3 location_name super_region_name location_ascii_name super_region_id region_id region_name

// sex 
	tostring sex, replace
	replace sex = "Female" // only women 

// file paths 
	replace path = file_path + "/" + file_name if path == "" 
	drop file_path file_name 

// representativeness 
	decode representative_name, gen(rep_name_new) 
	rename representative_name rep_name_numeric
	rename rep_name_new representative_name	

	replace representative_name = "Nationally representative only" if representative_name == "" 
	replace representative_name = "Nationally representative only" if representative_name == "Nationally representative"
	replace representative_name = "Not representative" if representative_name == "Subnationally representative" 
		
// urbanicity 
	replace urbanicity_type = "Mixed/both" if urbanicity_type == "representative" 
	replace urbanicity_type = "Mixed/both" if urbanicity_type == "" 
	replace urbanicity_type = "Urban" if urbanicity_type == "urban" 
	replace urbanicity_type = "Rural" if urbanicity_type == "rural" 

// Validation checks
	rename parameter_value mean 

	recode standard_error (0=.) 
	replace orig_uncertainty_type = "ESS" if standard_error == . & sample_size != .
	replace orig_uncertainty_type = "SE" if orig_uncertainty_type == ""
	gen uncertainty_type = "" 
	replace uncertainty_type = "Effective sample size" if orig_uncertainty_type == "ESS" 
	replace uncertainty_type = "Standard error" if orig_uncertainty_type == "SE" 
	gen uncertainty_type_value = . 
	** Dismod can't calculate error on 0 or 1 means so we will replace 0's with a small value and 1's with a large
	recode mean (0=.0001) (1=.999)
	drop if mean == . | (sample_size == . & standard_error == .) // Need mean and some variance metric
	drop if mean > 1

// Join on country IDs
	rename location_id location_id_old 

	merge m:1 ihme_loc_id using `countrycodes', keep(3) nogen
	drop location_id_old 
	rename location_ascii_name location_name 

// Create case definitions for tracking purposes
	gen case_definition = "Currently or formerly in marriage/union" if regexm(path, "DHS") 
	replace case_definition = "Ever married or lived with a man in a marriage-like relationship" if regexm(path, "GENACIS") 
	replace case_definition = "Ever married or lived with a man" if regexm(path, "MICS") 

	tempfile all 
	save `all', replace

// Outsheet 

// NIDS 
	// Load get NIDS function 
	run "$prefix/WORK/01_covariates/common/ubcov_central/_functions/get_nid.ado"
	get_nid, filepath_full(path)
	replace nid = record_nid if nid == .  
	drop record_nid

	// A few missing NIDs even after running get_nid
	replace nid = 76705 if regexm(path, "IDN_DHS6_2012") 
	replace nid = 20617 if regexm(path, "PER_EXP_DHS1_1986") 
	replace nid = 21421 if regexm(path, "PHL_DHS5_2008") 
	replace nid = 111432 if regexm(path, "SEN_DHS6_2012_2013") 
	replace nid = 82832 if regexm(path, "CAF_MICS4_2010_2011") 


** ***********************************************************************************************
// STEP 3: Apply Wilson Interval score method 
** ***********************************************************************************************
    /*
    // Fill in variance using p*(1-p)/n if variance is missing
    gen variance = (mean*(1-mean))/sample_size

    // Replace variance using Wilson Interval Score Method: p*(1-p)/n + 1.96^2/(4*(n^2)) if p*n or (1-p)*n is < 20
    gen cases_top = (1-mean)*sample_size
    gen cases_bottom = mean*sample_size

    replace variance = ((mean*(1-mean))/sample_size) + ((1.96^2)/(4*(sample_size^2))) if (cases_top < 20 | cases_bottom < 20)


** ***********************************************************************************************
// STEP 4: Convert to logit space
** ***********************************************************************************************

	// Delta method 
	gen variance_new = variance * (1/(mean*(1-mean)))^2
	gen standard_error_new = sqrt(variance)

    drop standard_error // drop old standard error 
    rename standard_error_new standard_error 

	// replace mean with logit of mean 
	replace mean = logit(mean)
*/


** ***********************************************************************************************
// STEP 4: Upload as incidence
** ***********************************************************************************************
	
	//replace mean = mean * sample_size


** ***********************************************************************************************
// STEP 5: Format for epi uploader 
** ***********************************************************************************************

// FORMAT FOR EPI UPLOADER 
	
	drop  health_state survey_name 

	gen modelable_entity_id =  9380 
	gen modelable_entity_name = "ever_partnered"
	gen description = "GBD 2015: ever partnered covariate"
	gen measure = "incidence"

	decode source_type, gen(source_type_new)
	replace source_type_new = "Survey - other/unknown" 
	drop source_type 
	rename source_type_new source_type

	rename sample_size effective_sample_size

	gen unit_value_as_published = 1 
	gen extractor = "lalexan1" 
	gen is_outlier = 0 
	gen underlying_nid = . 
	gen sampling_type = "" 
	gen recall_type = "Point" 
	gen recall_type_value = "" 
	gen unit_type = "Person" 
	gen input_type = "" 
	gen sample_size = . 
	gen cases = . 
	gen design_effect = . 
	gen site_memo = "" 
	gen case_name = "" 
	gen case_diagnostics = "" 
	gen response_rate = .
	gen note_SR = "" 
	gen note_modeler = "" 
	gen row_num = . 
	gen parent_id = . 
	gen data_sheet_file_path = "" 
		
	gen lower = . 
	gen upper = . 
	rename path file


// Drop duplicates for two surveys
	duplicates tag nid location_id year_start year_end age_start age_end representative_name urbanicity_type case_definition, gen(dup)
	bysort nid location_id year_start year_end age_start age_end representative_name urbanicity_type case_definition: gen num = _n if dup == 1 
	drop if dup == 1 & num == 2 
	drop dup num

	keep row_num modelable_entity_id modelable_entity_name description measure	nid	file location_name	location_id	location_name	/// 
	sex	year_start	year_end	age_start	age_end	measure	mean	lower	upper	standard_error	effective_sample_size	/// 
	uncertainty_type uncertainty_type_value	representative_name	urbanicity_type	case_definition	extractor ///
	unit_value_as_published source_type is_outlier underlying_nid /// 
	sampling_type recall_type recall_type_value unit_type input_type sample_size cases design_effect site_memo case_name /// 
	case_diagnostics response_rate note_SR note_modeler data_sheet_file_path parent_id


	order row_num modelable_entity_id modelable_entity_name description measure	nid	file location_name	location_id	location_name	/// 
	sex	year_start	year_end	age_start	age_end	measure	mean	lower	upper	standard_error	effective_sample_size	/// 
	uncertainty_type uncertainty_type_value	representative_name	urbanicity_type	case_definition	extractor ///
	unit_value_as_published source_type is_outlier underlying_nid /// 
	sampling_type recall_type recall_type_value unit_type input_type sample_size cases design_effect site_memo case_name /// 
	case_diagnostics response_rate note_SR note_modeler data_sheet_file_path parent_id

	tempfile all 
	save `all', replace 

// Save for Dismod upload
	// export excel using "`dismod_dir'/gbd2015_ever_partnered_$S_DATE.xlsx", firstrow(variables) sheet("extraction") replace

// Bring in old version of upload to merge on to replace values to re-upload 
	import excel using "$prefix/WORK/05_risk/risks/abuse_ipv_exp/data/exp/9380/review/download/me_9380_ts_2016_03_15__165811.xlsx", firstrow clear 
	duplicates tag nid location_id year_start year_end age_start age_end representative_name urbanicity_type case_definition, gen(dup)
	bysort nid location_id year_start year_end age_start age_end representative_name urbanicity_type case_definition: gen num = _n if dup == 1 
	drop if dup == 1 & num == 2
	drop dup num

	rename mean mean_old 
	rename standard_error standard_error_old 

	//drop source_type
	//gen source_type = 26 
	//label define source 26 "Survey - other/unknown" 

	foreach var in sampling_type recall_type_value site_memo case_name case_diagnostics note_SR note_modeler { 
		tostring `var', replace
	}


	merge 1:1 nid location_id year_start year_end age_start age_end representative_name urbanicity_type case_definition using `all', keep(3) nogen

	drop mean_old standard_error_old
	//replace lower = . 
	//replace upper = . 

	replace measure = "incidence"
	tostring recall_type_value, replace 
	tostring sampling_type, replace 
	replace recall_type_value = ""
	replace sampling_type = ""

	sort row_num

// Export 
	export excel using "$prefix/WORK/05_risk/risks/abuse_ipv_exp/data/exp/9380/review/upload/re_upload_ever_partnered_as_incidence.xlsx", firstrow(variables) sheet("extraction") replace

// Save another dataset in second hand smoke folder that has a sheet with variable definitions
	//export excel using "`outdir'/compiled_revised.xlsx", firstrow(variables) sheet("Data") sheetreplace
	
