// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:	Calculate incidence and prevalence of ectomy procedures by year, age, sex, and location. Format these calculations for upload into the Epi database

** **************************************************************************
** Configuration
** 			
** **************************************************************************
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"

// Set STATA workspace 
	clear
	set more off
	capture set maxvar 32000
	
// Set common directories, functions, and globals (shell, finalize_worker, finalization_folder...)
	run "$j/WORK/07_registry/cancer/03_models/02_yld_estimation/01_code/subroutines/set_paths.do"

** ****************************************************************
** SET MACROS FOR CODE
** ****************************************************************
// accept arguments
	args rate_id local_id

// Get acause and associated sexes
	use "$parameters_folder/causes.dta", clear
	levelsof acause if procedure_rate_id == `rate_id', clean local(cause)  
	levelsof procedure_proportion_id if procedure_rate_id == `rate_id', clean local(pr_id)	

// modelable entity name
	use "$parameters_folder/modelable_entity_ids.dta", clear
	levelsof modelable_entity_name if modelable_entity_id == `rate_id', clean local(modelable_entity_name)  

// get measure_ids
	use "$parameters_folder/constants.dta", clear
	local proportion_measure = proportion_measure_id[1]
	local incidence_measure = incidence_measure_id[1]

// Set data folder and save location of rate data
	local output_folder =  "$procedure_rate_folder/upload_`rate_id'"
	local modeled_proportions = "`output_folder'/modeled_proportions_`pr_id'.dta"

// load summary functions
	run "$summary_functions"

** **************************************************************************
** calculate the number of procedures
** **************************************************************************
// get data for the location and cause of interest
	clear
	local input_file = "$incidence_folder/`cause'/incidence_draws_`local_id'.dta"
	noisily di "Appending `input_file'"
	append using  "`input_file'"

// Keep relevant data
	keep if age <= 80
	tempfile data
	save `data', replace

// format data (keep year and sex variables to enable merge with population data)
	gen year_id = year
	gen sex_id = sex
	convert_to_age_group

// merge with incidence or prevalence
	merge m:1 location_id year_id sex_id age_group_id using `modeled_proportions', keep(3) nogen
	rename draw_* proportion_*

// calculate percentage
	foreach i of numlist 0/999 {
		gen procedures_`i' = proportion_`i'*incidence_`i'
	}
	drop proportion_* incidence_*

// Calculate summary statistics
	calculate_summary_statistics, data_var("procedures")
	rename (mean_ lower_ upper_) (mean lower upper)

** **************************************************************************
** Format data for epi uploader
** **************************************************************************
// add variable entries
	capture drop modelable_entity_id
	gen modelable_entity_id=`rate_id'
	gen modelable_entity_name="`modelable_entity_name'"
	gen extractor = "[name]" 

// add constants
	// sex	
	capture drop sex
	tostring sex_id, replace
	replace sex_id="Female" if sex_id=="2"
	replace sex_id="Male" if sex_id=="1"
	rename sex_id sex
	gen sex_issue=0
	
	// year
	rename year_id year_start
	gen year_end=year_start+4
	gen year_issue=0

	// age 
	gen age_start=.
	gen age_end=.
	replace age_start = (age -5)*5
	replace age_end = age_start +4
	replace age_end = 100 if age_group_id==21
	drop if age_group_id>21
	drop if age_start == .
	drop age_group_id 
	gen age_issue=0
	gen age_demographer=1
	
	// other	
	gen row_num=.
	gen parent_id=.
	gen input_type=.
	gen underlying_nid=.
	gen nid=257604
	gen source_type="Registry - cancer"
	gen unit_value_as_published=1
	gen field_citation_value=.
	gen file_path=.
	gen smaller_site_unit=0
	gen site_memo=.
	gen representative_name ="Nationally and subnationally representative" 
	gen urbanicity_type="Unknown"
	gen standard_error=.
	gen effective_sample_size=.
	gen cases=.
	gen sample_size=.
	gen unit_type="Person"
	gen unit_type_value=1
	gen measure_issue=0
	gen measure_adjustment=0
	gen design_effect=.
	gen uncertainty_type=.
	gen recall_type="Not Set"
	gen recall_type_value=.
	gen sampling_type=.
	gen response_rate=.
	gen case_name="cancer ectomy incidence rate"
	gen case_definition=.
	gen case_diagnostics=.
	gen group=.
	gen specificity=.
	gen group_review=.	
	gen note_modeler=.	
	gen note_SR=.
	gen is_outlier=0
	gen data_sheet_filepath=.
	gen uncertainty_type_value=95
	gen location_name=.
	gen page_num=.
	gen ihme_loc_id=.
	gen table_num=.
	gen underlying_field_citation_value=.

// keep and order relevant data
	keep row_num parent_id input_type modelable_entity_id modelable_entity_name nid underlying_nid underlying_field_citation_value field_citation_value file_path page_num table_num source_type location_name location_id ihme_loc_id smaller_site_unit site_memo representative_name urbanicity_type year_start year_end year_issue sex sex_issue age_start age_end age_issue age_demographer measure mean lower upper standard_error effective_sample_size cases sample_size design_effect unit_type unit_type_value unit_value_as_published measure_issue measure_adjustment uncertainty_type uncertainty_type_value recall_type recall_type_value sampling_type response_rate case_name case_definition case_diagnostics group specificity group_review note_modeler note_SR extractor is_outlier data_sheet_filepath
	order row_num parent_id input_type modelable_entity_id modelable_entity_name nid underlying_nid underlying_field_citation_value field_citation_value file_path page_num table_num source_type location_name location_id ihme_loc_id smaller_site_unit site_memo representative_name urbanicity_type year_start year_end year_issue sex sex_issue age_start age_end age_issue age_demographer measure mean lower upper standard_error effective_sample_size cases sample_size design_effect unit_type unit_type_value unit_value_as_published measure_issue measure_adjustment uncertainty_type uncertainty_type_value recall_type recall_type_value sampling_type response_rate case_name case_definition case_diagnostics group specificity group_review note_modeler note_SR extractor is_outlier data_sheet_filepath

// save
	compress
	outsheet using "`output_folder'/`incidence_measure'_ectomy_rate_input_`local_id'.csv", comma replace	
	
** **************************************************************************
** END
** **************************************************************************
