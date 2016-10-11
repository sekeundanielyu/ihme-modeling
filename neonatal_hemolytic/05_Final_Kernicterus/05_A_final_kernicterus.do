/* **************************************************************************
NEONATAL HEMOLYTIC MODELING
PART 5: Final Kernicterus Counts
Part A: Birth prevalence of Kernicterus due to all causes (rh disease, g6pd, and other)
6.9.14

The hemolytic modeling process is described in detail in the README in the 
hemolytic code folder.  This script completes the final step of modeling 
kernicterus: taking the sum of rh disease, g6pd, and other kernicterus birth prevalences 
to get kernicterus birth prevalence for all relevant causes, and reformatting so 
the data are ready to be uploaded to the database for dismod-running.

Copied from README:
E. Final kernicterus prevalence
	
	1. We simply take the sum of the kernicterus prevalences from parts A, B, and D (NOT C)
		to get final prevalence of kernicterus due to hemolytic diseases of the newborn:

		hemo_kern_prev = rh_kern_prev + g6pd_kern_prev + other_kern_prev

	2. These values, as well as excess mortality estimates due to hemolytic diseases, 
	are used as inputs into Dismod models to calculate the prevalence of impairment due 
	to kernicterus in older age groups.  
		
******************************************************************************/

clear all
set graphics off
set more off
set maxvar 32000


/*  //////////////////////////////////////////////
		WORKING DIRECTORY
////////////////////////////////////////////// */ 

		//root dir
	if c(os) == "Windows" {
		local j "J:"
		// Load the PDF appending application
		quietly do "`j'/Usable/Tools/ADO/pdfmaker_Acrobat11.do"
	}
	if c(os) == "Unix" {
		local j "/home/j"
		ssc install estout, replace 
		ssc install metan, replace
	} 
	
// locals
local target_me_id 3962

// functions
* run "`j'/WORK/10_gbd/00_library/functions/fastpctile.ado"
* run "`j'/WORK/10_gbd/00_library/functions/get_outputs_helpers/query_table.ado"
* run "`j'/WORK/10_gbd/00_library/functions/get_location_metadata.ado"


* // directories 
* 	local working_dir = "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/02_analysis/neonatal_hemolytic"
* 	local log_dir = "`j'/temp/User/neonatal/logs/neonatal_hemolytic"
* 	local out_dir "`working_dir'/05_final_kernicterus"
* 	local upload_dir "`j'/WORK/04_epi/01_database/02_data/neonatal_hemolytic"
	
* 	//set up input directories: one for each cause (we don't use preterm, but make the local to preserve indexing)
* 	local rh_disease_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/02_analysis/neonatal_hemolytic/01_rh_disease/01_D_final_birthprev/rh_disease_kernicterus_all_draws.dta"
* 	local g6pd_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/02_analysis/neonatal_hemolytic/02_g6pd/g6pd_kernicterus_all_draws.dta"
* 	local preterm_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/02_analysis/neonatal_hemolytic/03_preterm/preterm_kernicterus_all_draws.dta"
* 	local other_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/02_analysis/neonatal_hemolytic/04_other/other_kernicterus_all_draws.dta"

* // Create timestamp for logs
*     local c_date = c(current_date)
*     local c_time = c(current_time)
*     local c_time_date = "`c_date'"+"_" +"`c_time'"
*     display "`c_time_date'"
*     local time_string = subinstr("`c_time_date'", ":", "_", .)
*     local timestamp = subinstr("`time_string'", " ", "_", .)
*     display "`timestamp'"
	
* 	//log
* 	capture log close
* 	log using "$log_dir/05_A_final_kern_prev_`timestamp'.smcl", replace
	
* /* ///////////////////////////////////////////////////////////
* // Sum everything together
* ///////////////////////////////////////////////////////////// */


* local plot = 1


* //start with rh disease
* 	di in red "importing for rh disease"
* 	use if sex!=3 using "`rh_disease_dir'", clear
* 	rename draw_* rh_disease_draw_*
	
* 	//keep only dismod yearvals
* 	keep if year==1990 | year==1995 | year==2000 | year==2005 | year==2010 | year==2015
	
* //now g6pd
* 	di in red "merging on g6pd"
* 	//merge should be perfect
* 	merge 1:1 location_id year sex using "`g6pd_dir'", keep(3) nogen
* 	rename draw_* g6pd_draw_*
	
* //now other
* 	di in red "mergin on other"
* 	//merge should be perfect
* 	merge 1:1 location_id year sex using "`other_dir'", keep (3) nogen
* 	rename draw_* other_draw_*


