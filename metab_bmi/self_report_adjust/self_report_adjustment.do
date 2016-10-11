/***********************************************************************************************************															
 Project: Risk Factors BMI																	
 Purpose: Adjust for self-report bias													
***********************************************************************************************************/

clear all
set more off
cap log close

// System stuff
	if c(os) == "Unix" {
		local prefix "/home/j"
		set more off
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		local prefix "J:"
	}

	adopath + "`prefix'/WORK/10_gbd/00_library/functions"

local date = subinstr("`c(current_date)'", " ", "", .)

get_location_metadata, location_set_id(22) clear
keep ihme_loc_id region_name super_region_name location_id
tempfile geo_hierarchy
save `geo_hierarchy', replace

////////////////////////////////////////
//// Fit Model
////////////////////////////////////////

foreach indic in obese_mean overweight_mean {
	foreach sex of numlist 1 2 {

		if "`indic'" == "overweight_mean" {
			local shortname "ow"
		}
		if "`indic'" == "obese_mean" {
			local shortname "ob"
		}

		* Read in the dataset
		use "`prefix'/WORK/05_risk/risks/metab_bmi/data/exp/prepped_data/wide_gs_`shortname'.dta", clear

		merge m:1 ihme_loc_id using `geo_hierarchy', nogen keep(3)

		* Generate the measured indicator
		gen measured = 1 if cv_diagnostic == "measured"
		replace measured = 0 if measured == .

		* Generate time period indicator (splitting years n=36 into 3 12-year segments)
		gen year_id = floor((year_start + year_end) / 2)
		gen time_period = "1980-1991" if inrange(year_id, 1980, 1991)
		replace time_period = "1992-2003" if inrange(year_id, 1992, 2003)
		replace time_period = "2004-2015" if inrange(year_id, 2004, 2015)

		* Running the self-report adjustment only for adults
		keep if age_start >= 20

		* Prep for logit transform
		replace `indic' = .999 if `indic' == 1
		replace `indic' = .001 if `indic' == 0
		gen logit_`indic' = logit(`indic')

		preserve

		keep if sex_id == `sex'

		* Fit model
		mixed logit_`indic' measured##i.age_start || super_region_name: measured || region_name: measured || ihme_loc_id: measured || time_period: measured, reml iterate(10)

		* Extract random effect coefficients
		predict re*, reffects
		predict re_se*, reses

		* Extract fixed effect coefficients
		mat coeffs = e(b)
		mat variances = e(V)

		gen base_adjust = coeffs[1,2]
		gen base_variance = variances[2,2]

		gen age_effect = .
		local counter = 29
		foreach num of numlist 20(5)80 {
			replace age_effect = coeffs[1,`counter'] if age_start == `num'
			local counter = `counter' + 1
		}

		gen age_variance = .
		local counter = 29
		foreach num of numlist 20(5)80 {
			replace age_variance = variances[`counter',`counter'] if age_start == `num'
			local counter = `counter' + 1
		}

		* Generate adjustment factor (includes super region, and region random effects; take time period and country as noise)
		gen total_adjust = re1 + re3 + base_adjust + age_effect

		* Adjust the self-report data
		gen adjusted = logit_`indic' + total_adjust if measured == 0
		replace adjusted = logit_`indic' if measured == 1		
		replace adjusted = invlogit(adjusted)

		tempfile `indic'_sex_`sex'
		save ``indic'_sex_`sex'', replace

		restore
	}	
}

use `overweight_mean_sex_1', clear
append using `overweight_mean_sex_2'
keep age_start sex_id age_effect super_region_name re1 region_name re3 re_se1 re_se3 base_adjust base_variance age_variance
duplicates drop *, force
tempfile overweight_adjust
save `overweight_adjust', replace

erase `overweight_mean_sex_1'
erase `overweight_mean_sex_2'

use `obese_mean_sex_1', clear
append using `obese_mean_sex_2'
keep age_start sex_id age_effect super_region_name re1 region_name re3 re_se1 re_se3 base_adjust base_variance age_variance
duplicates drop *, force
tempfile obese_adjust
save `obese_adjust', replace

erase `obese_mean_sex_1'
erase `obese_mean_sex_2'

////////////////////////////////////////
//// Extract coefficients for prediction
////////////////////////////////////////

