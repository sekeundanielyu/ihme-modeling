// Generate custom CSMR for Afib

// Prep stata
	clear all
	set more off
	
	adopath + "strPath/functions"
// Only use 2015 data - want to capture recent changes in coding practices in certain countries.

// Get data
	// Set locals
		get_demographics, gbd_team(cod)
		local outdir "strPath/cvd_afib/custom_deaths"
		
		local loc_ids "74 71 75 76 45 44 101 94 98 77 81 78 92 80 95 35 82 48 84 83 85 86 50 89 90 72 91 55 93 99 102" 

		local ages "11 12 13 14 15 16 17 18 19 20 21"
	
	// Get LDI for regression
		get_covariate_estimates, covariate_name_short(LDI_pc) clear
		gen log_ldi = log(mean_value)
		drop age_group_id age_group_name sex_id *_value
		tempfile ldi
		save `ldi', replace 
		save "`outdir'_ldi.dta", replace
	
	// Get draws for csmr and prevalence for selected countries for 2015
		get_draws, gbd_id_field(modelable_entity_id) gbd_id(9366) measure_ids(5) location_ids(`loc_ids') status(best) sex_ids(1 2) year_ids(2015) age_group_ids(`ages') source(dismod) clear
		forvalues i=0/999 {
			rename draw_`i' prev_`i'
		}
		tempfile prev
		save `prev', replace
		//save "`outdir'_prev.dta", replace
	
		get_draws, gbd_id_field(cause_id) gbd_id(500) location_ids(`loc_ids') year_ids(2015) sex_ids(1 2) status(best) source(codem) clear
		forvalues i=0/999 {
			generate csmr_`i' = draw_`i'/pop
		}
		drop draw_*
		//save "`outdir'_csmr.dta", replace
		
	// Merge 
		merge 1:1 location_id year_id age_group_id sex_id using `prev', keep(3) nogen
		merge m:1 location_id year_id using `ldi', keep(3) nogen

	// Keep the variables that we're interested in 
		keep location_name location_id year_id age_group_id sex_id pop csmr* prev* log_ldi
	
	// Calculate EMR and lnEMR
		forvalues X=0/999 {
			gen EMR_`X'=(csmr_`X'/prev_`X')
			gen logEMR_`X'=log(csmr_`X'/prev_`X')
		}
		fastrowmean EMR_*, mean_var_name(mean_EMR)
		fastpctile EMR_*, pct(2.5 97.5) names(lower_EMR upper_EMR)
		drop EMR* csmr* prev_*
		save "`outdir'_emr_all.dta", replace
		
// Save non-ln versions for countries where we have data
	preserve
		keep location_id year_id sex_id age_group_id mean_EMR upper_EMR lower_EMR
		gen reg_loc = 1
		gen emr_parent = location_id
		tempfile emrdata
		save `emrdata', replace
	restore
	
	fastrowmean logEMR_*, mean_var_name(mean_logEMR)
	tempfile regression
	save `regression', replace
	
// Run the model
	cap log close
	log using "strPath/custom_deaths_50111.log", replace
	mixed mean_logEMR i.sex_id i.age_group_id log_ldi || location_id:
	mixed mean_logEMR i.sex_id i.age_group_id || location_id:
	log close

	//predict out
	//generate mean EMR
	predict log_mean_EMR, xb
	//generate se
	predict log_se_EMR, stdp

//clean up dataset
	keep sex* age_group_id log_mean_EMR log_se_EMR
	duplicates drop

	
