
/******************************************************************************\
           SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS
\******************************************************************************/

* BOILERPLATE *
  clear all
  set maxvar 10000
  set more off
  
  adopath + /home/j/WORK/10_gbd/00_library/functions
 
  tempfile appendTemp mergeTemp

  

* PULL IN LOCATION_ID AND INCOME CATEGORY FROM BASH COMMAND *  
  local location "`1'"

  capture log close
  log using /home/j/WORK/04_epi/02_models/01_code/06_custom/hepatitis/hepBLogs/log_`location', replace
  
  
* SET UP OUTPUT DIRECTORIES *  
  local outDir /ihme/scratch/users/strUser/hepB


* SET UP LOCALS WITH MODELABLE ENTITY IDS AND AGE GROUPS *  
  local meid  1651
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
  local cfAlpha = 40 + 18       // alpha and beta are derived from
  local cfBeta  = 7907 + 4257   // case fatatily data from Stroffolini et al (1997) & Bianco et al 2003


  
/******************************************************************************\
                      PULL IN DRAWS AND MAKE CALCULATIONS
\******************************************************************************/
  
    * PULL IN DRAWS FROM DISMOD MODELS FOR HBsAG INCIDENCE AND PREVALENVCE *
      get_draws, gbd_id_field(modelable_entity_id) gbd_id(`meid') source(dismod) location_ids(`location') age_group_ids(`ages') measure_ids(5) status(best) clear
      rename draw_* prev_*
      save `mergeTemp'
	  
      get_draws, gbd_id_field(modelable_entity_id) gbd_id(`meid') source(dismod) location_ids(`location') age_group_ids(`ages') measure_ids(6) status(best) clear
      rename draw_* incCarrier_*
      merge 1:1 age_group_id year_id sex_id using `mergeTemp', gen(merge56)
	  
	  
	  merge m:1 age_group_id using /ihme/scratch/users/strUser/hepB/inputs/hepB_chronic2acute_`location'.dta

	 
	  fastrowmean incCarrier_*, mean_var_name(incCarrierMean) 
      fastrowmean prev_*, mean_var_name(prevMean) 

      sort location_id sex_id age_group_id year_id

      by location_id sex_id age_group_id (year_id): gen inc1995   = incCarrierMean[2] if year_id>1995
      by location_id sex_id age_group_id (year_id): gen prevRatio = prevMean / prevMean[2] if year_id>1995

      



	
	* PERFORM DRAW-LEVEL CALCULATIONS TO SPLIT TYPHOID & PARATYPHOID, & CALCULATE MRs *
      forvalues i = 0/999 {
	    quietly {
		by location_id sex_id age_group_id (year_id): replace incCarrier_`i' = inc1995 * prevRatio * incCarrier_`i' / incCarrierMean if year_id>1995
		
		generate inc_`i' = (incCarrier_`i' * (1 - prev_`i'))  / rbeta(prCarrierAlpha, prCarrierBeta)  // divide incidence by probability of becoming a carrier to convert incidence of carrier state to total incidence
		generate acute_`i' = inc_`i' * rbeta(prAcuteAlpha, prAcuteBeta) // multiply by the probability of having symptomatic acute illness to incidence of symptomatic acute infection
		generate draw_`i' = acute_`i' * rbeta(`cfAlpha', `cfBeta')  // multiply by case fatality to estimate mortality rate
        }
        }

		
	
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
    rename incCarrier_* draw_*
  	forvalues year = 1990(5)2015 {
      forvalues sex = 1/2 {
        export delimited age_group_id draw_* using `outDir'/chronic/6_`location'_`year'_`sex'.csv if sex_id==`sex' & year_id==`year', replace
	    }
	  }
	drop draw_*
	
	rename prev_* draw_*
  	forvalues year = 1990(5)2015 {
      forvalues sex = 1/2 {
        export delimited age_group_id draw_* using `outDir'/chronic/5_`location'_`year'_`sex'.csv if sex_id==`sex' & year_id==`year', replace
	    }
	  }
	drop draw_*
	*/
	
	capture drop incCarrier_* prev_*
	
	* SET UP SEQUELA SPLIT *
    expand 4
    bysort age_group_id year_id sex_id: generate index = _n

    generate state = "inf_mild" if index==1
    replace  state = "inf_mod"  if index==2
    replace  state = "inf_sev"  if index==3
    replace  state = "_asymp" if index==4
	 
	 
	 
    * SPLIT OUT INCIDENCE *	 
    forvalues i = 0 /999 {
      quietly {
	    local prSev = rbeta(7, 19)  
	    generate draw_`i' = acute_`i' * `prSev'  if state=="inf_sev" | state=="inf_mod"
	    replace  draw_`i' = acute_`i' - draw_`i' if state=="inf_mod"
	    replace  draw_`i' = inc_`i' - acute_`i'  if state=="_asymp"
	    replace  draw_`i' = 0 if state=="inf_mild"
	    }
	  }
	  
	  drop acute_* inc_*
	  
	 
      * EXPORT SEQUELA INCIDENCE DRAWS *
	  foreach state in inf_mild inf_mod inf_sev _asymp {
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
	  foreach state in inf_mild inf_mod inf_sev _asymp {
		forvalues year = 1990(5)2015 {
        forvalues sex = 1/2 {
          export delimited age_group_id draw_* using `outDir'/`state'/5_`location'_`year'_`sex'.csv if state=="`state'" & sex_id==`sex' & year_id==`year', replace
		  }
		 }
		}
		


  
  log close
 