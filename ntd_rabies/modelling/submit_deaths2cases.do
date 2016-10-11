  clear all
  set more off


* ENSURE THAT OUTPUT DIRECTORY EXISTS *
  capture mkdir /ihme/scratch/users/strUser/rabies/inf_sev
  capture mkdir /home/j/WORK/04_epi/02_models/01_code/06_custom/rabies/logs

	
  quietly adopath + /home/j/WORK/10_gbd/00_library/functions
  
  get_demographics, gbd_team(cod)
 
  
* SUBMIT BASH FILES *
  foreach location_id of global location_ids {
    ! qsub  -P proj_custom_models -pe multi_slot 8 -N d2c_`location_id' "/home/j/WORK/04_epi/02_models/01_code/06_custom/rabies/code/submit_deaths2cases.sh" "`location_id'"
  	sleep 1000
	}
	