* //now just add 'em on up
* di in red "calculating kernicterus prevalence. for all causes"
* 			forvalues i=0/999{
* 				if mod(`i', 100)==0{
* 							di in red "working on number `i'"
* 				}
				
* 				gen draw_`i' = rh_disease_draw_`i' + g6pd_draw_`i' + other_draw_`i'
* 				drop rh_disease_draw_`i' g6pd_draw_`i' other_draw_`i'
* 			}  

		
*  ///////////////////////////////////////////////////////////
* // Save
* ///////////////////////////////////////////////////////////// 

* 	di in red "saving results"
* 	di "all draws"
* 		save "`out_dir'/final_kernicterus_all_draws.dta", replace
* 		export delimited "`out_dir'/final_kernicterus_all_draws.csv", replace
	
* 	di "summary stats"
* 		egen mean = rowmean(draw_*)
* 		fastpctile draw*, pct(2.5 97.5) names(lower upper)
* 		drop draw*
	
* 		save "`out_dir'/final_kernicterus_summary_stats.dta", replace
* 		export delimited "`out_dir'/final_kernicterus_summary_stats.csv", replace


* /* ///////////////////////////////////////////////////////////
* // Save and upload to DisMod 
* ///////////////////////////////////////////////////////////// */

* 	di in red "reformatting for database upload"
* 	gen modelable_entity_id = `target_me_id'
* 	tempfile data
* 	save `data', replace

* 	di "formatting for DisMod for `acause' `target_me_id'"
* 	query_table, table_name(modelable_entity) server(modeling-epi-db) database(epi) clear
* 	merge 1:m modelable_entity_id using `data', keep(3) nogen 
* 	save `data', replace

* 	get_location_metadata, location_set_id(9) clear
* 	merge 1:m location_id using `data', keep(3) nogen
* 	keep location_id location_name sex year mean lower upper modelable_entity_id modelable_entity_name 
* 	save `data', replace

* 	gen age_start = 0
* 	gen age_end = 0 

* 	rename year year_start
* 	gen year_end = year_start

* 	tostring sex, replace
* 	replace sex = "Male" if sex == "1"
* 	replace sex = "Female" if sex == "2"

* 	gen measure = "prevalence"
* 	gen representative_name = "Nationally and subnationally representative"
* 	gen year_issue = 0
* 	gen sex_issue = 0
* 	gen age_issue = 0
* 	gen age_demographer = 0
* 	gen unit_type = "Person"
* 	gen unit_value_as_published = 1
* 	gen measure_issue = 0
* 	gen measure_adjustment = 0
* 	gen extractor = "steeple"
* 	gen uncertainty_type = "Confidence interval"
* 	gen uncertainty_type_value = 95
* 	gen urbanicity_type = "Unknown"
* 	gen recall_type = "Not Set"
* 	gen is_outlier = 0
* 	gen standard_error = . 
* 	gen effective_sample_size = . 
* 	gen cases = . 
* 	gen sample_size = . 
* 	gen nid = 143264
* 	gen source_type = "Surveillance - other/unknown"
* 	gen row_num = . 
* 	gen parent_id = . 
* 	gen data_sheet_file_path = ""
* 	gen input_type = ""
* 	gen underlying_nid = .
* 	gen underlying_field_citation_value = ""
* 	gen field_citation_value = ""
* 	gen page_num = .
* 	gen table_num = .
* 	gen ihme_loc_id = ""
* 	gen smaller_site_unit = 0
* 	gen site_memo = ""
* 	gen design_effect = .
* 	gen recall_type_value = ""
* 	gen sampling_type = ""
* 	gen response_rate = . 
* 	gen case_name = ""
* 	gen case_definition = ""
* 	gen case_diagnostics = ""
* 	gen note_modeler = ""
* 	gen note_SR = ""
* 	gen specificity = .
* 	gen group = .
* 	gen group_review = .


* 	// save for upload
* 	export excel "`upload_dir'/`target_me_id'/04_big_data/`target_me_id'_prevalence.xlsx", firstrow(variables) sheet("extraction") replace

	// upload 
	!python ./bin/request_input_data_load.py --filepath "/home/j/WORK/04_epi/01_database/02_data/neonatal_hemolytic/`target_me_id'/04_big_data/`target_me_id'_prevalence.xlsx" --delete_group modelable_entity_id,nid

/* ///////////////////////////////////////////////////////////
// Plot
///////////////////////////////////////////////////////////// */	
	
	 * if `plot'==1{

		*  use "`out_dir'/final_kernicterus_summary_stats.dta", clear
		
		* //for ylabeling 
		* 	qui sum `varname'
		* 	local max_val = r(max)

		* 	pdfstart using "`out_dir'/time_series/final_kernicterus_time_series.pdf"
		* 	levelsof ihme_loc_id, local(ihme_loc_id_list)
				
		* 	foreach ihme_loc_id of local ihme_loc_id_list {
						
		* 		di in red "plotting for `ihme_loc_id'"
						
		* 		line mean year if ihme_loc_id == "`ihme_loc_id'", lcolor(purple) lwidth(*1.75) || line lower year if ihme_loc_id == "`ihme_loc_id'", lcolor(purple) lpattern(dash) lwidth(*1.75) || line upper year if ihme_loc_id == "`ihme_loc_id'", lcolor(purple) lpattern(dash) lwidth(*1.75) by(sex)	title("Final Kernicterus, `ihme_loc_id'") legend(order(1 2) label(1 "Kernicterus Prevalence") label(2 "95%CI")) ytitle("Prevalence") xtitle("Year") xlabel(1990(10)2015)
		* 		pdfappend
		* 		}
					
		* 	pdffinish, view
		
	 
	 * }


























