//About: The main script for generating nonfatal estimates for malaria.
//Prep Stata
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

	//run locals
	local run_whoadjust 1
	local run_mapaf 1
	local run_whoraw 1
	local run_study_level 1
	local append_format 1

	local incidence_dir "J:\WORK\04_epi\01_database\02_data\malaria\1442\01_input_data\incidence"
	local case_notif_dir "J:\WORK\04_epi\01_database\02_data\malaria\1442\01_input_data\case_reports"
	local output_dir "J:\WORK\04_epi\02_models\02_results\malaria\custom"
	
	local incidence "J:\WORK\04_epi\01_database\02_data\malaria\1442\01_input_data\incidence\map_cases_broadages.dta"
	local exclusions `j'/WORK/01_covariates/02_inputs/malaria/exclusions/malaria_exclusions_from_amillear_6-1-16_locadj.dta
	local malaria_locs "J:\temp\strUser\Malaria\malaria_locs.dta"
	
	local model_gov "`j'/WORK/01_covariates/02_inputs/malaria/model_maker/cfr_model_gov.xlsx"
	
	local pred_sq `output_dir'/`version'/prediction_square_`version'.dta
	


 if `run_mapaf' ==1 {
	
	//use the equations from the mortality part of malaria to calculate cfr, back calculate incidence and then scale
	//load and format the betas
	//figure out which model to use
	import excel "`model_gov'", clear firstr
	keep if gbd_submission == 1
	local model_num = model_num[1]
	
	//load the betas
	use "J:/temp/strUser/Malaria/outputs/beta_files_`model_num'.dta", clear
	//the below is manually done. Will need to be changed if the model changes
	split ar, parse("-")
	rename ar1 agegrp
	destring agegrp, replace
	tempfile betas
	save `betas', replace
		
	
	use `pred_sq', clear
	keep if map == 1
	
	//keep only estimation years
	keep if inlist(year_id, 1990,1995,2000,2005,2010,2015)
	
	gen age_bin = "infants" if agegrp ==1
	replace age_bin = "children" if agegrp ==2
	replace age_bin ="adults" if agegrp ==3

	merge m:1 agegrp using `betas', assert(3) nogen

	gen b_sex = cond(sex_id==2, b_2sex_id, 0)
	
	//generate the covariates we need
	gen log_mort_rate = log(mean_env_hivdeleted/pop_scaled)
	
	//calculate age specific logit_cfr and age specific cfr
	gen logit_cfr = b__cons + log_mort_rate*b_log_mort_rate + b_sex
	gen as_cfr = invlogit(logit_cfr)
	
	//generate implied age specific cases by cases =deaths/cfr
	gen implied_cases = mean_death/as_cfr
	
	replace implied_cases = 0 if age_group_id == 2 //no malaria for the wee children
	
	//generate the envelope of cases from map
	merge m:1 location_id age_bin year_id using `incidence', assert(2 3) keep(3) nogen
	
	//MAP uses a different underlying population than IHME, scale the cases to meet that population
	//calculate comparable population numbers( by age bin)
	bysort location_id year_id agegrp: egen ihme_age_bin_pop = total(pop_scaled)
	
	//scale map's cases to ihme populations
	forvalues i = 0/999{
		replace incidence_cases_`i' = incidence_cases_`i' * (ihme_age_bin_pop/population_map)
	}
	
	rename incidence_cases_* inc_agebin_*
	
	//find the total number of implied cases
	bysort location_id year_id agegrp: egen ihme_implied_cases_age_bin = total(implied_cases)
	
	//find the total number of deaths
	bysort location_id year_id agegrp: egen ihme_deaths_age_bin = total(mean_death)
	
	//use map incidence draws to come up with 1000 different scales to adjust the implied cases
	forvalues i = 0/999{
		gen draw_`i' = inc_agebin_`i' * (implied_cases/ihme_implied_cases_age_bin) //split 
		drop inc_agebin_`i'
	}
	
	//convert to incidence rate
	forvalues i = 0/999{
		replace draw_`i' = draw_`i'/pop_scaled
	}	
	
	//check for duplicates
	duplicates tag location_id age_group_id sex_id year_id, gen(tag)
	
	sum tag
	if `r(max)' >0{
		di as error "There are duplicates in this file (map)"
		asd
	}
	
	save "`output_dir'/`version'/map_africa.dta", replace
	
	//find the age pattern
	//within an age,sex,year combination, find the 5th pctile
	
	keep year_id sex_id age_group_id draw_*
	duplicates drop

	//1000 draws of the 5th percentile of incidence
	forvalues i = 0/999{
		bysort year_id age_group_id sex_id: egen pct_`i' = pctile(draw_`i'), p(5)
		drop draw_`i'
	}
	keep year_id age_group_id sex_id pct_*
	duplicates drop

	fastrowmean pct*, mean_var_name(mean_pct)
	save "`output_dir'/`version'/age_pattern.dta", replace
}

 if `run_whoraw' ==1 {

	//generate splits for South Africa and Saudi Arabia
	get_location_metadata, location_set_id(35) clear
	tempfile locs
	save `locs', replace
	
	//get pfpr for splitting later
	get_covariate_estimates, covariate_name_short(malaria_pfpr) clear
	keep location_id year_id mean_value
	rename mean_value malaria_pfpr
	merge m:1 location_id using `locs', assert(1 3) keep(3) nogen keepusing(parent_id ihme_loc_id)
	tempfile pfpr
	save `pfpr', replace
	
	//get populations, merge back on, convert to pop
	levelsof location_id, local(thelocs)
	get_populations,location_id(`thelocs') year_id(1990 1995 2000 2005 2010 2015) sex_id(3) age_group_id(22) clear
	
	merge m:1 location_id year_id using `pfpr', assert(2 3) nogen keep(3)
	
	gen prev_persons = malaria_pfpr * pop_scaled
	
	//keep SAU and ZAF
	keep if (strpos(ihme_loc_id, "SAU") | strpos(ihme_loc_id, "ZAF")) & !(ihme_loc_id == "SAU" | ihme_loc_id == "ZAF")
	
	gen parent_iso = substr(ihme_loc_id, 1,3)
	
	bysort year_id parent_iso: egen total_prev_persons = total(prev_persons)
	gen prev_frac = prev_persons/total_prev_persons
	
	keep year_id parent_iso prev_frac ihme_loc_id location_id
	tempfile prev_splits
	save `prev_splits', replace
	
	
	use `output_dir'/`version'/who_case_reports_`version'.dta, clear
	drop sex_id
	keep if who_raw == 1
	
	gen cases_conf = reported_cases_conf //number of cases
	rename pop_scaled agg_pop
	cap drop location_id

	merge m:1 ihme_loc_id using `locs', keepusing(parent_id location_id path_to_top_parent) assert(2 3) keep(3) nogen
	
	gen cases_conf_adj = cond(year <2000 & cases_conf ==0,.,cases_conf)
	
	//use a mixed effects regression to back cast in time
	mixed cases_conf_adj year_id || location_id:
	
	predict pred_cases,fit
	predict pred_xb, xb
	predict pred_xb_se, stdp
	
	//get out the reffs
	predict ref, reff
	predict ref_se, reses
	
	preserve
		keep location_id ref ref_se
		duplicates drop
		forvalues i = 0 /999{
			gen re_`i' =rnormal(ref, ref_se)
		}
		
		tempfile raw_reffs
		save `raw_reffs'
	restore
	
	//drop years we don't need
	keep if inlist(year_id, 1990, 1995,2000,2005,2010,2015)
	
	merge m:1 location_id using `raw_reffs', assert(1 3) nogen
	bysort location_id: gen case_95 = cases_conf if year_id==1995
	bysort location_id: egen case_95_2 = total(case_95)
	
	
	
	//generate 1000 draws of cases
	gen changed = 0
	forvalues i = 0/999{
		gen draw_`i' = cases_conf
		replace re_`i' = 0 if re_`i' == .
		//replace cases conf if before 1995 or before 2000 if 1995 ==0
		replace draw_`i' = rnormal(pred_xb, pred_xb_se) + re_`i' if (inlist(year_id,1990,1995) & (reported_cases_conf ==0 | reported_cases_conf ==.)) | (ihme_loc_id == "AZE" & year_id == 1990) | (ihme_loc_id == "UZB" & year_id ==1990) //assume countries with 0 cases reported are missing them
		replace changed = 1 if (inlist(year_id,1990,1995) & (reported_cases_conf ==0 | reported_cases_conf ==.)) | (ihme_loc_id == "AZE" & year_id == 1990) | (ihme_loc_id == "UZB" & year_id ==1990) //assume countries with 0 cases reported are missing them

		drop re_`i'
	
	}
	
	replace cases_conf = pred_cases if year_id<2000

	levelsof location_id, local(thelocs)
	levelsof year_id, local(theyears)

	//get the populations
	preserve
		get_populations, location_id(`thelocs') year_id(`theyears') sex_id(1 2) age_group_id(2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21) clear
		tempfile pops
		save `pops', replace
	restore	
	
	
	merge 1:m year_id location_id using `pops', assert(3) nogen
	
	//drop china since we have the subnats
	drop if location_id == 6

	//merge in the age pattern
	merge m:1 year_id age_group_id sex_id using "`output_dir'/`version'/age_pattern.dta", assert(3) keep(3) nogen
	
	//the age pattern is now incidence rates by age-- predict the numbe of cases per country year and assign accordingly
	forvalues i = 0/999{
		gen implied_cases = pop_scaled * pct_`i' // implied cases
		bysort location_id year_id: egen total_implied_cases = total(implied_cases) //within a country year, what is the estimated number of cases
		replace draw_`i' = draw_`i' *(implied_cases/total_implied_cases) //split proportionally
		
		drop implied_cases total_implied_cases pct_`i'
	}
	
	//split up SAU and ZAF into their component parts based on PFPR
	preserve
		keep if ihme_loc_id == "SAU" | ihme_loc_id == "ZAF"
		rename ihme_loc_id parent_iso
		count
		joinby parent_iso year_id using `prev_splits'
		count
		
		//split the draws
		forvalues i = 0/999{
			replace draw_`i' = draw_`i' * prev_frac if prev_frac != .
		}
		tempfile subnats
		save `subnats', replace
	restore
	
	//drop the originals and replace with the children
	drop if ihme_loc_id == "SAU" | ihme_loc_id == "ZAF" | ihme_loc_id == "MEX"
	append using `subnats'
	
	drop location_id
	merge m:1 ihme_loc_id using `locs', assert(2 3) keep(3) nogen keepusing(location_id)
	
	
	drop *pop*
	
	//get pops again, and convert to incidence
	levelsof location_id, local(thelocs)
	levelsof year_id, local(theyears)
	//get the populations
	preserve
		get_populations, location_id(`thelocs') year_id(`theyears') sex_id(1 2) age_group_id(2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21) clear
		tempfile pops
		save `pops', replace
	restore	
	
	merge 1:1 age_group_id location_id sex_id year_id using `pops', assert(3) nogen keepusing(pop_scaled)
	
	forvalues i = 0/999{
		replace draw_`i' = 0 if draw_`i' == .
		replace draw_`i'= draw_`i'/pop_scaled //split the cases proportionally by the age pattern for all of africa
	}
	
	//save the results and move along
	
	duplicates tag location_id age_group_id sex_id year_id, gen(tag)
	
	sum tag
	if `r(max)' >0{
		di as error "There are duplicates in this file (whoraw)"
		asd
	}
	
	
	save "`output_dir'/`version'/who_raw.dta", replace
}


