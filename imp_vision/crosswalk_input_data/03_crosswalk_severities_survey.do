

//Purpose: Apply crosswalk map for vision measures spanning multiple GBD severities 

local vision_dir "J:\WORK\04_epi\01_database\02_data\imp_vision" 
local proportions_map "`vision_dir'/02_nonlit/proportions_map_split_merged_severity_groups.dta"
	
******************************************************************************
// START CROSSWALKING
** Here I am going to split out all different types of groupings to our mild, moderate, severe, and blind categories
** for example, split mild/mod into mild and mod separately.  First, find the proportion then regression that proportion against age (regress mild_prop age).  use this coefficient to estimate proportion for each data point and then split prevalence by that.  Include a standard error for that prediction.
** carry forward uncertainty with the equation var(XY)=E(X2Y2)-E(XY)2=var(X)var(Y)+var(X)E(Y)^2+var(Y)E(X)^2
******************************************************************************


***Some SAGE countries didn't measure <6/60, so I used <6/18 as threshold for mod-plus 

	***************************************	
	// apply the proportions to split up groups as needed
	***************************************
use "J:\WORK\04_epi\01_database\02_data\imp_vision\02_nonlit\survey_tabulations_pre_crosswalk/SAGE_pres_mod_plus", clear 

merge m:1 age_start using `proportions_map', nogen keep(3)


//Expand, so that we will estimate moderate severe and blind 
	gen modelable_entity_id = . 
	expand(2), gen(exp)
		replace modelable_entity_id = 2566 if exp == 0
		replace modelable_entity_id = 2567 if exp == 1
	expand(2) if exp == 1, gen(exp1)
		replace modelable_entity_id = 2426 if exp1 == 1

//want to save combined data to database for completeness 
	
	gen group = 1 
	gen specificity = "mod plus"
	gen group_review = 0
	gen note_modeler = "parent - combined severities split via crosswalk"
	
	foreach meid in 2426 2566 2567 {
		preserve	
			keep if modelable_entity_id == `meid'
			tempfile raw_`meid'
			save `raw_`meid'', replace 
		restore 
		}

	drop group specificity group_review note_modeler

		//Mod Sev Blind 
		local group dmod_dsev_dvb
		local mean d_`group'
		local se d_se_`group'
		
		rename mean `mean'
		rename standard_error `se'

	tempfile raw 
	save `raw', replace


		local i 0 
		foreach cat in mod sev vb {
			use `raw', clear 
				if "`cat'" == "mod" keep if modelable_entity_id == 2566
				if "`cat'" == "sev" keep if modelable_entity_id == 2567
				if "`cat'" == "vb" keep if modelable_entity_id == 2426

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


//For each meid, merge back to metadata 
		preserve 
    		import excel "J:\WORK\04_epi\01_database\02_data\imp_vision\02_nonlit\surveys_from_struser_02092016/vision_survey_codebook.xlsx", firstrow sheet(metadata) clear
    		keep if series == "SAGE" & modelable_entity_id != 2424
    		drop series 
    		tempfile metadata
    		save `metadata', replace 
    	restore

* local meid 2426
foreach meid in 2426 2566 2567 {
	preserve	
		keep if modelable_entity_id == `meid'
		append using `raw_`meid''
		drop d_* *_p_d_* exp* var

		tostring sex, replace
			replace sex = "Male" if sex == "1"
			replace sex = "Female" if sex == "2"
		replace lower = . 
		replace upper = . 

		sort location_name sex age_start note_modeler
		merge m:1 location_name modelable_entity_id using `metadata', force nogen keep(3)
		cap mkdir "`vision_dir'/`meid'/04_big_data" 
		export excel "`vision_dir'/`meid'/04_big_data/SAGE_`meid'.xlsx", firstrow(var) sheet("extraction") replace 
	restore 
	}








//Sev_blind crosswalk 

use "J:\WORK\04_epi\01_database\02_data\imp_vision\02_nonlit\survey_tabulations_pre_crosswalk/NHANES_sev_blind", clear

merge m:1 age_start using `proportions_map', nogen keep(3)

//Expand, so that we will estimate moderate severe and blind 
	gen modelable_entity_id = . 
	expand(2), gen(exp)
		replace modelable_entity_id = 2567 if exp == 0
		replace modelable_entity_id = 2426 if exp == 1
	

//want to save combined data to database for completeness 
	
	gen group = 1 
	gen specificity = "sev + blind"
	gen group_review = 0
	gen note_modeler = "parent - combined severities split via crosswalk"
	
	foreach meid in 2426 2567 {
		preserve	
			keep if modelable_entity_id == `meid'
			tempfile raw_`meid'
			save `raw_`meid'', replace 
		restore 
		}

	drop group specificity group_review note_modeler

		//Sev Blind 
		local group dsev_dvb
		local mean d_`group'
		local se d_se_`group'
		
		rename mean `mean'
		rename standard_error `se'

	tempfile raw 
	save `raw', replace


		local i 0 
		foreach cat in sev vb {
			use `raw', clear 
				
				if "`cat'" == "sev" keep if modelable_entity_id == 2567
				if "`cat'" == "vb" keep if modelable_entity_id == 2426

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


//For each meid, merge back to metadata 
		preserve 
    		import excel "J:\WORK\04_epi\01_database\02_data\imp_vision\02_nonlit\surveys_from_struser_02092016/vision_survey_codebook.xlsx", firstrow sheet(metadata) clear
    		keep if series == "NHANES" & modelable_entity_id != 2424
    		drop series 
    		tempfile metadata
    		save `metadata', replace 
    	restore

* local meid 2426
foreach meid in 2426 2567 {
	preserve	
		keep if modelable_entity_id == `meid'
		append using `raw_`meid''

		gen cv_best_corrected = . 
			replace cv_best_corrected = 0 if var == "pres_sev_blind" 
			replace cv_best_corrected = 1 if var == "bc_sev_blind" 

		drop d_* *_p_d_* exp* var

		tostring sex, replace
			replace sex = "Male" if sex == "1"
			replace sex = "Female" if sex == "2"
		replace lower = . 
		replace upper = . 

		sort location_name sex age_start note_modeler
		merge m:1 location_name year_start modelable_entity_id using `metadata', force nogen keep(3)
		cap mkdir "`vision_dir'/`meid'/04_big_data" 
		export excel "`vision_dir'/`meid'/04_big_data/NHANES_`meid'.xlsx", firstrow(var) sheet("extraction") replace 
	restore 
	}









