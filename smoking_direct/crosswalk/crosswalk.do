** Purpose: Crosswalk different smoking definitions

** Set up
	clear *
	set more off

	if c(os) == "Unix" {
		local prefix "/home/j"
		set more off
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		local prefix "J:"
	}

	adopath + "`prefix'/WORK/10_gbd/00_library/functions"

	cd "J:/WORK/01_covariates/02_inputs/smoking_prevalence/Bloomberg_Tobacco/02_collapse/03_crosswalk"
	
// Import the location hierarchy that has been pulled from the database
get_location_metadata, location_set_id(22) clear
keep location_id ihme_loc_id super_region_name
tempfile locations
save `locations', replace

use to_crosswalk.dta, clear

foreach i of var *_any_mean *_daily_mean *_ltd_mean {
	if "`i'"== "smoked_tob_daily_mean" continue
	cap regress smoked_tob_daily_mean `i' if to_keep==1, nocons beta
	if _rc continue
	mat reg_results = r(table)
	local name = subinstr("`i'", "_mean", "", .)
	predict psk_`name'
	gen skve_`name' = (reg_results[2,1])^2
	gen skmse_`name' = e(rmse)^2
	qui sum psk_`name'
	local a = r(max)
	qui sum smoked_tob_daily_mean if e(sample)
	local b = r(max)
	local c = max(`a', `b')
}

tempfile cw_step1
save `cw_step1', replace

preserve

foreach var in daily_mean ltd_mean any_mean {
rename *`var' `var'_*
rename *_ *
}

reshape long daily_ ltd_ any_, i(nid underlying_nid ihme_loc_id year_start year_end age_start age_end sex_id smaller_site_unit) j(type) string

	cap regress daily_ any_ if to_keep==1, nocons
	mat reg_results = r(table)
	gen any_coeff = reg_results[1,1]
	gen skve_any = (reg_results[2,1])^2
	gen skmse_any = e(rmse)^2
	local any_coeff = any_coeff
	local skve_any = skve_any
	local skmse_any = skmse_any

	cap regress daily_ ltd_ if to_keep==1, nocons
	mat reg_results = r(table)
	gen ltd_coeff = reg_results[1,1]
	gen skve_ltd = (reg_results[2,1])^2
	gen skmse_ltd = e(rmse)^2
	local ltd_coeff = ltd_coeff
	local skve_ltd = skve_ltd
	local skmse_ltd = skmse_ltd

restore

	gen ltd_coeff = `ltd_coeff'
	gen skve_ltd = `skve_ltd'
	gen skmse_ltd = `skmse_ltd'
	gen any_coeff = `any_coeff'
	gen skve_any = `skve_any'
	gen skmse_any = `skmse_any'

preserve

reshape long all_tob_ all_tob_not_cig_ smoked_tob_ cig_ cig_manuf_ cig_rolled_ smoked_tob_not_cig_ smokeless_tob_, i(sex_id age_start age_end ihme_loc_id year_start year_end smaller_site_unit underlying_nid nid to_keep) j(freq) string

foreach var of varlist all_tob_-smokeless_tob_ {
	if "`var'"== "smoked_tob_" continue
	cap regress smoked_tob_ `var' if to_keep==1, nocons
	mat reg_results = r(table)
	gen `var'coeff = reg_results[1,1]
	gen skve_`var' = (reg_results[2,1])^2
	gen skmse_`var' = e(rmse)^2
	local `var'coeff = `var'coeff
	local skve_`var' = skve_`var'
	local skmse_`var' = skmse_`var'
}

restore

