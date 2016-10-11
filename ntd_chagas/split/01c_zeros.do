	
	
/******************************************************************************\
           SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS
\******************************************************************************/

* BOILERPLATE *
  clear all
  set maxvar 12000
  set more off
  
  adopath + /home/j/WORK/10_gbd/00_library/functions
 
  tempfile appendTemp mergeTemp

  

* PULL IN LOCATION_ID AND INCOME CATEGORY FROM BASH COMMAND *  
  local location "`1'"

  capture log close
  log using /home/j/WORK/04_epi/02_models/01_code/06_custom/chagas/logs/log_`location', replace
  
  
* SET UP OUTPUT DIRECTORIES *  
  local outDir /ihme/scratch/users/strUser/chagas

  
* CREATE ZERO DRAW FILE FOR EXCLUDED LOCATIONS *
  set obs 20
  generate age_group_id = _n+1
  forvalues i = 0 / 999 {
    generate draw_`i' = 0
	}
  
  expand 6
  bysort age_group_id: gen year_id = (_n * 5) + 1985
  
  expand 2, gen(sex_id)
  replace sex_id = sex_id + 1
  
  generate measure_id = 5
  generate location_id = `location'
  
 

 * EXPORT CHRONIC PREV ESTIMATES *
 foreach seq in digest_mild digest_mod hf afib asymp  {
   export delimited using /ihme/scratch/users/strUser/chagas/`seq'/`seq'_`location'.csv, replace
   }
	   
	
	
* CREATE AND EXPORT ACUTE FILE *	
  expand 2, gen(newObs)
  replace measure_id = measure_id + newObs
  drop newObs
	  
  export delimited using /ihme/scratch/users/strUser/chagas/acute/acute_`location'.csv, replace

  export delimited location_id year_id sex_id age_group_id measure_id draw_* using /ihme/scratch/users/strUser/chagas/total/total_`location'.csv, replace
  
  log close
	
	 
