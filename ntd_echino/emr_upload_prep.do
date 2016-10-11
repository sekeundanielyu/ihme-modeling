/////////
//Prepare emr data for upload (have to make request to create NIDs)
import excel using "J:/WORK/04_epi/01_database/02_data/ntd_echino/1484/03_review/03_upload/inc_csmr_emr_ntd_echino_1484_Y2016M06D03.xlsx", sheet("extraction") firstrow clear
drop if emr == .
drop if is_outlier == 1
drop if group_review == 0
replace row_num = .
replace parent_id = .
replace data_sheet_file_path = "/home/j/WORK/04_epi/01_database/02_data/ntd_echino/1484/02_uploaded/inc_csmr_emr_ntd_echino_1484_Y2016M06D03.xlsx"
replace input_type = "adjusted"
replace nid = 257601
replace field_citation_value = "Institute for Health Metrics and Evaluation (IHME). IHME GBD 2015 DisMod Cystic Echninococcosis Excess Mortality Rate Estimates."
replace page_num = ""
replace table_num = ""
replace source_type = "Mixed or estimation"
replace smaller_site_unit = .
replace site_memo = ""
replace age_demographer = .
replace measure = "mtexcess"
replace mean = emr
replace lower = .
replace upper = .
replace standard_error = se_emr
replace effective_sample_size = .
replace cases = .
replace sample_size = .
replace unit_type = "Person"
replace	unit_value_as_published	= 1
replace measure_issue = 0
replace measure_adjustment = .
replace uncertainty_type = "Standard error"
replace uncertainty_type_value = .
replace representative_name = "Not Set"
replace urbanicity_type = "Unknown"
replace recall_type = "Not Set"
replace recall_type_value = .
replace sampling_type = ""
replace case_name = ""
replace case_definition	= ""
replace case_diagnostics = ""
replace	note_modeler = ""
replace	note_SR = ""
replace	extractor = ""
//drop _data_id
replace specificity = ""
replace	group = .
replace	group_review = .
replace	cv_clinic_or_hospital = .

//keep all the columns needed for upload
keep row_num parent_id data_sheet_file_path input_type modelable_entity_id modelable_entity_name underlying_nid nid underlying_field_citation_value field_citation_value page_num table_num source_type	location_name location_id ihme_loc_id smaller_site_unit site_memo sex sex_issue year_start year_end year_issue age_start age_end age_issue age_demographer measure mean lower upper standard_error effective_sample_size cases sample_size design_effect unit_type unit_value_as_published measure_issue measure_adjustment uncertainty_type uncertainty_type_value representative_name urbanicity_type recall_type recall_type_value sampling_type response_rate case_name case_definition case_diagnostics note_modeler note_SR extractor is_outlier _data_id specificity group group_review cv_clinic_or_hospital

export excel using "J:/WORK/04_epi/01_database/02_data/ntd_echino/1484/03_review/03_upload/emr_ntd_echino_1484_Y2016M06D05.xlsx", firstrow(variables)  sheet("extraction") replace

export excel using "J:/WORK/04_epi/01_database/02_data/ntd_echino/1484/04_big_data/emr_ntd_echino_1484_Y2016M06D05.xlsx", firstrow(variables)  sheet("extraction") replace


