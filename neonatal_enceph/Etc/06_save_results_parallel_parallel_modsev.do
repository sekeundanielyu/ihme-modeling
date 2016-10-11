/*******************************************
Description: This is the second lower-level script submitted by 
06_save_results.do, and the first submitted by 06_save_results_parallel.do. 
06_save_results_parallel_parallel formats mild_imp prevalence data and runs 
save_results. We do not run a second DisMod model for mild impairment because 
we assume no excess mortality associated with mild impairment. Therefore there 
is no need to stream out in DisMod to get our final results. 

*******************************************/

clear all 
set more off
set maxvar 30000
version 13.0

// priming the working environment
if c(os) == "Windows" {
			local j "J:"
			// Load the PDF appending application
			quietly do "`j'/Usable/Tools/ADO/pdfmaker_acrobat11.do"
		}
		if c(os) == "Unix" {
			local j "/home/j"
			ssc install estout, replace 
			ssc install metan, replace
		} 

// arguments
local acause `1'
local me_id `2'
local age_id `3'

// test arguments
/*local acause "neonatal_enceph"
local me_id 2525
*/

// directories
local upload_dir "`j'/WORK/04_epi/01_database/02_data"

// functions
run "`j'/WORK/10_gbd/00_library/functions/save_results.do"
run "`j'/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
run "`j'/WORK/10_gbd/00_library/functions/get_outputs_helpers/query_table.ado"

************************************************************************************

// find gestational age group, age_start and end, target me_id and nid
di "finding gestational age, target me_id and nid"
if `me_id' == 1557 {
	local gest_age "ga1_"
	local target_me_id 8621
	local nid 256555
}
if `me_id' == 1558 {
	local gest_age "ga2_"
	local target_me_id 8622
	local nid 256555
}
if `me_id' == 1559 {
	local gest_age "ga3_"
	local target_me_id 8623
	local nid 256555
}
if `me_id' == 2525 {
	local gest_age ""
	local target_me_id 8653
	local nid 256562
}
if `me_id' == 9793 {
	local gest_age ""
	local target_me_id 8674
	local nid 256561
}
if `age_id' == 0 {
	local age_start 0
	local age_end 0
}
if `age_id' == 2 {
	local age_start 0
	local age_end 7
}
if `age_id' == 3 {
	local age_start 7
	local age_end 28
}
if `age_id' == 4 {
	local age_start 28
	local age_end 28
}

di "Acause is `acause' me_id `me_id' gestage `gest_age'"
di "importing modsev prevalence data"
local bprev_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/temp_outputs/`acause'/`me_id'/parallel_no_sub"

import delimited "`bprev_dir'/`age_start'_`age_end'_modsev_prev_final_prev.csv", clear

	// switch from draws to mean and bounds
	egen mean = rowmean(draw*)
	egen upper = rowpctile(draw*), p(97.5)
	egen lower = rowpctile(draw*), p(2.5)
	drop draw*

gen modelable_entity_id = `target_me_id'

// this is to drop locations that are not most_granular 
// now they're not being created in the squeezing process 
drop if upper == . 

tempfile data
save `data'

query_table, table_name(modelable_entity) server(modeling-epi-db) database(epi) clear
merge 1:m modelable_entity_id using `data', keep(3) nogen 
save `data', replace

get_location_metadata, location_set_id(9) clear
merge 1:m location_id using `data', keep(3) nogen
keep location_id location_ascii_name sex year mean lower upper modelable_entity_id modelable_entity_name 
save `data', replace

rename location_ascii_name location_name

gen age_start = `age_start'/365
gen age_end = `age_end'/365

rename year year_start
gen year_end = year_start

gen measure = "prevalence"

tostring sex, replace
replace sex = "Male" if sex == "1"
replace sex = "Female" if sex == "2"

gen representative_name = "Nationally and subnationally representative"
gen year_issue = 0
gen sex_issue = 0
gen age_issue = 0
gen age_demographer = 0
gen unit_type = "Person"
gen unit_value_as_published = 1
gen measure_issue = 0
gen measure_adjustment = 0
gen extractor = "steeple"
gen uncertainty_type = "Confidence interval"
gen uncertainty_type_value = 95
gen urbanicity_type = "Unknown"
gen recall_type = "Not Set"
gen is_outlier = 0
gen standard_error = . 
gen effective_sample_size = . 
gen cases = . 
gen sample_size = . 
gen nid = `nid'
gen source_type = "Surveillance - other/unknown"
gen row_num = . 
gen parent_id = . 
gen data_sheet_file_path = ""
gen input_type = ""
gen underlying_nid = .
gen underlying_field_citation_value = ""
gen field_citation_value = ""
gen page_num = .
gen table_num = .
gen ihme_loc_id = ""
gen smaller_site_unit = 0
gen site_memo = ""
gen design_effect = .
gen recall_type_value = ""
gen sampling_type = ""
gen response_rate = . 
gen case_name = ""
gen case_definition = ""
gen case_diagnostics = ""
gen note_modeler = ""
gen note_SR = ""
gen specificity = .
gen group = .
gen group_review = .

// save
export excel "`upload_dir'/`acause'/`target_me_id'/04_big_data/`target_me_id'_`age_start'_`age_end'_prevalence.xlsx", firstrow(variables) sheet("extraction") replace 
