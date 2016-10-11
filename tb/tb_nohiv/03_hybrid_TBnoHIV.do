// Description: prep TB hybrid model, calculate TB no-HIV		
				
				clear all
				set mem 5G
				set maxvar 32000
				set more off

				
				// gbd cause (acause)
				local acause tb
							
			    // locals 
				local model_version_id dismod_90644_90646
				local LMIC 9422_90644
				local data_rich 1175_90646
				
				
				// Make folders to store COMO files
		
		capture mkdir "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws"
		capture mkdir "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`model_version_id'"		
		

use "/ihme/gbd/WORK/04_epi/01_database/02_data/tb/temp/tb_epi_draws_`LMIC'.dta", clear

// drop aggregate locations
drop if inlist(location_id,1, 4, 5, 9, 21, 31, 32, 42, 56, 64, 65, 70, 73, 96, 100, 103, 104, 120, 124, 134, 137, 138, 158, 159, 166, 167, 174, 192, 199)

// drop countries with subnationals
drop if inlist(location_id,6, 67, 93, 95, 102, 130, 135, 152, 163, 180, 196)


// merge on data rich countries
merge m:1 location_id using "/home/j/WORK/04_epi/01_database/02_data/tb/1175/04_temp/data_rich.dta", keepusing(data_rich) nogen

drop if data_rich==1

drop data_rich model_version_id

keep if measure_id==5 | measure_id==6

tempfile LMIC
save `LMIC', replace



use "/ihme/gbd/WORK/04_epi/01_database/02_data/tb/temp/tb_epi_draws_`data_rich'.dta", clear

// drop aggregate locations
drop if inlist(location_id,1, 4, 5, 9, 21, 31, 32, 42, 56, 64, 65, 70, 73, 96, 100, 103, 104, 120, 124, 134, 137, 138, 158, 159, 166, 167, 174, 192, 199)

// drop countries with subnationals
drop if inlist(location_id,6, 67, 93, 95, 102, 130, 135, 152, 163, 180, 196)

// merge on data rich countries
merge m:1 location_id using "/home/j/WORK/04_epi/01_database/02_data/tb/1175/04_temp/data_rich.dta", keepusing(data_rich) nogen

keep if data_rich==1

drop data_rich model_version_id

keep if measure_id==5 | measure_id==6

append using `LMIC'

tempfile tb_all
save `tb_all', replace

save "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/hybrid_`model_version_id'.dta", replace


** ***********************************************************************************************************

// get population
	  
		clear all
		adopath + "/home/j/Project/Mortality/shared/functions"
		get_env_results
		tempfile pop_all
		save `pop_all', replace

// Bring in HIVTB

// hivtb inc
use /ihme/gbd/WORK/04_epi/01_database/02_data/tb/temp/HIVTB_inc_cyas_`model_version_id'_capped.dta, clear

// rename draws
forvalues i = 0/999 {
			  rename draw_`i' hivtb_`i'  
			  replace hivtb_`i'=hivtb_`i'*mean_pop
			}
tempfile hivtb_inc
save `hivtb_inc', replace

// hivtb prev

use /ihme/gbd/WORK/04_epi/01_database/02_data/tb/temp/HIVTB_prev_cyas_`model_version_id'_capped.dta, clear

// rename draws
forvalues i = 0/999 {
			  rename draw_`i' hivtb_`i'
			  replace hivtb_`i'=hivtb_`i'*mean_pop
			}
tempfile hivtb_prev
save `hivtb_prev', replace

// bring in TB all forms
** calculate TB no-HIV incidence
use "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/hybrid_`model_version_id'.dta", clear
keep if measure_id==6
merge m:1 location_id year_id age_group_id sex_id using `pop_all', keepusing(mean_pop) keep(3)nogen

forvalues i=0/999 {
			di in red "draw `i'"
			replace draw_`i'=draw_`i'*mean_pop
			}


merge 1:1 location_id year_id age_group_id sex using `hivtb_inc', keep(3) nogen
// loop through draws and subtract hiv_tb from tb all forms
		forvalues i=0/999 {
			replace draw_`i'=draw_`i'-hivtb_`i'
			replace draw_`i'=draw_`i'/mean_pop
			}

			drop mean_pop
tempfile tb_noHIV_inc
save `tb_noHIV_inc', replace

** calculate TB no-HIV prevalence
use "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/hybrid_`model_version_id'.dta", clear
keep if measure_id==5
merge m:1 location_id year_id age_group_id sex_id using `pop_all', keepusing(mean_pop) keep(3)nogen

forvalues i=0/999 {
			di in red "draw `i'"
			replace draw_`i'=draw_`i'*mean_pop
			}


merge 1:1 location_id year_id age_group_id sex using `hivtb_prev', keep(3) nogen
// loop through draws and subtract hiv_tb from tb all forms
		forvalues i=0/999 {
			replace draw_`i'=draw_`i'-hivtb_`i'
			replace draw_`i'=draw_`i'/mean_pop
			}
drop mean_pop
tempfile tb_noHIV_prev
save `tb_noHIV_prev', replace

append using `tb_noHIV_inc'

drop if age_group_id>21

replace modelable_entity_id=9969


save "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/TBnoHIV_`model_version_id'.dta", replace 


preserve

keep if measure_id==5

tempfile prev
save `prev', replace

restore

keep if measure_id==6

tempfile inc
save `inc', replace

** *********** save results **********************************************************************************************************************

use `prev',clear

levelsof(location_id), local(ids) clean
levelsof(year_id), local(years) clean

global sex_id "1 2"

foreach location_id of local ids {
		foreach year_id of local years {
			foreach sex_id of global sex_id {
					qui outsheet if location_id==`location_id' & year_id==`year_id' & sex_id==`sex_id' using "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`model_version_id'/5_`location_id'_`year_id'_`sex_id'.csv", comma replace
				}
			}
		}
		

		


use `inc',clear

levelsof(location_id), local(ids) clean
levelsof(year_id), local(years) clean

global sex_id "1 2"

foreach location_id of local ids {
		foreach year_id of local years {
			foreach sex_id of global sex_id {
					qui outsheet if location_id==`location_id' & year_id==`year_id' & sex_id==`sex_id' using "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`model_version_id'/6_`location_id'_`year_id'_`sex_id'.csv", comma replace
				}
			}
		}
		

		

do /home/j/WORK/10_gbd/00_library/functions/save_results.do
save_results, modelable_entity_id(9969) description(updated TB no-HIV hybrid model, `model_version_id') mark_best(yes) in_dir(/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`model_version_id') metrics(prevalence incidence)

		