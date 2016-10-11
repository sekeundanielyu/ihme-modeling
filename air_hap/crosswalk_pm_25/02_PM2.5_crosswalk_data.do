**Solid fuel and PM2.5 crosswalk
**Purpose: Explore data to select covariates and build model to generate PM2.5 crosswalk values
// none of the covariates are significant with pm 2.5 levels 

//Housekeeping
clear all
set maxvar 30000
set more off 

//Set directories
	if c(os) == "Windows" {
		global j "J:"
		global i "I:"
		set mem 1g
	}
	if c(os) == "Unix" {
		global j "/home/j"
		global i "/home/i"
		set mem 2g
		set odbcmgr unixodbc
	}

//Set relevant locals
local date 					"11May2016"
local date_out				"5Aug2016"
local pm_home_2013			"$j/WORK/2013/05_risk/01_database/02_data/air_hap/02_rr/04_models"
local pm_home_2015			"$j/WORK/05_risk/risks/air_hap/02_rr/02_output/PM2.5 mapping/lit_db"
local microdata				"$j/WORK/05_risk/risks/air_hap/02_rr/02_output/PM2.5 mapping/microdata/predict_pm_draws_`date'.dta" // pm 2.5 level predicted from DHS surveys

// set indicators for actions 
local compare 0 // whether to compare crosswalked data with original data 
local test_cov 0 // test the association with pm2.5 level and covariates from cov database 


***************************************************
*** PERFORM CROSSWALKS TO STANDARDIZE DATASET
***************************************************
// want all observations to be equivalent to area estimates for 24 hour periods --> cross walk kitchen, personal_exp, measure_std variables 
// Import dataset
	use "`pm_home_2015'/PM2.5_data_`date'.dta", clear 
	gen orig_se = pm_se
	gen orig_mean = pm_mean
	tempfile data
	save `data', replace

// 1. Other room to kitchen level exposure crosswalk:
// only want to adjust or crosswalk values if they are for area estimates (personal_exp == 0 and kit == 0)
	// break out subset of data that you want to crosswalk (only want to crosswalk area measures. from any other space to kitchen over a 24 hour pd bc all nonkitchen measures are for 24 hours)
	keep if personal_exp == 0 & measure_std == 1 

	* // test whether to do regression on pm_mean or logpm
	* *regress pm_mean kit 
	* // rvfplot // --> use regression in log
	* regress logpm kit 
	
	* // adjust data
	* set seed 14714831 
	* forvalues n = 1/1000 {
	* 	qui gen draw_`n' = rnormal(_b[kit], _se[kit])  // get 1000 draws for coefficient
	* 	qui gen ln_adjusted_`n' = logpm - (draw_`n' * (kit - 1)) // adjust non-kitchen values up to kitchen levels
	* 	qui gen exp_adjusted_`n' = exp(ln_adjusted_`n') // inverse log 
 * }

	* egen ln_mean_draws = rowmean(ln_adjusted_*) // get mean from the draws (log form)
	* egen exp_mean_draws = rowmean(exp_adjusted_*) // get mean from the draws (normal form)
	* egen exp_se_draws = rowsd(exp_adjusted_*) // get sd from the draws (normal form)
	
	* drop draw_* *adjusted_*

	* // replace non-kitchen values with adjusted values
	* replace logpm = ln_mean_draws if kit == 0
	* replace pm_mean = exp_mean_draws if kit == 0
	* replace pm_se = exp_se_draws if kit == 0
	
	* drop ln_mean_draws exp_mean_draws exp_se_draws
	
	tempfile adjusted
	save `adjusted', replace
	
	// append in the adjusted values to the data set
	use `data', clear
	drop if personal_exp == 0 & measure_std == 1
	append using `adjusted'
	
	tempfile kit_adjusted_data
	save `kit_adjusted_data', replace
	

* // 2. NON 24 HOUR TO 24 HOUR MEASUREMENTS; PERSONAL EXP TO AREA EXP; COOKING TIME MEASURES TO NONCOOKING CROSSWALK	
* 	// test each adjustment independently to make sure it is significant
* 		// test in both normal and log space
* 		** regress pm_mean measure_std
* 		** hettest
* 		** // rvfplot
* 		** regress logpm measure_std
	
* 		** regress pm_mean personal_exp
* 		** hettest
* 		** // rvfplot
* 		** regress logpm personal_exp
		
* 		** regress pm_mean cooking
* 		** regress logpm cooking
	
* 	*regress pm_mean measure_std personal_exp cooking
* 	*hettest
* 	// rvfplot
* 	regress logpm measure_std personal_exp cooking // use this regression
	
