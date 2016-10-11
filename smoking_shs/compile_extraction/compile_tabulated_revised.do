// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 			Updated 12 June 2014 (originally written 6 June 2014)
// Project:		RISK
// Purpose:		Compile all raw data extracted from surveys and literature for second-hand smoke exposure. Then, format for DisMod. Then get citations/NIDs
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
// STEP 1: Compile all raw data extracted from surveys and literature for second-hand smoke exposure. Then, format for DisMod. 
** ***********************************************************************************************
// Make locals for relevant files and folders
	local data_dir "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped"
	local files: dir "`data_dir'" files "*.dta"
	local outdir "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/02_compile"
	local dismod_dir "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/2512/input_data"

// Prepare location names & demographics for 2015

	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & inlist(level, 3, 4)

	keep ihme_loc_id location_id location_ascii_name super_region_name super_region_id region_name region_id

	tempfile countrycodes
	save `countrycodes', replace

// Bring in tabulated survey data extraction
	insheet using "`data_dir'/literature_extraction.csv", comma clear
	
// Append datasets for each extracted microdata survey series/country together (going to take care of DHS separately)
	foreach file of local files {
		if "`file'" != "compiled.dta" & "`file'" != "collapse_list.dta" & "`file'" != "collapsed_smoking_shs.dta" & !regexm("`file'", "dhs") {
			di in red "`file'"
			append using "`data_dir'/`file'", force
		}
	}

	tempfile master
	save `master', replace

// Clean up DHS 
	
	// dhs_gold_standard.dta consists of prevalence estimates that are based off of a question in the HH module about frequency of smoking in the household + information from the male/female modules about smoking status of that individual 
		use "`data_dir'/dhs_gold_standard.dta", clear 
		destring year_start, replace
		destring year_end, replace 

		gen case_definition = "Any passive smoke exposure inside the home daily or weekly among current non-daily smokers"

		tempfile gold_std_estimates
		save `gold_std_estimates', replace

		duplicates drop ihme_loc_id year_start, force
		keep ihme_loc_id year_start

		// create a list of country-years to compare to old extractions 
		tempfile gold_std_list
		save `gold_std_list', replace

		// Bring in old DHS extractions based on spousal smoking
		use "`data_dir'/dhs_spousal_smoking.dta", clear 
		append using "`data_dir'/dhs_ind_subnational.dta" 

		rename iso3 ihme_loc_id
		replace age_start = gbd_age if age_start == . 

		replace case_definition = "Current non-daily smokers who have a spouse that smokes"
		replace case_definition = "Children who have a parent who smokes" if mean_ch != . & mean == . 
		
		// these are matches between gold standard and old DHS extraction so we want to just keep the gold standard; or just in gold standard 
		merge m:1 ihme_loc_id year_start using `gold_std_list'
		drop if inlist(_m, 2, 3) 
		drop _m

		// append using new estimates
		append using `gold_std_estimates'

		rename ihme_loc_id iso3 
		drop orig_unit_type

		tempfile dhs 
		save `dhs', replace

		append using `master'

		replace iso3 = ihme_loc_id if iso3 == "" & ihme_loc_id != "" 
		drop ihme_loc_id 

