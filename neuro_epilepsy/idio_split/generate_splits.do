

clear all 
local in_dir "J:\WORK\04_epi\01_database\02_data\imp_epilepsy\04_models\02_inputs"
adopath + "J:/WORK/10_gbd/00_library/functions"
adopath +  "J:/WORK/10_gbd/00_library/functions/get_outputs_helpers"

import excel "`in_dir'/Epilepsy_fractions_2015.xlsx", firstrow clear
		gen year_id = (year_start + year_end) / 2 
		replace year_id = round(year_id, 1)
tempfile data_2015
save `data_2015', replace 


get_covariate_estimates, covariate_name_short(LDI_pc)  clear
	rename mean LDI_pc
	gen ln_LDI_pc = ln(LDI_pc)
	keep location_id year_id ln_LDI_pc
	tempfile covs 
	save `covs', replace
get_covariate_estimates, covariate_name_short(health_system_access_capped)  clear
	rename mean health_system_access_capped
	keep location_id year_id health_system_access_capped
	merge 1:1 location_id year_id using `covs', nogen 
merge 1:m location_id year_id using `data_2015'

tempfile epilepsy_fractions
save `epilepsy_fractions', replace 

//Merge with all locations, and keep super_region_name
	get_location_metadata, location_set_id(9) clear 
	keep location_id location_name super_region_name developed 
	drop if location_id == 1 // drop global 
	merge 1:m location_id using `epilepsy_fractions', nogen
		
	save `epilepsy_fractions', replace 


//Run Regressions 
	//Proportion idiopatic
		use `epilepsy_fractions', clear 

		gen ss_idiop = round(value_num_idio /value_prop_idio) 

		meglm value_num_idio ln_LDI_pc || super_region_name:, family(binomial ss_idiop)

		predict fitted_idio, xb
		predict se_fitted, stdp
		predict re_super_idio, remeans reses(re_super_se)
		//save for diagnostics 
		tempfile idio_results
		save `idio_results', replace

		duplicates drop location_id year_id fitted_idio re_super_idio, force

		keep location_id year_id *fitted* *super* 
		keep if year_id >= 1980 

		set seed 5336
		expand 1000
		gen fitted_draws = rnormal(fitted_idio,se_fitted)
		gen re_draws = rnormal(re_super_idio,re_super_se)
		gen final_logit = fitted_draws + re_draws
		gen final_draws_idio = invlogit(final_logit)

		keep location_id year_id final_draws_idio

			sort  location_id year_id
					egen group = group(location_id year_id)
					drop if group == . 
					gen count = _n 
					gen draw = count - (group - 1)*1000 - 1 // draw 0 to 999
					drop group count 
		save "`in_dir'/Idiopathic_draws.dta", replace


	//Proportion Severe 

	use `epilepsy_fractions', clear 
	gen ss_sev = round(value_num_sev/value_prop_sev) 
	meglm value_num_sev health_system_access_capped ln_LDI_pc || super_region_name:, family(binomial ss_sev)

	// Get logit-transformed fitted and random effects
	predict fitted_sev, xb
	predict se_fitted_sev, stdp
	predict re_super_sev, remeans reses(re_super_sev_se)
	//save for diagnostics 
	tempfile sev_results
	save `sev_results', replace

	duplicates drop location_id year_id fitted_sev re_super_sev, force

		keep location_id year_id *fitted* *super* 
		keep if year_id >= 1990 

	set seed 5336
	expand 1000
	gen fitted_draws_sev = rnormal(fitted_sev,se_fitted_sev)
	gen re_draws_sev = rnormal(re_super_sev,re_super_sev_se)
	gen final_logit_sev = fitted_draws_sev + re_draws_sev
	gen final_draws_sev = invlogit(final_logit_sev)

	keep location_id year_id final_draws_sev

	save "`in_dir'/Severe_draws.dta", replace

	//Treatment Gap : value_num_treat_gap is number UNTREATED 

	use `epilepsy_fractions', clear 
	gen ss_treat = round(value_num_treat_gap/value_treat_gap_prop) 
	meglm value_num_treat_gap health_system_access_capped ln_LDI_pc || super_region_name:, family(binomial ss_treat) 

	// Get logit-transformed fitted and random effects
	predict fitted_tg, xb
	predict se_fitted_tg, stdp
	predict re_super_tg, remeans reses(re_super_tg_se)
	//save for diagnostics 
	tempfile tg_results
	save `tg_results', replace

	duplicates drop location_id year_id fitted_tg re_super_tg, force

		keep location_id year_id *fitted* *super* 
		keep if year_id >= 1980 //for CSMR, I want 1980s  

	set seed 5336
	expand 1000
	gen fitted_draws_tg = rnormal(fitted_tg,se_fitted_tg)
	gen re_draws_tg = rnormal(re_super_tg,re_super_tg_se)
	gen final_logit_tg = fitted_draws_tg + re_draws_tg
	gen final_draws_tg = invlogit(final_logit_tg)

	keep location_id year_id final_draws_tg

	save "`in_dir'/Treat_Gap_draws.dta", replace



//Estimated propSeizure_free_under_treat based on meta-analysis 

use `epilepsy_fractions', clear 

gen YMean = .  
gen YSE = .

* local dev 1 
destring developed, replace

	replace developed = 1 if developed == . & super_region_name == "High-income"
	replace developed = 0 if developed == . & super_region_name != "High-income"

foreach dev in 0 1 {
	metan value_seizure_free_on_treat_prop value_lower_seiz_free value_upper_seiz_free if developed == `dev', random lcols(location_name year_id) rcols(value_denominator) textsize(175) title("Epilepsy Seizure Free on Tx, Developed = `dev'")
	replace YMean = `r(ES)' if developed == `dev'
	replace YSE = `r(seES)' if developed == `dev'
	}

keep location_id YMean YSE 
save "`in_dir'/Epilepsy_TxSeizureFree_prop.dta", replace 


