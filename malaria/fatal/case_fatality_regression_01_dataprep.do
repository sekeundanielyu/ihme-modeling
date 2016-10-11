clear all
set more off
cap restore, not
set trace off

//set OS
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		local prefix "/home/j"
		set odbcmgr unixodbc
		adopath + "/ihme/code/general/strUser/malaria"
	}
	else if c(os) == "Windows" {
		local prefix "J:"
		
		adopath + "C:/Users/strUser/Documents/Code/malaria"
	}
	adopath + "`prefix'/WORK/10_gbd/00_library/functions"
//Locals
	local ss_data "`prefix'\WORK\01_covariates\02_inputs\malaria\estimates\site_specific\ss_vars.dta"
	local antimalarial "`prefix'\WORK\01_covariates\02_inputs\malaria\estimates\general_drug_use/map_anyantimalarial_est.dta"
	local malaria_locs "J:\temp\strUser\Malaria\malaria_locs.dta"
	local map_incidence J:\WORK\04_epi\01_database\02_data\malaria\1442\01_input_data\incidence/map_untreated_cases_broadages.dta
	
	//file structure
	local main_path J:\WORK\03_cod\02_models\02_results\malaria\models
	local data_path "`prefix'/WORK/01_covariates/02_inputs/malaria/cfr_model"
	
	//data
	local pullfreshnums 0
	local submission_data "`data_path'/malaria_data_submission.dta"
	
	//site specific data
	local ss_data "`prefix'\WORK\01_covariates\02_inputs\malaria\estimates\site_specific\ss_vars.dta"
	local map_ss J:\WORK\01_covariates\02_inputs\malaria\data\map_data_5-19\site_specific_MAP_untreated_incidence_and_pop_formatted.dta
	//The governator	
	local model_gov "`prefix'/WORK/01_covariates/02_inputs/malaria/model_maker/cfr_model_gov.xlsx"
	
	local gen_covariates 1
	local gen_pred_sq 1
	local gen_data_sq 1 
	

//generate demos
	get_location_metadata, location_set_id(35) clear
	tempfile locnames
	save `locnames',replace

	get_demographics, gbd_team(cod) make_template get_population clear
	
	//keep only codem Africa
	merge m:1 location_id using `malaria_locs', keep(3) keepusing(estimate_2015 m_af_15) nogen //get demographics only has the lowest level
	keep if m_af_15 ==1 & estimate_2015 ==1
	tempfile demos
	save `demos', replace
	
//generate covs
if `gen_covariates' ==1{
//get the demographic square