// Fill in ISO3 based on filepaths
	replace iso3 = substr(file, 9, 3) if iso3 == "" & !regexm(file, "MACRO_DHS") & !regexm(file, "CHN")
	replace iso3 = substr(file, 19, 3) if iso3 == "" & regexm(file, "MACRO_DHS")
	replace iso3 = "ARG" if regexm(file, "ARG_NATIONAL_SURVEY_OF_RISK")

	// Fill in proper location identifiers
	// Location ids 
	rename location_id location_id_old
	rename iso3 ihme_loc_id

	gen ihme_loc_id_old = ihme_loc_id
	
	merge m:1 ihme_loc_id using `countrycodes', keep(1 3) nogen
	replace location_id = location_id_old if location_id == . 
	drop location_id_old


	// Fill in GBD age groups
	replace age_start = gbd_age if age_start == .
	replace age_end = gbd_age + 4 if age_end == . & gbd_age != .
	replace age_end = 100 if gbd_age == 80
	split age_cat, parse("-")
	replace age_cat1 = substr(age_cat1, 1, 2) if inlist(age_cat1, "75+", "85+") 
	destring age_cat1 age_cat2, replace
	replace age_start = age_cat1 if age_start == .
	replace age_end = age_cat2 if age_end == .
	replace age_end = 100 if substr(age_cat, -1, 1) == "+"
	** DHS surveys were extracted differently
	replace age_start = 0 if age_start == . & mean_ch != .
	replace age_end = 5 if age_end == . & mean_ch ! =.
	** Technically GYTS is 13-15 year olds, but we will use exposure in this age range as a proxy for all children under 15 
	replace age_start = 0 if survey == "GYTS" & age_start == .
	replace age_end = 15 if survey == "GYTS" & age_end == .

	replace age_start = 1 if age_start == 4 
	replace age_start = 10 if age_start == 13
	replace age_start = 15 if inlist(age_start, 16, 18, 19)
	replace age_start = 80 if age_start > 80 & age_start != .
	replace age_end = age_start + 4 if age_end == . 

	tempfile all 
	save `all', replace

	drop file_name 
	replace case_definition = case_name if case_name != "" 
	save `all', replace

// // Bring in ubcov dataset and merge subnational names to get correct ihme_loc_id 
		
		// ubcov sources include: Global Adult Tobacco Survey, Canadian Tobacco Use Monitoring Survey, BRFSS, National Adult Tobacco Survey, National Youth Tobacco Survey, National Health Interview Survey, SWAN and just 3 Global Youth Tobacco Surveys that weren't included in the first extraction 

	adopath + "$prefix/WORK/01_covariates/common/ubcov_central/_functions" 
	subnat_map, file("`data_dir'/collapsed_smoking_shs.dta") location_var(subnat_id) parent_loc_id(ihme_loc_id)
	
	// Six Minor Union territories 
	split ihme_loc_id, p("_") 
	rename ihme_loc_id2 location_id 
	destring location_id, replace 
	drop ihme_loc_id1
	replace location_id = 44539 if regexm(subnat_id, "rural") & regexm(ihme_loc_id, "temp") 
	replace ihme_loc_id = "IND_44539" if location_id == 44539
	replace location_id = 44540 if regexm(subnat_id, "urban") & regexm(ihme_loc_id, "temp") 
	replace ihme_loc_id = "IND_44540" if location_id == 44540 
	drop if regexm(ihme_loc_id, "temp")
	rename age_id age_group_id 

	// Drop the places (subnationals often within larger surveys) that don't have observations
	drop if mean_shs_household == . 


	// RESHAPE so that we have shs exposure at work and exposure at home for crosswalking in DisMod
	gen id = _n 
	reshape long mean_ se_ ss_ sd_, i(id) j(case_definition_new) string
	drop if mean_ == . // don't have exposure at work + home estimates 

	replace shs_case_def = "Exposure at work and home" if case_definition_new == "shs_exp_work"
	drop map subnat_id list_flag collapse_flag
	rename mean_ mean
	rename ss_ sample_size
	rename sd_ standard_deviation
	rename se_ standard_error
	

	gen standard_error_new = sqrt((mean*(1-mean))/sample_size)
	gen dif = standard_error_new - standard_error
	replace dif = abs(dif)

	//replace location_id = 385 if subnat_id == "Puerto Rico"
	drop if sample_size < 10 // leads to unstable estimates


	tempfile ubcov 
	save `ubcov', replace 


	// Add on age_ids 
	insheet using "`outdir'/convert_to_new_age_ids.csv", comma names clear 
	merge 1:m age_group_id using `ubcov', keep(3) nogen
	gen age_end = age_start + 4 
	drop age_group_id

	rename sex_id sex
	drop subnat_est
	rename location_id location_id_old

	save `ubcov', replace
	
	use `countrycodes', clear 
	merge 1:m ihme_loc_id using `ubcov', keep(3) nogen
	drop location_id_old 

	append using `all' // APPEND ALL OTHER DATA WITH UBCOV 2015 EXTRACTIONS


	// Fill in mean variable if missing
	foreach var in mean_ch prevalence shs_mean parameter_value prevalence {
		replace mean = `var' if mean == .
	}
	drop if mean == . 

	replace standard_error = shs_se if standard_error == . 
	replace standard_error = se_ch if standard_error == . 

	tempfile compiled 
	save `compiled', replace 

	
	// Sex should be string for epi uploader 
	tostring sex, replace 
	replace sex = "Male" if sex == "1" 
	replace sex = "Female" if sex == "2" 
	replace sex = "Both" if sex == "3" 

	
	// Different variable names were used for file path so this puts them all in the "file" variable
	foreach var in file_path filepath orig_file file_location {
		replace file = `var' if file == "" & `var' != ""
	}

	replace file = file + "/" + file_name if file_name != "" 

