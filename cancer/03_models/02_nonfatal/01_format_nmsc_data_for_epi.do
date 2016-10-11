
// Purpose:		Format NMSC data for modeling in epi


** *************************************************************************************************************
** Define programs
** *************************************************************************************************************
// define progam to generate age_start and age_end
program def set_age
	drop if age<3 
	gen age_start=.
	gen age_end=.
	replace age_start=0 if age==2
	replace age_start=5 if age==7
	replace age_start=10 if age==8
	replace age_start=15 if age==9
	replace age_start=20 if age==10
	replace age_start=25 if age==11
	replace age_start=30 if age==12
	replace age_start=35 if age==13
	replace age_start=40 if age==14
	replace age_start=45 if age==15
	replace age_start=50 if age==16
	replace age_start=55 if age==17
	replace age_start=60 if age==18
	replace age_start=65 if age==19
	replace age_start=70 if age==20
	replace age_start=75 if age==21
	replace age_start=80 if age==22
	replace age_end=4 if age==2
	replace age_end=9 if age==7
	replace age_end=14 if age==8
	replace age_end=19 if age==9
	replace age_end=24 if age==10
	replace age_end=29 if age==11
	replace age_end=34 if age==12
	replace age_end=39 if age==13
	replace age_end=44 if age==14
	replace age_end=49 if age==15
	replace age_end=54 if age==16
	replace age_end=59 if age==17
	replace age_end=64 if age==18
	replace age_end=69 if age==19
	replace age_end=74 if age==20
	replace age_end=79 if age==21
	replace age_end=99 if age==22
end

** *************************************************************************************************************
** Format BCC data
** *************************************************************************************************************
// Clear memory and set memory and variable limits
clear  
set more off

// Get data
use "J:\WORK\07_registry\cancer\02_database\01_mortality_incidence\data\intermediate\02_registries_refined.dta" if acause == "neo_nmsc_bcc", clear

// keep relevant information
drop sourceINC sourceMOR nidMOR deaths* dataType year year_span
rename nidINC nid

** drop data from Canada and USA
drop if iso3=="CAN" & registry=="British Columbia"
drop if iso3=="USA"

// save population data for after reshape
preserve
	drop cases*
	reshape long pop, i(iso3 location_id national year* sex acause registry source nid) j(age)
	tempfile pop_data
	save `pop_data', replace
restore
drop pop*

// reshape, then re-merge population data
reshape long cases, i(iso3 location_id national year* sex acause registry source nid) j(age)
merge 1:1 iso3 location_id national year* sex acause registry source nid age using `pop_data', assert(3) nogen

// gen epi age groups
set_age


// add remaining variables
gen row_num=.
gen parent_id=.
gen data_sheet_file_path=.
gen input_type=.
gen modelable_entity_id=1760
gen modelable_entity_name="Basal cell carcinoma"
gen underlying_nid=.
gen source_type="Registry - cancer"
gen unit_value_as_published=1
gen field_citation_value=.
gen file_path=.
gen smaller_site_unit=1
rename registry site_memo
gen representative_name ="Nationally and subnationally representative" if national==1
replace representative_name ="Representative for subnational location only" if national==0
gen urbanicity_type="Unknown"
tostring sex, replace
replace sex="Female" if sex=="2"
replace sex="Male" if sex=="1"
gen sex_issue=0
gen year_issue=0
gen age_issue=0
gen measure = "incidence"
gen age_demographer=1
gen mean=.
gen lower=.
gen upper=.
gen standard_error=.
gen effective_sample_size=.
rename pop sample_size
gen unit_type="Person"
gen unit_type_value=1
gen measure_issue=0
gen measure_adjustment=0
gen design_effect=.
gen uncertainty_type=.
gen recall_type="Not Set"
gen recall_type_value=.
gen sampling_type=.
gen respons_rate=.
gen case_name="BCC"
gen case_definition=.
gen case_diagnostics=.
gen group=.
gen specificity=.
gen group_review=.	
gen note_modeler=.	
gen note_SR=.
gen extractor="[name]"
gen is_outlier=0
gen	cv_nmsc=.
gen	data_sheet_filepath=.
gen uncertainty_type_value=.
gen response_rate=.

*order based on epi extraction sheet
order row_num parent_id input_type modelable_entity_id modelable_entity_name nid underlying_nid field_citation_value file_path source_type location_id smaller_site_unit site_memo representative_name urbanicity_type year_start year_end year_issue sex sex_issue age_start age_end age_issue age_demographer measure mean lower upper standard_error effective_sample_size cases sample_size design_effect unit_type unit_type_value unit_value_as_published measure_issue measure_adjustment uncertainty_type uncertainty_type_value recall_type recall_type_value sampling_type response_rate case_name case_definition case_diagnostics group specificity group_review note_modeler note_SR extractor is_outlier

*drop what is not needed
drop age
drop source
drop gbd_iteration
drop subdiv
drop iso3
drop national
drop acause

