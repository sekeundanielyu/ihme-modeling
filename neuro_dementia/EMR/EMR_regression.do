//Find EMR for countries with decent reporting and estimate EMR for the rest

//Prep stata
	clear all
	set more off
	if c(os) == "Unix" {
		local j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		local j "J:"
	}
	adopath + "`j'/WORK/10_gbd/00_library/functions"
	
//Set locals
	local reg_locs "`j'/temp/strUser/neuro/reg_locs_4-4.xlsx"
	local version 7
	//local basecase young //old
	local output_csv "`j'/WORK/03_cod/02_models/02_results/neuro_dementia/dementia_regression_results_`version'.csv"
	local output_dta "`j'/WORK/03_cod/02_models/02_results/neuro_dementia/dementia_regression_results_`version'.dta"
	local draws_out "`j'/WORK/03_cod/02_models/02_results/neuro_dementia/dementia_regression_draws_`version'.dta"
	local output_excel "`j'/WORK/04_epi/01_database/02_data/neuro_dementia/1943/01_input_data/01_nonlit/estimated_mtexcess/reg_results_`version'.xlsx"
	
	//things for get draws
	local ages 13 14 15 16 17 18 19 20 21
	local sexes 1 2
	local meid 1943
	local cid 543
	local prev_id 48560
	//local csmr_id

//get prevalence and csmr draws
	//start by grabbing the locations
	import excel using "`reg_locs'", firstrow clear
	keep location_id
	levelsof location_id, local(thelocs)
	
	//get draws of prev
	get_draws, gbd_id_field(modelable_entity_id) measure_ids(5) source(dismod) age_group_ids(`ages') sex_ids(`sexes')  gbd_id(`meid') location_ids(`thelocs') year_ids(2015) status(best) clear
	keep location_id year_id sex_id age_group_id draw_*
	forvalues X=0/999 {
		ren draw_`X' prev_`X'
	}
	drop if location_id ==.
	tempfile prev
	save `prev'

	//get csmr-- the draws start as deaths
	//get_draws, gbd_id_field(cause_id) age_group_ids(`ages') source(codem) gbd_id(`cid') location_ids(`thelocs') year_ids(2015) status(latest) clear
	
	clear
	append using "`j'/temp/strUser/neuro/62108a.dta" "`j'/temp/strUser/neuro/62105a.dta"
	
	gen keeper = 0
	keep if year_id == 2015
	foreach lll of local thelocs{
		replace keeper = 1 if location_id == `lll'
	}
	keep if keeper ==1
	
	
	forvalues X=0/999 {
		ren draw_`X' deaths_`X'
	}
	drop if location_id ==.
	tempfile csmr
	save `csmr'
	
	
//merge and adjust age categories
	merge 1:1 location_id year_id age_group_id sex_id using `prev', assert(3)
	save `draws_out', replace
	
//get covariates
	preserve
		get_covariate_estimates, covariate_name_short(ldi_pc) clear
		keep location_id mean_value year_id
		keep if year_id == 2015
		gen ldi = mean_value
		tempfile ldi
		save `ldi', replace
		
		get_covariate_estimates, covariate_name_short(education_yrs_pc) clear
		keep if year_id ==2015
		gen educ = mean_value
		keep location_id age_group_id educ sex_id
		tempfile educ
		save `educ', replace
	restore
	
	merge m:1 location_id using `ldi', assert(2 3) keep(3) nogen
	merge m:1 location_id age_group_id sex_id using `educ', assert(2 3) keep(3) nogen
	
	//convert covs to amounts
	replace ldi = ldi *pop
	replace educ = educ*pop
	
	
	
	//drop the existing base category
	drop if age_group_id ==.
	gen new_age = age_group_id
	
//collapse age_group_id 13, 14, 15, 16 (40-59) to a new base category
	replace new_age = 1 if age_group_id <=16
	
	//convert prevelence to cases
	forvalues i = 0/999 {
		replace prev_`i' = prev_`i' * pop
		
	}
	
	keep location_id year_id new_age sex_id pop deaths* prev* ldi educ
	
	//Collapse the bottom age_groups
	count
	collapse (sum) pop deaths* prev* ldi educ, by(location_id year_id new_age sex_id)
	count
	
	gen log_ldi = log(ldi/pop)
	gen educ_pc = educ/pop
	
	//convert back to csmr and prev
		forvalues i = 0/999 {
		gen csmr_`i' = deaths_`i' / pop
		drop deaths_`i'
		replace prev_`i' = prev_`i' / pop
		
	}

	
