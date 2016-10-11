	
	
/******************************************************************************\
           SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS
\******************************************************************************/

* BOILERPLATE *
  clear all
  set maxvar 12000
  set more off
  
  adopath + /home/j/WORK/10_gbd/00_library/functions
 
  tempfile appendTemp mergeTemp prevalence incidence

  

* PULL IN LOCATION_ID AND INCOME CATEGORY FROM BASH COMMAND *  
  local location "`1'"
  local endemic  "`2'"

  capture log close
  log using /home/j/WORK/04_epi/02_models/01_code/06_custom/chagas/logs/log_`location', replace
  
  
* SET UP OUTPUT DIRECTORIES *  
  local outDir /ihme/scratch/users/stanaway/chagas


* SET UP LOCALS WITH MODELABLE ENTITY IDS AND AGE GROUPS *  
  local meid  1450
  local ages 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21
	

  
/******************************************************************************\
                      PULL IN DRAWS AND MAKE CALCULATIONS
\******************************************************************************/
  
    * PULL IN DRAWS FROM DISMOD MODELS FOR INCIDENCE AND PREVALENVCE *
      if `endemic'==0 {
	    use `outDir'/inputs/prev_`location'.dta, clear
		generate measure_id = 5
		rename draw_* prev_*
	    }
		
	  else if inlist(`location', 98, 99) {
	    do /home/j/WORK/04_epi/02_models/01_code/06_custom/chagas/code/01b_elimination.do "`location'"
		}

	  else {
	    get_draws, gbd_id_field(modelable_entity_id) gbd_id(`meid') source(dismod) location_ids(`location') age_group_ids(`ages') measure_ids(5) status(best) clear
        rename draw_* prev_*
		}
		
      save `mergeTemp'
	  
	  preserve
	  rename prev_* draw_*
	  keep location_id year_id sex_id age_group_id measure_id draw_* 
      save `prevalence'
	  restore
  
	  merge m:1 age_group_id sex_id using /ihme/scratch/users/strUser/chagas/inputs/chronicPr_`location'.dta

	  
	  
	  rename prHf* hf*
	  rename afibPr* afib*
	  
	  forvalues i = 0 / 999 {
		quietly {
		generate digest_mild_`i' = digest_`i' * 0.6   
		generate digest_mod_`i'  = digest_`i' * 0.4
		drop digest_`i'
		}
	    }

	  

	
	* PERFORM DRAW-LEVEL CALCULATIONS  *
	  forvalues i = 0 / 999 {
		    quietly {

			foreach seq in hf afib digest_mild digest_mod {
			  replace `seq'_`i' = `seq'_`i' * prev_`i'
			  replace `seq'_`i' = 0 if `seq'_`i'==0 | missing(`seq'_`i')
			  }

			}
		    }
			
			
			
	 
	 foreach seq in digest_mild digest_mod hf afib {
	   rename `seq'_* draw_*
       export delimited location_id year_id sex_id age_group_id measure_id draw_* using /ihme/scratch/users/strUser/chagas/`seq'/`seq'_`location'.csv, replace
	   drop draw_*
	   }
	   
	 
	 
	 
*ACUTE*	 
   if `endemic'==0 {
	  clear
      set obs 20
      generate age_group_id = _n+1
      forvalues i = 0 / 999 {
        generate draw_`i' = 0
	    }
  
      expand 6
      bysort age_group_id: gen year_id = (_n * 5) + 1985
      
      expand 2, gen(sex_id)
      replace sex_id = sex_id + 1
  
      generate measure_id  = 6
	  generate location_id = `location'
	  
	  save `incidence' 
	  }
		

  
    else {	 
	  get_draws, gbd_id_field(modelable_entity_id) gbd_id(`meid') source(dismod) location_ids(`location') age_group_ids(`ages') measure_ids(6) status(best) clear

	  if inlist(`location', 98, 99) {
	    if `location' == 98 local eYear 1999
        else if `location' == 99 local eYear 1997
		  
		forvalues i = 0 / 999 {
		  quietly replace draw_`i' = 0  if year_id>=`eYear'
		  }
	    }
			 
		  
	  save `incidence' 
	  }
	  
	expand 2, gen(newObs)
	replace measure_id = measure_id - newObs
	  
  	forvalues i = 0 / 999 {
	 quietly {
		local prAcute = rbeta(10, 190)
		replace draw_`i' = draw_`i' * `prAcute'
		replace draw_`i' = draw_`i' * 6/52 if measure_id==5
		}
	  }
		
	  keep location_id year_id sex_id age_group_id measure_id draw_* 
	  
	
    export delimited using /ihme/scratch/users/strUser/chagas/acute/acute_`location'.csv, replace
	
	clear 
	append using `prevalence' `incidence'
	

	
	export delimited location_id year_id sex_id age_group_id measure_id draw_* using /ihme/scratch/users/strUser/chagas/total/total_`location'.csv, replace

	log close
	
	 
