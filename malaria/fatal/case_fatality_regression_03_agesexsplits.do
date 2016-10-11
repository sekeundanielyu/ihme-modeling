//take in CFR model results and age split based on regional patterns
//to age sex split a broad bin the formula is roughly:
//(age-specific deaths) = (region age specific rate * country pop age specific) * (age binned deaths estimated / sum of (region rate age specific *kenya pop) for all age specific ranges within the bin)
clear all
set more off
cap restore, not
set trace off

//set OS
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		local prefix "/home/j"
		set odbcmgr unixodbc
		local datapath "/snfs3/strUser/malaria_draws"
		adopath + "/ihme/code/general/strUser/malaria"
	}
	else if c(os) == "Windows" {
		local prefix "J:"
		local datapath "`prefix'/temp/strUser/Malaria"
		adopath + "C:/Users/strUser/Documents/Code/malaria"
	}
	adopath + "`prefix'/WORK/10_gbd/00_library/functions"
	
	
//Set locals
	local model_version 20
	local cfr_results "J:\temp\strUser\Malaria\outputs\draws_`model_version'.dta"
	local models_2015_new 71426 71420 71429 71423
	local models_c = subinstr("`models_2015_new'", " ", ",", .)
	di "`models'"
//get locations
	get_location_metadata, location_set_id(35) clear
	tempfile locnames
	save `locnames',replace

//figure out the regions represented
	use `cfr_results', clear
	merge m:1 location_id using `locnames', assert(2 3) keep(3) keepusing(region_id) nogen
	
	levelsof region_id, local(theregions)
	levelsof location_id, local(thelocations)
	
	preserve
		keep location_id
		duplicates drop
		tempfile cfr_locs
		save `cfr_locs', replace
	restore
	
	//keep only required columns
	rename pop_scaled cfr_agg_pop
	rename mean_env_hivdeleted cfr_agg_env
	keep location_id region_id year_id sex_id age_group cfr_agg_pop cfr_agg_env draw* deaths_mean
	rename deaths_mean agg_age_death_mean

	tempfile cfr
	save `cfr', replace
	
//get the CODEm estimates
	//use the code I borrowed from scatter plots. Returns the same results as get estimates and is faster
	create_connection_string
	local conn_string = r(conn_string)
	#delimit;
	odbc load, exec("SELECT m.location_id, m.year_id, m.sex_id, m.age_group_id, m.upper_cf,m.lower_cf, m.mean_cf,o.mean_env_hivdeleted AS mean_env, o.mean_pop,o2013.mean_env_whiv AS mean_env_2013, o2013.mean_pop AS mean_pop_2013, mv.description, mv.model_version_id
	FROM cod.model m
	INNER JOIN cod.model_version mv ON m.model_version_id = mv.model_version_id
	INNER JOIN
	 mortality.output o ON o.location_id = m.location_id AND o.year_id = m.year_id AND o.age_group_id = m.age_group_id AND o.sex_id = m.sex_id
	INNER JOIN
	 mortality.output_version ov ON o.output_version_id = ov.output_version_id AND ov.is_best = 1
	LEFT JOIN
	 mortality.output o2013 ON o2013.location_id = m.location_id AND o2013.year_id = m.year_id AND o2013.age_group_id = m.age_group_id AND o2013.sex_id = m.sex_id AND o2013.output_version_id=12
	WHERE mv.model_version_id in (`models_c') AND (m.age_group_id BETWEEN 2 AND 21)") `conn_string' clear ;
	#delimit cr
	
	//split into lowest level locations version and regional version
	merge m:1 location_id using `cfr_locs', assert(1 3)
	
	//generate age_group
	gen age_group = 1 if inrange(age_group_id,3,5)
	replace age_group = 2 if inrange(age_group_id, 6,7)
	replace age_group =3 if age_group ==.
	
	//generate the aggregate death rates
	preserve
		gen deaths = mean_cf * mean_env
		
		//aggreate deaths, env and pop and recreate death rate
		fastcollapse deaths mean_env mean_pop,type(sum) by(location_id year_id age_group sex_id)
		gen agg_dr =deaths/mean_pop
		keep location_id age_group year_id sex_id agg_dr
		tempfile agg
		save `agg', replace
	restore
	
	merge m:1 location_id age_group year_id sex_id using `agg', assert(3) nogen keepusing(agg_dr)
	

	//keep the cfr locations
	preserve
		keep if _merge==3
		
		//generate death rate
		gen codem_dr_loc = (mean_cf * mean_env)/mean_pop
		rename agg_dr agg_dr_loc
		//reduce number of columns
		keep location_id year_id sex_id age_group_id age_group mean_pop codem_dr_loc agg_dr_loc mean_env mean_pop
		rename mean_env as_loc_env
		rename mean_pop as_loc_pop
		tempfile dr_square
		save `dr_square', replace
	restore
	
	//keep the regions
	gen keeper = 0
	foreach rrr of local theregions{
		replace keeper =1 if location_id == `rrr'
	}
	
	keep if keeper == 1
	rename location_id region_id
	gen codem_dr_rgn = (mean_cf * mean_env)/mean_pop
	rename agg_dr agg_dr_rgn
	rename mean_env rgn_env
	keep region_id year_id sex_id age_group_id age_group mean_pop codem_dr_rgn agg_dr_rgn rgn_env
	rename mean_pop rgn_pop
	tempfile dr_region
	save `dr_region', replace
	
	
//Build the dataset. Start with the DR square, then the draws and then regional estimates
	use `dr_square', clear
	merge m:1 age_group location_id sex_id year_id using `cfr', assert(3) keep(3) nogen
	merge m:1 region_id age_group_id sex_id year_id using `dr_region', assert(3) keep(3) nogen

//Now all the various rates and what not are in. time to split some deaths
	//generate expected age specific deaths and age binned deaths
	
	gen expect_deaths = codem_dr_rgn * as_loc_pop
	bysort location_id year_id sex_id age_group: egen agg_expect_deaths = total(expect_deaths)
	forvalues i = 0/999{
		replace draw_`i' = expect_deaths * (draw_`i'/agg_expect_deaths)
	}

//save results requires the following fields: : location_id, year_id, sex_id, age_group_id, cause_id, and draw_0 – draw_999
keep location_id year_id sex_id age_group_id draw*
gen model_id = "CFR Model `model_version'"
save "J:\WORK\03_cod\02_models\02_results\malaria/cfr_results_model_`model_version'.dta", replace
	
	
	