*idenfity sources with issues (missing or unidentified NID, no population/sample size
tab nid if sample_size==.
tab nid if sample_size==0
tab location_id sex  if nid==.
drop if nid==.
drop if sample_size==.
drop if sample_size==0

// save
save "J:\WORK\04_epi\01_database\02_data\neo_nmsc\1760\01_input_data\01_nonlit\03_registry\bcc.dta", replace
export delimited using "J:\WORK\04_epi\01_database\02_data\neo_nmsc\1760\01_input_data\01_nonlit\03_registry\bcc_cancer_registry_2015.csv", replace



** *************************************************************************************************************
** Format SCC data
** *************************************************************************************************************
// Clear memory and set memory and variable limits
clear  
set more off

// Get data
use "J:\WORK\07_registry\cancer\02_database\01_mortality_incidence\data\intermediate\02_registries_refined.dta" if acause == "neo_nmsc_scc", clear

// keep relevant information
drop sourceINC sourceMOR nidMOR deaths* dataType year year_span
rename nidINC nid

** dropping CANADA BC since the data we have from lit review is at the 4 digit ICD code level (can differentiate BCC from SCC). data is therefore more accurate the then CI5 data since that is reported as C44 and has to undergo split into SCC and BCC based on lit proportion from Karakas et al)
drop if iso3=="CAN" & registry=="British Columbia"
** dropping USA data since SEER does not include NMSC
drop if iso3=="USA"

// save population data for after reshape
preserve
	drop cases*
	reshape long pop, i(iso3 location_id national year* sex acause registry source nid) j(age)
	tempfile pop_data
	save `pop_data', replace
restore
drop pop*

// reshape, then re-merge population data
reshape long cases, i(iso3 location_id national year* sex acause registry source nid) j(age)
merge 1:1 iso3 location_id national year* sex acause registry source nid age using `pop_data', assert(3) nogen

// gen epi age groups
set_age

// add remaining variables
gen row_num=.
gen parent_id=.
gen data_sheet_file_path=.
gen input_type=.
gen modelable_entity_id=2513
gen modelable_entity_name="Cutaneous squamous cell carcinoma"
gen underlying_nid=.
gen source_type="Registry - cancer"
gen unit_value_as_published=1
gen field_citation_value=.
gen file_path=.
gen smaller_site_unit=1
rename registry site_memo
gen representative_name ="Nationally and subnationally representative" if national==1
replace representative_name ="Representative for subnational location only" if national==0
gen urbanicity_type="Unknown"
tostring sex, replace
replace sex="Female" if sex=="2"
replace sex="Male" if sex=="1"
gen sex_issue=0
gen year_issue=0
gen age_issue=0
gen measure = "incidence"
gen age_demographer=1
gen mean=.
gen lower=.
gen upper=.
gen standard_error=.
gen effective_sample_size=.
rename pop sample_size
gen unit_type="Person"
gen unit_type_value=1
gen measure_issue=0
gen measure_adjustment=0
gen design_effect=.
gen uncertainty_type=.
gen recall_type="Not Set"
gen recall_type_value=.
gen sampling_type=.
gen respons_rate=.
gen case_name="SCC"
gen case_definition=.
gen case_diagnostics=.
gen group=.
gen specificity=.
gen group_review=.	
gen note_modeler=.	
gen note_SR=.
gen extractor="[name]"
gen is_outlier=0
gen	cv_nmsc
gen	data_sheet_filepath=.
gen uncertainty_type_value=.
gen response_rate=.

*order based on epi extraction sheet
order row_num parent_id input_type modelable_entity_id modelable_entity_name nid underlying_nid field_citation_value file_path source_type location_id smaller_site_unit site_memo representative_name urbanicity_type year_start year_end year_issue sex sex_issue age_start age_end age_issue age_demographer measure mean lower upper standard_error effective_sample_size cases sample_size design_effect unit_type unit_type_value unit_value_as_published measure_issue measure_adjustment uncertainty_type uncertainty_type_value recall_type recall_type_value sampling_type response_rate case_name case_definition case_diagnostics group specificity group_review note_modeler note_SR extractor is_outlier

*drop what is not needed
drop age
drop source
drop gbd_iteration
drop subdiv
drop iso3
drop national
drop acause

*idenfity sources with issues (missing or unidentified NID, no population/sample size
tab nid if sample_size==.
tab nid if sample_size==0
tab location_id sex  if nid==.
drop if nid==.
drop if sample_size==.
drop if sample_size==0

// save
save "J:\WORK\04_epi\01_database\02_data\neo_nmsc\2513\01_input_data\01_nonlit\03_registry\scc.dta", replace
export delimited using "J:\WORK\04_epi\01_database\02_data\neo_nmsc\2513\01_input_data\01_nonlit\03_registry\scc_cancer_registry_2015.csv", replace

** **********
** END
** **********
