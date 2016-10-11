
** Purpose: Calculate prevalence as: prevalence = mortality/cfr*duration

** set up
	clear all
	set more off
	
** locals 
	local acause tetanus // gbd cause (acause)
	local cause "A07"
	local outcome `cause'.a				
	local model_version_id v2
	local measure prevalence
	local measure_id 5		
       
** Bring in duration data
	insheet using "duration_draws.csv", comma clear names
	keep if cause == "`outcome'"
	replace cause = "`cause'"
	renpfix draw dur_draw
	tempfile duration
	save `duration', replace


** Bring in codcorrect deaths
   use "codcorrect_draws.dta", clear
   keep if metric_id==1
   drop rei_id metric_id measure_id
   tostring age, replace force format(%12.3f)
   destring age, replace force
   tempfile deaths
   save `deaths', replace

** Read in cfr draws (from DisMod), 
	use "cfr_draws.dta", clear
	forvalues n = 0/999 {
		rename draw_`n' cfr_draw_`n'
	}
** Merge on codcorrect deaths
	merge 1:1 location_id sex year age using `deaths', keep(3)nogen
	
	
** Merge on population & envelope data
	merge 1:1 location_id sex_id year_id age using "pop_data_all.dta", keep(3) nogen
	gen cause="`cause'"

** Bring in duration
	merge m:1 cause using `duration'
	drop _m
	
	tempfile deaths_cfr_duration
	save `deaths_cfr_duration', replace
	
** calculate prev as mort/cfr*duration
    use `deaths_cfr_duration', clear
	preserve
	forvalues x = 0/999 {
		** Convert deaths to death rates
		gen death_rate`x' = draw_`x'/mean_pop
		drop draw_`x'
		gen draw_`x' = death_rate`x'/cfr_draw_`x'*dur_draw`x'
	}
	drop death_rate* cfr_* dur_* 
	sort location_id year age
	replace modelable_entity_id=1426
	save "`acause'_prev_draws_`model_version_id'.dta", replace

** calculate incidence = mortality / case fatality
    restore
	forvalues x = 0/999 {
		** Convert deaths to death rates
		gen death_rate`x' = draw_`x'/mean_pop
		drop draw_`x'
		gen inc_draw_`x' = death_rate`x'/cfr_draw_`x'
	}
	drop death_rate* dur_* 
	sort location_id year age
	
	save "`acause'_inc_draws_`model_version_id'.dta", replace

	