//run the who_adjusted
if `run_whoadjust'==1{
	
	get_location_metadata, location_set_id(9) clear
	keep location_id level parent_id
	tempfile par_locs
	save `par_locs', replace
	
	local age_pattern `output_dir'/`version'/age_pattern.dta

	//load data
	use `output_dir'/`version'/who_case_reports_`version'.dta, clear
	keep if who_adjust ==1
	
	cap log close
	log using "`output_dir'/`version'/mi_malaria_regression_who_adj_`version'.log", replace
	
	//generate covariates
	//replace mean_death = .000000001 if mean_death ==0 //nominal value
	gen log_malar_death_rate = log(mean_death/pop_scaled)
	gen hsa_mort = health_system_access2 * (mean_death/pop_scaled)
	gen hsa_cap_mort = health_system_access_capped * (mean_death/pop_scaled)
	gen malar_death_rate = mean_death/pop_scaled
	//generate incidence
	gen incid_conf = (reported_cases_conf/pop_scaled)
	sum incid_conf if incid_conf !=0
	//replace incid_conf = `r(min)' if incid_conf == 0
	gen log_incid_conf = log(incid_conf) //the missings are for 2013-2015 where we don't have data
	
	//regression time
	//GBD 2013 Formula reg incid_conf hsa_cap_mort malaria_pfpr, nocons
	
	//GBD 2015 Best:
	mixed incid_conf hsa_cap_mort malaria_pfpr if who_adjust==1, nocons || location_id:

	cap log close
	
	local used_reffs 0
	//collect the random effects
	if e(cmd) == "menbreg"{
		predict re_means, remeans reses(re_se)
		local used_reffs 1
	}
	else if e(cmd)=="mixed"{
		predict re_means, reffects
		predict re_se, reses
		local used_reffs 1
	}
	if `used_reffs'==1{
		keep location_id re_means re_se who_adjust who_raw
		keep if who_adjust == 1 & who_raw !=1
		
		duplicates drop
		
		//make a 1000 draws of reffs
		forvalues i = 0/999{
			gen reff_`i' = rnormal(re_means,re_se)
		}

		preserve
			keep if location_id == 135
			rename location_id parent_id
			merge 1:m parent_id using `par_locs', assert(2 3) keep(3) nogen keepusing(location_id)
			drop parent_id
			tempfile brazil_reffs
			save `brazil_reffs'
		restore
		drop if location_id == 135 //drop brazil
		drop if location_id == 130 // drop mexico because its subnats already have reffs
		append using `brazil_reffs'
	}
	
	
	tempfile reffs
	save `reffs', replace	
	
	//collect betas
	matrix m = e(b)'
	// store the covariance matrix (again, leave out three columns
	matrix C = e(V)
	
	
	if `used_reffs' == 1{
		matrix m = m[1..(rowsof(m)-2),1] //this removes the random effects, alpha and the constant which we don't use
		matrix C = C[1..(colsof(C)-2), 1..(rowsof(C)-2)]
	}
	
	// create a local that corresponds to total number of parameters
	local covars: rownames m
	local num_covars: word count `covars'
	// create an empty local that you will fill with the name of each beta (for each parameter)
	local betas
	// fill in this local
	forvalues j = 1/`num_covars' {
		local this_covar: word `j' of `covars'
		local covar_fix=subinstr("`this_covar'","b.","",.)
		local covar_rename=subinstr("`covar_fix'",".","",.)
		local betas `betas' b_`covar_rename'
	}

	
	//bring in the prediction dataset
	use `output_dir'/`version'/prediction_square_`version'.dta, clear
	keep if who_adjust == 1 & who_raw !=1
	
	//collapse to the country level
	drop mean_death upper_death lower_death mean_env_hivdeleted pop_scaled age_group_id agegrp sex_id
	duplicates drop
	isid location_id year_id
	//generate required variables
	replace country_death = .000001 if country_death ==0
	gen log_malar_death_rate = log(country_death/country_pop)
	gen hsa_mort = health_system_access2*(country_death/country_pop)
	gen hsa_cap_mort = health_system_access_capped * (country_death/country_pop)
	//rename things-- be careful
	gen pop_scaled = country_pop
	gen reported_cases_conf = 1 //add a placeholder
	predict pred_xb_preadj, xb
	
	//make hsa_adjustment
	//adjust for systematic under count by seeting HSA to 95th percentile observed
	
	//regular HSA
	sum health_system_access2 if year_id == 2015, detail
	rename health_system_access2 health_system_access_orig //more value saving	
	rename hsa_mort hsa_mort_orig
	local hsa_95 = r(p95)
	gen health_system_access2 = `hsa_95'
	gen hsa_mort = (country_death/country_pop) * health_system_access2
	
	//hsa_capped
	sum health_system_access_capped if year_id == 2015, detail
	rename health_system_access_capped health_system_access_capped_orig //more value saving
	rename hsa_cap_mort hsa_cap_mort_orig
	local hsa_95 = r(p95)
	gen health_system_access_capped = `hsa_95'
	gen hsa_cap_mort = (country_death/country_pop) * health_system_access_capped
	
	
	
	predict pred_xb_postadj, xb	//for some reason, prediction adds ln(pop_scaled)
	drop pop_scaled
	gen og_point =1
	set obs 1000 //add some more observations

	//generate 1000 draws of betas
	drawnorm `betas', means(m) cov(C)
	
	//merge in the random effects if using
	if `used_reffs' ==1 {
		merge m:1 location_id using `reffs', assert(1 3)
	}
	//calculate draws
	forvalues i = 0/999{
		
		local j = `i'+1
		if `used_reffs'{
			replace reff_`i' = 0 if reff_`i' ==.
		}

		gen draw_`i' = ((b_hsa_cap_mort[`j'] * hsa_cap_mort) + (b_malaria_pfpr[`j'] * malaria_pfpr)) * country_pop
		
		cap drop reff_`i'
	}
	
	drop if og_point ==.

	fastrowmean draw*, mean_var_name(mean_draw) 
	
	duplicates tag location_id year_id, gen(tag)
	save "`output_dir'/`version'/who_adjust_draws_presplit.dta", replace
	sum tag
	if `r(max)' >0{
		di as error "There are duplicates in this file (who_adj)"
		asd
	}
	
	
	//prepare for converting national level estimates into age and sex specific estimates
	
	//apply the africa age pattern
	joinby year_id using "`output_dir'/`version'/age_pattern.dta"
	drop pct*
	cap drop pop_scaled
	preserve
		levelsof location_id, local(locations)
		levelsof year_id, local(years)
		levelsof sex_id, local(sexes)
		levelsof age_group_id, local(ages)
		
		get_populations, year_id(`years') location_id(`locations') sex_id(`sexes') age_group_id(`ages') clear
		tempfile pop
		save `pop', replace
	
	restore	
	
	merge 1:1 year_id location_id sex_id age_group_id using `pop', assert(3) nogen
	
	
	forvalues i = 0/999{
		gen implied_cases = pop_scaled * mean_pct // implied cases
		bysort location_id year_id: egen total_implied_cases = total(implied_cases) //within a country year, what is the estimated number of cases
		replace draw_`i' = (draw_`i'*(implied_cases/total_implied_cases))/pop_scaled //split proportionally
		
		drop implied_cases total_implied_cases
	}
	
	save "`output_dir'/`version'/who_adjust_draws.dta", replace
}

