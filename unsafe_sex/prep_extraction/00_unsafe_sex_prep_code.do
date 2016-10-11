** **************************************************************************
// Date: 			3/19/2014
// Project:		RISK
// Purpose:		Preps extracted hiv transmission proportion data for upload into dismod.  

** **************************************************************************
** RUNTIME CONFIGURATION
** **************************************************************************
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
	
// Create timestamp for logs
	local c_date = c(current_date)
	local c_time = c(current_time)
	local c_time_date = "`c_date'"+"_" +"`c_time'"
	display "`c_time_date'"
	local time_string = subinstr("`c_time_date'", ":", "_", .)
	local timestamp = subinstr("`time_string'", " ", "_", .)
	display "`timestamp'"
	
// Set directory
	cd "$prefix/WORK/05_risk/risks/unsafe_sex"

// Set up get demographics 
	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & inlist(level, 3, 4)

	keep ihme_loc_id location_id location_ascii_name super_region_name super_region_id region_name region_id
	
	//tostring location_id, replace
	rename location_ascii_name country

	rename ihme_loc_id iso3

	tempfile isos 
	save `isos', replace

// Try get nids function for new UNAIDS reports 
	run "$prefix/WORK/01_covariates/common/ubcov_central/_functions/get_nid.ado"


// // create locals for relevant files and folders
	// local isodat  				"$prefix/DATA/IHME_COUNTRY_CODES/IHME_COUNTRYCODES.DTA" // NOTE: MAKE THIS A SQL PULL
	local data					"./data" 
	local output				"./products"
	local raw_data				"./data/exp/raw/unsafe_sex_extractions_revised.xlsx"
	local cdc_data   			"./data/exp/raw/unsafe_sex_extractions_usa_2015.xlsx"
	local epi_type				"$prefix/Project/Causes of Death/codem/models/A02/GBD 2013 HIV/Program_inputs/data/AIM_assumptions/classification/epi_class/defaults/epi_class_GBD.csv"
	local unaids_nids			"./data/exp/raw/UNAIDS_reports_NIDs.xlsx"
	local cdc_nids 				"$prefix/DATA/Incoming Data/USA/HIV_SURVEILLANCE_STATE_REPORTS"
	local outdir				"./data/exp/prepped"

** * ****************************************************************************************
** 	BRING IN DATA
** *****************************************************************************************

	// bring in data
		import excel using "`raw_data'", sheet("Extractions") firstrow clear

	// drop observations that are only for idu/csw prevalences and don't have transmission data
		drop if sexual_percent == . & IDU_percent == .

	// drop variables not related to proportions of transmission
		drop prevalence_among_IDU prevalence_among_CSW table_prevalence_IDU table_prevalence_CSW language

		tempfile unaids_raw
		save `unaids_raw', replace


** * ***************************************************************************************
** OBTAIN AND MERGE ON ISOs, EPIDEMIC CLASSIFICATIONS & NIDs
** * ***************************************************************************************
clear 

// prep epidemic status data. These are the classifications used in IHME's specturm modeling
	insheet using "`epi_type'", comma names clear

	tempfile types
	save `types', replace

// load NIDs
	import excel using "`unaids_nids'", firstrow clear

	tempfile nids
	save `nids', replace

// merge iso's on data set 
	use `unaids_raw', clear

// fix naming issues for merge
	replace country = "Syria" if country == "Syrian Arab Republic"
	replace country = "Macedonia" if country == "former Yugoslav Republic of Macedonia"

// merge 
	// drop observations that didn't get merged. Data from Monaco, San Marino, and Tuvalu in orignial data set gets dropped since these are not modeled in dismod
	merge m:m country using `isos', keep(3) nogen
		

// merge on epidemic status using WHO classifications
	merge m:1 iso3 using `types'
	drop if _merge == 2
	drop _merge

// merge on NIDs
	merge m:1 country source source_year using `nids'
	drop if _merge == 2
	drop _merge

// clean up 
	destring unknown_percent, replace 

// Add European CDC NIDs for new years 
	rename NID nid 
	replace nid = 164897 if regexm(source, "European Centre for Disease Prevention and Control") & year_start == 2013
	replace nid = 249586 if regexm(source, "European Centre for Disease Prevention and Control") & year_start == 2014

	tempfile data 
	save `data', replace

** * ***************************************************************************************
** CDC NATIONAL and STATE-LEVEL ADDITIONS FOR 2015
** * ***************************************************************************************

