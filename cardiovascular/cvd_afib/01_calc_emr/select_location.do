clear all
set more off


	adopath + "strPath/functions"
	run "strPath/pdfmaker_Acrobat11.do"
	
// locals
	local age_group_id = "11 12 13 14 15 16 17 18 19 20 21"
	
// get estimates of csmr and prev for 2015
	get_location_metadata, location_set_id(35) clear
	keep location_id ihme_loc_id location_name is_estimate level
	tempfile locs
	save `locs', replace
	
// get prevalence 
	get_estimates, gbd_team(epi) model_version_id(50111) measure_ids(5) year_ids(2015) sex_ids(1 2) age_group_ids(`age_group_id') clear
	tempfile prev
	save `prev', replace
	//get_estimates, gbd_team(epi) model_version_id(49940) measure_ids(5) year_ids(2015) sex_ids(1 2) age_group_ids(27) clear
	//tempfile check
	//save `check', replace


// get deaths	
	get_estimates, gbd_team(cod) model_version_id(67904) year_ids(2015) age_group_ids(`age_group_id') clear
	tempfile death
	save `death', replace
	get_estimates, gbd_team(cod) model_version_id(68207) year_ids(2015) age_group_ids(`age_group_id') clear
	append using `death'
	save `death', replace

// get age_weights
	create_connection_string, server(strServer) database(strDatabase) user(strUser) password(strPassword)
	local conn_string = r(conn_string)
	odbc load, exec("SELECT * FROM strDatabase.age_group_weight") `conn_string' clear 
		
	keep if gbd_round_id ==3 & age_group_weight_description =="IHME standard age weight"
	tempfile weights
	save `weights', replace
	
	merge 1:m age_group_id using `death', assert(1 3) keep(3) nogen
	
	gen agestd_csmr = mean_death_rate*age_group_weight_value
	fastcollapse agestd_csmr, by(location_id year_id sex_id) type(sum)
	save `death', replace
	
	use `prev', clear
	merge m:1 age_group_id using `weights', assert(1 3) keep(3) nogen
	gen agestd_prev = mean*age_group_weight_value
	fastcollapse agestd_prev, by(location_id sex_id year_id) type(sum)
	
	
//	merge 1:1 location_id sex_id year_id using `check'


	merge 1:1 location_id year_id sex_id using `death', assert(3) nogen
	merge m:1 location_id using `locs', assert(2 3) keep(3) nogen
	gen ratio = agestd_csmr/agestd_prev
	keep if level ==3
	
	keep location_id location_name ihme_loc_id agestd_csmr agestd_prev ratio sex_id

outsheet using "strPath/custom_deaths_prev_csmr_50111.csv", replace comma 	

pdfstart using "strPath/prev_csmr_agestd_50111.pdf"
twoway (scatter agestd_prev agestd_csmr), by(sex_id, title("Prevalence vs CSMR, Age-standardized") note(" ") legend(off))
pdffinish

graph save "strPath/agestd_prev_csmr.gph", replace
