// SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS

// BOILERPLATE 
  clear all
  set maxvar 10000
  set more off
  
  adopath + "strPath/functions"
 
  tempfile appendtemp1 appendtemp2


// PULL IN LOCATION_ID AND INCOME CATEGORY FROM BASH COMMAND
  local location "`1'"
	  
  capture log close
  log using strPath/log_ihd_ratio_`location', replace
  
  
// SET UP OUTPUT DIRECTORIES
  local out_dir strPath/cvd_ihd/mi_to_IHD_csmr

  
// SET UP LOCALS WITH MODELABLE ENTITY IDS AND AGE GROUPS *  
  local meid 2570
  local causeid 493
  local ages 11 12 13 14 15 16 17 18 19 20 21

// PULL IN DRAWS AND MAKE CALCULATIONS
// Get population information
	get_populations, location_id(`location') sex_id(1 2) age_group_id(`ages') year_id(1990 1995 2000 2005 2010 2015) clear
	tempfile pop_temp
	save `pop_temp'
	
// Pull in draws from DisMod proportion model
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(`meid') measure_ids(18) location_ids(`location') age_group_ids(`ages') status(best) source(dismod) clear
	forvalues i = 0/999 {
		quietly generate chronic_ihd_ratio_`i' = 1 - draw_`i'
		drop draw_`i'
	}
	quietly save `appendtemp1', replace
	
// Get death data
	get_draws, gbd_id_field(cause_id) gbd_id(`causeid') location_ids(`location') age_group_ids(`ages') status(best) source(dalynator) measure_ids(1) clear
	keep if metric_id==1
	merge 1:1 sex_id age_group_id year_id using `pop_temp', keep(3) nogen
	forvalues i = 0/999 {
	    quietly replace draw_`i' = draw_`i'/pop
		quietly rename draw_`i' ihd_deaths_`i' 
	}
	
	quietly save `appendtemp2', replace

// Merge and transform data
		use `appendtemp1', clear
		merge 1:1 age_group_id location_id year_id sex_id using `appendtemp2', keep(3) nogen
		
		
		forvalues i = 0/999 {
			replace chronic_ihd_ratio_`i' = chronic_ihd_ratio_`i' * ihd_deaths_`i'
			replace ihd_deaths_`i' = ihd_deaths_`i' * pop //Re-convert deaths from rate-space to number space
		}
			fastrowmean chronic_ihd_ratio_*, mean_var_name(mean)
			fastrowmean ihd_deaths_*, mean_var_name(sample_size)
			drop chronic_ihd_ratio_* ihd_deaths_*
		
				
save "strPath/csmr_ihd_`location'.dta", replace

log close