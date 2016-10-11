// Calculate study-level attributable fractions for Hib 
// These outputs are then used in DisMod to calculate age-specific PAFs
// the meta-analytic effect size result is then adjusted for national-level
// values to estimate a final hib paf. //

clear all
set more off
cap log close
set maxvar 15000
set seed 2038947

do "J:/WORK/10_gbd/00_library/functions/get_covariate_estimates.ado"
do "J:/WORK/10_gbd/00_library/functions/get_best_model_versions.ado"
do "J:/WORK/10_gbd/00_library/functions/get_estimates.ado"
do "J:/WORK/10_gbd/00_library/functions/get_location_metadata.ado"

// run Hib first
local pat  hib
local file Study-Level_PAFs

// This is an adjustment to account for imperfect vaccine effectiveness
local vi .8  

// Get vaccine coverage estimates //
get_covariate_estimates, covariate_name_short(Hib3_coverage_prop) clear
drop age_group_id
gen fcovmean = mean_value
gen fcovsd = (upper_value-lower_value)/2/1.96
tempfile hib_cov
save `hib_cov'

get_covariate_estimates, covariate_name_short(PCV3_coverage_prop) clear
drop age_group_id
gen pcv_mean = mean_value
gen pcv_sd = (upper_value-lower_value)/2/1.96
tempfile pcv_cov
save `pcv_cov'

// Get IHME location metadata
get_location_metadata, location_set_id(9) clear
tempfile locations
save `locations'

// Right now Hib and PCV are done separately but Hib must be done first //

*****Reads the data and generates new varaibles: ve as vaccine efficacy, vi as vaccine efficacy against invasive, and cov as coverage"*******
// Extracted study data, format variables in RR and log space
		import delimited "J:/temp/user/LRI/Files/hib-data.csv", clear		
		drop if status == "EXCLUDE"
		gen author = first + "_" +  iso3 + string(studyyear_end)
		gen ihme_loc_id = iso3
		gen rr_inv = (100 - veinvasivedisease) / 100
		gen rr_inv_low = (100 - v44 ) / 100
		gen rr_inv_up = (100 - v43 ) / 100
		
		foreach var of varlist rr_* {
					gen ln_`var' = ln(`var')
		}
		
		gen ln_rr_se = (ln_rr_inv_up- ln_rr_inv) / 1.96

	keep if studytype=="RCT"

/// Uncertainty comes from bootstrapped draws ///
	gen _0id = _n
	
// This central do file just creates 1000 draws from a normal distribution given mean and sd //
// Outputs are saved in a matrix //
	run "J:\Project\Causes of Death\CoDMod\Models\B\codes\small codes\gen matrix of draws.do" lnrr_ve lnrr_vese ve
	run "J:\Project\Causes of Death\CoDMod\Models\B\codes\small codes\gen matrix of draws.do" lnrr_vi lnrr_vise vi
	run "J:\Project\Causes of Death\CoDMod\Models\B\codes\small codes\gen matrix of draws.do" cov covse cov
// calculate matrix mathematics (v is the Ve/Vi equation in RR) //
		mata 
				e = st_matrix("ve")
				i = st_matrix("vi")
				c = st_matrix("cov")
				v = (1 :- exp(e)) :/ (1 :- exp(i)) :/ c
				r = ln( 1 :- v)
				st_matrix("result",r)
		end
	sort _0id
	svmat result, names(draw)
	egen adlnrr = rowmean(draw*)
	egen adlnrrse = rowsd(draw*)
	drop draw*
	
// Save summary file //	
	save "J:/temp/user/LRI/MidFiles/hib_RCT_studies.dta", replace
	
//// Prepare for DisMod (sub/small functionality) ////
	gen time_lower = studyyear_start
	gen time_upper = studyyear_end
	gen age_lower = age_start
	gen age_upper = age_end
	gen super = "none"
	encode source,gen(sourceid)
	gen subreg = "none"
	gen integrand = "incidence"
	// Exporting 'corrected' values for adlnrr
	gen meas_value = exp(adlnrr)
	gen meas_stdev = (exp(adlnrrse) - 1)*meas_value
	gen x_sex = 0
	gen x_ones = 1
	gen x_befaft = 0
	gen x_ccorcohort = 0
	replace x_befaft = 1 if regexm(studytype,"fore")
	replace x_ccorcohort = 1 if regexm(studytype,"ontrol") | regexm(studytype,"ohort")
	drop if meas_value == .
	cap drop subreg region super

	merge m:1 ihme_loc_id using `locations', keepusing(region_name super_region_name) keep(1 3)
	gen subreg = ihme_loc_id
	rename region_name region
	rename super_region_name super
	
	foreach var of varlist subreg region super {
		cap replace `var' = subinstr(`var'," ","_",.)
		cap replace `var' = subinstr(`var'," ","_",.)
		cap replace `var' = subinstr(`var'," ","_",.)
		cap replace `var' = subinstr(`var',"__","_",.)
	}

// save file for dismod age pattern //
	outsheet source iso3 author studytype time_* age_* super region sourceid subreg integrand meas_value meas_stdev x_* ///
		using "J:/temp/user/LRI/MidFiles/hib_fordismod.csv", comma replace
	
//// Create a non-age specific PAF for country, year after adjusting for country level Hib vaccine coverage ////
// This will be used in the pneumococcal PAF calculation //
// Meta-analysis of the study-level PAFs //
	metan adlnrr adlnrrse, random nograph
	local par  `r(ES)' 
	di in red `par' 
	local parl  `r(ci_low)'
	local paru  `r(ci_upp)'

// Pulls back in the Hib vaccine coverage covariate //	
	use location_id year_id fcovmean fcovsd using `hib_cov', clear
	gen adve = 1-exp(`par')
	gen advese = adve * (`paru' - `parl') / (2*1.96)
	gen optvi = `vi'
	
	label variable adve "Crude PAF for Hib"
	label variable advese "Standard error of the crude PAF for Hib"
	label variable optvi "Current country Hib vaccination effectiveness (`vi')"

	drop if year == .
// 1000 draws from mean, std //
	run "J:\Project\Causes of Death\CoDMod\Models\B\codes\small codes\gen draws for a file.do" fcovmean fcovsd
	gen mrg = 1
	tempfile main_i
	save `main_i'
	
// The base study-level PAF, 'adve' is just one value (effect size from meta-analysis of RCTs) //
	clear 
	set obs 1
	gen adve = 1-exp(`par')
	gen advese = adve * (`paru' - `parl') / (2*1.96)
	gen _0id = _n
	run "J:\Project\Causes of Death\CoDMod\Models\B\codes\small codes\gen matrix of draws.do" adve advese madve
	svmat madve, names(ad) 
	gen mrg = 1
	tempfile madve
	save `madve'
	
// Merge them together, calculate PAF by matrix multiplication ! //
	use `main_i', clear
	merge m:1 mrg using `madve'
	
	forval i =1/1000 {
		gen paf`i' = ad`i' * (1 - v`i' * optvi) / (1 - ad`i' * v`i' * optvi)
	}
	
	egen paf_mean = rowmean(paf*)
	egen paf_sd = rowsd(paf*)
	gen finve = paf_mean
	drop paf* v* ad* id var2 mrg _0id _m

	save "J:/temp/user/LRI/MidFiles/hib_RCT_studypaf.dta", replace		
}