//get sort out the covariates
	//drug resistence
	get_covariate_estimates, covariate_name_short(malaria_pw_resistance) clear
	keep location_id year_id mean_value
	duplicates drop
	rename mean_value malaria_pw_resistance
	tempfile pwdr
	save `pwdr', replace
	
	//old incidence
	get_covariate_estimates, covariate_name_short(malaria_incidence) clear
	keep location_id year_id mean_value age_group_id
	
	//generate age groups
	drop if age_group_id == 2
	gen age_group = 1 if inrange(age_group_id,3,5)
	replace age_group = 2 if inrange(age_group_id, 6,7)
	replace age_group =3 if age_group ==.
	
	gen age_bin = "infants" if inrange(age_group_id,2,5)
	replace age_bin = "children" if inrange(age_group_id,6,7)
	replace age_bin ="adults" if age_group_id>=8
	
	drop age_group_id
	duplicates drop
	rename mean_value malaria_incidence
	
	//merge all the country year covariates together
	merge m:1 location_id year_id using `pwdr',assert(2 3) keep(3) nogen
	
	//merge antimalarial
	merge m:1 location_id year_id using `antimalarial', assert(1 3) keep(3) nogen

	//merge in required locs
	merge m:1 location_id using `malaria_locs', keep(3) keepusing(estimate_2015 m_af_15) nogen //get demographics only has the lowest level
	keep if m_af_15 ==1 & estimate_2015 ==1
	
	//merge in map incidence and population
	merge m:1 location_id year_id age_bin using `map_incidence', assert(2 3) keep(3) nogen
	
	//convert to incidence rate and find the mean
	forvalues i = 0/999{
		replace untreated_incidence_cases_`i' = untreated_incidence_cases_`i'/population_map
		rename untreated_incidence_cases_`i' map_untreated_incidence_`i'
	}
	
	fastrowmean map_untreated_incidence_*, mean_var_name(mean_map_untreated_incidence)
	drop age_group_id
	tempfile covariates
	save `covariates', replace
	save `main_path'/covariates.dta, replace 
}
else {
	local covariates `main_path'/covariates.dta
}
//for the demographics, get the envelope and collapse to broad age bins
if `gen_pred_sq' == 1{	
	
	use `demos', clear
	
	keep location_id year_id age_group_id sex_id pop_scaled
	
	//get the demographics I need the envelope for
	levelsof location_id, local(locations)
	levelsof year_id, local(years)
	levelsof sex_id, local(sexes)
	levelsof age_group_id, local(ages)
	preserve
		get_populations_malaria, year_id(`years') location_id(`locations') sex_id(`sexes') age_group_id(`ages') clear
		tempfile env
		save `env', replace
	restore
	
	merge 1:1 location_id year_id sex_id age_group_id using `env', assert(2 3) keep(3) nogen
	
	//collapse by broad age group
	drop if age_group_id == 2
	gen age_group = 1 if inrange(age_group_id,3,5)
	replace age_group = 2 if inrange(age_group_id, 6,7)
	replace age_group =3 if age_group ==.
	
	fastcollapse pop_scaled mean_env_hivdeleted, by(age_group location_id year_id sex_id) type(sum)
	
	//merge in covariates
	merge m:1 location_id year_id age_group using `covariates', assert(2 3) keep(3) nogen
	
	gen type = "prediction"
	
	//clean up
	drop ll_codem_af m_af_15 estimate_2015 gaul_comb age_bin_num
	
	
	save `demos', replace
	save `main_path'/malaria_cfr_pred_sq.dta, replace
}
// generate the dataset
if `gen_data_sq' !=0{
	//pull in the original/submission dataset
	if `gen_data_sq' ==1{
		use `submission_data', clear
		
		//sort out data and column names
		keep nid data_type location_id year age_group_id sex_id study_deaths sample_size pop env site ihme_loc_id
		rename env mean_env_hivdeleted
		rename pop pop_scaled
		rename year year_id
		
		//create age groups
		drop if age_group_id == 2
		gen age_group = 1 if inrange(age_group_id,3,5)
		replace age_group = 2 if inrange(age_group_id, 6,7)
		replace age_group =3 if age_group ==.
		
		gen age_bin = "adults" if age_group== 3
		replace age_bin = "children" if age_group== 2
		replace age_bin = "infants" if age_group== 1
		
		
		fastcollapse pop_scaled mean_env_hivdeleted study_deaths sample_size, by(age_bin data_type age_group location_id year_id sex_id nid site) type(sum)
	
		//merge in non site level covariates
		merge m:1 location_id year_id age_group using `covariates', assert(2 3) keep(3) keepusing(malaria_pw_resistance antimalarial) nogen
		
		//bring in site specific covariates
		preserve
			use "`ss_data'", clear
			cap rename year year_id
			keep site year_id inc_*
			duplicates drop
			tempfile ss_m_i
			save `ss_m_i', replace
		restore
		
		
		//new incidence and population numbers
		gen year = year_id
		merge m:1 nid age_bin location_id year site using `map_ss', keep(3) nogen
		
		//convert to incidence rate and find the mean
		forvalues i = 0/999{
			replace untreated_incidence_cases_`i' = untreated_incidence_cases_`i'/site_population
			rename untreated_incidence_cases_`i' map_untreated_incidence_`i'
		}
		
		gen type = "data_points"
		fastrowmean map_untreated_incidence_*, mean_var_name(mean_map_untreated_incidence)
		
		//make sure the datapoints are from the proper countries
		merge m:1 location_id using `malaria_locs', keep(3) keepusing(estimate_2015 m_af_15) nogen //get demographics only has the lowest level
		keep if m_af_15 ==1 & estimate_2015 ==1
		drop m_af_15 estimate_2015 year
		
		//mark which ones were in submission
		gen year = year_id
		
		preserve
			use `ss_data', clear
			keep site year_id
			duplicates drop
			tempfile ss
			save `ss', replace
		restore
		
		merge m:1 site year_id using `ss', keep(1 3)
		rename _merge submission_datapoint
		replace submission_datapoint = submission_datapoint ==3

		save `main_path'/malaria_cfr_dataset.dta, replace
	}
}

//combine the two datasets
	clear
	
	append using `main_path'/malaria_cfr_pred_sq.dta
	append using `main_path'/malaria_cfr_dataset.dta
	
//generate shared variables
	
	//scaled deaths (regenerating the cause fraction implictly)
		gen scaled_deaths = (study_deaths/sample_size) * mean_env_hivdeleted
	//untreated cases (scaled to poplevel for site)
		gen mean_untreated_cases = pop_scaled*mean_map_untreated_incidence
	//death rate (site specific only)
		gen death_rate = ((study_deaths/sample_size) * mean_env_hivdeleted)/pop_scaled
	//cfr
		gen cfr = death_rate/mean_map_untreated_incidence
	//logit cfr
		gen logit_cfr = logit(cfr)
	//mortality
		gen mort_rate = mean_env_hivdeleted / pop_scaled
	//log mortality
		gen log_mort_rate = log(mort_rate)

//save the files again
	preserve
		keep if type == "data_points"
		save `main_path'/malaria_cfr_dataset_upd.dta, replace
	restore
	preserve
		keep if type == "prediction"
		save `main_path'/malaria_cfr_pred_sq_upd.dta, replace
	restore

	
	
	