// Specify national representation type 
	
	gen representative_name = . 
	replace representative_name = national_type if national_type != . 
	replace representative_name = national_type_id if national_type_id != . & national_type == . 
	replace representative_name = 1 if national == 1
	// replace national_type = 2 if parent_iso3 != iso3 & parent_iso3 != ""
	replace representative_name = 3 if site != "" & national_type == . & representative_name == . 
	replace site = "" if site == "National"
	replace representative_name = 1 if regexm(name, "DHS") | regexm(file, "NATIONAL")
	replace representative_name  = 2 if regexm(source, "micro_GATS")
	replace representative_name = 4 if regexm(file, "NATIONAL_ADULT_TOBACCO")  
	replace representative_name = 1 if regexm(file, "INTERVIEW") 
	replace representative_name = 1 if regexm(file, "NATIONAL_YOUTH_TOBACCO") 
	replace representative_name = 1 if regexm(file, "NATIONAL_ADULT_TOBACCO") 
	replace representative_name = 1 if regexm(file, "GLOBAL_ADULT_TOBACCO") 
	replace representative_name = 3 if regexm(file, "SWAN") 
	replace representative_name = 4 if regexm(file, "BRFSS") 
	replace representative_name = 1 if regexm(file, "CANADIAN_TOBACCO_USE") 
	replace representative_name = 3 if regexm(file, "BRA_RISK_FACTOR") 
	replace representative_name = 10 if regexm(file, "VIGITEL") 

		// GATS
		replace representative_name = 6 if regexm(file, "GLOBAL_ADULT_TOBACCO") & regexm(ihme_loc_id, "IND") 
		replace representative_name = 4 if regexm(file, "GLOBAL_ADULT_TOBACCO") & regexm(ihme_loc_id, "BRA") 

		// GYTS
		split file, p("/") 
		replace representative_name = 3 if regexm(file5, "[A-Z]") == 1 & file5 != "" & regexm(file, "GLOBAL_YOUTH") // for those that are city-specific, denote this
		drop file1 file2 file3 file4 file5 file6 file7 file8

		// DHS 
		replace representative_name = 6 if site != "" & regexm(file, "MACRO_DHS")


	replace representative_name  = 1 if representative_name == . // Assume nationally representative if no site extracted
	label define national 1 "Nationally representative only" 2 "Representative for subnational location only" 3 "Not representative" 4 "Nationally and subnationally representative" /// 
	5 "Nationally and urban/rural representative" 6 "Nationally, subnationally and urban/rural representative" 7 "Representative for subnational location and below" /// 
	8 "Representative for subnational location and urban/rural" 9 "Representative for subnational location, urban/rural and below" 10 "Representative of urban areas only" /// 
	11 "Representative of rural areas only" 
	label values representative_name national

	// Looks like for epi uploader we want it to be a string and then it converts to numeric upon upload 
	decode representative_name, gen(rep_name_new)
	rename representative_name rep_name_numeric
	rename rep_name_new representative_name
	