* 	// extract variance covariance matrix and generate draws of betas since there are multiple coefficients 
* 	// create a columnar matrix (rather than default, which is row) by using the apostrophe
* 		matrix m = e(b)'
* 	// store the covariance matrix 
* 		matrix C = e(V)
* 	// drop constants from dummies in both the m and C matrices. 
* 		matrix m = m[1..(rowsof(m)-1), 1]
* 		matrix C = C[1..(rowsof(C)-1), 1..(colsof(C)-1)]
	
* 	// create a local that corresponds to the variable name for each parameter
* 		local covars: rownames m
* 	// create a local that corresponds to total number of parameters
* 		local num_covars: word count `covars'
* 	// create an empty local that you will fill with the name of each beta (for each parameter)
* 			local betas
* 	// fill in this local
* 		forvalues j = 1/`num_covars' {
* 			local this_covar: word `j' of `covars'
* 			local covar_fix=subinstr("`this_covar'","b.","",.)
* 			local covar_rename=subinstr("`covar_fix'",".","",.)
* 			local betas `betas' b_`covar_rename'
* 			//"
* 		}
			
* 	set obs 1000		
* 	// use the "drawnorm" function to create draws using the mean and standard deviations from your covariance matrix
* 		drawnorm `betas', means(m) cov(C) seed(57707621) 

* 	// crosswalk. Adjusting values coded as 0 for measure std to be equivalent to if they were coded as 1. 
* 	// adjusting values coded as 1 for personal exp to be equivalent to if they were coded as 0 (area measurments)
* 	// adjsuting values coded as 1 for cooking to be equivalent to if they were coded as 0 (non-cooking measurments)
	
* 	// new logpm = logpm + (b_measstd *(1-meas_std)) + (b_personalexp*(0-personalexp))
* 	forvalues n = 1/1000 {
* 		// Adjust to be 24 hour kitchen estimates (personal_exp = 0)
* 		qui gen ln_draw_`n' = logpm + ( b_measure_std[`n'] * (1-measure_std)) + (b_personal_exp[`n'] * (0 - personal_exp)) + (b_cooking[`n'] * (0 - cooking)) //!!!!!!!!!!!!!!!!!!!!!!!!
* 		qui gen adjusted_draw_`n' = exp(ln_draw_`n')
	
* 	}
* 	// drop empty observations
* 	drop if ln_draw_1 == .
* 	// compute means/sd
* 	egen ln_mean = rowmean(ln_draw_*)
* 	egen area_mean = rowmean(adjusted_draw_*)
* 	egen area_se = rowsd(adjusted_draw_*)
	
* 	drop ln_draw* adjusted_draw* b_* 
	
* 	// replace values in data set that needed to be crosswalked
* 	replace logpm = ln_mean if measure_std == 0 | personal_exp == 1 | cooking == 1
* 	replace pm_mean = area_mean if measure_std == 0 | personal_exp == 1 | cooking == 1
* 	replace pm_se = area_se if measure_std == 0 | personal_exp == 1 | cooking == 1
	
* 	drop ln_mean area_mean area_se 
	
* 	gen crosswalked = 1 if measure_std == 0 | personal_exp == 1 | cooking == 1 | kit == 0
* 	replace crosswalked = 0 if crosswalked == .

// remap locations
drop location_name 
	**CHINA**
	replace ihme_loc_id = "CHN_498" if title=="Air pollutants in"
	replace ihme_loc_id = "CHN_498" if title=="Indoor PM and CO concentrations in rural Guizhou, China"
	replace ihme_loc_id = "CHN_498" if title=="Relationship between pulmonary function and indoor air pollution from coal combustion among adult residents in an inner-city area of southwest China"
	replace ihme_loc_id = "CHN_509" if title=="A comparision of particulate matter from biomass - burning rural and non biomas-burning urban households in northeasten China"
	replace ihme_loc_id = "CHN_509" if title=="Source apportionment of air pollution exposures of rural Chinese women cooking with biomass fuels"
	replace ihme_loc_id = "CHN_518" if title=="Characterizations of particle-bound trace metals and polycyclic aromatic hydrocarbons (PAHs) within Tibetan tents of south Tibetan Plateau, China"
	replace ihme_loc_id = "CHN_518" if title=="Indoor air pollution from solid biomass fuels combustion in rural agricultural area of Tibet, China"
	replace ihme_loc_id = "CHN_518" if title=="Personal PM2.5 and indoor CO in nomadic tents using open and chimney biomass stoves on the Tibetan Plateau"
	replace ihme_loc_id = "CHN_520" if title=="Indoor air pollution and blood pressure in adult women living in rural China"
	replace ihme_loc_id = "CHN_520" if title=="Patterns and predictors of personal exposure to indoor air pollution from biomass combustion among women and children in rural China"
	replace ihme_loc_id = "CHN_520" if title=="Personal and Indoor PM 2.5 Exposure from Burning Solid Fuels in Vented and Unvented Stoves in a Rural Region of China with a High Incidence of Lung Cancer"
	replace ihme_loc_id = "CHN_520" if title=="Measurement and modeling of indoor air pollution in rural households with multiple stove interventions in Yunnan, China"

	**MEXICO**
	replace ihme_loc_id = "MEX_4653" if title=="Assessment of particulate concentrations from domestic biomass combustion in rural Mexico"
	replace ihme_loc_id = "MEX_4657" if title=="The Effect of Biomass Burning on Respiratory Symptoms and Lung Function in Rural Mexican Women"
	replace ihme_loc_id = "MEX_4658" if title=="Impact of patsari improved cookstoves on indoor air quality Michoacan, Mexico"
	replace ihme_loc_id = "MEX_4658" if title=="Indoor particle size distributions in homes with open fires and improved Patsari Cookstoves and improved Patsari cook stoves"
	replace ihme_loc_id = "MEX_4658" if title=="Reduction in personal exposures to particulate matter and carbon monoxide as a result of the installation of a Patsari improved cook stove in Michoacan Mexico"
	replace ihme_loc_id = "MEX_4658" if title=="The impact of improved wood-burning stoves on fine particulate matter concentrations in rural Mexican homes"

	**2015**
	**IND
	/* it is hard to decide because Bundelkhand crosses both Uttar Pradesh and Madhya Pradesh, with the larger portion lying in M.P.
	So for now I will label it as MP,rural, but need discussion*/
	replace ihme_loc_id="IND_43926" if title=="Impact of improved cookstoves on indoor air quality in the Bundelkhand region in India"
	replace ihme_loc_id="IND_43942" if title=="Activation of protein kinase B (PKB/Akt) and risk of lung cancer among rural women in India who cook with biomass fuel"
	replace ihme_loc_id="IND_43942" if title=="Assessment of DNA damage by comet assay and fast halo assay in buccal epithelial cells of Indian women chronically exposed to biomass smoke"
	replace ihme_loc_id="IND_43942" if title=="Changes in sputum cytology, airway inflammation and oxidative stress due to chronic inhalation of biomass smoke during cooking in premenopausal rural Indian women"
	replace ihme_loc_id="IND_43927" if title=="Characteristics of trace metals in fine (PM2.5) and inhalable (PM10) particles and its health risk assessment along with in-silico approach in indoor environment of India" & rural==1
	replace ihme_loc_id="IND_43891" if title=="Characteristics of trace metals in fine (PM2.5) and inhalable (PM10) particles and its health risk assessment along with in-silico approach in indoor environment of India" & rural==0
	replace ihme_loc_id="IND_43927" if title=="Impact of improved biomass cookstoves on indoor air quality near Pune, India"
	replace ihme_loc_id="IND_43942" if title=="Indoor Air Pollution from Biomass Burning Activates Akt in Airway Cells and Peripheral Blood Lymphocytes : A Study among Premenopausal Women in Rural India"
	replace ihme_loc_id="IND_43940" if title=="Indoor exposure to respirable particulate matter and particulate-phase PAHs in rural homes in North India"
	replace ihme_loc_id="IND_43940" if title=="Indoor/outdoor relationship of fine particles less than 2.5 mm (PM2.5) in residential homes locations in central Indian region" & rural==1
	replace ihme_loc_id="IND_43904" if title=="Indoor/outdoor relationship of fine particles less than 2.5 mm (PM2.5) in residential homes locations in central Indian region" & rural==0
	replace ihme_loc_id="IND_43940" if title=="Particulate matter concentrations and their related metal toxicity in rural residential environment of semi-arid region of India"
	replace ihme_loc_id="IND_43926" if title=="Quantitative Metrics of Exposure and Health for Indoor Air Pollution from Household Biomass Fuels in Guatemala and India" & pm_mean==1100
	replace ihme_loc_id="IND_43926" if title=="Quantitative Metrics of Exposure and Health for Indoor Air Pollution from Household Biomass Fuels in Guatemala and India" & pm_mean==390
	replace ihme_loc_id="IND_43942" if title=="Quantitative Metrics of Exposure and Health for Indoor Air Pollution from Household Biomass Fuels in Guatemala and India" & pm_mean==170
	replace ihme_loc_id="IND_43942" if title=="Quantitative Metrics of Exposure and Health for Indoor Air Pollution from Household Biomass Fuels in Guatemala and India" & pm_mean==1300
	replace ihme_loc_id="IND_43937" if title=="Quantitative Metrics of Exposure and Health for Indoor Air Pollution from Household Biomass Fuels in Guatemala and India" & pm_mean==130
	replace ihme_loc_id="IND_43937" if title=="Quantitative Metrics of Exposure and Health for Indoor Air Pollution from Household Biomass Fuels in Guatemala and India" & pm_mean==410
	replace ihme_loc_id="IND_43941" if title=="Quantitative Metrics of Exposure and Health for Indoor Air Pollution from Household Biomass Fuels in Guatemala and India" & pm_mean==460
	replace ihme_loc_id="IND_43941" if title=="Quantitative Metrics of Exposure and Health for Indoor Air Pollution from Household Biomass Fuels in Guatemala and India" & pm_mean==970
	replace ihme_loc_id="IND_43887" if title=="Women’s personal and indoor exposures to PM2.5 in Mysore, India: Impact of domestic fuel usage"
	replace ihme_loc_id="IND_43904" if title=="Seasonal trends of PM10, PM5.0, PM2.5 & PM1.0 in indoor and outdoor environments of residential homes located in North-Central India"
	replace ihme_loc_id="IND_43942" if title=="Systemic inflammatory changes and increased oxidative stress in rural Indian women cooking with biomass fuels"

	save "`pm_home_2015'/crosswalked_data_`date_out'.dta", replace 
	
	preserve 
	// append the PM 2.5 values predicted from DHS microdata: updated in 2015
	use "`microdata'",clear 
	// year 
	destring startyear,replace 
	destring endyear,replace 
	egen year_id = rowmean(startyear endyear)
	replace year_id = int(year_id)
	drop startyear endyear 
	// log transform pm 
	gen logpm=log(mean)
	rename mean pm_mean
	// title 
	gen str title="DHS"

	tempfile dhs 
	save `dhs',replace 
	restore 

	append using `dhs'

// get location infomation (location_id location_name region_id super_regon_id
	preserve 
	clear 
	include "J:/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
	get_location_metadata, location_set_id(9)
	keep if level>=3
	keep ihme_loc_id location_name location_id super_region_id super_region_name region_id region_name 
	tempfile codes
	save `codes', replace 
	restore 

	merge m:1 ihme_loc_id using `codes', keep(3) nogen

	save "`pm_home_2015'/complete_data_`date_out'.dta", replace  // complete dataset for PM2.5 mapping values (w/o covairates)

*****************
***END OF CODE***
*****************


*** * *****************
*** COMPARE SE AMONG ORIGINAL DATA AND AFTER CROSSWALK
*** * **********************
	if `compare'==1 {
	// tag which observations had se measures before crosswalk
	gen has_both = 1 if orig_se != .

	summ pm_se if crosswalked == 1 & extract == 0 & orig_se != .
	local max1 = r(max)
	summ orig_se if crosswalked == 1 & extract == 0
	local max2 = r(max)
	local max = max(`max1', `max2')
	di `max'

	// scatter
	twoway scatter pm_se orig_se if  crosswalked == 1 & has_both == 1|| function y =x, range(0 `max') xtitle("Original SE") ytitle("SE after crosswalk")
}
*** * ******************************************************************
*** TEST REGRESSIONS WITH COUNTRY LEVEL COVARIATES AND LOCATION RE'S
*** ********************************************************************	
	if `test_cov'==1 {
// get covatiates from central covairates database 
	include "J:/WORK/10_gbd/00_library/functions/get_covariate_estimates.ado"
	local startyear 1980
	local endyear 2015

	**LDI**
	get_covariate_estimates, covariate_name_short(LDI_pc) clear
	rename mean_value ldi
	gen ln_ldi = ln(ldi)
	keep if year_id<=`endyear'
	keep if year_id>=`startyear'
	keep location_id location_name year_id sex_id ln_ldi
	tempfile ldi
	save `ldi', replace

	**maternal education**
	get_covariate_estimates, covariate_name_short(maternal_educ_yrs_pc) clear
	rename mean_value educ
	keep if year_id<=`endyear'
	keep if year_id>=`startyear'
	keep location_id location_name year_id sex_id educ
	tempfile meduc
	save `meduc', replace

	**Urbanicity**
	get_covariate_estimates, covariate_name_short(prop_urban) clear
	rename mean_value prop_urban
	keep if year_id<=`endyear'
	keep if year_id>=`startyear'
	keep location_id location_name year_id sex_id prop_urban
	tempfile urbanicity
	save `urbanicity', replace

	**Proportion of the population living above 1500m**
	get_covariate_estimates, covariate_name_short(pop_1500mplus_prop) clear
	rename mean_value prop_1500plus
	keep if year_id<=`endyear'
	keep if year_id>=`startyear'
	keep location_id location_name year_id sex_id prop_1500plus
	tempfile 1500plus
	save `1500plus', replace

	**Population weighted - average rainfall per year**
	get_covariate_estimates, covariate_name_short(rainfall_pop_weighted) clear
	rename mean_value rainfall_pop_weighted
	keep if year_id<=`endyear'
	keep if year_id>=`startyear'
	keep location_id location_name year_id sex_id rainfall_pop_weighted
	tempfile rainfall
	save `rainfall', replace

	**Temperature (90th percentile)
	get_covariate_estimates, covariate_name_short(temperature_90_perc) clear
	rename mean_value temperature_90_perc
	keep if year_id<=`endyear'
	keep if year_id>=`startyear'
	keep location_id location_name year_id sex_id temperature_90_perc
	tempfile temperature 
	save `temperature', replace
		
	**Average latitude 
	get_covariate_estimates, covariate_name_short(latitude) clear
	rename mean_value latitude
	keep if year_id<=`endyear'
	keep if year_id>=`startyear'
	keep location_id location_name year_id sex_id latitude
	tempfile latitude 
	save `latitude', replace
		
	**biomass prev covariate from gbd 2013
	get_covariate_estimates, covariate_name_short(pollution_indoor_biomass_prev) clear
	rename mean_value pollution_indoor_biomass_prev
	keep if year_id<=`endyear'
	keep if year_id>=`startyear'
	keep location_id location_name year_id sex_id pollution_indoor_biomass_prev
	tempfile biomass 
	save `biomass', replace
	
	**coal prev covariate from gbd 2013
	get_covariate_estimates, covariate_name_short(pollution_indoor_coal_prev) clear
	rename mean_value pollution_indoor_coal_prev
	keep if year_id<=`endyear'
	keep if year_id>=`startyear'
	keep location_id location_name year_id sex_id pollution_indoor_coal_prev
	tempfile coal 
	save `coal', replace

	/* not sure which one to use yet
	**COPD asdr for females(less likely to reflect smoking) from gbd 2010
		use "`pm_home'/output/pm_mapping/covariates/copd_asdr_timeseries.dta", clear
		rename final_death_rate copd_asdr_female
		tempfile copd
		save `copd', replace
		
		**Proportion of outdoor kitchens...not sure where did this come from?
		/* The location_id is not updated, ask Kara */
		use "`outdoor_kitchen_data'", clear
		rename locatio
		tempfile outdoor_kit
		save `outdoor_kit', replace
*/


	//Compile covariates
	use `ldi',clear 
	merge 1:1 location_id year_id using `meduc', keep(3) nogen
	merge 1:1 location_id year_id using `urbanicity', keep(3) nogen
	merge 1:1 location_id year_id using `1500plus', keep(3) nogen
	merge 1:1 location_id year_id using `rainfall', keep(3) nogen
	merge 1:1 location_id year_id using `temperature', keep(3) nogen
	merge 1:1 location_id year_id using `latitude', keep(3) nogen
	merge 1:1 location_id year_id using `biomass', keep(3) nogen
	merge 1:1 location_id year_id using `coal', keep(3) nogen
	*merge 1:1 iso3 year using `copd', keep(3) nogen
	
	tempfile covariates
	save `covariates', replace 

