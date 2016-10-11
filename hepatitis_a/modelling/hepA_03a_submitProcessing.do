
/******************************************************************************\
           SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS
\******************************************************************************/

* BOILERPLATE *
  clear all
  set maxvar 10000
  set more off
  
  adopath + /home/j/WORK/10_gbd/00_library/functions
 
 
* SETUP DIRECTORIES * 
  local outDir /ihme/scratch/users/stanaway/hepA
  capture mkdir `outDir'
  
  foreach subDir in logs temp death total inf_mild inf_mod inf_sev _asymp {
    capture mkdir `outDir'/`subDir'
	} 
 
 
* LOAD COEFFICIENTS AND PROCESS BY LOCATION * 
  use /home/j/WORK/04_epi/02_models/01_code/06_custom/hepatitis/inputs/hepA_modelCoefficients.dta, replace

  levelsof location_id, local(locations) clean

  foreach location of local locations {
    preserve
    keep if location_id==`location' 
    save `outDir'/temp/`location'.dta , replace 
  
    ! qsub  -pe multi_slot 8 -N hepA_`location' "/home/j/WORK/04_epi/02_models/01_code/06_custom/hepatitis/code/hepA_submit_processing.sh" "`location'" 
    restore
    }

  
  