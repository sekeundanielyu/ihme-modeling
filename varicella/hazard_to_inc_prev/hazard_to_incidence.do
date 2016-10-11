
** Description : calculate population incidence rate = hazard *(1-prevalence) at the draw level
	

** set up
	clear all
	set more off
	set mem 1g
	if c(os)=="Unix" global j "/home/j"
	else global j "J:"
	local cause "A05"
	local outcome `cause'.a
	
	// gbd cause (acause)
				local acause varicella
							
			// locals 
				local model_version_id v2
				local measure incidence
				local measure_id 6
				
			// Make folders to store COMO files
		
					
        capture mkdir "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws"
		capture mkdir "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`model_version_id'"	


// convert DisMod incidence draws to prevalence draws

use "$j/WORK/04_epi/01_database/02_data/varicella/GBD2015/temp/varicella_dismod_draws.dta", clear
preserve
keep if measure_id==5
drop measure_id model*
tempfile prev
save `prev', replace

restore
keep if measure_id==6
drop measure_id model*
tempfile inc
save `inc', replace

use `prev', clear
forvalues i = 0/999 {
			  rename draw_`i' prev_draw_`i'
			}
merge m:m location_id year age sex using `inc', keep(3) nogen
   
      forvalues i = 0/999 {
	    quietly replace draw_`i' = draw_`i' * (1-prev_draw_`i')
        }
	 
	  drop prev*

	  gen modelable_entity_id=1440
	  gen measure_id=6
	  
save "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`acause'_`measure'_draws_`model_version_id'.dta", replace

// prep for COMO
	levelsof(location_id), local(ids) clean
	levelsof(year_id), local(years) clean

global sex_id "1 2"

foreach location_id of local ids {
		foreach year_id of local years {
			foreach sex_id of global sex_id {
					qui outsheet if location_id==`location_id' & year_id==`year_id' & sex_id==`sex_id' using "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`model_version_id'/`measure_id'_`location_id'_`year_id'_`sex_id'.csv", comma replace
				}
			}
		}
		

	// save results and upload
	
	do /home/j/WORK/10_gbd/00_library/functions/save_results.do
    save_results, modelable_entity_id(1440) description(mild infection due to varicella `measure' `model_version_id') mark_best(no) in_dir(/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`model_version_id') metrics(incidence)

	
	