use "`pm_home_2015'/complete_data_`date'.dta", clear 
merge m:1 location_id year_id using `covariates', keep(3) nogen

// RUNNING REGRESSIONS

	mixed logpm educ || super_region_id: || region_id: || ihme_loc_id:  // non-significant
	
	mixed logpm ln_ldi || super_region_id: || region_id: || ihme_loc_id: // non-significant
	
	mixed logpm prop_urban || super_region_id: || region_id: || ihme_loc_id: // non-significant
	
	mixed logpm pollution_indoor_biomass_prev || super_region_id: || region_id: || ihme_loc_id: // non-significant
	
	*xtmixed logpm outdoor_kit_prop || super_region_id: || region_id: || ihme_loc_id: // ns
	
	mixed logpm prop_1500plus || super_region_id: || region_id: || ihme_loc_id: //
	
	mixed logpm rainfall_pop_weighted || super_region_id: || region_id: || ihme_loc_id: // ns
	
	mixed logpm temperature_90_perc || super_region_id: || region_id: || ihme_loc_id: // ns
	
	mixed logpm latitude || super_region_id: || region_id: || ihme_loc_id: // ns

	// try environmental vars with maternal_educ
	mixed logpm educ prop_1500plus || super_region_id: || region_id: || ihme_loc_id: // ns
	mixed logpm educ rainfall_pop_weighted || super_region_id: || region_id: || ihme_loc_id: // non-significant
	mixed logpm prop_1500plus rainfall_pop_weighted || super_region_id: || region_id: || ihme_loc_id: // non-significant
	mixed logpm educ prop_1500plus rainfall_pop_weighted || super_region_id: || region_id: || ihme_loc_id:, iterate(50) // significant,????
	
	mixed logpm educ temperature_90_perc || super_region_id: || region_id: || ihme_loc_id: // non-significant
	mixed logpm prop_1500plus temperature_90_perc || super_region_id: || region_id: || ihme_loc_id: // significant
	mixed logpm edu prop_1500plus temperature_90_perc || super_region_id: || region_id: || ihme_loc_id: // significant

	mixed logpm educ latitude || super_region_id: || region_id: || ihme_loc_id: // non-significant
	mixed logpm educ biomass_prev || gbd_superregion: || region_id: || ihme_loc_id: // non-significant
}

** // country level covariates that has prepped: biomass_prev, coal_prev, ln_ldi, maternal_educ, prop_urban, pop_1500mplus_prop, rainfall_pop_weighted, temperature_90_perc, latitude
** // test basic regressions to see which have strongest associations
	** local covars "biomass_prev coal_prev ln_ldi maternal_educ prop_urban pop_1500mplus_prop rainfall_pop_weighted temperature_90_perc latitude"
	** foreach covar of local covars {
		** di in red "`covar'"
		** regress pm_mean `covar'
		** hettest // other than ln_ldi, results of hettest for all other vars indicate that pm concentration should be in log
		** regress logpm `covar'
	** }

