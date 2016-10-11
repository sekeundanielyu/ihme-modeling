
/******************************************************************************\
           SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS
\******************************************************************************/

* BOILERPLATE *
  clear all
  set maxvar 10000
  set more off
  
  adopath + /home/j/WORK/10_gbd/00_library/functions
 
  tempfile appendTemp mergeTemp
  
  local model 49253

  

* PULL IN LOCATION_ID AND INCOME CATEGORY FROM BASH COMMAND *  
  local location "`1'"

  log using /home/j/WORK/04_epi/02_models/01_code/06_custom/hepatitis/hepCLogs/log_`location', replace
  
  
* SET UP OUTPUT DIRECTORIES *  
  local outDir /ihme/scratch/users/strUser/hepC


* SET UP LOCALS WITH MODELABLE ENTITY IDS AND AGE GROUPS *  
  local meid  1655
  local ages 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21


  
* CREATE EMPTY ROWS FOR INTERPOLATION *
  
  set obs `=_N + 2015 - 1979'
  generate year_id = _n + 1979
  drop if mod(year_id, 5)==0 & year>1989
  
  expand 20
  bysort year_id: generate age_group_id = _n + 1
  
  expand 2
  bysort year_id age_group_id: generate sex_id = _n
  
  save `appendTemp'
 
 
* DEFINE LOCALS WITH ALPHA AND BETA FOR CASE FATALITY *
  local cfAlpha = 3      // alpha and beta are derived using method of moments based on pooled 
  local cfBeta  = 2445    // case fatatily data from Stroffolini et al (1997) & Bianco et al 2003
  
  local chronicAlpha = 209.8232140700943
  local chronicBeta  = 69.34291421296759



  
/******************************************************************************\
                      PULL IN DRAWS AND MAKE CALCULATIONS
\******************************************************************************/
  
    * PULL IN DRAWS FROM DISMOD MODELS FOR HBsAG INCIDENCE AND PREVALENVCE *
      get_draws, gbd_id_field(modelable_entity_id) gbd_id(`meid') location_ids(`location') age_group_ids(`ages') measure_ids(5) source(dismod) status(`model') clear
      rename draw_* prev_*
      save `mergeTemp'
	  
      get_draws, gbd_id_field(modelable_entity_id) gbd_id(`meid') location_ids(`location') age_group_ids(`ages') measure_ids(6) source(dismod) status(`model') clear
      rename draw_* inc_*
      merge 1:1 age_group_id year_id sex_id using `mergeTemp', gen(merge56)
	  
	  

	
	* PERFORM DRAW-LEVEL CALCULATIONS TO SPLIT TYPHOID & PARATYPHOID, & CALCULATE MRs *
      forvalues i = 0/999 {
	    quietly {
		local cfTemp = rbeta(`cfAlpha', `cfBeta') 
		local chronicTemp = rbeta(`chronicAlpha', `chronicBeta') 
		
		replace  inc_`i' = (inc_`i' * (1 - prev_`i')) 
		
		generate prevChronic_`i' = prev_`i' * `chronicTemp'
		generate incChronic_`i'  = inc_`i' * `chronicTemp'
		
		generate draw_`i' = inc_`i' * `cfTemp' // multiply by case fatality to estimate mortality rate
        }
        }
		
	  drop prev_*


	
/******************************************************************************\
                             INTERPOLATE DEATHS
\******************************************************************************/			

  append using `appendTemp'
	
  fastrowmean draw_*, mean_var_name(drawMean)		
	
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


	  foreach var of varlist draw_* {
		quietly {
		bysort age_group_id sex_id (year_id): replace `var' = `var'[`indexStart'] * exp(ln(drawMean[`indexEnd']/drawMean[`indexStart']) * (`index'-`indexStart') / (`indexEnd'-`indexStart')) if year_id==`year'
		replace  `var' = 0 if missing(`var') & year_id==`year'
        }
		
		di "." _continue
		}
	}
		
		
/******************************************************************************\
                    EXPORT FILES AND PERFORM SEQUELA SPLITS
\******************************************************************************/		
		
	* EXPORT DEATHS *
	forvalues year = 1980/2015 {
     forvalues sex = 1/2 {
        export delimited age_group_id draw_* using `outDir'/death/death_`location'_`year'_`sex'.csv if sex_id==`sex' & year_id==`year', replace
  	    }
      }
	
	drop draw_*
	
	
	keep if mod(year_id,5)==0 & year_id>=1990
	

	
	* EXPORT CHRONIC PREVALENCE DRAWS *	
    rename incChronic_* draw_*
  	forvalues year = 1990(5)2015 {
      forvalues sex = 1/2 {
        export delimited age_group_id draw_* using `outDir'/chronic/6_`location'_`year'_`sex'.csv if sex_id==`sex' & year_id==`year', replace
	    }
	  }
	drop draw_*
	
	rename prevChronic_* draw_*
  	forvalues year = 1990(5)2015 {
      forvalues sex = 1/2 {
        export delimited age_group_id draw_* using `outDir'/chronic/5_`location'_`year'_`sex'.csv if sex_id==`sex' & year_id==`year', replace
	    }
	  }
	drop draw_*
	
	
	* SET UP SEQUELA SPLIT *
    expand 3
    bysort age_group_id year_id sex_id: generate index = _n

    generate state = "inf_mod" if index==1
    replace  state = "inf_sev" if index==2
    replace  state = "_asymp"  if index==3
	 
    local inf_mod  0.24 .06
    local inf_sev  0.01 .0025
    local _asymp   0.75 .1875

    foreach state in inf_mod inf_sev _asymp {
      gettoken mu sigma: `state'
	  local `state'Alpha = `mu' * (`mu' - `mu'^2 - `sigma'^2) / `sigma'^2 
      local `state'Beta  = ``state'Alpha' * (1 - `mu') / `mu' 
	  }
	 
    * SPLIT OUT INCIDENCE *	 
    forvalues i = 0 /999 {
	
	  local correction = 0
	  foreach state in inf_mod inf_sev _asymp {
	    local `state'Pr = rbeta(``state'Alpha', ``state'Beta')
		local correction = `correction' + ``state'Pr'
		}
	  
	  foreach state in inf_mod inf_sev _asymp {
	    local `state'Pr = ``state'Pr' / `correction'
		quietly replace inc_`i' = inc_`i' * ``state'Pr'  if state=="`state'"
	    }

	  }
	  
	  rename inc_* draw_*
	 
      * EXPORT SEQUELA INCIDENCE DRAWS *
	  foreach state in inf_mod inf_sev _asymp {
		forvalues year = 1990(5)2015 {
        forvalues sex = 1/2 {
          export delimited age_group_id draw_* using `outDir'/`state'/6_`location'_`year'_`sex'.csv if state=="`state'" & sex_id==`sex' & year_id==`year', replace
		  }
		 }
		}
			
			
	  * CALCULATE PREVALENCE *	
		forvalues i = 0/999 {
	   	  quietly replace draw_`i' = draw_`i' * 6 /52 
		  }
			
			
	  * EXPORT SEQUELA PREVALENCE DRAWS *	
	  foreach state in inf_mod inf_sev _asymp {
		forvalues year = 1990(5)2015 {
        forvalues sex = 1/2 {
          export delimited age_group_id draw_* using `outDir'/`state'/5_`location'_`year'_`sex'.csv if state=="`state'" & sex_id==`sex' & year_id==`year', replace
		  }
		 }
		}
		


  
  log close
 