// Specify locality type 
	replace urbanicity_type = 1 if inlist(rep_name_numeric, 1, 2, 4, 6) 
	replace urbanicity_type = 1 if regexm(file, "SWAN") | regexm(file, "SCOTTISH") | regexm(file, "WELSH") | regexm(file, "ENGLISH") 
	replace urbanicity_type = 2 if site == "URBAN" | urbanicity == "urban"
	replace urbanicity_type = 2 if regexm(site, "Urban")
	replace urbanicity_type = 2 if regexm(file, "URBAN") 
	replace urbanicity_type = 2 if representative_name == "Representative of urban areas only"
	replace urbanicity_type = 2 if regexm(file, "GLOBAL_YOUTH_TOBACCO") & representative_name != "Nationally representative" 
	replace urbanicity_type = 2 if regexm(file, "VIGITEL") 
	replace urbanicity_type = 3 if site == "RURAL" | urbanicity == "rural"
	replace urbanicity_type = 3 if regexm(site, "Rural")
	replace urbanicity_type = 3 if regexm(file, "RURAL") 
	replace urbanicity_type = 3 if representative_name == "Representative of rural areas only" 

	replace urbanicity_type = 0 if urbanicity_type == . 

	label define urbanicity 0 "Unknown" 1 "Mixed/both" 2 "Urban" 3 "Rural"
	label values urbanicity_type urbanicity

	// Looks like epi uploader we want it to be a string 
	
	decode urbanicity_type, gen(urbanicity_type_new) 
	drop urbanicity_type 
	rename urbanicity_type_new urbanicity_type
	

// Drop small sample sizes 
	drop if sample_size < 10

// Sample size
	replace sample_size = sample if sample_size == .
	
// Uncertainty
	replace standard_error = se if standard_error == .
	replace standard_error = se_ch if standard_error == .
	replace lower = lower_ci if lower == .
	replace upper = upper_ci if upper == .
	replace lower = abs(lower) if lower < 0 
	gen uncertainty_type = "" 
	replace uncertainty_type = "Effective sample size" if orig_uncertainty_type == "ESS" 
	replace uncertainty_type = "Standard error" if orig_uncertainty_type == "SE" 
	replace uncertainty_type = "Standard error" if standard_error != . & orig_uncertainty_type == ""
	replace uncertainty_type = "Confidence interval" if upper != . & lower != . & standard_error == . & uncertainty_type == "" 
	replace uncertainty_type = "Effective sample size" if sample_size != . & orig_uncertainty_type == "" & uncertainty_type == "" 
	replace standard_error = (upper - lower)/ (2*1.96) if standard_error == .
	gen uncertainty_type_value = 95 
	replace uncertainty_type_value = . if lower == . | upper == . 
	
// Year
	replace year_start = year if year_start == .
	replace year_end = year if year_end == .
	tostring year_start, replace
	tostring year_end, replace
	split name, parse("_")
	replace year_start = name3 if year_start == "."
	replace year_end = name4 if year_end == "." & (substr(name4, 1, 1) == "2" | substr(name4, 1, 1) == "1")
	replace year_end = year_start if year_start != "." & year_end == "."
	replace year_start = "2013" if year_start == "DHS7" 
	destring year_start, replace
	destring year_end, replace


// Source
	replace source = survey_name if source == ""
	replace source = survey if source == ""
	replace citation = field_citation if citation == ""

// Fill in covariates
	replace rep_name_numeric = 3 if regexm(file, "BRA_RISK_FACTOR_MORBIDITY") 

	tostring orig_unit_type, replace
	replace orig_unit_type = "Rate per capita" if orig_unit_type == ""
	