** // test combinations	
	** regress logpm ln_ldi maternal_educ // --> maternal edu and ln_ldi are collinear (should not be used together in model) (prop_urban is also collinear with both of these covs)
	
	** regress logpm ln_ldi coal_prev
	** regress logpm maternal_educ coal_prev // has more significant p values, slightly lower mse and slightly higher r-squared/adjusted r-squared
	
** // explore models with location random effects
	** xtmixed logpm maternal_educ || gbd_superregion: || gbd_region:
	** xtmixed logpm ln_ldi || gbd_superregion: || gbd_region:

	** xtmixed logpm maternal_educ coal_prev || gbd_superregion: || gbd_region:
	** xtmixed logpm maternal_educ biomass_prev || gbd_superregion: || gbd_region:

* ************************
* MATERNAL EDU ONLY 
* *******************************

	** use `crosswalked_data', clear
	** xtmixed logpm maternal_educ || gbd_superregion: || gbd_region: || iso3:
	
	** // predict re's and save in a dataset
	** predict re*, reffects
	** predict re_se*, reses
	
	** rename re1 re_super
	** rename re2 re_region
	** rename re3 re_iso3
	
	** rename re_se1 re_se_super
	** rename re_se2 re_se_region
	** rename re_se3 re_se_iso3
	
** // save datasets with the three levels of random effects
	** keep iso3 gbd_superregion gbd_region re*
	** preserve
	** keep gbd_superregion re_super re_se_super
	** duplicates drop
	** tempfile sr_re
	** save `sr_re', replace
	** restore
	** preserve
	** keep gbd_region re_region re_se_region
	** duplicates drop
	** tempfile region_re
	** save `region_re', replace
	** restore
	** preserve
	** keep iso3 re_iso3 re_se_iso3
	** duplicates drop
	** tempfile iso_re
	** save `iso_re', replace
	** restore
	
	** use `predict_data', clear
	** predict pred_mat_only
	** merge m:1 gbd_superregion using `sr_re'
	** drop _merge
	** merge m:1 gbd_region using `region_re'
	** drop _merge
	** merge m:1 iso3 using `iso_re'
	** drop _merge
	
	** replace re_super = 0 if re_super == .
	** replace re_region = 0 if re_region == .
	** replace re_iso = 0 if re_iso == .
	
	** replace pred_mat_only = pred_mat_only + re_super + re_region + re_iso
	
	** gen exp_mat_only = exp(pred_mat_only)
	
	** tempfile predict_data
	** save `predict_data', replace
	
* ************************
* MATERNAL EDU, COOKING 
* *******************************

	** use `crosswalked_data', clear
	** xtmixed logpm maternal_educ cooking || gbd_superregion: || gbd_region: || iso3:
	
	** // predict re's and save in a dataset
	** predict re*, reffects
	** predict re_se*, reses
	
	** rename re1 re_super
	** rename re2 re_region
	** rename re3 re_iso3
	
	** rename re_se1 re_se_super
	** rename re_se2 re_se_region
	** rename re_se3 re_se_iso3
	
