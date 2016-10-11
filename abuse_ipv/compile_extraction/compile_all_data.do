// July 24, 2015 (original date: July 25, 2014) - almost the one year anniversary of this code! hooray :) 
// Purpose: Compile all tabulated data

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

// Set up
	clear all
	set more off
	local data_dir "J:/WORK/05_risk/risks/abuse_ipv_exp/data/exp/01_tabulate/"
	local outdir "J:/WORK/05_risk/risks/abuse_ipv_exp/data/exp/02_compile"

// Prepare countrycodes database
	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & inlist(level, 3, 4)

	keep ihme_loc_id location_id location_ascii_name super_region_name super_region_id region_name region_id
	
	rename ihme_loc_id iso3 
	tostring location_id, replace
	rename location_ascii_name location_name
	
	tempfile countrycodes
	save `countrycodes', replace	

/********************** BRING IN AND CLEAN UP GBD 2010 and 2013 DATA **************/

// GBD 2010
	insheet using "`data_dir'/prepped/gbd2010_ipv_exp_revised.csv", comma clear
	rename denominator sample_size
	drop if linkauth == "DHS"
	drop if linkauth == "GENACIS" // we re-tabulated the data "in house" for GBD 2015 so we're dropping the tabulations from experts
	gen description = "GBD 2010 expert group data"
	tempfile 2010
	save `2010'

// GBD 2013
	insheet using "`data_dir'/prepped/gbd2013_ipv_exp_revised.csv", comma clear
	drop if nid == 126441 // extracted prevalence of male perpetration of IPV rather than female numbers so re-extracted in 2015

	** Add BRFSS microdata extraction
	append using "`data_dir'/prepped/brfss_prepped.dta"
	** Add DHS --> re-ran and adding in new 2015 data section 
	append using "`data_dir'/prepped/dhs_tabulation_currpart.dta"	
	** Add Mexico subnational data
	append using "`data_dir'/prepped/mexico_subnational.dta"
	replace description  = "GBD 2013"
	
	tempfile 2013
	save `2013'


// Combine
	clear 
	append using `2013' `2010' 
	tempfile compiled
	save `compiled', replace
	
	keep nid iso3 year_start year_end uniqueid linkauth pubyr author
	duplicates drop	
	
	tempfile identifiers
	save `identifiers', replace

// Prep re-extracted
	import excel "`data_dir'/raw/re_extracted_expert_data/GBD_2010_ipv_raw_data_part1_aggregated_small_sample_sizes.xlsx", firstrow sheet("Data1") clear
	replace checked = "" if checked == "ILL"
	destring checked, replace
	drop if author == "DHS"
	tempfile part1
	save `part1', replace
	** The systematic reviewers did not check/re-extract DHS data because we have microdata and the plan was to extract from that instead. 
	import excel "`data_dir'/raw/re_extracted_expert_data/GBD_2010_ipv_raw_data_part1_aggregated_small_sample_sizes.xlsx", firstrow sheet("dhs_tabulations") clear
	append using `part1'
	save `part1', replace
	
	import excel "`data_dir'/raw/re_extracted_expert_data/GBD_2010_ipv_raw_data_part2_aggregated_small_sample_sizes.xlsx", firstrow sheet("Data2") clear
	rename loqual_definition loqual_description
	rename reextracted re_extracted
	// keep if re_extracted == 1 // 
	destring nid, replace
	gen site = re_notes if iso3 == "ZAF"
	
	append using `part1'
	rename mean parameter_value
	gen description = "GBD 2010 expert group data"
	
	drop if nid == 150528 // this is the tabulated GENACIS microdata that we got from experts in 2010; now that we have access to GENACIS micro-data, we did our own tabulations
	tempfile sourced
	save `sourced', replace
	
