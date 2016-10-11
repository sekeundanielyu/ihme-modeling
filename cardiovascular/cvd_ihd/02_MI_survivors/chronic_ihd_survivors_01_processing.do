// SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS

// BOILERPLATE 
  clear all
  set maxvar 10000
  set more off
  
  adopath + "strPath/functions"
  
  tempfile cfr incidence


// PULL IN LOCATION_ID AND INCOME CATEGORY FROM BASH COMMAND
  local location "`1'"
	  
  capture log close
  log using strPath/log_survivors_`location', replace
  
	  
// SET UP OUTPUT DIRECTORIES
  local strPath/cvd_ihd/chronic_ihd_survivor

  
// SET UP LOCALS WITH MODELABLE ENTITY IDS AND AGE GROUPS *  
  local meid 1814
  local ages 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21

// PULL IN DRAWS AND MAKE CALCULATIONS
  
// Pull in draws for excess mortality and incidence
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(`meid') measure_ids(6 9) location_ids(`location') age_group_ids(`ages') status(best) source(dismod) clear
	// generate case fatality rate from excess mortality rate
		preserve
		keep if measure_id==9
		forvalues i = 0/999 {
			quietly generate cf_`i' = draw_`i'/(12+draw_`i') 
		}
		quietly save `cfr', replace
		restore
	// get incidence data
		keep if measure_id==6
		forvalues i = 0/999 {
			quietly rename draw_`i' incidence_`i' 
		}
		quietly save `incidence', replace

// Merge and transform data
		use `cfr', clear
		merge 1:1 age_group_id location_id year_id sex_id using `incidence', keep(3)
		levelsof location_id if _merge==1
		levelsof location_id if _merge==2
		
		forvalues i = 0/999 {
			generate chronic_incidence_`i' = incidence_`i' * (1-cf_`i')
		}
			fastrowmean chronic_incidence*, mean_var_name(mean)
			fastpctile chronic_incidence*, pct(2.5 97.5) names(lower upper)
				
save "strPath/mi_survivors_`location'.dta", replace

log close