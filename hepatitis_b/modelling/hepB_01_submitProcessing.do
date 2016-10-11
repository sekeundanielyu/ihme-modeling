* BOILERPLATE *
  clear all
  set maxvar 10000
  set more off
  
  adopath + /home/j/WORK/10_gbd/00_library/functions
  
  

* ENSURE THAT OUTPUT DIRECTORIES EXIST *
  local states death _asymp inf_mild inf_mod inf_sev chronic

  capture mkdir /ihme/scratch/users/strUser/hepB
  capture mkdir /ihme/scratch/users/strUser/hepB/inputs
  foreach state of local states {
    capture mkdir /ihme/scratch/users/strUser/hepB/`state'
	}
    
	
* LOAD LOCATION_IDS *  
  get_demographics, gbd_team(cod)
  
  
* LOAD FILE WITH CHRONIC - ACUTE CONVERSION DATA *
  use /home/j/WORK/04_epi/02_models/01_code/06_custom/hepatitis/inputs/hepB_chronic2acute.dta, clear
  

  
* SUBMIT BASH FILES *
  foreach location_id of global location_ids {
    save /ihme/scratch/users/strUser/hepB/inputs/hepB_chronic2acute_`location_id'.dta, replace
    ! qsub -P proj_custom_models -pe multi_slot 8 -N split_`location_id' "/home/j/WORK/04_epi/02_models/01_code/06_custom/hepatitis/code/hepB_submitProcessing.sh" "`location_id'" 
  	sleep 1000
	}
	