// Merge
	** Make datset restricted to observations that were accidentally excluded from the dataset for re-extraction/sourcing (i.e. excluded from this file: "J:/DATA/Incoming Data/WORK/05_risk/1_ready/citation_research/data_files/abuse_csa_2014_july_9_total.xlsx")
	merge m:1 nid iso3 year_start year_end uniqueid linkauth pubyr author using `identifiers'
	keep if _merge == 2 & nid != .
	keep nid iso3 year_start year_end uniqueid linkauth pubyr author
	merge 1:m nid iso3 year_start year_end uniqueid linkauth pubyr author using `compiled', nogen keep(match)
	tostring site, replace
	
	** Append the re-extracted datasets
	append using `sourced'
	
// Drop all data that does not meet GBD or cause definitions
	drop if exclusion_reference == 1 
	
// Drop incorrect extractions
	drop if incorrect_extraction == 1 & re_extracted == 0
	
// For now exclude surveys that measure the proportion of men that have perpetrated IPV since we don't currently have a method for crosswalking this metric
	gen data_status = ""
	replace data_status = "excluded" if male_perpetrator == 1

// Drop duplication & add in subnationals for literature 
	drop if regexm(field_citation, "Pune") & parameter_value == 18
	replace iso3 = "IND_43891" if regexm(field_citation, "Pune") // iso3 code for Maharashtra, Urban 
	replace iso3 = "IND_43906" if regexm(field_citation, "Calcutta") // iso3 for West Bengal, Urban (Calcutta is located in West Bengal) 
	replace iso3 = "ZAF_487" if iso3 == "ZAF" & regexm(re_notes, "Mpumalanga") 
	replace iso3 = "ZAF_486" if iso3 == "ZAF" & regexm(re_notes, "Northern Province") // Northern Province is now known as Limpopo
	replace iso3 = "ZAF_482" if iso3 == "ZAF" & regexm(re_notes, "Eastern Cape") 
	replace iso3 = "CHN_354" if iso3 == "HKG" 
	
//  Merge with country codes database
	merge m:1 iso3 using `countrycodes', nogen keep(match)


	** Format units
	foreach var in parameter_value lower upper standard_error  {
		replace `var' = `var' / units if units != .
	}
	
	replace units = 1 

	drop if nid == 19456 & regexm(file, "SP") // want to drop the special DHS for DOM 2007
	drop if nid == 77819 & regexm(file, "SP") // again, dropping special DHS for DOM 2013
	drop if nid == 20663 // these are DHS' where linkauth is not tagged as DHS so they were not captured 

	tempfile gbd_2010_2013
	save `gbd_2010_2013', replace

/********************** BRING IN AND CLEAN UP GBD 2015 DATA **************/

// GBD 2015
	use "`data_dir'/prepped/yrbs_prepped.dta", clear 
	append using "`data_dir'/prepped/brfss_states_prepped.dta" // also adding in state subnational estimates for U.S.
	replace iso3 = iso3 + "_" + location_id if (location_id != "" & location_id != "102") 
	replace iso3 = "VIR" if iso3 == "USA_422"
	replace iso3 = "PRI" if iso3 == "USA_385" 
	** Add GENACIS microdata extraction 
	append using "`data_dir'/prepped/genacis_prepped.dta"
	gen description = "GBD 2015"
	gen linkauth = "GENACIS" if survey_name == "GENACIS"
	tempfile 2015
	save `2015' 

	// Add in new DHS surveys 
		use "`data_dir'/prepped/dhs_tabulation_currpart_revised.dta", clear 
		tempfile dhs_2015
		save `dhs_2015', replace 

		// merge with old DHS file -- ONLY want to keep new surveys that weren't in 2013 dataset (those were added in the section of code above!)
		use "`data_dir'/prepped/dhs_tabulation_currpart.dta", clear 
		split file, p("/") 
		gen path = file1 + "/" + file2 + "/" + file3 + "/" + file4 + "/" + file5
		drop file*

		merge m:m nid iso3 year_start using `dhs_2015', keep(2) nogen
		append using `2015'

		tempfile all_but_ubcov
		save `all_but_ubcov', replace

	// Add in literature updates from 2015
	insheet using "`data_dir'/prepped/gbd_2015_ipv_exp.csv", comma names clear 
	tostring location_id, replace
	replace parameter_value = parameter_value / units 
	replace lower = lower / units 
	replace upper = upper / units
	replace units = 1 
	gen lit = "1" 

	tostring site, replace 
	append using `all_but_ubcov'
	save `all_but_ubcov', replace

	// Clean up ubcov output 
	 
	  use `countrycodes', clear 
		duplicates tag location_name, gen(dup) 
		drop if dup == 1 & !regexm(iso3, "BRA") & !regexm(iso3, "GEO") 
		drop dup
		tempfile countrycodes_adapted
		save `countrycodes_adapted', replace
	
 