// CDC state-level data 
	// bring in data 
	import excel using "`cdc_data'", sheet("Extractions") firstrow clear 
	drop age_start age_end
	gen age_start = . 
	gen age_end = . 

	drop country 
	rename notes country 
	replace country = "United States" if country == "" 

	merge m:m country using `isos', keep(3) nogen

	append using `data', force


** * ***************************************************************************************
** CHECK AND CLEAN DATA
** * ***************************************************************************************


// create var for total sexual transmission - currently, if a report included sexual and CSW/clients, sexual is reported without including CSW or clients of CSW. They should be added together to get an overall sexual percentage
	gen sexual_all_percent = .
	replace sexual_all_percent = (sexual_percent + CSW_percent + clients_percent)
	replace sexual_all_percent = sexual_percent if CSW_percent == . & clients_percent == .
	replace sexual_all_percent = 0 if sexual_percent == . & CSW_percent == . & clients_percent == . 


*** * ************************************************************************************************************************
*** CHECK THAT ALL PERCENTAGES ADD UP TO 1. TOTAL SEXUAL + IDU+ ALL OTHER SHOULD SUM TO 100%
*** * **************************************************************************************************************************
	
	
// clean up unknown variable so that it is in numeric form 
	//replace unknown_percent = "." if unknown_percent == ""
	//destring unknown_percent, replace 
	
// create variable to check percentages
	gen check_percent = .
	replace check_percent = sexual_all_percent + IDU_percent + all_other_percent 
	replace check_percent = sexual_all_percent + IDU_percent + unknown_percent if all_other_percent == . & unknown_percent != .  
	replace check_percent = (sexual_all_percent + IDU_percent) if all_other_percent == . & IDU_percent != .
	replace check_percent = (sexual_all_percent + all_other_percent) if IDU_percent == . & all_other_percent != . 
	replace check_percent = sexual_all_percent if IDU_percent == . & all_other_percent == . 

// create outliering variable. will be blank for all included points, "issues" for points that need to be revisited and "exlcude" for points that have issues that have already been explored
	gen data_status = ""
	replace data_status = "issues" if check_percent >= 1.01 | check_percent <= 0.99 // these are likely extraction issues that need to be revisited
	replace data_status = "excluded" if check_percent == 0 // exclude points for which we have no transmission data
	replace data_status = "excluded" if country == "Lebanon" & data_status == "issues" // percentages in each category in UNAIDS Lebanon country report do not sum to 100%
	replace data_status = "excluded" if country == "South Africa" & data_status == "issues" // data from UNAIDs report is only for IDU/CSW/MSM - does not sum to 100 or allow calculation of all sexual transmission
	replace data_status = "excluded" if country == "Estonia" & source == "UNAIDS"	// Estonia's observations from UNAIDS only report IDU and other. Do not report any sexual transmission
	replace data_status = "excluded" if country == "Iraq" & source == "UNAIDS" // percentages in each category do not sum to 100%; also likely a lot of bias because both homosexual and needle exchange not included in breakdown
// create issues explanation variable to tag the specific issue with points that need to be re-extracted
	gen issues = ""
	replace issues = "check extraction" if data_status == "issues"

	
*** * **************************************************************************************************************************
*** CHECK NUMBER OF CASES
*** * ***************************************************************************************************************************
	
	
// need to ensure that there is a total number of cases or number of cases reported for each expsoure category. This will be used as uncertainty since the proportions are point estimates reported without CI's
	gen has_sample = (total_cases_reported != .)
	replace has_sample = (sexual_n != . | CSW_n != . | IDU_n != . | all_other_n != .) if has_sample == 0
	replace data_status = "excluded" if has_sample == 0 & data_status != "issues" // exclude points without sample sizes because these have no uncertainty measures. If they are already marked as issues  they have extraction errors, so leave this as the study status and look for sample size when revisiting extraction

