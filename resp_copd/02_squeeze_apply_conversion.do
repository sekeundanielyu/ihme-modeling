//Squeeze US 2005 dismod gold class results to 1. Convert to severity splits. Save files to split the rest of the data

//set stata settings
	clear
	set more off
	set maxvar 32767
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		local prefix "/home/j"
		set odbcmgr unixodbc
		local ver 1
	}
	else if c(os) == "Windows" {
		local prefix "J:"
		local ver 0
	}
	qui adopath + `prefix'/WORK/10_gbd/00_library/functions/
	
	//pass arguments
	args folder_name loc_id output asympt mild moderate severe
	di in red "`folder_name' `loc_id' `output'"
	di in red "`asympt' `mild' `moderate' `severe'"

//set locals
	local types asympt mild moderate severe
	local testing 0
	local g1 3062 //mild: gold class 1
	local g2 3063 //moderate: gold class 2
	local g3 3064 //severe: gold class 3-4
	local copd 1872
	local gc `g1' `g2' `g3'
	local years 1990 1995 2000 2005 2010 2015
	
//locals for files
	local sev_split "/share/scratch/users/strUser/copd/severity_conversions_both.dta"

//load the gold class values for run
	//get draws defaults to best model
	timer on 1
	if c(os) == "Unix" {
		clear
		tempfile draws
		save `draws', emptyok replace
		//prevalence is measure_id 5-- we use proportion though
		foreach ggg of local gc{
			//foreach year of local years{ is commented out pending more testing
			//	di "`year'"
				get_draws, gbd_id_field(modelable_entity_id) gbd_id(`ggg') location_ids(`loc_id') measure_ids(18) year_ids(`years') sex_ids(1 2) source(epi) clear
				
				count
				if `r(N)' ==0 {
					di in red "get draws failed."
					ERROR FIX ME PLEASE
				}
				append using `draws'
				save `draws', replace
			//} //close year
		} //close gold class
	} //close unix

	timer off 1
	timer list 1
	di "*****"
//Scale the draws to 1
	forvalues i = 0(1)999{
		qui {
		di "scaling draw `i'"
		bysort location_id sex_id year_id age_group_id measure_id: egen total_draw = total(draw_`i')
		replace draw_`i' = draw_`i' / total_draw
		drop total_draw
		} //end qui
	}
	drop model_version_id
	
	rename draw_* draw_*_
	di "reshape squeezed values"
	qui reshape wide draw_*_, i(sex_id year_id age_group_id measure_id location_id) j(modelable_entity_id)
	
	//for some reason, age_group_ids >= 27 are sneaking in. Drop them
	drop if age_group_id > 21 
	
//now that we have draws scaled to 1, bring in the MEPS results
	merge m:1 age_group_id sex_id using `sev_split', assert(3)
	
//convert from gold to meps/severity
	forvalues j = 0(1)999 {
		qui di "Converting Draw `j'"
		
		gen draw_`j'_`severe' = draw_`j'_`g3' * x_sev`j'
		gen draw_`j'_`asympt' = draw_`j'_`g1' * x_asymp`j'
		gen draw_`j'_`mild' = (1-(draw_`j'_`severe'+draw_`j'_`asympt')) * x_mild`j'
		gen draw_`j'_`moderate' = (1-(draw_`j'_`severe'+draw_`j'_`asympt')) * x_mod`j'
		
		//clean up dataspace
		drop draw_`j'_`g1' draw_`j'_`g2' draw_`j'_`g3' x_sev`j' x_asymp`j' x_mild`j' x_mod`j'
		
	}

	//drop measure id to prevent conflicts
	drop measure_id
	
//get COPD prev
	preserve
		get_draws, gbd_id_field(modelable_entity_id) gbd_id(`copd') location_ids(`loc_id') status(best) measure_ids(5 6) sex_ids(1 2) source(epi) clear //get prevalence and incidence
		rename draw_* draw_*_epi
		tempfile prev_draws
		save `prev_draws', replace
	restore
	
	
	
	merge 1:m sex_id age_group_id location_id year_id using `prev_draws', assert(2 3) nogen keep(3)
	
//calculate severity splits
	forvalues j = 0/999 {
		qui {
		replace draw_`j'_`severe' = draw_`j'_`severe' *draw_`j'_epi
		replace draw_`j'_`asympt' = draw_`j'_`asympt' *draw_`j'_epi
		replace draw_`j'_`mild' = draw_`j'_`mild'*draw_`j'_epi
		replace draw_`j'_`moderate' = draw_`j'_`moderate' *draw_`j'_epi
		//drop draw_`j' 
		}
	}

//format for upload
	//drop draw_*_prev
// save into me_id_sex_year_country specific files
	local measures prevalence incidence
	foreach year of local years{
		foreach sex in 1 2 {
		foreach measure of local measures{
				foreach type of local types{
					preserve
						if "`measure'" == "prevalence"{
							local mmm 5
						}
						else {
							local mmm 6
						}
						
						//tab sex_id
						//tab year_id
						//tab measure_id
						
						di "`sex' `year' `mmm'"
						keep if sex_id == `sex' & year_id ==`year' & measure_id == `mmm'
						
						count
						di in red "`r(N)'"
						
						local sex_name = cond(`sex'==1, "male", "female")
						di in red "Saving `type' ``type'' `loc_id' `year' `sex' `sex_name'"
						keep location_id year_id sex_id age_group_id measure_id draw_*_``type''
						rename draw_*_``type'' draw_*
						export delim "`output'`folder_name'/``type''/`measure'_`loc_id'_`year'_`sex'.csv", replace
					restore	
				} //close types
			} //close measure
		} //close sex
	} //close year

	
	
	
	
	
	
	