//calculate logemr
	forvalues X=0/999 {
		gen EMR_`X'=(csmr_`X'/prev_`X')
		gen logEMR_`X'=log(csmr_`X'/prev_`X')
	}
	egen mean_EMR = rowmean(EMR_*)
	egen upper_EMR = rowpctile(EMR_*), p(97.5)
	egen lower_EMR = rowpctile(EMR_*), p(2.5)
	drop EMR*
	preserve
		keep location_id year_id sex_id new_age mean_EMR upper_EMR lower_EMR
		gen reg_loc = 1
		gen emr_parent = location_id
		tempfile emrdata
		save `emrdata', replace
	restore
	
	egen meanlogEMR=rmean(logEMR_*)

	
//Run the model
	cap log close
	log using "`j'/WORK/03_cod/02_models/02_results/neuro_dementia/log_`version'.log", replace

	mixed meanlogEMR i.sex_id i.new_age log_ldi || location_id:
	mixed meanlogEMR i.sex_id i.new_age educ_pc || location_id:
	mixed meanlogEMR i.sex_id i.new_age || location_id:
	log close

//predict out
	//generate mean EMR
	predict log_mean_EMR, xb
	//generate se
	predict log_se_EMR, stdp

//clean up dataset
	keep sex* new_age log_mean_EMR log_se_EMR
	duplicates drop

//convert from logspace
	//generate a 1000 draws of beta
	forvalues i = 0/999 {
		gen draw_`i' = exp(rnormal(log_mean_EMR, log_se_EMR))
	}
	egen emean_EMR = rowmean(draw*)
	egen eupper_EMR = rowpctile(draw*), p(97.5)
	egen elower_EMR = rowpctile(draw*), p(2.5)
	drop draw*

//expand to all countries in the EPI database
	preserve
		get_location_metadata, location_set_id(9) clear
		keep if is_estimate ==1
		keep location_id location_name level parent_id
		keep if level >= 3 //keep national and subnational
		tempfile locs
		save `locs'
	restore
	
	//assign values to each country
	cross using `locs'
//Add in the regression countries
	merge 1:1 location_id new_age sex_id using `emrdata', assert(1 3) nogen
	
//standardize column names
	gen mean = cond(mean_EMR == ., emean_EMR, mean_EMR)
	gen lower = cond(lower_EMR == ., elower_EMR, lower_EMR)
	gen upper = cond(upper_EMR == . , eupper_EMR, upper_EMR)
	drop *EMR*
	tempfile hold
	save `hold', replace
	use `hold', clear
	
// add in parent data for the subnational units
	drop emr_parent
	gen emr_parent = parent_id
	merge m:1 emr_parent new_age sex_id using `emrdata', keep(1 3)
	
	replace mean = mean_EMR if _merge==3
	replace lower = lower_EMR if _merge==3
	replace upper = upper_EMR if _merge==3
	drop *EMR* _merge parent_id emr_parent
	
//standardize year, age and sex
	gen year_start = 1990
	gen year_end = 2015
	gen age_start = cond(new_age==1, 40,(new_age-5)*5)
	gen age_end = cond(new_age==1, 59, age_start+4)
	replace age_end = 100 if age_end == 84
	
	gen sex = cond(sex_id==1, "Male", "Female")

//populate sheets for the uploader. Most of the below is gobbldy gook
	gen parent_id = .
	
	gen nid = 236209
	gen underlying_nid = nid
	gen modelable_entity_id = 1943 //Alzheimer disease and other dementias
	gen modelable_entity_name = "Alzheimer disease and other dementias"
	gen source_type = "Mixed or estimation"
	gen measure = "mtexcess"
	gen standard_error = . //should be back calculated
	
	gen unit_type = "Person*year"
	gen unit_type_value = 2
	gen unit_value_as_published = 1
	
	gen input_type =""
	gen effective_sample_size = .
	gen sample_size = .
	gen cases =.
	gen design_effect =.
	gen is_outlier =0
	gen site_memo = .
	gen case_name = ""
	gen case_definition = ""
	gen case_diagnostics = ""
	gen response_rate = .
	
	gen uncertainty_type_value = 95
	gen uncertainty_type = .
	gen representative_name = "Nationally and subnationally representative"
	gen urbanicity_type = "Unknown"
	gen recall_type = "Point"
	gen recall_type_value = 1
	gen sampling_type = "Simple random"
	
	gen note_modeler = "Data prepared by running a dismod model, extracting csmr and prev, calculating EMR. This is the result"
	gen note_SR = "some of the data columns are meaningless (e.g. sample_type does not really = Simple random since they are esimates"
	gen extractor = "strUser"

	
	export excel using "`output_excel'", replace firstrow(var) sheet("extraction")
	di "`output_excel'"

//export data
	save `output_dta', replace
	//export delim `output_csv', replace


	