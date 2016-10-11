
/******************************************************************************\
           SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS
\******************************************************************************/

* BOILERPLATE *
  clear all
  set maxvar 10000
  set more off
  
  adopath + /home/j/WORK/10_gbd/00_library/functions

* PULL IN LOCATION_ID AND INCOME CATEGORY FROM BASH COMMAND *  
  local location "`1'"
  local income   "`2'"
  local model    "`3'"

  log using /home/j/WORK/04_epi/02_models/01_code/06_custom/intest/logs/log_`location', replace
  
* SET UP OUTPUT DIRECTORIES *  
  local rootDir     /ihme/scratch/users/strUser/intest_b
  local outDir_para `rootDir'/paratyphoid
  local outDir_typh `rootDir'/typhoid

* SET UP LOCALS WITH MODELABLE ENTITY IDS *  
  local inc_meid  2523
  local typh_meid 1247
  local para_meid 1252
  
  local typh_cid 319
  local para_cid 320
  
  local typh_inf_mod_meid 1249
  local typh_inf_sev_meid 1250
  local typh_abdom_sev_meid 1251
  local typh_gastric_bleeding_meid 3134
  
  local para_inf_mild_meid 1253
  local para_inf_mod_meid 1254
  local para_inf_sev_meid 1255
  local para_abdom_mod_meid 1256

  local ages 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21

 
  tempfile appendTemp mergeTemp

  
* CREATE EMPTY ROWS FOR INTERPOLATION *
  
  set obs `=_N + 2015 - 1979'
  generate year_id = _n + 1979
  drop if mod(year_id, 5)==0 & year>1989
  
  expand 20
  bysort year_id: generate age_group_id = _n + 1
  
  expand 2
  bysort year_id age_group_id: generate sex_id = _n
  
  save `appendTemp'
  

  
/******************************************************************************\
                      PULL IN DRAWS AND MAKE CALCULATIONS
\******************************************************************************/
  
    * PULL IN DRAWS FROM DISMOD MODELS FOR OVERALL INCIDENCE, PR TYPHOID & PR PARATYPHOID *
      foreach x in inc typh para {
	    if "`x'" == "inc" {
		  get_draws, gbd_id_field(modelable_entity_id) gbd_id(``x'_meid') location_ids(`location') age_group_ids(`ages') source(dismod) status(`model') clear
		  }
		  
        else {
		  get_draws, gbd_id_field(modelable_entity_id) gbd_id(``x'_meid') location_ids(`location') age_group_ids(`ages') source(dismod) status(best) clear
		  }
		  
        rename draw_* `x'_*
  
        if "`x'" != "inc" merge 1:1 age_group_id year_id sex_id using `mergeTemp', assert(3) nogenerate
        save `mergeTemp', replace
        }

	* MERGE IN CASE FATALITY DATA *  
      merge m:1 age_group_id using /ihme/scratch/users/strUser/intest/inputs/cfDraws_`location'.dta, assert(3) nogenerate

	
	* PERFORM DRAW-LEVEL CALCULATIONS TO SPLIT TYPHOID & PARATYPHOID, & CALCULATE MRs *
      forvalues i = 0/999 {
	    quietly {
		  replace inc_`i' = 0 if age_group_id<3   
		  replace inc_`i' = inc_`i'/2 if age_group_id==3  
		  
      	  replace typh_`i' = inc_`i' * typh_`i' / (typh_`i' + para_`i')
          replace para_`i' = inc_`i' - typh_`i'
  
          replace cf_typh_`i' = cf_typh_`i' * typh_`i'
          replace cf_para_`i' = cf_para_`i' * para_`i'
          }
        }

		
		
       rename inc_* draw_*
	   replace measure_id = 6
	   replace modelable_entity_id = `inc_meid'
	   replace location_id = `location'
	   outsheet location_id year_id sex_id age_group_id modelable_entity_id measure_id draw_* using `rootDir'/parent/6_`location'.csv, comma replace
       rename draw_* inc_*
        
	  
    
	
/******************************************************************************\
                             INTERPOLATE DEATHS
\******************************************************************************/			

append using `appendTemp'

foreach type in typh para {

  fastrowmean cf_`type'_*, mean_var_name(cfMean_`type')	
	
  forvalues year = 1980/2015 {
	
	local index = `year' - 1979

	if `year'< 1990  {
	  local indexStart = 1990 - 1979
	  local indexEnd   = 2015 - 1979
	  }	
	  
	else {
	  local indexStart = 5 * floor(`year'/5) - 1979
	  local indexEnd   = 5 * ceil(`year'/5)  - 1979
	  if `indexStart'==`indexEnd' continue
	  }

  
	foreach var of varlist cf_`type'_* {
		quietly {
		bysort age_group_id sex_id (year_id): replace `var' = `var'[`indexStart'] * exp(ln(cfMean_`type'[`indexEnd']/cfMean_`type'[`indexStart']) * (`index'-`indexStart') / (`indexEnd'-`indexStart')) if year_id==`year'
		replace  `var' = 0 if missing(`var') & year_id==`year'
        }
		
		di "." _continue
		}	
	}
  }
			
		
		
		
/******************************************************************************\
                    EXPORT FILES AND PERFORM SEQUELA SPLITS
\******************************************************************************/		
		
* EXPORT DEATHS *
  capture generate cause_id = .

   foreach x in typh para {
     rename cf_`x'_* draw_* 
     replace measure_id = 1
     replace cause_id = ``x'_cid'
	 replace location_id = `location'
	 outsheet location_id year_id sex_id age_group_id cause_id measure_id draw_* using `outDir_`x''/death/death_`location'.csv, comma replace
     drop draw_*
	 }
        

	
	drop cause_id measure_id
	keep if mod(year_id,5)==0 & year_id>=1990
	
	* BRING IN SEQUELA SPLIT DATA *
	  cross using /ihme/scratch/users/strUser/intest/inputs/sequela_splits_`location'.dta
	
	  levelsof state_para, clean local(state_para)
	  levelsof state_typh, clean local(state_typh)
	  
	  
	  
    * SPLIT OUT INCIDENCE *
	  foreach x in typh para {
	    forvalues i = 0/999 {
	   	  quietly {
		  
		    generate splitTemp = rbeta(alpha_`x', beta_`x')
            bysort age_group_id year_id sex_id: egen correction = total(splitTemp)
	        replace splitTemp  = splitTemp / correction
	 
		    replace `x'_`i' = `x'_`i' * splitTemp
			
			drop splitTemp correction
			}
	      }
		 }
		 
		expand 2, gen(measure_id)
		replace measure_id = measure_id + 5
		
	    * CALCULATE PREVALENCE *	
		foreach x in typh para {
		  forvalues i = 0/999 {
	   	    quietly replace `x'_`i' = `x'_`i' * 6 /52  if measure_id==5   // apply six-weeks duration
		    }
		  }
		
		
		
		
      * EXPORT SEQUELA INCIDENCE DRAWS *
	  	
		foreach x in typh para {
		  rename `x'_* draw_*
   	      foreach state of local state_`x' {
		    replace modelable_entity_id = ``x'_`state'_meid'
			replace location_id = `location'
            outsheet location_id year_id sex_id age_group_id modelable_entity_id measure_id draw_* using `outDir_`x''/`state'/full_`location'.csv if state_`x'=="`state'", comma replace
		    }
		  drop draw_*
		  }
		
					

  
  log close
  
  
  