foreach var in all_tob_ all_tob_not_cig_ cig_ cig_manuf_ cig_rolled_ smoked_tob_not_cig_ smokeless_tob_ {
	gen `var'coeff = ``var'coeff'
	gen skve_`var' = `skve_`var''
	gen skmse_`var' = `skmse_`var''
}

* replace smoked_tob_daily_mean by order (dual frequency-type crosswalk)
local predvar smoked_tob_any cig_daily all_tob_any all_tob_daily cig_manuf_daily all_tob_not_cig_daily
gen used_this_var = ""
gen cw_smoked_tob_daily_mean= smoked_tob_daily_mean
gen cw_smoked_tob_daily_ss = smoked_tob_daily_ss
gen ind_cwsk_tob_daily= 0 if smoked_tob_daily_mean!=.
local num = 1
foreach i of local predvar{
	gen isk_`i' = 1 if cw_smoked_tob_daily_mean==. & psk_`i'!=.
	replace used_this_var = "`i'" if smoked_tob_daily_mean==. & psk_`i'!=. & cw_smoked_tob_daily_mean==. 
	replace cw_smoked_tob_daily_mean=psk_`i' if cw_smoked_tob_daily_mean==.
	gen pesk_`i'= `i'_mean^2 * skve_`i' + skmse_`i' if isk_`i'==1
	replace ind_cwsk_tob_daily=`num' if isk_`i' == 1
	replace cw_smoked_tob_daily_ss = `i'_ss if isk_`i'==1 & cw_smoked_tob_daily_ss == .
	local num = `num' + 1
}

* replace the variance of predicted smk_tob_daily yhat to one column
gen cw_smoked_tob_daily_se = 0 if smoked_tob_daily_mean != .
gen cw_smoked_tob_daily_data_se = smoked_tob_daily_se
foreach i of local predvar {
	replace cw_smoked_tob_daily_se= sqrt(pesk_`i') if cw_smoked_tob_daily_se==.
	replace cw_smoked_tob_daily_data_se = `i'_se if cw_smoked_tob_daily_data_se==.
}

* perform separate frequency and type crosswalks for indicators without a good dual frequency-type crosswalk
foreach var in  cig_ cig_manuf_ {
	gen temp = 1 if cw_smoked_tob_daily_mean == . & `var'any_mean != .
	replace cw_smoked_tob_daily_mean = `var'any_mean * `var'coeff * any_coeff if cw_smoked_tob_daily_mean == .
	replace cw_smoked_tob_daily_se = (((`var'any_mean^2) * skve_`var') + skmse_`var') + (((`var'any_mean^2) * skve_any) + skmse_any)  if temp == 1
	replace cw_smoked_tob_daily_ss = `var'any_ss if cw_smoked_tob_daily_ss == . & temp == 1
	replace cw_smoked_tob_daily_data_se = `var'any_se if cw_smoked_tob_daily_data_se == . & temp == 1
	drop temp
}

drop if cw_smoked_tob_daily_mean == .
gen model_se = cw_smoked_tob_daily_se
replace cw_smoked_tob_daily_se = sqrt((cw_smoked_tob_daily_data_se^2) + (cw_smoked_tob_daily_se^2))

// clean up dataset
keep nid underlying_nid source_type smaller_site_unit ihme_loc_id year_start year_end age_start age_end sex_id type ss_imputed used_this_var cw_smoked_tob_daily_mean cw_smoked_tob_daily_ss cw_smoked_tob_daily_se cw_smoked_tob_daily_data_se model_se
rename cw_smoked_tob_daily_mean data
rename cw_smoked_tob_daily_ss sample_size
rename cw_smoked_tob_daily_se standard_error
rename cw_smoked_tob_daily_data_se data_se
rename used_this_var original_variable
rename model_se cw_model_se

* Recalculate sample sizes to feed into age-sex-split
replace sample_size = (data * (1-data)) / standard_error^2 if standard_error != 0

merge m:1 ihme_loc_id using `locations', nogen keep(3)

replace age_end = 84 if age_end >80
replace age_start = 10 if age_start < 10
drop if age_end < 10
drop if age_start > age_end
drop if sex_id == .

*Expand the sample sizes that were imputed to be consistent with the number of age-sex groups represented
gen age_covered = ceil((age_end - age_start) / 5)
replace sample_size = sample_size * age_covered if age_covered > 0 & ss_imputed == 1
replace sample_size = sample_size * 2 if sex_id == 3 & ss_imputed == 1
drop age_covered

replace original_variable = "smoked_tob_daily" if original_variable == ""

save "J:/WORK/01_covariates/02_inputs/smoking_prevalence/Bloomberg_Tobacco/02_collapse/03_crosswalk/crosswalked_dataset.dta", replace
export delimited using "J:/WORK/01_covariates/02_inputs/smoking_prevalence/Bloomberg_Tobacco/02_collapse/03_crosswalk/crosswalked_dataset.csv", replace