if `run_study_level' == 1 {

	use `output_dir'/`version'/study_level_dataset_`version'.dta, clear
	keep if study_level ==1
	
	
	//create variables
	//the old regression regress ln_incid_study ln_malar_death_rate africa pfpr_ratio ag_agegrp* pcd_dummy
	//follow 2013 strat:
	replace malaria_pfpr = 0.0001 if malaria_pfpr ==.
	replace incidence = .0001 if incidence==.
	
	gen ln_incidence = ln(incidence)
	gen ln_malar_death_rate = ln(mean_death/pop_scaled)
	gen malar_death_rate = mean_death/pop_scaled

	gen africa = cond(super_region_id ==166 | inlist(ihme_loc_id, "YEM"),1,0)
	gen pfpr_ratio = pfpr_2010/malaria_pfpr
	
	//create interactions
	xi i.agegrp*malar_death_rate, prefix(ag_)
	
	//outliers
	sum incidence, detail
	gen outlier = incidence if incidence < r(p1)
	replace incidence = . if outlier != .
	
	//remove relative to last GBDs stuff
	drop if strpos(reference ,"Dicko")
	
	cap log close
	log using "`output_dir'/`version'/mi_malaria_study_level_`version'.log", replace
	regress ln_incidence ln_malar_death_rate africa pfpr_ratio ag_agegrp* pcd_dummy
	cap log close
	
	//use the dataset
	use `output_dir'/`version'/prediction_square_`version'.dta, replace
	
	//subset dataset
	keep if study_level==1 & map!=1
	
	//collapse to the three main age groups
	
	//pop weight covariate
	replace malaria_pfpr = malaria_pfpr *pop_scaled
	
	keep location_id ihme_loc_id year_id agegrp sex_id mean_death pop_scaled malaria_pfpr
	
	fastcollapse mean_death pop_scaled malaria_pfpr, by(location_id ihme_loc_id year_id agegrp sex_id) type(sum)
	replace malaria_pfpr = malaria_pfpr/pop_scaled
	
	//generate covs
	replace mean_death = .000001 if mean_death == 0
	gen ln_malar_death_rate = ln(mean_death/pop_scaled)
	gen malar_death_rate = mean_death/pop_scaled
	gen africa = 0
	
	gen pfpr_ratio = 1
	
	//create interactions
	xi i.agegrp*malar_death_rate, prefix(ag_)
	gen ag_agegrp_4 = 0
	gen pcd_dummy =0
	//extract betas
	predict pred
	
	matrix m = e(b)'
	// create a local that corresponds to the variable name for each parameter
		local covars: rownames m
	// create a local that corresponds to total number of parameters
		local num_covars: word count `covars'
	// create an empty local that you will fill with the name of each beta (for each parameter)
		local betas
	// fill in this local
		forvalues j = 1/`num_covars' {
			local this_covar: word `j' of `covars'
			local covar_fix=subinstr("`this_covar'","b.","",.)
			local covar_fix=subinstr("`this_covar'","o.","o",.)
			local covar_rename=subinstr("`covar_fix'",".","",.)
			local betas `betas' b_`covar_rename'
		}
	// store the covariance matrix (again, you don't want the last rows and columns that correspond to dispersion parameter)
		matrix C = e(V)
		matrix C = C[1..(colsof(C)), 1..(rowsof(C))] // RE: matrix C = C[1..(colsof(C)-1), 1..(rowsof(C)-1)]
	// use the "drawnorm" function to create draws using the mean and standard deviations from your covariance matrix
		drawnorm `betas', means(m) cov(C)
		
	//generate predictions
	forvalues j = 1/1000 {
		local i = `j'-1
		generate xb_d`j' = 0
		foreach c of local covars {
				noisily display "`c'"
				replace xb_d`j' = xb_d`j' + `c' * b_`c'[`j']
				
		}
	
			
		replace xb_d`j'=exp(xb_d`j') * pop_scaled //convert to cases
		// rename
		rename xb_d`j' draw_`i'	
	}
	
	
	//get national level estimates
	fastcollapse pop_scaled draw*, by(location_id year_id) type(sum)
	
	//use the MAP data to age split
	rename pop_scaled country_pop
	
	//apply the africa age pattern
	joinby year_id using "`output_dir'/`version'/age_pattern.dta"
	
	cap drop pop_scaled
	preserve
		levelsof location_id, local(locations)
		levelsof year_id, local(years)
		levelsof sex_id, local(sexes)
		levelsof age_group_id, local(ages)
		
		get_populations, year_id(`years') location_id(`locations') sex_id(`sexes') age_group_id(`ages') clear
		tempfile pop
		save `pop', replace
	
	restore	
	
	merge 1:1 year_id location_id sex_id age_group_id using `pop', assert(3) nogen
	
	
	forvalues i = 0/999{
		gen implied_cases = pop_scaled * pct_`i' // implied cases
		bysort location_id year_id: egen total_implied_cases = total(implied_cases) //within a country year, what is the estimated number of cases
		replace draw_`i' = (draw_`i'*(implied_cases/total_implied_cases))/pop_scaled //split proportionally
		
		drop implied_cases total_implied_cases pct_`i'
	}
	
	save "`output_dir'/`version'/study_level_draws.dta", replace
}




//Append the results together
if `append_format' == 1{
	clear
	//get epi diagnostics
	get_demographics, gbd_team(epi) make_template clear
	tempfile epi_sq
	save `epi_sq', replace
	clear
	append using "`output_dir'/`version'/who_adjust_draws.dta" "`output_dir'/`version'/who_raw.dta" "`output_dir'/`version'/map_africa.dta" "`output_dir'/`version'/study_level_draws.dta"
 
	//mexico is sneaking in. Not sure why-- drop it
	drop if ihme_loc_id == "MEX"
	
	//clear up the dataset
	keep age_group_id sex_id year_id location_id ihme_loc_id draw* modeling_group
	
	merge 1:1 location_id age_group_id sex_id year_id using `epi_sq', assert(2 3) nogen
	
	//apply exclusions
	merge m:1 location_id year_id using `exclusions', assert(2 3) keep(3) keepusing(malaria)
	
	//bound draws to 0
	foreach draw of varlist draw*{
		replace `draw' = 0 if `draw'==. | `draw' < 0
		replace `draw' = 0 if malaria == 0
	}
	
	
	save `output_dir'/`version'/malaria_nonfatal_incidence.dta,replace

}


	