// for sources that reported number of cases in each category - check that they add up to the total number of cases reported
// if cases are not reported, change them from missing to 0 - will replace with actual values shortly
// create local with category variables
	local cats sexual CSW clients IDU all_other 
	di "`cats'"
	foreach c of local cats {
		di "`c'"
		replace `c'_n = 0 if `c'_n == .
		}
	gen check_total_n = sexual_n + CSW_n + IDU_n + all_other_n + clients_n
	gen check_total_diff = total_cases_reported - check_total_n if check_total_n != 0  // all data points with a mismatch betwen total and sum are already marked with "issues" except for 3 points from USA off by 1 or 2 and one point from Netherlands off by 4
	replace total_cases_reported = check_total_n if country == "United States" & source == "CDC: National Center for HIV/AIDS, Viral Hepatitis, STD, and TB Prevention, Division of HIV/AIDS Prevention"
	replace total_cases_reported = check_total_n if country == "Netherlands" & source == "UNAIDS" & year_start == 2010
	replace total_cases_reported = check_total_n if country == "Georgia" & source == "UNAIDS" & year_start == 2014
	replace total_cases_reported = check_total_n if country == "Guatemala" & source == "UNAIDS" & year_start == 2013
	replace total_cases_reported = check_total_n if country == "Iraq" & source == "UNAIDS" & year_start == 1986
	replace total_cases_reported = check_total_n if country == "Pakistan" & source == "UNAIDS" & year_start == 2012
	replace total_cases_reported = check_total_n if country == "Tanzania" & source == "UNAIDS" & year_start == 2013
	replace total_cases_reported = check_total_n if country == "Netherlands" & source == "SHM"

	
	drop check_total_diff check_total_n

// replace number in each category with total * percent in category if number is 0
	foreach c of local cats {
		di "`c'"
		replace `c'_n = total_cases_reported * `c'_percent if `c'_n == 0
		}

// create a count for the total sexual transmission category
	gen sexual_all_n = sexual_all_percent * total_cases_reported
	

*** * **************************************************************************************************************************
*** CHECK FOR CUMULATIVE AND INCIDENT CASES FROM A SINGLE COUNTRY/SURVEY 
*** * **************************************************************************************************************************
// if a survey has both incident and cumulative cases reported, we only want to keep observations from the incident cases active.

// create indicator of whether survey/country reports for incident cases
	bysort source iso3: gen incident = 1 if prevalent_or_incident_cases == "incident" | prevalent_or_incident_cases == "newly diagnosed"
	replace incident = 0 if incident == .
	bysort source iso3: egen maxincident = max(incident) 
	drop incident 
	rename maxincident incident 

// create an indicator of whether survey/country reports for cumulative or non-incident cases
	bysort source iso3: gen prevalent = 1 if prevalent_or_incident_cases == "cumulative" | prevalent_or_incident_cases == "current cases"
	replace prevalent = 0 if prevalent == .
	bysort source iso3: egen maxprevalent = max(prevalent)
	drop prevalent
	rename maxprevalent prevalent
	
// create indicator of whether survey/country has observations for both incident and prevalent/cumulative cases
	bysort source iso3: gen has_both = 1 if incident == 1 & prevalent == 1
	
// create indicator of which to drop - will have both and have cumulative or current cases
	bysort source iso3: gen drop_me = 1 if has_both == 1 & (prevalent_or_incident_cases == "cumulative" | prevalent_or_incident_cases == "current cases")
	
// mark indicators based on drop_me var
	replace data_status = "excluded" if drop_me == 1
	drop incident prevalent has_both drop_me
	
	
*** * **************************************************************************************************************************
*** CREATE MODELING CATEGORIES
*** * **************************************************************************************************************************
// clean up ordering
	order source iso3 country year_start sex sexual_all_n sexual_all_percent sexual_n sexual_percent CSW_n CSW_percent IDU_n IDU_percent all_other_n all_other_percent

// create sexualcsw variables. will move over correct numbers from sexual_all and sexual, then drop sexual and csw columns
	gen sexual_csw_n = .
	gen sexual_csw_percent = . 

// if CSW_n and CSW_percent are missing, we cannot make an estimate for sexual_csw variables because we only have data on total sexual transmission. These entries will stay as missing in their sexual_csw vars. 
// if CSW_n and CSW_percent are not missing, then we can model proportion of sexual transmission due to CSW. In these cases, sexual_csw_percent will be CSW_percent/sexual_all_percent (proportion of sexual transmission due to CSW). Sexual_csw_n will be equal to number of cases for CSW if reported
	replace sexual_csw_n = CSW_n if CSW_n != . 
	replace sexual_csw_percent = CSW_percent/sexual_all_percent if CSW_percent != . 

// drop CSW and sexual variables, since now this data is included in sexual_all and sexual_noncsw
	drop CSW_n CSW_percent sexual_n sexual_percent

	order source iso3 country year_start sex sexual_all_n sexual_all_percent sexual_csw_n sexual_csw_percent
	
