// Pull in epi draws from 2015 for nonendemic model

clear all
set more off
set maxvar 32767

adopath + "strPath/functions"
adopath + "strPath/functions/utils"		
  
// Pull in parameters from bash command
	local location "`1'"
	capture log close
	log using strPath/logs/high_`location', replace

// Pull in epi draws for high income locations
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(3076) source(dismod) measure_ids(5 6) location_ids(`location') status(best) clear
	
// Save files to folder for 1810
	local sexes 1 2
	local years 1990 1995 2000 2005 2010 2015
	local measures 5 6
	foreach measure of local measures {
		foreach year of local years {
			foreach sex of local sexes {
				preserve
					keep if measure_id==`measure' & sex_id==`sex' & year==`year'
					outsheet age_group_id draw_* strPath/me_1810/`measure'_`location'_`year'_`sex'.csv, comma replace
				restore
			}
		}
	}	

log close