** // save datasets with the three levels of random effects
	** keep iso3 gbd_superregion gbd_region re*
	** preserve
	** keep gbd_superregion re_super re_se_super
	** duplicates drop
	** tempfile sr_re
	** save `sr_re', replace
	** restore
	** preserve
	** keep gbd_region re_region re_se_region
	** duplicates drop
	** tempfile region_re
	** save `region_re', replace
	** restore
	** preserve
	** keep iso3 re_iso3 re_se_iso3
	** duplicates drop
	** tempfile iso_re
	** save `iso_re', replace
	** restore
	
	** use `predict_data', clear
	** predict pred_mat_cooking
	** drop re*
	** merge m:1 gbd_superregion using `sr_re'
	** drop _merge
	** merge m:1 gbd_region using `region_re'
	** drop _merge
	** merge m:1 iso3 using `iso_re'
	** drop _merge
	
	** replace re_super = 0 if re_super == .
	** replace re_region = 0 if re_region == .
	** replace re_iso = 0 if re_iso == .
	
	** replace pred_mat_cooking = pred_mat_cooking + re_super + re_region + re_iso
	
	** gen exp_mat_cooking = exp(pred_mat_cooking)
	
	** tempfile predict_data
	** save `predict_data', replace
	
* ************************
* MATERNAL EDU, COPD, COOKING 
* *******************************
	
	** use `crosswalked_data', clear
	** xtmixed logpm maternal_educ copd_asdr_female cooking || gbd_superregion: || gbd_region: || iso3:
	
	** // predict re's and save in a dataset
	** predict re*, reffects
	** predict re_se*, reses
	
	** rename re1 re_super
	** rename re2 re_region
	** rename re3 re_iso3
	
	** rename re_se1 re_se_super
	** rename re_se2 re_se_region
	** rename re_se3 re_se_iso3
	
** // save datasets with the three levels of random effects
	** keep iso3 gbd_superregion gbd_region re*
	** preserve
	** keep gbd_superregion re_super re_se_super
	** duplicates drop
	** tempfile sr_re
	** save `sr_re', replace
	** restore
	** preserve
	** keep gbd_region re_region re_se_region
	** duplicates drop
	** tempfile region_re
	** save `region_re', replace
	** restore
	** preserve
	** keep iso3 re_iso3 re_se_iso3
	** duplicates drop
	** tempfile iso_re
	** save `iso_re', replace
	** restore
	
	** use `predict_data', clear
	** predict pred_mat_copd_cooking
	** drop re*
	** merge m:1 gbd_superregion using `sr_re'
	** drop _merge
	** merge m:1 gbd_region using `region_re'
	** drop _merge
	** merge m:1 iso3 using `iso_re'
	** drop _merge
	
	** replace re_super = 0 if re_super == .
	** replace re_region = 0 if re_region == .
	** replace re_iso = 0 if re_iso == .
	
	** replace pred_mat_copd_cooking = pred_mat_copd_cooking + re_super + re_region + re_iso
	
	** gen exp_mat_copd_cooking = exp(pred_mat_copd_cooking)
	
	** tempfile predict_data
	** save `predict_data', replace
* ************************
* BIOMASS AND COOKING 
* *******************************
	** use `crosswalked_data', clear
	** xtmixed logpm biomass_prev cooking || gbd_superregion: || gbd_region: || iso3:
	
	** // predict re's and save in a dataset
	** predict re*, reffects
	** predict re_se*, reses
	
	** rename re1 re_super
	** rename re2 re_region
	** rename re3 re_iso3
	
	** rename re_se1 re_se_super
	** rename re_se2 re_se_region
	** rename re_se3 re_se_iso3
	