// where unknown percent is reported, subtract this from all_other to get total number attributable to "other" causes only
	preserve
	gen ratio = unknown_percent / all_other_percent if unknown_percent !=. & all_other_percent != . 
	bysort country: egen mean_ratio = mean(ratio)

	// first generate ratio of unknown to all_other to split those where we don't have 
	tostring all_other_percent, replace force format(%3.2f)
	destring all_other_percent, replace
	tostring unknown_percent, replace force format(%3.2f)
	destring unknown_percent, replace
	replace all_other_percent = all_other_percent - unknown_percent if unknown_percent != . 
	replace all_other_n = all_other_percent * total_cases_reported 

*** * **************************************************************************************************************************
*** EXCLUDE CASES WHERE OTHER CATEGORY IS >25%
*** * **************************************************************************************************************************
// We want to exclude data from all three transmission categories when an extraction reported 25% or more of transmission attributable to other causes
	replace data_status = "excluded" if all_other_percent >= .25
	
*** * **************************************************************************************************************************
*** CREATE COVARIATES
*** * **************************************************************************************************************************


// mark whether data is for hiv or aids cases. hiv/aids and hiv & aids are coded as hiv cases since hiv cases will outnumber aids cases
	gen cv_aids = 0 
	replace cv_aids = 1 if hiv_or_aids_cases == "aids" | hiv_or_aids_cases == "hiv & aids" | hiv_or_aids_cases == "hiv/aids"

// mark whether data is for incident/newly diagnosed cases or cumulative/current cases
	gen cv_cumulative_cases = 0
	replace cv_cumulative_cases = 1 if prevalent_or_incident_cases == "cumulative" | prevalent_or_incident_cases == "current cases" 

// mark whether a country's epidemic is generalized or concentrated
	gen cv_generalized = 0
	replace cv_generalized = 1 if epi_class == "GEN"

// mark whether the "all_other" category contains cases with unknown origin
	gen cv_other_unknown = 0
	replace cv_other_unknown = 1 if regexm(definition_all_other, "unknown") | regexm(definition_all_other, "not specified") | regexm(definition_all_other, "undetermined") | regexm(definition_all_other, "no risk reported") | regexm(definition_all_other, "no reported exposure") | regexm(definition_all_other, "not identified")
	
// mark whether study reported number of cases with unknown transmission origin
	gen cv_unknown_reported = 0
	replace cv_unknown_reported = 1 if unknown_percent != . 

// mark whether the "all_other" category includes MTCT
	gen cv_other_mtct = 0
	replace cv_other_mtct = 1 if regexm(definition_all_other, "MTCT") | regexm(definition_all_other, "vertical") | regexm(definition_all_other, "mtct")
	
// mark whether data is from ECDC - we are treating this as gold standard data since it comes from national surveillance systems and is corrected for reporting delays
	gen cv_ecdc_data = 1
	replace cv_ecdc_data = 0 if source_site == "HIV/AIDS in Europe 2012"

	
*** * **************************************************************************************************************************
*** MAKE FORMAT CONSISTENT WITH UPLOAD TEMPLATE
*** * **************************************************************************************************************************
	
	
// reshape so that the observations for each type are in their own row

	drop check_percent has_sample unknown* clients*
	rename *_n *_N
	reshape long @N @percent, i(source iso3 year_start source_year sex prevalent_or_incident_cases hiv_or_aids_cases year_end age_start cv_other_mtct) j(type) string
	
	replace notes = country if notes == ""
	drop country
	rename notes country

	tempfile all 
	save `all', replace

	// Merge on states 
	//use `isos', clear 
	//keep if regexm(iso3, "USA") // drop for now so that can merge but revisit this if needed 
	//merge 1:m country using `all', keep(3) nogen


// make exclusions for extractions that do not include an estimate for the percent unknown in the "other" category - idea is that unknown cases are actually likely attributable to sex and idu so "other" is being inflated while the numbers in these other categories are too low
// in these cases drop the other category, but retain sexual and IDU
	replace data_status = "excluded" if cv_unknown_reported == 0 & type == "all_other_"  
		
