  clear all
  set more off

  local childrenOutMeids 2892 2893 2891 2894
  
* ENSURE THAT OUTPUT DIRECTORY EXISTS *
  capture mkdir /ihme/scratch/users/strUser/cirrhosis/
  
  foreach id of local childrenOutMeids {
    capture mkdir /ihme/scratch/users/strUser/cirrhosis/`id'
	}
	
  quietly adopath + /home/j/WORK/10_gbd/00_library/functions
  quietly adopath + /home/j/temp/strUser/functions
  
  get_demographics, gbd_team(cod)
 
  
* SUBMIT BASH FILES *
  foreach location_id of global location_ids {
    ! qsub  -P proj_custom_models -pe multi_slot 8 -N split_`location_id' "/home/j/WORK/04_epi/02_models/01_code/06_custom/cirrhosis/code/submit_split_epi.sh" "`location_id'"
  	sleep 1000
	}
	

