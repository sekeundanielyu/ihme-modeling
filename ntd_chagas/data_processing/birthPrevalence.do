

* BOILERPLATE *
  clear all
  set more off  

  if c(os) == "Unix" {
    local j "/home/j"
    set odbcmgr unixodbc
    }
  else if c(os) == "Windows" {
    local j "J:"
    }

	
* SET ENVIRONMENTAL LOCALS (PATHS, FILENAMES MODEL NUBMERS, ETC) *
  local currentModel 24516

  local inDir /clustertmp/WORK/04_epi/02_models/02_results/ntd_chagas/cases/_parent/`currentModel'/draws
  local outFile  `j'/WORK/04_epi/01_database/02_data/ntd_chagas/04_models/gbd2013/02_inputs/chagasBirthPrev.dta

  tempfile pregTemp pregTempMaster mergingTemp appendTemp 


* DERIVE PARAMETERS OF BETA DISTRIBUTION FOR RATE OF VERTICAL TRANSMISSION *
  local mu    = 0.047  // mean and SD here are from meta-analysis by Howard et al (doi: 10.1111/1471-0528.12396)
  local sigma = (0.056 - 0.039) / (invnormal(0.975) * 2)
  local alpha = `mu' * (`mu' - `mu'^2 - `sigma'^2) / `sigma'^2 
  local beta  = `alpha' * (1 - `mu') / `mu' 

	



adopath + `j'/WORK/04_epi/01_database/01_code/04_models/prod
get_demographics, type(epi) subnational(yes)

use `j'/WORK/04_epi/02_models/01_code/06_custom/chagas/data/chagasPopulationAtRisk.dta, clear
bysort iso3: egen maxPrAtRisk = max(prAtRisk)
levelsof iso3 if maxPrAtRisk>0, local(chagasIsos) clean


use "`j'/WORK/04_epi/01_database/02_data/hepatitis/04_models/gbd2013/02_inputs/prPreg.dta", clear
generate sex = 2
merge 1:1 location_id year age sex using `j'/WORK/02_mortality/04_outputs/02_results/envelope.dta, keep(match) nogenerate
gen nPreg = prPreg * mean_pop
keep iso3 year age nPreg
save `pregTempMaster', replace


local count 1

  foreach year in $years {
  
    use `pregTempMaster', clear
    keep if year==`year'
    save `pregTemp', replace
	
	foreach iso of local chagasIsos {

	  import delimited using  `inDir'/incidence_`iso'_`year'_female.csv, clear
	  save `mergingTemp', replace
	  
	  use `pregTemp', clear
      keep if iso3 == "`iso'" 
	  merge 1:1 age using `mergingTemp'
	  
	  forvalues i = 0/999 {
        local vertical    = rbeta(`alpha', `beta')  
		quietly gen bPrev_`i' = nPreg * draw_`i' * `vertical'
		}
		
	  collapse (sum) nPreg bPrev_*, fast
	  forvalues i = 0/999 {
	    quietly replace bPrev_`i' = bPrev_`i' / nPreg
		}
		
	  gen iso3 = "`iso'"
	  gen year = `year'
	  
	  if `count' != 1 append using `outFile'
	  save `outFile', replace
	  
	  local ++count
	  }
	}
 
* APPEND FILES TOGETHER *

use `outFile', clear

egen mean  = rowmean(bPrev_*)
egen upper = rowpctile(bPrev_*), p(97.5)
egen lower = rowpctile(bPrev_*), p(2.5)

generate int year_start = year
generate int year_end = year

drop bPrev_* nPreg year

generate age_start = 0
generate age_end = 0
generate long nid = 153661

generate acause = "ntd_chagas"
generate grouping = "cases"
generate healthstate = "_parent"
generate int sequela_id = 1450
generate sequela_name = "Chagas seroprevalence among at-risk population"
generate description = "gbd 2013: chagas"
generate source_type = "Other"
generate data_type = "Other"
generate parameter_type = "Prevalence"
generate orig_unit_type = "Rate per capita"
generate orig_uncertainty_type = "CI"
generate is_raw = "adjusted"
generate extractor = "stanaway"
generate byte cv_donors = 0
generate byte cv_endemic = 0

save `outFile', replace

import delimited using `j'/WORK/04_epi/01_database/02_data/ntd_chagas/03_review/05_upload/ntd_chagas_2014_10_03.csv, bindquotes(strict) clear
export delimited using `j'/WORK/04_epi/01_database/02_data/ntd_chagas/03_review/05_upload/ntd_chagas_2014_10_03-Bkup.csv, replace
append using `j'/WORK/04_epi/01_database/02_data/ntd_chagas/04_models/gbd2013/02_inputs/`outFile'
export delimited using `j'/WORK/04_epi/01_database/02_data/ntd_chagas/03_review/05_upload/ntd_chagas_2014_10_07.csv, replace






