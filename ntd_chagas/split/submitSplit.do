* BOILERPLATE *
  clear all
  set maxvar 10000
  set more off
  
  adopath + /home/j/WORK/10_gbd/00_library/functions
  
  tempfile endemic
  

* CREATE DIRECTORIES * 
  local outDir /ihme/scratch/users/strUser/chagas
  capture mkdir `outDir'
  
  foreach seq in inputs acute digest digest_mild digest_mod hf afib asymp total {
    capture mkdir `outDir'/`seq'
	}

  capture mkdir /home/j/WORK/04_epi/02_models/01_code/06_custom/chagas/logs
 
 
 
* BUILD LIST OF ENDEMIC LOCATIONS * 
  get_location_metadata, location_set_id(8) clear
  keep if is_estimate==1 
  
  generate endemic =(strmatch(lower(region_name), "*latin america*") | inlist(ihme_loc_id, "BLZ", "GUY", "SUR"))
  keep location_id endemic


  merge 1:m location_id using /home/j/WORK/04_epi/02_models/01_code/06_custom/chagas/data/latinAmericanMigrants.dta, nogenerate
  
 
  levelsof location_id if endemic==1, local(endemicLocations) clean
  levelsof location_id if missing(draw_0) & endemic!=1, local(zeroLocations) clean
  levelsof location_id if !missing(draw_0) & endemic!=1,  local(nonZeroLocations) clean
  

  
 foreach location in `endemicLocations' {
   ! qsub -P proj_custom_models -pe multi_slot 8 -N chagas_`location' "/home/j/WORK/04_epi/02_models/01_code/06_custom/chagas/code/submitFirstSplit.sh" "`location'" "1"
   sleep 500
   }
  

  
  foreach location in `nonZeroLocations' {
   preserve
   keep if location_id==`location'
   save `outDir'/inputs/prev_`location'.dta, replace
   restore
   
   ! qsub -P proj_custom_models -pe multi_slot 8 -N chagas_`location' "/home/j/WORK/04_epi/02_models/01_code/06_custom/chagas/code/submitSplit.sh" "`location'" "0"
   sleep 500
   }
 
 
  foreach location of local zeroLocations {
   ! qsub -P proj_custom_models -pe multi_slot 8 -N chagas_`location' "/home/j/WORK/04_epi/02_models/01_code/06_custom/chagas/code/submitZeros.sh" "`location'" 
   sleep 500
   }
 
 
 