// make vars for dismod upload
	rename type healthstate
	gen modelable_entity_id = 2637 if healthstate == "IDU_" 
	gen modelable_entity_name = "Proportion HIV due to intravenous drug use" if modelable_entity_id == 2637 
	replace modelable_entity_id = 2638 if healthstate == "sexual_all_"
	replace modelable_entity_name = "Proportion HIV due to sex" if modelable_entity_id == 2638 
	replace modelable_entity_id = 2639 if healthstate == "all_other_" 
	replace modelable_entity_name = "Proportion HIV due to other" if modelable_entity_id == 2639
	replace modelable_entity_id = 2636 if healthstate == "sexual_csw_"  
	replace modelable_entity_name = "Proportion HIV due to commercial sex work" if modelable_entity_id == 2636 


	/*
	replace healthstate = "hiv_idu" if healthstate == "IDU_"
	replace healthstate = "hiv_other" if healthstate == "all_other_"
	replace healthstate = "hiv_sex" if healthstate == "sexual_all_"
	replace healthstate = "hiv_sex_csw" if healthstate == "sexual_csw_"
	*/

// mark outliers
		replace data_status = "excluded" if healthstate == "hiv_sex_csw" & country == "Sierra Leone"
		replace data_status = "excluded" if country == "Jordan" & year_start == 1986
		// drop Vanuatu - only report one case for each year observation
		replace data_status = "excluded" if country == "Vanuatu"


	rename table table_num
	rename page_number page_num
	
	replace sex = 3 if healthstate == "hiv_sex_csw" 

	//drop age_start age_end 
	//gen age_start = . 
	//gen age_end = . 
	replace age_start = 15 if age_start == . & modelable_entity_name == "Proportion HIV due to intravenous drug use" 
	replace age_end = 49 if age_end == . & modelable_entity_name == "Proportion HIV due to intravenous drug use" 
	replace age_start = 15 if age_start == . & modelable_entity_name == "Proportion HIV due to commercial sex work" 
	replace age_end = 49 if age_end == . & modelable_entity_name == "Proportion HIV due to commercial sex work"
	replace age_start = 0 if age_start == . & modelable_entity_name == "Proportion HIV due to sex"
	replace age_end = 100 if age_end == . & modelable_entity_name == "Proportion HIV due to sex"
	replace age_start = 0 if age_start == . & modelable_entity_name == "Proportion HIV due to other"
	replace age_end = 100 if age_end == . & modelable_entity_name == "Proportion HIV due to other"

	rename percent mean 

	gen lower = .
	gen upper = .
	gen standard_error = . 
	gen uncertainty_type = "Effective sample size" 
	gen uncertainty_type_value = . 


	rename N cases

	gen representative_name = "Nationally representative only"
	gen urbanicity_type = "Mixed/both"


	gen numerator = cases
	gen effective_sample_size = total_cases_reported
	rename total_cases_reported denominator 

// convert means from percentages to fractions
	//replace mean = mean / 100

	//gen unit_type = 2 // indicates percent (datat will be divided by 100 in upload script)
	//replace mean = mean * 100

	gen extractor = "strUser"
	gen recall_type = "Point" 


	//replace source_type = 30 
	//label define source 30 "Surveillance - facility" 
	//label values source_type source 
	drop source_type
	gen source_type = "Surveillance - facility"
	
	gen case_name = "" 
	gen case_definition = "" 
	gen unit_value_as_published = 1 
	gen unit_type = "Person"
	gen measure = "proportion"	
	gen is_outlier = 0
	//replace is_outlier = 1 if data_status == "excluded"
	gen underlying_nid = . 
	gen sampling_type = "" 
	gen recall_type_value = "" 
	gen input_type = "" 
	gen sample_size = . 
	//gen cases = . 
	gen design_effect = . 
	gen site_memo = "" 
	gen case_diagnostics = "" 
	gen response_rate = .
	gen note_SR = "" 
	gen note_modeler = ""
	gen row_num = . 
	gen parent_id = . 
	gen data_sheet_file_path = "" 

	// Validation checks
	drop if mean == . | (upper == . & lower == . & effective_sample_size == . & standard_error == .) // Need mean and some variance metric
	drop if effective_sample_size == 0 
	drop if mean < lower & lower != .
	drop if upper < mean 
	drop if mean > 1

	// Delete outliered data 
	//drop if data_status == "excluded"

	// Sex 
	tostring sex, replace
	replace sex = "Male" if sex == "1"
	replace sex = "Female" if sex == "2"
	replace sex = "Both" if sex == "3"

	//order acause grouping healthstate nid page_num table_num source_type data_type iso3 sex year_start year_end age_start age_end parameter_type mean lower upper standard_error sample_size numerator denominator unit_type orig_uncertainty_type is_raw data_status issues extractor cv_* notes

	drop if mean == . // & sample_size == . // drop sexual_noncsw points from countries where we don't have this data
	drop cv_unknown_reported
	
	drop prevalent_or_incident_cases hiv_or_aids_cases table_total_cases definition_sexual definition_all_other data_source epi_class

	// Only keep necessary variables
	local variables row_num modelable_entity_id modelable_entity_name measure	nid	file iso3	location_id	/// 
	sex	year_start	year_end	age_start	age_end	measure	mean	lower	upper	standard_error	effective_sample_size	/// 
	uncertainty_type uncertainty_type_value	representative_name	urbanicity_type	extractor ///
	unit_value_as_published cv_* source_type is_outlier underlying_nid /// 
	sampling_type recall_type recall_type_value unit_type input_type sample_size cases design_effect site_memo /// 
	case_diagnostics response_rate note_SR note_modeler data_sheet_file_path parent_id data_status /// 
	case_name case_definition

	keep `variables' 
	order `variables'
	