foreach indic in obese overweight {

	if "`indic'" == "overweight" {
		local shortname "ow"
	}
	if "`indic'" == "obese" {
		local shortname "ob"
	}

	use ``indic'_adjust', clear

	* Extract base adjust
	preserve
		keep sex_id base_adjust base_variance
		rename base_adjust base_adjust_`shortname'
		rename base_variance base_variance_`shortname'
		duplicates drop *, force
		tempfile base_adjust
		save `base_adjust', replace
		collapse (mean) base_adjust_`shortname' base_variance_`shortname'
		gen sex_id = 3
		append using `base_adjust'
		save `base_adjust', replace
	restore

	* Extract age effects
	preserve
		keep age_start sex_id age_effect age_variance
		rename age_effect age_effect_`shortname'
		rename age_variance age_variance_`shortname'
		duplicates drop *, force
		tempfile age_effects
		save `age_effects', replace
		collapse (mean) age_effect_`shortname' age_variance_`shortname', by(age_start)
		gen sex_id = 3
		append using `age_effects'
		save `age_effects', replace
	restore

	* Extract geographic effects
	preserve
		keep super_region_name re1 re_se1 sex_id
		rename re1 re1_`shortname'
		rename re_se1 re_se1_`shortname'
		duplicates drop *, force
		tempfile super_region_effects
		save `super_region_effects', replace
		collapse (mean) re1_`shortname' re_se1_`shortname', by(super_region_name)
		gen sex_id = 3
		append using `super_region_effects'
		save `super_region_effects', replace
	restore
	preserve
		keep region_name re3 re_se3 sex_id
		rename re3 re3_`shortname'
		rename re_se3 re_se3_`shortname'
		duplicates drop *, force
		tempfile region_effects
		save `region_effects', replace
		collapse (mean) re3_`shortname' re_se3_`shortname', by(region_name)
		gen sex_id = 3
		append using `region_effects'
		save `region_effects', replace
	restore

////////////////////////////
//// Run the Adjustment
////////////////////////////
	use "`prefix'/WORK/05_risk/risks/metab_bmi/data/exp/prepped_data/wide_full_`shortname'.dta", clear

	merge m:1 ihme_loc_id using `geo_hierarchy', nogen keep(3)

	* Generate the measured indicator
	gen measured = 1 if cv_diagnostic == "measured"
	replace measured = 0 if measured == .

	* Generate time period indicator (splitting years n=36 into 3 12-year segments)
	gen year_id = floor((year_start + year_end) / 2)
	gen time_period = "1980-1991" if inrange(year_id, 1980, 1991)
	replace time_period = "1992-2003" if inrange(year_id, 1992, 2003)
	replace time_period = "2004-2015" if inrange(year_id, 2004, 2015)
	
	* Generate the mid age, which is rounded to the closest 5 year age group
	gen age_mid = round(((age_start + age_end)/2), 5)
	gen age_temp = age_start // Store the actual age_start while we merge
	drop age_start
	rename age_mid age_start
	replace age_start = 80 if age_start > 80 & age_start != .

	keep if age_start >= 20

	merge m:1 sex_id using `base_adjust', nogen
		erase `base_adjust'
	merge m:1 age_start sex_id using `age_effects', nogen
		erase `age_effects'
	merge m:1 super_region_name sex_id using `super_region_effects', nogen
		erase `super_region_effects'
	merge m:1 region_name sex_id using `region_effects', nogen
		erase `region_effects'

	bysort region_name: egen temp = mean(re3_`shortname')
	replace re3_`shortname' = temp if re3_`shortname' == .
	drop temp
	bysort region_name: egen temp = mean(re_se3_`shortname')
	replace re_se3_`shortname' = temp if re_se3_`shortname' == .
	drop temp
	bysort super_region_name: egen temp = mean(re1_`shortname')
	replace re1_`shortname' = temp if re1_`shortname' == .
	drop temp
	bysort super_region_name: egen temp = mean(re_se1_`shortname')
	replace re_se1_`shortname' = temp if re_se1_`shortname' == .
	drop temp

	* Prep for logit transform
	replace `indic'_mean = .999 if `indic'_mean == 1
	replace `indic'_mean = .001 if `indic'_mean == 0
	gen logit_mean = logit(`indic'_mean)
	gen logit_variance = (`indic'_se)^2 * (1/(`indic'_mean*(1-`indic'_mean)))^2

	* Adjust mean
	gen logit_adjusted_mean = logit_mean + base_adjust + age_effect + re1 + re3 if cv_diagnostic == "self-report"
	replace logit_adjusted_mean = logit_mean if cv_diagnostic == "measured"

	* Adjust variance
	gen logit_adjusted_variance = logit_variance + base_variance + age_variance + re_se1^2 + re_se3^2 if cv_diagnostic == "self-report"
	replace logit_adjusted_variance = logit_variance if cv_diagnostic == "measured"

	* Back transform to normal space
	gen adjusted_mean = invlogit(logit_adjusted_mean)
	gen adjusted_variance = logit_adjusted_variance / (1/(adjusted_mean * (1-adjusted_mean)))^2

	* Replace with true age start
	replace age_start = age_temp

	* Adjust sample size to be consistent with the updated estimate
	replace `indic'_ss = (adjusted_mean *(1-adjusted_mean)) / adjusted_variance if adjusted_variance != . & adjusted_variance != 0

	* Clean dataset
	keep nid year_start year_end ihme_loc_id sex_id cv_urbanicity cv_diagnostic age_start age_end smaller_site_unit year_id adjusted_mean adjusted_variance location_id `indic'_ss
	gen standard_deviation = .
	rename adjusted_variance variance
	rename adjusted_mean data
	rename `indic'_ss sample_size
	
	export delimited using "`prefix'/WORK/05_risk/risks/metab_bmi/data/exp/adjusted_data/wide_full_`shortname'.csv", replace
}