// Merge on with location name 
	replace location_name = site if location_name == ""


// replace definition
	replace case_definition = definition if case_definition == ""
	replace case_definition = case_name if case_definition == ""
	replace case_definition = shs_case_def if case_definition == "" 
	//replace case_definition = "Non-smokers who live with a spouse or parent that smokes" if regexm(file, "DHS")
	replace case_definition = "Never smokers who have one or more parents who smoke" if regexm(file, "GSHS")
	replace case_definition = "Never smokers who have one or more parents who smoke" if regexm(file, "GYTS") & cv_act_of_smoking == 1 
	replace case_definition = "Anybody smoked in house in past 7 days in your presence" if regexm(file, "GYTS") & cv_act_of_smoking == 0 
	replace case_definition = "Non-daily smokers with persons smoking in accomodation" if regexm(file, "SCOTTISH_HEALTH_SURVEY")
	replace case_definition = "Anyone who lives in house smokes inside the home" if survey_name == "NHANES" 
	replace case_definition = "Anyone who lives in house smokes indoors" if survey_name == "VIGITEL" 
	replace case_definition = "Live with someone now who smokes" if regexm(file, "NATIONAL_YOUTH_TOBACCO") & inlist(year_start, 2000, 2002, 2004, 2006, 2009, 2012)
	replace case_definition = "Someone smoked a tobacco product in home while you were there" if regexm(file, "NATIONAL_YOUTH_TOBACCO") & year_start == 2011
	replace case_definition = "Does anyone smoke inside this house/flat on most days?" if regexm(file, "HEALTH_SURVEY_FOR_ENGLAND")
	replace case_definition = "Children who have a parent who smokes" if regexm(file, "MACRO_DHS") & age_start == 0 

** ***********************************************************************************************
// STEP 2: Generate covariates for crosswalking before DisMod and modelling
** ***********************************************************************************************
	gen cv_not_represent = rep_name_numeric == 3 // & parent_iso3 == iso3
	replace cv_not_represent = 1 if regexm(file, "VIGITEL") 

// ACT OF SMOKING
	// 0 = ask about whether someone actually smokes inside the home (smokes in your house|inside the home)
	// 1 = asks whether they live with a smoker 

	replace cv_act_of_smoking = regexm(case_definition, "living with a smoker|live with someone now|living with one or more smokers|people in household smoke now|parents who smoke|spouse that smokes|parent who smokes") 

// ANYBODY SMOKING
	// 0 = asks about whether anyone smokes inside the home ("Anyone|any passive smoke exposure")
	// 1 = restricted definition to either whether spouse/partner smokes or parents smokes 

	replace cv_anybody_smoking = regexm(case_definition, "parents who smoke|parent who smokes|spouse that smokes")


	//gen cv_family_smoker = regexm(case_definition, "spouse|parent|parents")
	//gen cv_defi_smoker = regexm(case_definition, "live|parent|spouse|living|smokers in household|how many other people in household smoke now") & cv_smokerathome == .
	gen cv_exp_work_home = regexm(case_definition, "work") & cv_work_home == .
	gen cv_exp_indoor_outdoor = 0 if cv_outdoor == .
	replace cv_exp_indoor_outdoor = 1 if cv_outdoor == 1 
	

// Only keep necessary variables
	keep nid file path location_id location_name ihme_loc_id year_start year_end sex age_start age_end sample_size mean standard_error file source representative_name urbanicity_type orig_unit_type orig_uncertainty_type case_definition /// 
	location_id location_name cv_not_represent cv_act_of_smoking cv_anybody_smoking cv_exp_work_home cv_exp_indoor_outdoor citation location_type upper lower uncertainty_type uncertainty_type_value 
	