** // save datasets with the three levels of random effects
	** keep iso3 gbd_superregion gbd_region re*
	** preserve
	** keep gbd_superregion re_super re_se_super
	** duplicates drop
	** tempfile sr_re
	** save `sr_re', replace
	** restore
	** preserve
	** keep gbd_region re_region re_se_region
	** duplicates drop
	** tempfile region_re
	** save `region_re', replace
	** restore
	** preserve
	** keep iso3 re_iso3 re_se_iso3
	** duplicates drop
	** tempfile iso_re
	** save `iso_re', replace
	** restore
	
	** use `predict_data', clear
	** predict pred_biomass_cooking
	** drop re*
	** merge m:1 gbd_superregion using `sr_re'
	** drop _merge
	** merge m:1 gbd_region using `region_re'
	** drop _merge
	** merge m:1 iso3 using `iso_re'
	** drop _merge
	
	** replace re_super = 0 if re_super == .
	** replace re_region = 0 if re_region == .
	** replace re_iso = 0 if re_iso == .
	
	** replace pred_biomass_cooking = pred_biomass_cooking + re_super + re_region + re_iso
	
	** gen exp_biomass_cooking = exp(pred_biomass_cooking)
	
	** tempfile predict_data
	** save `predict_data', replace
* ************************
* BIOMASS, COOKING, ELEVATION 
* *******************************
	
		** use `crosswalked_data', clear
	** xtmixed logpm biomass_prev cooking pop_1500mplus_prop || gbd_superregion: || gbd_region: || iso3:
	
	** // predict re's and save in a dataset
	** predict re*, reffects
	** predict re_se*, reses
	
	** rename re1 re_super
	** rename re2 re_region
	** rename re3 re_iso3
	
	** rename re_se1 re_se_super
	** rename re_se2 re_se_region
	** rename re_se3 re_se_iso3
	
** // save datasets with the three levels of random effects
	** keep iso3 gbd_superregion gbd_region re*
	** preserve
	** keep gbd_superregion re_super re_se_super
	** duplicates drop
	** tempfile sr_re
	** save `sr_re', replace
	** restore
	** preserve
	** keep gbd_region re_region re_se_region
	** duplicates drop
	** tempfile region_re
	** save `region_re', replace
	** restore
	** preserve
	** keep iso3 re_iso3 re_se_iso3
	** duplicates drop
	** tempfile iso_re
	** save `iso_re', replace
	** restore
	
	** use `predict_data', clear
	** predict pred_biomass_elev_cooking
	** drop re*
	** merge m:1 gbd_superregion using `sr_re'
	** drop _merge
	** merge m:1 gbd_region using `region_re'
	** drop _merge
	** merge m:1 iso3 using `iso_re'
	** drop _merge
	
	** replace re_super = 0 if re_super == .
	** replace re_region = 0 if re_region == .
	** replace re_iso = 0 if re_iso == .
	
	** replace pred_biomass_elev_cooking = pred_biomass_elev_cooking + re_super + re_region + re_iso
	
	** gen exp_biomass_elev_cooking = exp(pred_biomass_elev_cooking)
	
	** tempfile predict_data
	** save `predict_data', replace
	
* ************************
* BIOMASS, COOKING, LDI 
* *******************************
	** use `crosswalked_data', clear
	** xtmixed logpm biomass_prev cooking ln_ldi || gbd_superregion: || gbd_region: || iso3:
	
	** // predict re's and save in a dataset
	** predict re*, reffects
	** predict re_se*, reses
	
	** rename re1 re_super
	** rename re2 re_region
	** rename re3 re_iso3
	
	** rename re_se1 re_se_super
	** rename re_se2 re_se_region
	** rename re_se3 re_se_iso3
	
** // save datasets with the three levels of random effects
	** keep iso3 gbd_superregion gbd_region re*
	** preserve
	** keep gbd_superregion re_super re_se_super
	** duplicates drop
	** tempfile sr_re
	** save `sr_re', replace
	** restore
	** preserve
	** keep gbd_region re_region re_se_region
	** duplicates drop
	** tempfile region_re
	** save `region_re', replace
	** restore
	** preserve
	** keep iso3 re_iso3 re_se_iso3
	** duplicates drop
	** tempfile iso_re
	** save `iso_re', replace
	** restore
	
	** use `predict_data', clear
	** predict pred_biomass_ldi_cooking
	** drop re*
	** merge m:1 gbd_superregion using `sr_re'
	** drop _merge
	** merge m:1 gbd_region using `region_re'
	** drop _merge
	** merge m:1 iso3 using `iso_re'
	** drop _merge
	
	** replace re_super = 0 if re_super == .
	** replace re_region = 0 if re_region == .
	** replace re_iso = 0 if re_iso == .
	
	** replace pred_biomass_ldi_cooking = pred_biomass_ldi_cooking + re_super + re_region + re_iso
	
	** gen exp_biomass_ldi_cooking = exp(pred_biomass_ldi_cooking)
