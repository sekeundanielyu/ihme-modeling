** Purpose: Calculate prevalence as: prev = mort/cfr*duration

** set up
	clear all
	set more off
	
	// gbd cause (acause)
				local acause diptheria
							
			// locals 
				local model_version_id v2
				local measure prevalence
				local measure_id 5
				local cause "A05"
	            local outcome `cause'.a
	
			

** Bring in duration data, tempfile
	insheet using "duration_draws.csv", comma clear names
	keep if cause == "`outcome'"
	replace cause = "`cause'"
	renpfix draw dur_draw
	tempfile duration
	save `duration', replace

** Get population data
   
    clear all
		adopath + "$j/Project/Mortality/shared/functions"
		get_env_results
		
	tempfile pop_data
	save `pop_data', replace
  
** Bring in codcorrect deaths
	use "codcorrect_draws.dta", clear
	keep if metric_id==1
	drop rei_id metric_id measure_id
	tostring age, replace force format(%12.3f)
	destring age, replace force
	tempfile deaths
	save `deaths'

** Read in cfr draws (from DisMod), 
	use "cfr_draws.dta", clear
	forvalues n = 0/999 {
		rename draw_`n' cfr_draw_`n'
	}
	
** Merge on codcorrect deaths
	merge 1:1 location_id sex_id year_id age using `deaths', keep(3)nogen
	
	
** Merge on population & envelope data
	merge 1:1 location_id sex_id year_id age using `pop_data', keepusing(mean_pop) keep(3) nogen
	
	gen cause="`cause'"

** Bring in duration
	merge m:1 cause using `duration', nogen
		
	tempfile deaths_cfr_duration
	save `deaths_cfr_duration', replace
	
** calculate prev as mort/cfr*duration
	use `deaths_cfr_duration', clear

	forvalues x = 0/999 {
		** Convert deaths to death rates
		gen death_rate`x' = draw_`x'/mean_pop
		drop draw_`x'
		gen draw_`x' = death_rate`x'/cfr_draw_`x'*dur_draw`x'
	}
	drop death_rate* cfr_* dur_* 
	sort location_id year_id age_group_id
	replace modelable_entity_id=1421
	save "diphtheria_prev_draws_`model_version_id'.dta", replace

	


