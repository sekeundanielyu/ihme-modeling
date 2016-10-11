//About: takes the results from 02, applies an estimate of the fraction of cases that are severe and preps everything for the epi uploader
	clear all
	set more off
	set maxvar 32767
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

//Set Locals
	local version v53
	local base_dir "`j'/WORK/04_epi/02_models/02_results/malaria/custom"
	local clust_folder /share/scratch/users/strUser/malaria/
	local base_file `base_dir'/`version'/malaria_nonfatal_incidence.dta
	local code_folder /ihme/code/general/strUser/malaria/nonfatal
	local ratios `j'/WORK/04_epi/02_models/02_results/malaria/custom/longterm_ratio.dta
	local emr "J:\WORK\04_epi\01_database\02_data\malaria\1446\8653_mtexcess.dta"
//get various requited parameters
	quiet run "`j'/WORK/10_gbd/00_library/functions/create_connection_string.ado"
	create_connection_string
	local conn_string = r(conn_string)
	#delimit ;
	odbc load, exec("SELECT age_group_id, age_group_years_start, age_group_years_end
	FROM
		shared.age_group
	WHERE
		age_group_id>1 & age_group_id <22 ") `conn_string' clear ;
	#delimit cr
	
	tempfile ages
	save `ages', replace
	
	get_location_metadata,location_set_id(9) clear
	tempfile locs
	save `locs', replace
	
	
//Load ratios
	use `ratios', clear
	gen id = 1
	tempfile rat
	save `rat', replace
	
//Load incidence
	use `base_file', clear
	
	//add ages
	merge m:1 age_group_id using `ages', assert(2 3) keep(3) nogen
	rename age_group_years_start age_start
	rename age_group_years_end age_end
	
	keep location_id age_start age_end year_id sex_id ihme_loc_id draw* age_group_id
	
	levelsof location_id, local(thelocs)
	levelsof year_id, local(theyears)
	//get the populations
	preserve
		get_populations, location_id(`thelocs') year_id(`theyears') sex_id(1 2) age_group_id(2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21) clear
		tempfile pops
		save `pops', replace
	restore	
	
	merge 1:1 location_id year_id sex_id age_group_id using `pops', assert(3) nogen
	
	//convert small age groups to 0 to 1
	foreach draw of varlist draw* {
		replace `draw' = `draw' * pop_scaled
	}
	
	replace age_start =0 if age_end <1
	replace age_end = 1 if age_start ==0
	
	fastcollapse pop_scaled draw*, by(location_id age_start age_end year_id sex_id ihme_loc_id) type(sum)
	
	//convert back to incidence rate
	foreach draw of varlist draw* {
		replace `draw' = `draw' / pop_scaled
	}
	
	
	
	gen id =1
	merge m:1 id using `rat', assert(3) nogen 

//Convert to long term incidence
	forvalues i=0/999{
		replace draw_`i' = draw_`i' * ratio_`i'
		drop ratio_`i'
	}
	
//Keep only under 20 years old
	keep if age_end <= 20
	
	//mean, upper and lower
	fastrowmean draw_*, mean_var_name(mean)
	fastpctile draw*, pct(2.5 97.5) names(lower upper)
	
	
	drop draw_*
		
	
//make nice for the epi format
	gen age_issue = 0 
	gen age_demographer = 0
	
	//years
	rename year_id year_start
	gen year_end = year_start
	gen year_issue = 0
	
	//sexes
	gen sex = cond(sex_id ==1 , "Male", "Female")
	gen sex_issue = 0
	
	//measure
	gen measure = "incidence"
	gen measure_issue = 0
	gen measure_adjustment = 0
	
	//location
	merge m:1 location_id using `locs', assert(2 3) keep(3) nogen keepusing(ihme_loc_id location_name)
	gen location_issue = 0
	//sourcing
	gen nid = 150244 //this is wrong but a decent placeholder until I get a newone
	gen source_type = "Mixed or estimation"
	gen underlying_nid = ""
	gen uncertainty_type=""
	gen input_type = ""
	
	//model able entity
	gen modelable_entity_id = 1446
	gen modelable_entity_name = "Moderate to severe impairment due to malaria"
	
	//site info
	gen site_memo = ""
	
	
	//Other related tidbits
	gen standard_error = .
	gen effective_sample_size =.
	gen sample_size = .
	gen cases =.
	gen design_effect = .
	gen unit_type = "Person"
	gen unit_value_as_published = 1
	gen uncertainty_type_value =95
	
	//representativeness
	gen representative_name = "Nationally representative only"
	gen urbanicity_type = "Mixed/both"
	
	//recall
	gen recall_type = "Not Set"
	gen recall_type_value = .
	
	//sampling
	gen sampling_type = .
	gen response_rate = .
	
	//case data
	gen case_name = "Clinical Malaria from main malaria model"
	gen case_definition = ""
	gen case_diagnostics = ""
	
	//notes
	gen note_modeler = "`version'"
	
	
	//extraction
	gen extractor = "strUser"
	gen is_outlier = 0
	
	//group review nonsense
	gen group = ""
	gen group_review = ""
	gen specificity = ""
	
	gen row_num =.
	gen parent_id = .
	
	//append the emr data
	append using `emr', force
	
	//sort out files and stuff
	replace nid = 150244
	replace modelable_entity_id = 1446
	replace modelable_entity_name = "Moderate to severe impairment due to malaria, all countries"
	
	drop note_SR
	gen note_SR = "EMR, not SMR 2"
	
	
	cap mkdir `j'/WORK\04_epi\01_database\02_data\malaria\1446\04_big_data
	export excel using "`j'/WORK\04_epi\01_database\02_data\malaria\1446\04_big_data/long_term_malaria_from_model_`version'.xlsx", replace first(var) sheet("extraction")
