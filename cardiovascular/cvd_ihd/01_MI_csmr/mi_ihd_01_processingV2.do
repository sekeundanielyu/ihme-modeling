// SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS

// BOILERPLATE 
  clear all
  set maxvar 10000
  set more off
  
  adopath + "strPath/functions"
 
  tempfile mi_ihd_ratio ihd_deaths


// PULL IN LOCATION_ID AND INCOME CATEGORY FROM BASH COMMAND
	local location "`1'"
	//local year "`2'"	
	capture log close
	log using strPath/logs/log_`location', replace
  
  
// SET UP OUTPUT DIRECTORIES
	local out_dir strPath/mi_to_IHD_csmr

  
// SET UP LOCALS WITH MODELABLE ENTITY IDS AND AGE GROUPS *  
	local meid 2570
	local causeid 493
	local ages 11 12 13 14 15 16 17 18 19 20 21

// PULL IN DRAWS AND MAKE CALCULATIONS
// Get population
	get_populations, location_id(`location') sex_id(1 2) age_group_id(`ages') year_id(1990 1995 2000 2005 2010 2015) clear
	tempfile pop_temp
	save `pop_temp'

// Pull in draws from DisMod proportion model
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(`meid') measure_ids(18) location_ids(`location') age_group_ids(`ages') status(best) source(dismod) clear
	forvalues i = 0/999 {
		quietly rename draw_`i' mi_ihd_ratio_`i'
	}
	save `mi_ihd_ratio', replace
	
// Get death data
	get_draws, gbd_id_field(cause_id) gbd_id(`causeid') location_ids(`location') age_group_ids(`ages') status(best) source(dalynator) measure_ids(1) clear
	keep if metric_id==1
	merge 1:1 sex_id age_group_id year_id using `pop_temp', keep(3) nogen
	forvalues i = 0/999 {
	    quietly replace draw_`i' = draw_`i'/pop_scaled //Change to death rate (total deaths/population)
		quietly rename draw_`i' ihd_deaths_`i' 
	}
	save `ihd_deaths', replace
	
	
// Merge and transform data
	// IHD deaths are used as the effective sample size (uncertainty) for this data, and MI deaths are the mean/proportion that we want
		use `mi_ihd_ratio', clear
		merge 1:1 age_group_id location_id year_id sex_id using `ihd_deaths', keep(3) nogen
				
		forvalues i = 0/999 {
			quietly replace mi_ihd_ratio_`i' = mi_ihd_ratio_`i' * ihd_deaths_`i'
			quietly replace ihd_deaths_`i' = ihd_deaths_`i' * pop_scaled //Re-convert deaths from rate-space to number space
		}
			fastrowmean mi_ihd_ratio_*, mean_var_name(mean)
			fastrowmean ihd_deaths_*, mean_var_name(sample_size)
			drop mi_ihd_ratio_* ihd_deaths_*
		
				
save "`out_dir'/csmr_mi_`location'.dta", replace

log close
