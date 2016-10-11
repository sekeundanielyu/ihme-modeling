
/******************************************************************************\
           SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS
\******************************************************************************/

* BOILERPLATE *
  clear all
  set maxvar 11000
  set more off
  
  adopath + /home/j/WORK/10_gbd/00_library/functions
 
  tempfile appendTemp mergeTemp

  

* PULL IN LOCATION_ID AND INCOME CATEGORY FROM BASH COMMAND *  
  local location "`1'"

  capture log close
  log using /home/j/WORK/04_epi/02_models/01_code/06_custom/hepatitis/hepELogs/log_`location', replace
  
  
* SET UP OUTPUT DIRECTORIES *  
  local outDir /ihme/scratch/users/strUser/hepE


* SET UP LOCALS WITH MODELABLE ENTITY IDS AND AGE GROUPS *  
  local meid  1659
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
 
 
  
  
/******************************************************************************\
                      PULL IN DRAWS AND MAKE CALCULATIONS
\******************************************************************************/
  
    * PULL IN DRAWS FROM DISMOD MODELS FOR ANTI-HEV INCIDENCE AND PREVALENVCE *
      get_draws, gbd_id_field(modelable_entity_id) gbd_id(`meid') location_ids(`location') age_group_ids(`ages') measure_ids(5) source(dismod) status(best) clear
      rename draw_* prev_*
      save `mergeTemp'
	  
      get_draws, gbd_id_field(modelable_entity_id) gbd_id(`meid') location_ids(`location') age_group_ids(`ages') measure_ids(6) source(dismod) status(best) clear
      rename draw_* inc_*
      merge 1:1 age_group_id year_id sex_id using `mergeTemp', gen(merge56)
	  
	  
	  merge 1:1 year_id age_group_id sex_id using /ihme/scratch/users/strUser/hepE/inputs/hepE_cf_`location'.dta


	
	* PERFORM DRAW-LEVEL CALCULATIONS TO CONVERT INCIDENCE AMONG SUSCEPTABLES TO POPULATION INCIDENCE AND ESTIMATE DEATHS *
      forvalues i = 0/999 {
	    quietly {
		replace  inc_`i' = (inc_`i' * (1 - prev_`i'))  
		generate draw_`i' = inc_`i' * cfr_`i'               // multiply by case fatality to estimate mortality rate
        }
        }

		
	
/******************************************************************************\
                             INTERPOLATE DEATHS
\******************************************************************************/			

  
  *append using `appendTemp'
	
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
	
	drop draw_* cfr_*
	keep if mod(year_id,5)==0 & year_id>=1990
	



* PRODUCE INCIDENCE DRAWS *
generate prAcute   = logit(0.6 * (1 - exp(-0.011 * ageMid^1.86)))   
generate prAcuteSe = .25  

local prSev    = 0.02/0.6  
local prSevSe  = `prSev' / 4
local alphaSev = `prSev' * (`prSev' - `prSev'^2 - `prSevSe'^2) / `prSevSe'^2 
local betaSev  = `alphaSev' * (1 - `prSev') / `prSev'

  
forvalues i = 0/999 {
  quietly {
    local random = rnormal(0,1)
	
    generate sympTemp = invlogit(rnormal(prAcute, prAcuteSe)) * inc_`i'    
    generate _asymp6_`i'  = inc_`i'  - sympTemp
    generate inf_sev6_`i' = rbeta(`alphaSev', `betaSev') * sympTemp
    replace  inf_sev6_`i' = 0 if missing(inf_sev6_`i')
	generate inf_mod6_`i' = sympTemp - inf_sev6_`i'
	generate inf_mild6_`i' = 0 
	
	drop sympTemp

    foreach seq in _asymp inf_mild inf_mod inf_sev {
	  replace  `seq'6_`i' = 0 if age_group_id <= 3
	  generate `seq'5_`i' = `seq'6_`i' * 4 / 52  
      }
	  }
  di "." _continue
  }



* EXPORT SEQUELA DRAWS *  
 
levelsof year_id, local(years) clean

foreach parameter in 5 6 {
 foreach state in inf_mild inf_mod inf_sev _asymp {
  rename `state'`parameter'_* draw_*
   foreach year of local years {
    foreach sex in 1 2 {
     export delimited age_group_id draw_* using `outDir'/`state'/`parameter'_`location'_`year'_`sex'.csv if year_id==`year' & sex_id==`sex', replace 
	 } 
	}
   rename draw_* `state'`parameter'_*
   }
  }



  
  log close
 