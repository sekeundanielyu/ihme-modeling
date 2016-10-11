//Sexsplit data from Lai using Claims data

//Prep Stata
	clear all
	set more off
	cap restore, not
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		local j "/home/j"
		set odbcmgr unixodbc
		local ver 1
	}
	else if c(os) == "Windows" {
		local j "J:"
		local ver 0
	}
	qui adopath + `j'/WORK/10_gbd/00_library/functions/
	
	//locals
	local tables2 J:/WORK/04_epi/01_database/02_data/resp_asthma/1907/01_input_data/00_lit/00_pdfs/00_extracted/lai_tbl_s2_extracted.csv
	local tables3 J:/WORK/04_epi/01_database/02_data/resp_asthma/1907/01_input_data/00_lit/00_pdfs/00_extracted/lai_tbl_s3_extracted.csv
	local marketscan "J:\WORK\04_epi\01_database\02_data\resp_asthma\1907\01_input_data\01_nonlit\marketscan\ALL_resp_asthma_1907_nr_prev_may_28_2016.xlsx"
	
	//get marketscan formatted
	import excel using `marketscan', clear first
	
	//keep only US pattern
	keep if location_id == 102
	
	//keep only the best marketscan year
	keep if year_start ==2012
	
	//table 2 is on 6-7 year olds and table 3 is 13-14; keep only the relevant ages
	keep if age_start == 5 | age_start == 10
	
	//find the sex fraction
	bysort age_start: egen total_cases = total(cases)
	gen sex_frac_cases = cases/total_cases
	bysort age_start: egen total_samp = total(sample_size)
	gen sex_frac_samp = sample_size/total_samp
	
	keep sex age* cases total_cases sex_frac*
	
	gen age = "6-7" if age_start == 5
	replace age = "13-14" if age_start ==10
	
	keep age sex sex_frac_*
	reshape wide sex_frac_*, i(age) j(sex) string
	tempfile sex_fracs
	save `sex_fracs', replace
	
	//bring in the lai tables for splitting
	import delim using `tables2', clear
	gen age = "13-14"
	tempfile t2
	save `t2', replace
	
	import delim using `tables3', clear
	gen age = "6-7"
	tempfile t3
	save `t3', replace
	append using `t2'
	
	//bring in sex fraction and apply
	merge m:1 age using `sex_fracs', assert(3) nogen
	
	gen casesMale = cases * sex_frac_casesMale
	gen sample_sizeMale = samplesize *sex_frac_sampMale
	gen casesFemale = cases * sex_frac_casesFemale
	gen sample_sizeFemale = samplesize *sex_frac_sampFemale
	
	//set year as the average year of the center
	gen year_start = round(year_id/numcentres)
	gen year_end = round(year_id/numcentres)
	
	//clean up the dataset and then prepare for the uploader
	keep location_id numcentres year_start year_end age_start age_end cases* sample_size*
	
	drop cases //drop the main cases var
	
	
	reshape long sample_size cases, i(year* age* location_id numcentres) j(sex) string
	tostring numcentres, replace
	//Prep for epi upload 
	gen row_num = . 
	gen parent_id = .
	gen mean = .
	gen standard_error = .
	gen nid = 111335
	gen underlying_nid = . 
	gen input_type = "adjusted"
	gen modelable_entity_name = "Asthma cases"
	gen modelable_entity_id = 1907 
	//gen file_path = ""
	gen source_type = "Survey - cross-sectional"
	//gen smaller_site_unit = 0
	gen site_memo = "This datapoint refers to " + numcentres + " sites"
	gen year_issue = 0
	gen sex_issue = 0
	gen age_issue = 0
	gen age_demographer = 0
	gen measure = "prevalence" //CSMR
	gen upper = .
	gen lower = .
	gen design_effect = .
	gen urbanicity_type = "Mixed/both"
	gen uncertainty_type = ""
	gen uncertainty_type_value = ""
	gen unit_type = "Person"
	gen unit_value_as_published = 1
	gen measure_issue = 0
	gen measure_adjustment = 1
	gen effective_sample_size = . 
	gen representative_name = "Nationally and subnationally representative"
	gen response_rate = ""
	gen recall_type = "Point"
	gen recall_type_value = ""
	gen sampling_type = ""
	gen case_name = ""
	gen case_diagnostics = ""
	gen case_definition = "Current Wheeze"
	gen is_outlier = 0
	gen extractor = "strUser"
	gen note_SR = ""
	gen note_modeler = "Data have been sex split using 2012 claims data pattern"
	gen cv_marketscan_all_2010=0
	gen cv_marketscan_all_2000 =0
	gen cv_marketscan_all_2012=0
	gen cv_wheezing =0
	gen table_num = cond(age_start == 6,"table s3", "table s2")
	
	export excel using "J:\WORK\04_epi\01_database\02_data\resp_asthma\1907\04_big_data\rextracted_lai_nowheeze_fixedsamp.xlsx", replace first(var) sheet("extraction")