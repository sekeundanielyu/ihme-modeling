//Malaria NonFatal
//About: This code loads and formats data for the 4 stages of the incidence regression: MAP, WHO Raw, WHO Adj and Study level.
	clear all
	set more off
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
	qui adopath + "C:\Users\strUser\Documents\Code\malaria"
//Set Locals
	local version v53
	local version_descrip "Final"

	local incidence_dir "J:\WORK\04_epi\01_database\02_data\malaria\1442\01_input_data\incidence"
	local case_notif_dir "J:\WORK\04_epi\01_database\02_data\malaria\1442\01_input_data\case_reports"
	local output_dir "J:\WORK\04_epi\02_models\02_results\malaria\custom"
	local study_level_data `incidence_dir'/all_sources_prepped_with_pfpr_for_regression_april14_nopatil.dta
	
	
	local malaria_locs "J:\temp\strUser\Malaria\malaria_locs.dta"
	local cov_list health_system_access2 malaria_pfpr sds health_system_access_capped ldi_pc malaria_par_prop

//modeling groups
	//for 2015, drop the study level group. Africa will be split from MAP and outside africa gets moved to WHO adjust
	//force the groups to match the 2015 location split. Assign national units to the proper groups

	
//Step 1: Assign locations to their modeling groups
	use `malaria_locs', clear
	keep location_id ihme_loc_id m_af_15 m_af_13
	//keep if estimate_2015==1
	levelsof ihme_loc_id if m_af_15==1, local(map)
	//local map `map' KEN
	levelsof ihme_loc_id if m_af_15 !=1, local(who_adjust) clean
	
	
	local tiny_islands VIR ASM BMU PRI GUM MNP	
	
	local who_raw ZAF BLZ PAN IRN SAU KGZ TJK CHN TUR AZE UZB GEO KOR ARG CRI ARM MYS LKA BTN IRQ PRK PAR MEX SLV ECU CPV DZA
	
	//all vivax countries and outside of africa countries
	local who_adjust `who_adjust' BRA MEX `who_raw'
	local og_who ZAF BLZ PAN IRN SAU KGZ TJK CHN
	
	local study_level IND YEM GUF MYT IDN MMR PNG KEN `map'
	
	//aggregate group
	local groups map who_adjust who_raw study_level tiny_islands og_who
	
	//get a clean set of locations
	get_location_metadata, location_set_id(9) clear
	keep location_name location_id ihme_loc_id level parent_id is_estimate super_region_id region_id
	foreach ggg of local groups{
		gen `ggg' = 0
		
		foreach loc of local `ggg'{
			replace `ggg' = 1 if strpos(ihme_loc_id,"`loc'") > 0
		}
	}
	
	//replace who_adjust = 0 if who_raw ==1
	replace who_adjust = 0 if tiny_islands ==1
	replace who_adjust = 0 if study_level == 1
	egen group_num = rowtotal(`groups')
	
	//drop countries w/o malaria or unneeded india
	drop if group_num == 0
	drop if strpos(ihme_loc_id, "IND")>0 & strlen(ihme_loc_id)==8
	
	levelsof location_id, local(thelocs)
	
	
	tempfile location_groups
	save `location_groups', replace
	
//Subset by loc type
	//national locs
	preserve
		keep if level==3
		tempfile lv3locs
		save `lv3locs', replace
	restore
	
	//subnational points
	preserve
		keep if parent_id ==6
		tempfile chn_subnats
		save `chn_subnats', replace
	restore
	
	preserve
		keep if parent_id == 130
		tempfile mx_subnats
		save `mx_subnats'
	restore
	
//Step 2: Get some logistics out of the way
//Make file system
	cap mkdir `output_dir'/`version'

//Step 3: get Covs (only national level ones for now)
//Get Covariates:
	local aa_bs_covs
	foreach cov of local cov_list{
		di "`cov'"
		get_covariate_estimates, covariate_name_short(`cov') clear
		keep location_id year_id mean_value
		rename mean_value `cov'
		tempfile `cov'_est
		save ``cov'_est', replace
	}
	
	//merge the covs together
	local iter 0
	foreach cov of local cov_list{
		if `iter'==0{
			use ``cov'_est', clear
			local iter 1
		}
		else{
			merge 1:1 location_id year_id using ``cov'_est', assert(1 3) nogen keep(3)
		}
	
	}
	tempfile covs
	save `covs', replace
	

//Step 4: Collect deaths and populations
//Bring in mean estimates of codcorrected deaths from 1980-2015
	local thelocs = subinstr("`thelocs'", " ", ",", .)
	create_connection_string
	local conn_string = r(conn_string)
	#delimit;
	odbc load, exec("SELECT  
		o.location_id, 
		o.year_id, 
		o.sex_id, 
		o.age_group_id,
		o.mean_death,
		o.upper_death,
		o.lower_death
	FROM 
		cod.output o 
	JOIN 
		cod.output_version ov USING (output_version_id) 
	WHERE 
		ov.best_start IS NOT NULL AND 
		ov.best_end IS NULL AND 
		cause_id = 345 AND
		o.age_group_id <22
		AND o.location_id in (`thelocs');") `conn_string' clear ;
	#delimit cr


	levelsof location_id, local(locations)
	levelsof year_id, local(years)
	levelsof sex_id, local(sexes)
	levelsof age_group_id, local(ages)
	preserve
		get_populations_malaria, year_id(`years') location_id(`locations') sex_id(`sexes') age_group_id(`ages' 2) clear
		tempfile pop
		save `pop', replace
	restore
	
	//merge in deaths
	merge 1:1 year_id location_id sex_id age_group_id using `pop', assert(2 3) nogen
	replace mean_death = 0 if mean_death == .
	
	//for the study level regression, we need 4 groups, 0-4,5-14,15+ and 0+. Everything else is at the national level
	gen agegrp = 1 if inrange(age_group_id,2,5)
	replace agegrp=2 if inrange(age_group_id, 6,7)
	replace agegrp =3 if agegrp ==.
	
	tempfile dp_sq
	save `dp_sq', replace
	
//make subsets
	//by age bin and sex (ages 1 2 3, sexes 1 2)
	fastcollapse mean_death pop_scaled, by(location_id year_id agegrp sex_id) type(sum)
	tempfile dp_123_12
	save `dp_123_12', replace
		
	//sex 1 2, age 4
	use `dp_sq', clear
	fastcollapse mean_death pop_scaled, by(location_id year_id sex_id) type(sum)
	gen agegrp = 4
	tempfile dp_4_12
	save `dp_4_12', replace
	
	//sex 3, age 1 2 3
	use `dp_sq', clear
	fastcollapse mean_death pop_scaled, by(location_id year_id agegrp) type(sum)
	gen sex_id = 3
	tempfile dp_123_3
	save `dp_123_3', replace
	
	//calculate deaths and pop by location year
	use `dp_sq', clear
	fastcollapse mean_death pop_scaled, by(location_id year_id) type(sum)
	gen sex_id =3
	gen agegrp = 4
	tempfile dp_4_3
	save `dp_4_3', replace
	


//create study level dataset
	use `study_level_data',clear
	
	drop if year<1980 //should remove one weird gabon point
	
	rename iso3 ihme_loc_id
	rename year year_id
	gen sex_id = 3 if sex =="both"
	replace sex_id = 2 if sex == "female"
	replace sex_id = 1 if sex == "male"
	replace pcd_dummy = 0 if pcd_dummy == 2
	
	rename parameter_value incidence
	
	merge m:1 ihme_loc_id using `location_groups', keep(3) nogen //this drops some weird india data and a GUF data point
	
	tempfile incid_study
	save `incid_study', replace
	
	//get the death data all sorted out
	clear
	append using `dp_123_12' `dp_4_12' `dp_123_3' `dp_4_3'
	
	merge 1:m year_id agegrp sex_id location_id using `incid_study', assert(1 3) keep(3) nogen
	
	
	//merge on covs and save
	merge m:1 location_id year_id using `covs', assert(2 3) keep(3) nogen
	
	gen modeling_group = "study_level"
	save `output_dir'/`version'/study_level_dataset_`version'.dta, replace
	
	
//Create WHO dataset
		import delimited "`case_notif_dir'/wmr13_annex_6b_adjlocnames2.csv", varnames(1) clear 
		
		//fill in country names
		replace countryarea = countryarea[_n-1] if missing(countryarea)
		rename countryarea location_name
		
		//sort out parameters
		rename v2 parameter
		keep if strmatch(parameter, "Confirmed*") | strmatch(parameter, "Presumed*") | strmatch(parameter, "Imported*")
		replace parameter = "_conf" if strmatch(parameter, "Confirmed*")
		replace parameter = "_probconf" if strmatch(parameter, "Presumed*")	
		replace parameter = "_imported" if strmatch(parameter, "Imported*")	
		
		//fix column names
		local y 1990
		forvalues i = 3/25 {
			rename v`i' yr`y'
			local y = `y' + 1
		}
		destring yr*, ignore("," "-") replace
		
		//aggregate
		fastcollapse yr*, by(location_name parameter) type(sum)
		
		merge m:1 location_name using `lv3locs', keep(3) keepusing(location_id ihme_loc_id) nogen
		
		
		merge m:1 location_id using `location_groups', assert(2 3) nogen keepusing(who_raw) keep(1 3)

		//use the most recent non blank estimate as 2015 
		forvalues y =2013/2015{
			gen yr`y' = yr2012 if who_raw == 1
		}

		drop who_raw
		reshape long yr, i(ihme_loc_id parameter) j(year_id)
		rename yr reported_cases
	// reshape so that PARAMETER is WIDE
		reshape wide reported_cases, i(ihme_loc_id year_id) j(parameter) string
	// subtract imported cases from confirmed cases
		replace reported_cases_imported = 0 if reported_cases_imported == .
		gen reported_cases_conf_orig=reported_cases_conf
		replace reported_cases_conf = reported_cases_conf - reported_cases_imported
		
		replace reported_cases_conf= 0 if reported_cases_conf <0 // if there were more imported cases than confirmed cases, set confirmed to 0
		
		
		merge 1:1 location_id year_id using `dp_4_3', keepusing(location_id)
		count if _merge==1 & !inlist(ihme_loc_id, "BHS", "JAM","RUS")
		
		if `r(N)' > 0{
			sdfasdf
		}
		else{
			keep if _merge ==3
			drop _merge
		}
	//save and move on
		tempfile incid_reported
		save `incid_reported', replace
		
	//Bring in China subnats: (Removed because of data use agreements)

			

	//Bring in Mexico Data
	insheet using "J:\Project\Causes of Death\CoDMod\Models\A12\YLDs\data\GBD2013\input\mexico_malaria_cases.csv", comma names clear

	rename entidadfederativa location_name
	rename paludismovivax54b reported_cases_conf
	rename ao year_id
	keep location_name reported_cases_conf year
	replace location_name = "Coahuila" if location_name == "Coahuila de Zaragoza"
	replace location_name = "Querétaro" if location_name == "Querétaro de Arteaga"


	merge m:1 location_name using `mx_subnats', assert(1 3) keep(3) nogen keepusing (location_id ihme_loc_id)
	destring year_id, replace
	//create a flat line forward and backward
	replace reported_cases_conf = subinstr(reported_cases_conf, " ", "", .)
	destring reported_cases_conf, replace
	reshape wide reported_cases_conf, i(location_name location_id ihme_loc_id) j(year_id)

	
	forvalues i =1990/1997{
		gen reported_cases_conf`i' = . //for the back case, assume missing
	}
	forvalues i =2009/2015{
		gen reported_cases_conf`i' = reported_cases_conf2008 //for the back case, assume missing
	}
	

	reshape long reported_cases_conf, i(location_name location_id ihme_loc_id) j(year_id)


	tempfile mexico
	save `mexico', replace

	//Append reported datasets together
	use `incid_reported', clear
	append using `china' `mexico'


	//drop unneeded variables/variables that will be readded by the square
	keep ihme_loc_id year_id reported_cases* location_id
	
	gen agegrp =4
	gen modeling_group = "WHO"
	merge 1:1 location_id year_id using `dp_4_3', assert(2 3) keep(3) nogen
	
	merge 1:1 location_id year_id using `covs', assert(2 3) keep(3) nogen
	merge m:1 location_id using `location_groups', assert(2 3) keep(3) nogen
	keep if is_estimate ==1
	cap drop age_group_id sex_id
	save `output_dir'/`version'/who_case_reports_`version'.dta, replace

//create the prediction squares: country year level for everyone, with age bins for study level
	get_demographics, gbd_team(epi) clear make_template
	
	gen agegrp = 1 if inrange(age_group_id,2,5)
	replace agegrp=2 if inrange(age_group_id, 6,7)
	replace agegrp =3 if agegrp ==.
	
	keep location_id location_name year_id agegrp age_group_id sex_id
	duplicates drop
	
	merge m:1 location_id using `location_groups', assert(1 3) keep(3) nogen
	keep if is_estimate ==1
	
	merge m:1 location_id year_id using `dp_4_3', assert(1 3) keep(3) nogen
	rename mean_death country_death
	rename pop_scaled country_pop
	
	merge 1:1 location_id age_group_id sex_id year_id using `dp_sq', assert(2 3) keep(3) nogen
	
	merge m:1 location_id year_id using `covs', assert(2 3) keep(3) nogen
	save `output_dir'/`version'/prediction_square_`version'.dta, replace
	
