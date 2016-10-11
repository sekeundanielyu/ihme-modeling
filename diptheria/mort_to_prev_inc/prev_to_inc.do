
** Purpose: Calculate incidence as: incidence = prevalence/duration


** set up
	clear all
	set more off
								
			// locals 
			    local acause diptheria
				local model_version_id v2
				local measure incidence
				local measure_id 6
				local cause "A05"
	            local outcome `cause'.a
	
			

use "diphtheria_prev_draws_`model_version_id'.dta", clear

drop model_version_id cause_id mean_pop cause

gen acause="diptheria"
// rename
forvalues n = 0/999 {
		rename draw_`n' prev_draw_`n'
	}
** Bring in duration
	merge m:1 acause using "diphtheria_duration_draws.dta"
	drop _m
	forvalues x = 0/999 {
		** Convert prevalence to incidence
		
		gen draw_`x' = prev_draw_`x'/dur_draw`x'
	}
	
	drop prev_* dur_draw* acause
	

	replace measure_id=6

save "diphtheria_inc_draws_`model_version_id'.dta", replace
		
	