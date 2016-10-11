

//Purpose: Apply crosswalk map for vision measures spanning multiple GBD severities 
	
local proportions_map "`out_dir'/proportions_map_split_merged_severity_groups.dta"
local vision_dir "J:\WORK\04_epi\01_database\02_data\imp_vision" 
	
******************************************************************************
// START CROSSWALKING
** Here I am going to split out all different types of groupings to our mild, moderate, severe, and blind categories
** for example, split mild/mod into mild and mod separately.  First, find the proportion then regression that proportion against age (regress mild_prop age).  use this coefficient to estimate proportion for each data point and then split prevalence by that.  Include a standard error for that prediction.
** carry forward uncertainty with the equation var(XY)=E(X2Y2)-E(XY)2=var(X)var(Y)+var(X)E(Y)^2+var(Y)E(X)^2
******************************************************************************


	***************************************	
	// apply the proportions to split up groups as needed
	***************************************
import excel "J:\WORK\04_epi\01_database\02_data\imp_vision\00_documentation\2015_data_with_incorrect_severities_need_xwalk.xlsx", firstrow clear 

	replace is_outlier = 0 

			duplicates drop modelable_entity_id row_num, force 

		//Turn all uncertainty into standard error 
			//From sample size: (variance = pq/n)
			replace standard_error = sqrt(mean*(1-mean)/sample_size) if standard_error == . 
			//if no standard_error or sample_size, do from confidence intervals
			replace standard_error = (upper - mean)/1.96 if standard_error == . 

			replace uncertainty_type_value = .
			replace measure_issue = 0
			replace year_issue = 0
			replace lower = . 
			replace upper = . 
			replace cases = . 
			replace uncertainty_type = "Standard error"

merge m:1 age_start using `proportions_map', nogen keep(3)


//Expand, so that we will estimate both severe and blind 
	expand(2), gen(exp)
		replace modelable_entity_id = 2567 if exp == 0
		replace modelable_entity_name = "Severe vision impairment envelope" if exp == 0
		replace modelable_entity_id = 2426 if exp == 1
		replace modelable_entity_name = "Blindness impairment envelope" if exp == 1

//want to save combined data to database for completeness 
	
	replace group = 1 
	replace specificity = "severe + blind"
	replace group_review = 0
	replace note_modeler = "parent - combined severities split via crosswalk"
	
	foreach meid in 2426 2567 {
		preserve	
			keep if modelable_entity_id == `meid'
			tempfile raw_`meid'
			save `raw_`meid'', replace 
		restore 
		}

	drop group specificity group_review note_modeler

//2015 lit extractions needing crosswalks are only in the sev_blind categories.
	rename mean d_dsev_dvb
	rename standard_error d_se_dsev_dvb

		local group dsev_dvb
		local mean d_`group'
		local se d_se_`group'
		
	tempfile raw 
	save `raw', replace


		local i 0 
		foreach cat in sev vb {
			use `raw', clear 
				if "`cat'" == "sev" keep if modelable_entity_name == "Severe vision impairment envelope"
				if "`cat'" == "vb" keep if modelable_entity_name == "Blindness impairment envelope"

			// crosswalk variables
				local crosswalk `cat'_p_d_`group'
				local crosswalk_se `cat'_p_d_`group'_se
			
			// adjust estimate
				gen mean= `mean'*`crosswalk'
			
			// adjust se
				gen standard_error = sqrt(((`mean')^2 * (`crosswalk_se')^2)  + ((`se')^2 * (`crosswalk'^2)) + ((`se')^2 * (`crosswalk_se'^2))) 
		

			if `i' == 0 tempfile expanded 
			else append using `expanded'
			save `expanded', replace 

			local ++ i 
			}

gen group = 2
gen group_review = 1 
gen specificity = "severity"
gen note_modeler = "Split from combined severities via crosswalk"


foreach meid in 2426 2567 {
	preserve	
		keep if modelable_entity_id == `meid'
		append using `raw_`meid''
		drop d_* *_p_d_* exp cv_sev_blind
		export excel "`vision_dir'/`meid'/03_review/03_upload/lit_2015_data_crosswalked.xlsx", firstrow(var) sheet("extraction") replace 
	restore 
	}





