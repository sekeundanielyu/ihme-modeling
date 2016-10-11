* BOILERPLATE *
  clear all
  set maxvar 10000
  set more off
  
  adopath + /home/j/WORK/10_gbd/00_library/functions
  
  

* ENSURE THAT OUTPUT DIRECTORIES EXIST *
  local states death _asymp inf_mild inf_mod inf_sev 

  capture mkdir /ihme/scratch/users/strUser/hepE
  capture mkdir /ihme/scratch/users/strUser/hepE/inputs
  foreach state of local states {
    capture mkdir /ihme/scratch/users/strUser/hepE/`state'
	}
    
* PULL IN CF DRAWS AND CREATE LOCATION-SPECIFIC FILES *	
  use "/home/j/WORK/04_epi/02_models/01_code/06_custom/hepatitis/inputs/hepE_cfDraws.dta", clear
  
  levelsof location_id, local(location_ids) clean
  
 
* SUBMIT BASH FILES *
  foreach location_id of local location_ids {
    preserve
	keep if location_id==`location_id'
    save /ihme/scratch/users/strUser/hepE/inputs/hepE_cf_`location_id'.dta, replace
	restore
	
	sleep 1000
	
    ! qsub -P proj_custom_models -pe multi_slot 8 -N split_`location_id' "/home/j/WORK/04_epi/02_models/01_code/06_custom/hepatitis/code/hepE_submitProcessing.sh" "`location_id'" 

	}
