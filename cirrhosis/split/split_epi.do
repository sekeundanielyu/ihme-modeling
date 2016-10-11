
/******************************************************************************\
           SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS
\******************************************************************************/

* BOILERPLATE *
  clear all
  set maxvar 10000
  set more off
  
  adopath + /home/j/WORK/10_gbd/00_library/functions

  local location "`1'"


  capture log close
  log using /home/j/WORK/04_epi/02_models/01_code/06_custom/cirrhosis/logs/log_`location', replace
  
* SET UP OUTPUT DIRECTORIES *  
  local outDir /ihme/scratch/users/strUser/cirrhosis

* SET UP LOCALS WITH MODELABLE ENTITY IDS *  

  local ages 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21

  local parentMeid 1919
  local childrenInMeids  1920 1921 1922 1923
  local childrenOutMeids 2892 2893 2891 2894
 
  tempfile appendTemp mergeTemp

  

  
/******************************************************************************\
                      PULL IN DRAWS AND MAKE CALCULATIONS
\******************************************************************************/
  
    * PULL IN DRAWS FROM DISMOD MODELS FOR OVERALL CIRRHOSIS AND ETIOLOGY PR MODELS  *
      foreach id in `parentMeid' `childrenInMeids' {
	    if `id' == `parentMeid' local measures 5 6
		else local measures 18
		
        get_draws, gbd_id_field(modelable_entity_id) measure_ids(`measures') gbd_id(`id') location_ids(`location') age_group_ids(`ages') source(dismod) status(best) clear
        rename draw_* draw`id'_*
  
        if `id' != `parentMeid' {
		  drop m*_id
		  merge 1:m age_group_id year_id sex_id location_id using `mergeTemp', assert(3) nogenerate
		  }
		  
        save `mergeTemp', replace
        }

	
	* PERFORM DRAW-LEVEL CALCULATIONS TO SPLIT CIRRHOSIS *
      forvalues i = 0/999 {
	    quietly {
		egen correction = rowtotal(draw*_`i')
		replace correction = correction - draw`parentMeid'_`i'
		
	    foreach id in `childrenInMeids' {
	      replace draw`id'_`i' = draw`parentMeid'_`i' * draw`id'_`i' / correction
          }
		drop correction
		}
        }

		
	
/******************************************************************************\
                    EXPORT FILES AND PERFORM SEQUELA SPLITS
\******************************************************************************/		
		
	* EXPORT SPLIT ESTIMATES *
	foreach inId of local childrenInMeids {
      gettoken outId childrenOutMeids: childrenOutMeids
	  rename draw`inId'_* draw_*
	  
	  forvalues year = 1990(5)2015 {
        forvalues sex = 1/2 {
          export delimited age_group_id draw_* using `outDir'/`outId'/5_`location'_`year'_`sex'.csv if sex_id==`sex' & year_id==`year' & measure_id==5, replace
		  export delimited age_group_id draw_* using `outDir'/`outId'/6_`location'_`year'_`sex'.csv if sex_id==`sex' & year_id==`year' & measure_id==6, replace
          }
	    }
	  drop draw_*	
      }
	
  
  log close
  
  
  
  