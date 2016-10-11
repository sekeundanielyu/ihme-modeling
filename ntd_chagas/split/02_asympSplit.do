	
	
/******************************************************************************\
           SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS
\******************************************************************************/

* BOILERPLATE *
  clear all
  set maxvar 12000
  set more off
  
  adopath + /home/j/WORK/10_gbd/00_library/functions
 
  tempfile appendTemp mergeTemp

  

* PULL IN LOCATION_ID AND INCOME CATEGORY FROM BASH COMMAND *  
  local location "`1'"

  capture log close
  log using /home/j/WORK/04_epi/02_models/01_code/06_custom/chagas/logs/asympSplitLog_`location', replace
  
  
* SET UP OUTPUT DIRECTORIES *  
  local outDir /ihme/scratch/users/strUser/chagas


* SET UP LOCALS WITH MODELABLE ENTITY IDS AND AGE GROUPS *  
  local meids  1450 1451 1453 1454 1452 1455 1456 1457
  local ages 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21
	

  
/******************************************************************************\
                      PULL IN DRAWS AND MAKE CALCULATIONS
\******************************************************************************/
  
    * PULL IN DRAWS FROM DISMOD MODELS FOR INCIDENCE AND PREVALENVCE *
	  local count 1
	  
	  foreach meid of local meids {
	  di _n "`meid'" _n
        get_draws, gbd_id_field(modelable_entity_id) gbd_id(`meid') source(dismod) location_ids(`location') age_group_ids(`ages') measure_ids(5) status(best) clear
        	  
        if `count' >1 append using `appendTemp', force
		save `appendTemp', replace
		
		local ++count
		}
	  

	
	* PERFORM DRAW-LEVEL CALCULATIONS  *
  	  forvalues i = 0 / 999 {
	    quietly replace draw_`i' = -1 * draw_`i' if modelable_entity_id!=1450
	    }
		
	
	
	fastcollapse draw_*, by(location_id age_group_id sex_id year_id measure_id) type(sum)
			
	keep location_id year_id sex_id age_group_id measure_id  draw_* 		

    export delimited using /ihme/scratch/users/strUser/chagas/asymp/asymp_`location'.csv, replace




	
	log close
	
	 