/*
		use "`data_dir'/prepped/collapsed_abuse_ipv.dta", clear 
		rename subnat_id location_name 
		replace location_name = proper(location_name) 
		rename ihme_loc_id iso3
		merge m:1 iso3 using `countrycodes', keep(1 3) nogen 
		rename location_id location_id_old 
*/

		use "`data_dir'/prepped/collapsed_abuse_ipv.dta", clear 
		preserve 
		keep if subnat_id == "Paraiba"
		tempfile paraiba 
		save `paraiba', replace
		restore
		drop if subnat_id == "Paraiba" 

		// Fix India so that we can match on Goa, urban and Goa, rural 
		replace subnat_id = "Goa, Urban" if subnat_id == "Urban" & ihme_loc_id == "IND_4850" 
		replace subnat_id = "Goa, Rural" if subnat_id == "Rural" & ihme_loc_id == "IND_4850" 
		drop if ihme_loc_id == "IND_4850" & subnat_id == "" 

		// Already uploaded MEX ENA national-level and KEN DHS national-level estimates so want to drop these 
		drop if nid == 21365 & subnat_id == "" 
		drop if nid == 105286 & subnat_id == "" 

		save "`data_dir'/collapsed_abuse_ipv_for_mapping.dta", replace

		adopath + "$prefix/WORK/01_covariates/common/ubcov_central/_functions" 
		subnat_map, file("`data_dir'/collapsed_abuse_ipv_for_mapping.dta") location_var(subnat_id) parent_loc_id(ihme_loc_id)

		drop if regexm(subnat_id, "NO SABE") 
		
		// Parse for location_ids 

		split ihme_loc_id, p("_") 
		rename ihme_loc_id2 location_id
		drop ihme_loc_id1

		rename location_id location_id_old 

		rename ihme_loc_id iso3
		merge m:1 iso3 using `countrycodes', keep(1 3) nogen 

		replace location_id = location_id_old if location_id == "" 
		drop location_id_old

		// Append Paraiba, which wasn't mapping correctly 

		append using `paraiba'
		replace iso3 = "BRA_4764" if subnat_id == "Paraiba" 
		replace location_id = "4764" if iso3 == "BRA_4764" 

		// replace Goa with correct location_id
		replace iso3 = "IND_43881" if iso3 == "IND_4850" & subnat_id == "urban" // Goa, Urban 
		replace location_name = "Goa, Urban" if iso3 == "IND_43881"
		replace location_id = "43881" if iso3 == "IND_43881"
		replace iso3 = "IND_43917" if iso3 == "IND_4850" & subnat_id == "rural" // Goa, Rural
		replace location_name = "Goa, Rural" if iso3 == "IND_43917"
		replace location_id = "43917" if iso3 == "IND_43917"

		tempfile ubcov 
		save `ubcov', replace

		insheet using "`outdir'/convert_to_new_age_ids.csv", comma names clear 
		rename age_group_id age_id
		merge 1:m age_id using `ubcov', keep(3) nogen
		gen age_end = age_start + 4 
		//replace iso3 = iso3 + "_" + location_id if regexm(file_path, "BRA") & location_name != "" 
		rename se_abuse_ipv standard_error
		rename sd_abuse_ipv standard_deviation
		rename ss_abuse_ipv sample_size 
		rename mean_abuse_ipv mean
		rename sex_id sex 
		drop subnat_est list_flag collapse_flag standard_deviation
		rename spouseon spouseonly
		rename notviostudy notviostudy1
		drop age_id
		rename file_path file 

		save `ubcov', replace