// Validation checks
	recode standard_error (0=.) 
	replace lower = . if lower == upper
	replace upper = . if lower == .
	replace orig_uncertainty_type = "ESS" if orig_uncertainty_type == "SE" & standard_error == . & sample_size != .
	replace orig_uncertainty_type = "ESS" if orig_uncertainty_type == "CI" & lower == . & sample_size != .
	** Dismod can't calculate error on 0 or 1 means so we will replace 0's with a small value and 1's with a large
	recode mean (0=.0001) (1=.999)
	drop if mean == . | (upper == . & lower == . & sample_size == . & standard_error == .) // Need mean and some variance metric
	drop if mean < lower & lower != .
	drop if upper < mean 
	drop if mean > 1
	tabmiss `variabes'

// Save
	tempfile compiled
	save `compiled', replace
	
	
** ******************************************************************************************
// STEP 3: Match data to the proper NIDs/citations based on J:/DATA filepaths 
** ******************************************************************************************
// Prepare NID and filepath database 
	
	clear
	set debug on
	#delim ;
	odbc load, exec("SELECT fl.field_location_value location, fn.field_file_name_value filename, records.nid record_nid, records.file_id file_nid
	FROM
	(SELECT entity_id nid, field_internal_files_target_id file_id
	FROM ghdx.field_data_field_internal_files) records
	JOIN ghdx.field_data_field_location fl ON fl.entity_id = records.file_id
	JOIN ghdx.field_data_field_file_name fn ON fn.entity_id = records.file_id
	ORDER BY record_nid") dsn(ghdx) clear;
	#delim  cr

	rename location path
	replace path = subinstr(path,"\","/",.)

	collapse (first) record_nid, by(path)
	
	tempfile citations 
	save `citations', replace


// Bring in compiled and prepped dataset and format filepaths so that they can be merged with the NID/Filepath database
	use `compiled', clear
	// replace site = upper(site)
	
	tostring year_start, replace
	replace file = upper(file)
	replace file = subinstr(file,"\","/",.)
	replace file = subinstr(file,"//","/",.)
	replace file = subinstr(file,"/HOME/J","J:",.)
	replace file = subinstr(file, "/home/j","J:",.)
	replace file = "J:/DATA/ARG/NATIONAL_SURVEY_OF_RISK_FACTORS_ENFR" + "/" + year_start + "/" + file + ".TXT" if regexm(file, "ENFR") 
	replace file = subinstr(file, "Y2012M10D11", "Y2012M30D12",.) if regexm(file, "ENFR")
	replace file = subinstr(file, ".DTA", ".dta", .) if regexm(file, "SCOTTISH_HEALTH_SURVEY") & (year_start == "1995" | year_start == "1998")
	replace file = subinstr(file, "J:/DATA/GLOBAL_ADULT_TOBACCO_SURVEY/BGD/", "J:/DATA/GLOBAL_ADULT_TOBACCO_SURVEY/BGD/2009/", .) if regexm(file, "BGD_GATS") 
	replace file = subinstr(file, "CHN_GATS_2009_2010", "CHN_GATS_2010",.)
	replace file = subinstr(file, "JUAREZ", "CIUDAD_JUAREZ", .) if year_start == "2006" & !regexm(file, "CIUDAD") 
	replace file = subinstr(file, "ABUJAH", "ABUJA", .) if year_start == "2008"
	replace file = file + ".DTA" if file == "J:/DATA/MACRO_DHS/IND/2005_2006/IND_DHS5_2005_2006_CUP_Y2010M04D01"
	replace file = subinstr(file,"J:/DATA/KOR/NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY","J:/DATA/KOR/NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY_KNHANES",.)
	replace file = file + ".PDF" if file == "J:/DATA/KOR/NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY_KNHANES/2009/KOR_NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY_2009_REP_Y2013M05D02"
	replace file = subinstr(file, "IND_STEPS_NCD_2007_2008_REP_Y2011M0620.PDF", "IND_IDSP_NCD_RISK_FACTOR_SURVEILLANCE_2007_2008_REP_Y201M0620.PDF", .)
	replace file = subinstr(file, "URBAN_", "", .) if file == "J:/DATA/WHO_STEP_GSHS/DZA/URBAN_2010/DZA_URBAN_GSHS_2010_Y2013M10D29.DTA"
	replace file = "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/SDN/2009/SDN_GYTS_2009_LABELED.DTA" if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/SDN/2009/SUD_GYTS_2009_LABELED.DTA"
	
	replace path=regexs(1) if regexm(file,"^(.+)/([^/]+)$") & path == ""
	replace path = path + "/" + year_start if path=="J:/DATA/ARG/NATIONAL_SURVEY_OF_RISK_FACTORS_ENFR"
	replace nid = 132624 if path=="J:/DATA/GLOBAL_ADULT_TOBACCO_SURVEY/ARG/2012"
	destring year_start, replace
	
	tempfile data
	save `data', replace

// Merge with NIDs/citations
	merge m:1 path using `citations', update keep(1 3 4 5)
	compress
	// br if nid==.

	// replace new queried record nids for missing nids in existing dataset
	replace nid = record_nid if nid == .

	// Manually fill in NIDs that are still missing
		replace nid = 129919 if file == "J:/DATA/WHO_STEP_GSHS/ATG/2009/ATG_GSHS_2009.DTA"
		replace nid = 129934 if regexm(file, "MDV_GSHS")
		replace nid = 129996 if regexm(file, "MWI_GSHS") 
		replace nid  = 110391 if regexm(file, "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/TON/2010")

		// Health Survey England
		replace nid = 22352 if regexm(file, "J:/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/1998")
		replace nid = 22364 if regexm(file, "J:/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/1999")
		replace nid = 22374 if regexm(file, "J:/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2000")
		replace nid = 22388 if regexm(file, "J:/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2001")
		replace nid = 22403 if regexm(file, "J:/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2002")
		replace nid = 22433 if regexm(file, "J:/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2003")
		replace nid = 22449 if regexm(file, "J:/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2004")
		replace nid = 22463 if regexm(file, "J:/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2005")
		replace nid = 22476 if regexm(file, "J:/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2006")
		replace nid = 95628 if regexm(file, "J:/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2007")
		replace nid = 95629 if regexm(file, "J:/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2008")
		replace nid = 95630 if regexm(file, "J:/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2009")
		
		// Scottish Health Survey
		replace nid = 204732 if regexm(file, "J:/DATA/GBR/SCOTTISH_HEALTH_SURVEY/1995")
		replace nid = 204731 if regexm(file, "J:/DATA/GBR/SCOTTISH_HEALTH_SURVEY/1998")
		replace nid = 204730 if regexm(file, "J:/DATA/GBR/SCOTTISH_HEALTH_SURVEY/2003")
		replace nid = 204729 if regexm(file, "J:/DATA/GBR/SCOTTISH_HEALTH_SURVEY/2008")

		// China GATS
		replace nid = 21975 if regexm(file, "J:/DATA/GLOBAL_ADULT_TOBACCO_SURVEY/CHN/2009_2010")

		// KNAHES
		replace nid = 112656 if regexm(file,  "J:/DATA/KOR/NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY_KNHANES/2009") 
		replace nid = 120208 if regexm(file,  "J:/DATA/KOR/NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY_KNHANES/2011")

		// IND NCD 2007-2008 
		replace nid = 67200 if regexm(file, "J:/DATA/WHO_STEPS_NCD/IND/2007_2008")

		// DZA WHO STEPS GSHS 
		replace nid = 115913 if regexm(file, "J:/DATA/WHO_STEP_GSHS/DZA/RURAL_2010") 
		replace nid = 74357 if regexm(file, "J:/DATA/WHO_STEP_GSHS/PSE/2010") 

		tostring year_start, replace
		tostring year_end, replace
		replace year_start = "2009" if regexm(file, "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/TON/2010")
		replace year_end = "2009" if regexm(file, "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/TON/2010")
		replace nid = 108779 if regexm(file, "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/IND/ORISSA_2002")
		destring year_start, replace
		destring year_end, replace
		
	/*
		replace nid = 109953 if iso3 == "BFA" & year_start == 2009 & source == "GYTS" & regexm(file, "BOBO_DIOULASSO_2009")
		replace nid = 109956 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/BFA/OUAGADOUGOU_2009_Y2013M09D09_2009"
		replace nid = 110354 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/CHN/HONG_KONG_2009_2009"
		replace nid = 120575 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/CMR/CENTRE_REGION_1_2008"
		replace nid = 120576 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/CMR/CENTRE_REGION_2_2008"
		replace nid = 110364 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/POL/2009"
		replace nid = 94473 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/IRQ/BAGHDAD_Y2013M03D11_2008"
		replace nid = 94613 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/JOR/UNRWA_Y2013M03D11_2008"
		replace nid = 109980 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/LBN/UNRWA_Y2013M03D11_2008"
		replace nid = 28844 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/MWI/LILONGWE_MALAWI-LILONGWE 2005 GYTS_WEB_2005"
		replace nid = 109971 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/NGA/ABUJAH_2008"
		replace nid = 109981 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/PSE/BANK_UNRWA_Y2013M03D11_2008"
		replace nid = 110353 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/PSE/2009"
		replace nid = 109982 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/PSE/STRIP_UNRWA_Y2013M03D11_2008"
		replace nid = 112138 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/SRB/2004"
		replace year_start = 2003 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/SRB/2004"
		replace year_end = 2003 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/SRB/2004"
		replace nid = 110352 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/SYR/UNRWA_Y2013M03D11_2008"
		
		replace nid = 29596 if file == "J:/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/VEN/2001"
*/
	
	// Fill in last few missing files 
	//replace file = "J:/DATA/USA/BRFSS/2008/USA_BRFSS_2008_Y2012M02D13.DTA" if nid == 30008 

	replace file = "J:/DATA/USA/NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY/2007_2008/USA_NHANES_2007_2008_SMQ_E.DTA" if nid == 25914

	replace file = "J:/DATA/USA/NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY/2005_2006/USA_NHANES_2005_2006_SMQFAM_D.DTA" if nid == 47478 

	replace file = "J:/DATA/USA/NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY/2003_2004/USA_NHANES_2003_2004_SMQFAM_C_Y2013M10D14.DTA" if nid == 47962 

	replace file = "J:/DATA/USA/NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY/2009_2010/USA_NHANES_2009_2010_SMQFAM_F.DTA" if nid == 48332

	replace file = "J:/DATA/USA/NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY/2001_2002/USA_NHANES_2001_2002_SMQFAM_B.DTA" if nid == 49205

	replace file = "J:/DATA/USA/NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY/1999_2000/USA_NHANES_1999_2000_SMQFAM.DTA" if nid == 52110

	replace file = "J:/DATA/USA/NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY/2011_2012/USA_NHANES_2011_2012_SMQFAM_G_Y2013M10D11.DTA" if nid == 110300 

	replace file = "J:/LIMITED_USE/PROJECT_FOLDERS/SWE/FROM_COLLABORATORS/SMOKING/SECOND_HAND_SMOKING_SWE" if nid == 145872 

	//replace file = "J:/DATA/USA/BRFSS/1998/USA_BRFSS_1998_Y2012M02D13.DTA" if nid == 29948 
	//replace file = "J:/DATA/USA/BRFSS/1999/USA_BRFSS_1999_Y2012M02D13.DTA" if nid == 29953 
	//replace file = "J:/DATA/USA/BRFSS/2000/USA_BRFSS_2000_Y2012M02D13.DTA" if nid == 29958 
	// replace nid = 106015 if nid == 29958


	drop _merge 

	outsheet using "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/02_compile/unadjusted_compiled_estimates.csv", comma names replace

	
