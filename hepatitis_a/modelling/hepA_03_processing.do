
/******************************************************************************\
           SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS
\******************************************************************************/

* BOILERPLATE *
  clear all
  set maxvar 15000
  set more off
  
  adopath + /home/j/WORK/10_gbd/00_library/functions

* PULL IN LOCATION_ID FROM BASH COMMAND *  
  local location "`1'"

  local outDir /ihme/scratch/users/stanaway/hepA
  
  log using /home/j/WORK/04_epi/02_models/01_code/06_custom/hepatitis/hepALogs/log_`location', replace

  
* OPEN LOCATION FILE *
  use `outDir'/temp/`location'.dta, clear
  

* PRODUCE DEATH DRAWS *
local cfAlpha = cfAlpha[1]  
local cfBeta = cfBeta[1]  

forvalues i = 0/999 {
  quietly {
    local cf = rbeta(`cfAlpha', `cfBeta')

	generate prev_`i' = invcloglog(rnormal(fixed, fixedSe) + rnormal(random1, randomSe1) + rnormal(random2, randomSe2) + rnormal(random3, randomSe3) + rnormal(random4, randomSe4))
    replace  prev_`i' = prev_`i' - ((prev_`i' - 0.5) * 0.00002)
	
	generate inc_`i' = (-1 * ln(1 - prev_`i') / ageMid) * (1 - prev_`i') 
	replace  inc_`i' = 0 if age_group_id <= 3
	
	generate draw_`i' = inc_`i' * `cf' * mean_pop
	}
  di "." _continue
  }


* EXPORT DEATH DRAWS *
levelsof year_id, local(years) clean

foreach year of local years {
  foreach sex in 1 2 {
    export delimited age_group_id draw_* using `outDir'/death/death_`location'_`year'_`sex'.csv if year_id==`year' & sex_id==`sex', replace 
	}
  }

  
foreach year of local years {
  foreach sex in 1 2 {
    export delimited age_group_id draw_* using `outDir'/death/death_`location'_`year'_`sex'.csv if year_id==`year' & sex_id==`sex', replace 
	}
  }  

  
* COLLAPSE TO QUINQUENNIAL ESTIMATES FOR NON-FATAL *  
keep year_id age_group_id sex_id ageMid inc_* mean_pop inc_* prev_*
replace year_id = round(year_id, 5)
drop if year_id < 1990

fastcollapse inc_* prev_* mean_pop, by(year_id age_group_id ageMid sex_id) type(mean)



* EXPORT SEROPREVALENCE AND INCIDENCE OF INFECTION *

levelsof year_id, local(years) clean

local parameter 5

foreach prefix in prev inc {
  rename `prefix'_* draw_*
   foreach year of local years {
    foreach sex in 1 2 {
     export delimited age_group_id draw_* using `outDir'/total/`parameter'_`location'_`year'_`sex'.csv if year_id==`year' & sex_id==`sex', replace 
	 } 
	}
   rename draw_* `prefix'_*
   local ++parameter
   }
   
  

* PRODUCE INCIDENCE DRAWS *
generate prAcute   = logit(0.852 * (1 - exp(-0.01244 * ageMid^1.903)))   // probability of acute infection by age from Armstrong & Bell,2002; DOI: 10.1542/peds.109.5.839
generate prAcuteSe = .25  // standard error back calculated from Armstrong & Bell's CI's for prAcute in 10-17 year olds and is in logit space

local prSev    = 0.005 / 0.7
local prSevSe  = `prSev' / 4
local alphaSev = `prSev' * (`prSev' - `prSev'^2 - `prSevSe'^2) / `prSevSe'^2 
local betaSev  = `alphaSev' * (1 - `prSev') / `prSev'

  
forvalues i = 0/999 {
  quietly {

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