/********************** COMBINE ALL DATA **************/

	clear 
	append using `all_but_ubcov' `ubcov' `gbd_2010_2013' 

	rename physvio phys_ipv 
	rename sexvio sexual_ipv 
	rename severe case_severe 
	rename nointrain interviewer_trained 
	rename currpart violence_partner 
	rename mixed urban_mixed
	rename pastyr recall_1yr
	drop violence 
	rename notviostudy violence
	replace violence = 0 if violence == 1 
	replace violence = 1 if violence == 0 // flipped violence covariate for 2015; 0 = not violence-specific study; 1 = violence-specific study 

	replace mean = parameter_value if mean == . 
	drop if mean == . 
	//drop if sample_size < 10 // unstable estimates below this point

	keep nid iso3 location_id year_start year_end sex age_start age_end sample_size mean standard_error  upper lower spouseonly case_severe phys_ipv sexual_ipv interviewer_trained violence violence_partner recall_1yr past2yr pstatall pstatcurr units file path source_type orig_uncertainty_type national_type urbanicity_type urban rural urban_mixed lit
	
	order nid iso3 location_id year_start year_end sex age_start age_end sample_size mean standard_error upper lower spouseonly case_severe phys_ipv sexual_ipv interviewer_trained violence violence_partner recall_1yr past2yr pstatall pstatcurr units file path  source_type orig_uncertainty_type national_type urbanicity_type urban rural urban_mixed lit

	tempfile compiled
	save `compiled', replace


// Format for Dismod

	** Format units
	foreach var in lower upper standard_error  {
		replace `var' = `var' / units if units != .
	}
	
	** Define source types
	drop source_type
	gen source_type = 26 
	label define source 26 "Survey - other/unknown" 
	label values source_type source

	** Format units
	gen unit_value_as_published = 1 
	gen unit_type = "Person"

	** Format study level covariates
	foreach covar in spouseonly case_severe phys_ipv sexual_ipv interviewer_trained violence violence_partner recall_1yr past2yr pstatall pstatcurr { 
		rename `covar' cv_`covar'
		recode cv_`covar' (. = 0)
	} 

	// Specify representation
	rename national_type representative_name
	replace representative_name = 4 if regexm(file, "BRA") 
	replace representative_name = 4 if regexm(file, "IND") & regexm(file, "MACRO_DHS") 
	replace representative_name = 2 if regexm(file, "GOA_SAAHAS") 
	replace representative_name = 2 if regexm(file, "SCOTLAND") 
	replace representative_name = 2 if urban == 1 | rural == 1 
	replace representative_name = 1 if representative_name == . 
	label define national 1 "Nationally representative only" 2 "Representative for subnational location only" 3 "Not representative" 4 "Nationally and subnationally representative" /// 
	5 "Nationally and urban/rural representative" 6 "Nationally, subnationally and urban/rural representative" 7 "Representative for subnational location and below" /// 
	8 "Representative for subnational location and urban/rural" 9 "Representative for subnational location, urban/rural and below" 10 "Representative of urban areas only" /// 
	11 "Representative of rural areas only" 
	label values representative_name national

	// Epi uploader wants as string value
	decode representative_name, gen(rep_name_new)
	rename representative_name rep_name_numeric
	rename rep_name_new representative_name
	

// Specify location type
	replace urbanicity_type = lower(urbanicity_type)
	encode urbanicity_type, gen(urbanicitytype)
	drop urbanicity_type
	rename urbanicitytype urbanicity_type
	recode urbanicity_type (1=0) (2=1) (4=2)
	label drop urbanicitytype
	replace urbanicity_type = 1 if representative_name == "Nationally representative only" 
	replace urbanicity_type = 2 if urban == 1 & urbanicity_type == .
	replace urbanicity_type = 3 if urban == 0 & urbanicity_type == .
	replace urbanicity_type = 0 if urbanicity_type == .
	replace urbanicity_type = 0 if nid ==  169744 	
	label define urbanicity 0 "Unknown" 1 "Mixed/both" 2 "Urban" 3 "Rural" 4 "Suburban" 5 "Peri-urban"
	label values urbanicity_type urbanicity
	
		// Fix for epi uploader 
			decode urbanicity_type, gen(urbanicity_type_new) 
			drop urbanicity_type 
			rename urbanicity_type_new urbanicity_type

// Fix uncertainty variables
	recode lower upper standard_error (0=.)
	replace lower = . if upper == .
	replace upper = . if lower == .
	replace standard_error = (upper - lower)/ (2*1.96) if standard_error == .

	drop if sample_size < 10 // These means are too unstable
	rename orig_uncertainty_type uncertainty_type

	replace uncertainty_type = "Confidence interval" if lower != . & upper != . 
	replace uncertainty_type = "Confidence interval" if uncertainty_type == "CI"

	replace uncertainty_type = "Standard error" if standard_error != . & uncertainty_type == ""
	replace uncertainty_type = "Standard error" if uncertainty_type == "SE" 

	replace uncertainty_type = "Effective sample size" if uncertainty_type == ""
	replace uncertainty_type = "Effective sample size" if uncertainty_type == "ESS"	
	
	gen uncertainty_type_value = 95 if uncertainty_type == "Confidence interval" 
	replace uncertainty_type_value = . if lower == . 


// Fill in epi variables
	
	** Fill in sex-specific variables
	gen modelable_entity_id = 2452
	gen modelable_entity_name = "Intimate partner violence"

// Fix missing location ids 
	destring location_id, replace
	rename location_id location_id_old 

	merge m:1 iso3 using `countrycodes', keep(1 3) nogen
	destring location_id, replace
	replace location_id = location_id_old if location_id == . 
	drop location_id_old
	
// Final things for epi uploader
	 rename sample_size effective_sample_size

	** Specify recall type
	gen recall_type = 2 if (cv_recall_1yr != 1 & cv_past2yr != 1) 
	replace recall_type = 3 if cv_recall_1yr == 1 | cv_past2yr == 1 
	label define recall 1 "Point" 2 "Lifetime" 3 "Period: years" 4 "Period: months" 5 "Period: weeks" 6 "Period: days" 
	label values recall_type recall

		// Fix for epi uploader 
			decode recall_type, gen(recall_type_new) 
			drop recall_type
			rename recall_type_new recall_type

	//gen unit_value_as_published = 1 
	gen measure = "proportion"	
	gen extractor = "lalexan1" 
	gen is_outlier = 0 
	gen underlying_nid = . 
	gen sampling_type = "" 
	gen recall_type_value = "" 
	gen input_type = "" 
	gen sample_size = . 
	gen cases = . 
	gen design_effect = . 
	gen site_memo = "" 
	gen case_diagnostics = "" 
	gen response_rate = .
	gen note_SR = "" 
	gen note_modeler = "Literature sources for GBD 2015" if lit == "1"
	gen row_num = . 
	gen parent_id = . 
	gen data_sheet_file_path = "" 

// Validation checks
	drop if mean == . | (upper == . & lower == . & effective_sample_size == . & standard_error == .) // Need mean and some variance metric
	drop if mean < lower & lower != .
	drop if upper < mean 
	drop if mean > 1

// Only keep necessary variables
	local variables row_num modelable_entity_id modelable_entity_name description measure	nid	file iso3 location_name	location_id	location_name	/// 
	sex	year_start	year_end	age_start	age_end	measure	mean	lower	upper	standard_error	effective_sample_size	/// 
	orig_unit_type	uncertainty_type uncertainty_type_value	representative_name	urbanicity_type	case_definition	extractor ///
	unit_value_as_published cv_* source_type is_outlier underlying_nid /// 
	sampling_type recall_type recall_type_value unit_type input_type sample_size cases design_effect site_memo case_name /// 
	case_diagnostics response_rate note_SR note_modeler data_sheet_file_path parent_id case_name


// Save raw data
	export excel "`outdir'/compiled_unadjusted_tabulations_full_dataset.xlsx", sheet(Data) firstrow(variables) sheetreplace
			


/*
Only add new data (1/19/16)
	keep if nid == 21365 | nid == 228081 | nid == 105286
	drop if nid == 105286 & iso3 == "MEX" // national estimates already uploaded

		// 21365 --> Kenya DHS 2008-2009
		// 228081 --> Goa SAAHAS study 
		// 105286 --> Mex ENA 