// exclude data points from the future (these are from modeling studies)
	replace data_status = "excluded" if year_start > 2015

// rename covariates for epi upload (they are named differently in database)
	rename cv_aids cv_aids_transmission
	rename cv_other_unknown cv_unk_transmission 
	rename cv_other_mtct cv_mtct 
	rename cv_ecdc_data cv_ecdc 
	rename cv_cumulative_cases cv_cumulative 
	rename cv_generalized cv_conc_epidemic 


// 	Generate group, group_review and specificty variables to hide excluded datapoints but keep them in the database in case we want to revisit them 
	bysort nid: gen flag = 1 if data_status == "excluded" 
	bysort nid: egen max_flag = sum(flag)

	levelsof nid if max_flag != 0, local(nids_with_exclusions)

	gen group = . 
	local counter = 1 

	foreach nid of local nids_with_exclusions { 
		
		replace group = `counter' if nid == `nid'

		local counter = `counter' + 1
         di "`counter'"

	}

	// make group_review variable
		// group_review = 1 if gold standard definition 
		// group_review = 0 if alternative definition

		gen group_review = 1 if group != . & data_status == "" 
		gen specificity = "gold standard definition" if group_review == 1 
		replace group_review = 0 if group != . & data_status == "excluded"
		replace specificity = "non-reference case definition" if group_review == 0 


	drop max_flag flag data_status 

	export excel using "`outdir'/gbd2015_unsafe_sex.xlsx", firstrow(var) replace

	tempfile all_data 
	save `all_data', replace

*** * **************************************************************************************************************************
*** UPLOAD BY ME ID FOR EACH MODE OF TRASMISSION
*** * **************************************************************************************************************************

	levelsof modelable_entity_id, local(mes)


	foreach me of local mes { 
	
		use `all_data', clear
		keep if modelable_entity_id == `me'
		
		tempfile `me'_all 
		save ``me'_all', replace

	} 


	//////////////////////////////////////////////////
	// Intravenous Drug Use
	//////////////////////////////////////////////////
	
	use "`2637_all'", clear 
	export excel using "J:\WORK\05_risk\risks\unsafe_sex\data\exp\2637\input_data\2015_idu_data.xlsx", sheet("extraction") firstrow(variables) replace
	
	
	//////////////////////////////////////////////////
	// Sex
	//////////////////////////////////////////////////

	use "`2638_all'", clear
	export excel using "J:\WORK\05_risk\risks\unsafe_sex\data\exp\2638\input_data\2015_sex_data.xlsx", sheet("extraction") firstrow(variables) replace


	//////////////////////////////////////////////////
	// Other
	//////////////////////////////////////////////////
	
	use "`2639_all'", clear
	export excel using "J:\WORK\05_risk\risks\unsafe_sex\data\exp\2639\input_data\2015_other_data.xlsx", sheet("extraction") firstrow(variables) replace

	//////////////////////////////////////////////////
	// Commercial sex work
	//////////////////////////////////////////////////
	
	//use "`2636_all'", clear 
	//export excel using "J:\WORK\05_risk\risks\unsafe_sex\data\exp\2636\input_data\2015_csw_data.xlsx", sheet("extraction") firstrow(variables) replace

	

/*
cov definitions
cv_aids 				indicates that transmission mode was recorded for aids cases rather than hiv cases
cv_cumulative_cases		indicates that transmission mode reported for cumulative or current cases not newly diagnosed cases
cv_generalized			indicates that a country's epidemic is generalized, not concentrated
cv_other_unknown		indicates "other" category includes cases of unknown transmission 
cv_other_mtct			indicates "other" category includes cases from MTCT
*/
	
	
	
	
	
	
	

	
	
	
	
	
	
	
	
	
	
	