// Convert from logspace and generate a 1000 draws of beta
	forvalues i = 0/999 {
		gen draw_`i' = exp(rnormal(log_mean_EMR, log_se_EMR))
	}
	fastrowmean draw_*, mean_var_name(emean_EMR)
	fastpctile draw_*, pct(2.5 97.5) names(elower_EMR eupper_EMR)
	drop draw*

// Expand to all countries in the EPI database
	preserve
		get_location_metadata, location_set_id(9) clear
		keep if is_estimate ==1
		keep location_id location_name level parent_id
		keep if level >= 3 //keep national and subnational
		tempfile locs
		save `locs'
		save `outdir'_locs, replace
	restore
	
// Assign values to each country
	cross using `locs'

// Add in the regression countries
	merge 1:1 location_id age_group_id sex_id using `emrdata', assert(1 3) nogen

// Standardize column names
	gen mean = cond(mean_EMR == ., emean_EMR, mean_EMR)
	gen lower = cond(lower_EMR == ., elower_EMR, lower_EMR)
	gen upper = cond(upper_EMR == . , eupper_EMR, upper_EMR)
	drop *EMR*
	tempfile hold
	save `hold', replace
	
// Add in parent data for the subnational units
	drop emr_parent
	gen emr_parent = parent_id
	merge m:1 emr_parent age_group_id sex_id using `emrdata', keep(1 3)
	
	replace mean = mean_EMR if _merge==3
	replace lower = lower_EMR if _merge==3
	replace upper = upper_EMR if _merge==3
	drop *EMR* _merge parent_id emr_parent year_id 

	save "`outdir'/emr_50111.dta", replace
	
	drop reg_loc

// Organize data for upload		
	// Standardize year, age and sex
		gen year_start = 1990
		gen year_end = 2015
		gen age_start = 30 if age_group_id==11
		replace age_start = 35 if age_group_id==12
		replace age_start = 40 if age_group_id==13
		replace age_start = 45 if age_group_id==14
		replace age_start = 50 if age_group_id==15
		replace age_start = 55 if age_group_id==16
		replace age_start = 60 if age_group_id==17
		replace age_start = 65 if age_group_id==18
		replace age_start = 70 if age_group_id==19
		replace age_start = 75 if age_group_id==20
		replace age_start = 80 if age_group_id==21
		gen age_end = age_start+4
		replace age_end = 99 if age_start==80
		
		gen sex = cond(sex_id==1, "Male", "Female")

// Populate sheets for the uploader. Most of the below is gobbldy gook
		gen parent_id = .
	
		gen nid = 236209
		gen underlying_nid = ""
		gen modelable_entity_id = 9366
		gen modelable_entity_name = "Atrial Fibrillation with EMR"
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
		gen sampling_type = ""
		gen note_modeler = "Custom EMR generated from DisMod prevalence model and CODEm CSMR"
		gen note_SR = ""
		gen extractor = "strUser"
		gen age_issue=0
		gen sex_issue=0
		gen measure_issue=0
		gen year_issue=0
		gen row_num=""

		save "`outdir'/emr_9366_50111.dta", replace

		export excel using "strPath/afib_emr_50111.xlsx", replace sheet("extraction") firstrow(variables)
		
// Merge in row nums

preserve
	//get the database connection set up
	quiet run "strPath/functions/create_connection_string.ado"
	create_connection_string, server(strSever) database(strDatabase) user(strUser) password(strPassword)
	local conn_string = r(conn_string)
	
	#delimit ;
	odbc load, exec("select row_num, location_id, sex_id, year_start, year_end, age_start, age_end, measure_id, input_data.last_updated_action, modelable_entity_id, modelable_entity_name
				from
					epi.input_data
				join
					epi.modelable_entity using (modelable_entity_id)
				where
					modelable_entity_id in (9366)
				and
					input_data.last_updated_action <> 'DELETE'
				and
					measure_id = 9;") `conn_string' clear ;
	#delimit cr
	
	tempfile row_nums
	save `row_nums'
	
restore
	destring row_num, replace
	merge 1:1 location_id sex_id age_start age_end using `row_nums', keepusing(row_num) nogen update keep(3 4)
	drop age_group_id sex_id
	export excel using "strPath/afib_emr_row_num.xlsx", replace firstrow(var) sheet("extraction")
	