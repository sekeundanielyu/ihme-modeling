	
	
clear all
set more off
set maxvar 32000

adopath + /home/j/WORK/10_gbd/00_library/functions

local location "`1'"
local ages 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21
local sexes 1 2
local years 1990 1995 2000 2005 2010 2015 

local outDir /ihme/scratch/users/strUser/rabies/inf_sev

tempfile pop

capture log close
log using /home/j/WORK/04_epi/02_models/01_code/06_custom/rabies/logs/log_`location'.smcl, replace 



* PULL IN POPULTION ESTIMATES *
  get_populations , year_id(`years') location_id(`location') sex_id(`sexes') age_group_id(`ages') clear
  save `pop', replace
  
* PULL IN DEATH ESTIMATES *
  get_draws, gbd_id_field(cause_id) gbd_id(359) source(dalynator) status(best) location_ids(`location') age_group_ids(`ages')  sex_ids(`sexes') measure_ids(1) clear
  drop if year_id<1988 | metric_id!=1
  keep year_id sex_id age_group_id draw_*


* SAMPLE DRAWS FROM ALL YEARS WITHIN EACH FIVE-YEAR ESTIMATION PERIOD *  
  reshape long draw_, i(year_id sex_id age_group_id) j(n)
  drop if missing(draw_)

  replace year_id = round(year_id, 5)
  
  gen random = runiform()
  bysort year_id age_group_id sex_id (random): replace n = _n - 1
  keep if n <= 999
  drop random

  reshape wide draw_, i(year_id sex_id age_group_id) j(n)


* MERGE IN POPULATION ESTIMATES * 
  merge 1:1 year_id sex_id age_group_id using `pop', assert(2 3) nogenerate

forvalues i = 0/999 {
	  quietly replace draw_`i' = (draw_`i' + rnbinomial(draw_`i',.99)) if draw_`i'>=0.0001  
	  quietly replace draw_`i' =  draw_`i' / pop
	  quietly replace draw_`i' = 0 if age_group_id<4
	  }
	  
	  
	foreach year in 1990 1995 2000 2005 2010 2015 {
	  foreach sex in 1 2 {
		export delimited age_group_id draw_* if year_id==`year' & sex_id==`sex' using `outDir'/6_`location'_`year'_`sex'.csv, replace
		}
	  }
  
    forvalues i = 0/999 {
	  quietly replace draw_`i' = draw_`i' * (2/52)
	  }	
	  
	foreach year in 1990 1995 2000 2005 2010 2015 {
	  foreach sex in 1 2 {
		export delimited age draw_* if year==`year' & sex_id==`sex' using `outDir'/5_`location'_`year'_`sex'.csv, replace
		}
      }

log close
