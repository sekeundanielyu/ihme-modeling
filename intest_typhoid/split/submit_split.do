  clear
  set more off

  local drModel 79576
  local endemicModel 78415
  

* ENSURE THAT OUTPUT DIRECTORIES EXIST *
  local states_typhoid death inf_mod inf_sev abdom_sev gastric_bleeding
  local states_paratyphoid death inf_mild inf_mod inf_sev abdom_mod

  local rootDir /ihme/scratch/users/strUser/intest_b
  capture mkdir `rootDir'
  
  foreach x in typhoid paratyphoid {
    capture mkdir `rootDir'/`x'
    foreach state of local states_`x' {
      capture mkdir `rootDir'/`x'/`state'
	  }
    }

  capture mkdir `rootDir'/parent
  

	
	
* LOAD FILE WITH LOCATION_IDS AND INCOME *  
  use /home/j/WORK/04_epi/02_models/01_code/06_custom/intest/inputs/submit_split_data.dta, clear

  generate model = `endemicModel' if inlist(super_region_id, 4, 158, 166, 137)
  replace  model = `drModel' if inlist(super_region_id, 31, 64, 103) | dataRich==1

  
* SUBMIT BASH FILES *
  forvalues i = 1/`=_N' {
    ! qsub -P proj_custom_models -pe multi_slot 8 -N split_`=location_id[`i']' "/home/j/WORK/04_epi/02_models/01_code/06_custom/intest/code/submit_split.sh" "`=location_id[`i']'" "`=incomeCat[`i']'" "`=model[`i']'"
  	sleep 1000
	}

	
	
