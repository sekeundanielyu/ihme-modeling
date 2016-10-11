// Use DisMod input for age distribution and country-level paf estimates from
// 00_studylevel_hib.do for final hib paf estimates and writing csvs for save_results //


// Set up //
if c(os)=="Unix" global j "/home/j"
else global j "J:"
set more off
cap log close
clear all
set matsize 8000
set maxvar 10000

local date = c(current_date)

do "$j/WORK/10_gbd/00_library/functions/get_covariate_estimates.ado"
do "$j/WORK/10_gbd/00_library/functions/get_best_model_versions.ado"
do "$j/WORK/10_gbd/00_library/functions/get_estimates.ado"
do "$j/WORK/10_gbd/00_library/functions/get_location_metadata.ado"

// Get IHME location metadata //
get_location_metadata, location_set_id(9) clear
tempfile locations
save `locations'

// Get vaccine coverage estimates //
get_covariate_estimates, covariate_name_short(Hib3_coverage_prop) clear
drop age_group_id
drop sex_id
gen fcovmean = mean_value
gen fcovsd = (upper_value-lower_value)/2/1.96
gen hibmean = mean_value

tempfile hib_cov
save `hib_cov'

		use "J:\temp\user\LRI\vaccine type coverage.dta", clear
		keep if vtype == "PCV7"
		replace covmean = covmean / 100
		replace covupper = covupper / 100
		replace covlower = covlower / 100
		
		tempfile vtype
		save `vtype'		
		
		use location_id year_id paf_mean paf_sd fcovmean fcovsd optvi using "J:\temp\user\LRI\MidFiles\hib_RCT_studypaf.dta", clear
	
		merge m:1 location_id using `locations'
		//merge 1:1 ihme_loc_id using `locations'
		drop _m
		rename paf_mean hibmean
		rename fcovmean hib_cov
		rename fcovsd hib_covsd
//		gen hib_sd = .05
		rename optvi hibve
		gen hibvese = .0001
		//gen year_id = year
		tempfile hibve
		save `hibve'
		
		use `pcv_cov', clear
		replace gpr_lower = 0 if pcv3_pred <.01
		replace gpr_upper = 0 if pcv3_pred <.01
		replace pcv3_pred = 0 if pcv3_pred <.01
		***
		
		tempfile pcvcoverage
		save `pcvcoverage'
		gen region = "Africa" if regexm(region_name, "Africa")
		replace region = "Asia" if regexm(region_name, "Asia")
		replace region = "Europe" if regexm(region_name, "Europe")
		replace region = "LAC" if regexm(region_name, "Latin") |  regexm(region_name, "aribbean")
		replace region = "North America" if regexm(region_name, "North America")
		replace region = "Oceania" if regexm(region_name, "Oceania")
		tab region_name if region == ""
		replace region = "North America" if regexm(region_name, "Australasia")

		merge 1:1 location_id year_id using `hibve', keep(1 3) nogen
 
		merge m:1 region using `vtype', keep(3) nogen
		rename pcv3_pred vcov
		gen vcovsd = (gpr_upper - gpr_lower) / (2*1.96)
		rename covmean vtcov
		gen vtcovsd = (covupper - covlower)/ (2*1.96)
		
		gen fcovmean = vcov * vtcov
		gen fcovsd = sqrt(vtcovsd^2 * vcov^2 + vtcov^2 * vcovsd^2 + vcovsd^2 * vtcovsd^2)

		save `vtype', replace
		save "J:/temp/user/LRI/MidFiles/pneumo_vaccine_covs.dta", replace
}		
local vi .8 

local cnt 0

// Import age distribution from DisMod //

		insheet using "$j\temp\user\LRI\hib_dm_4_27re5nore\pred_out.csv", comma clear
		replace pred_median = pred_median[1] if age_upper < 5
		drop if age >=5
		drop if _n == 1
		local scale = pred_median[1]
		replace pred_median = pred_median / `scale'
		gen mrg = 1
		tempfile agescalar
		save `agescalar'
		use "$j/temp/user/LRI/MidFiles/hib_RCT_studies.dta", clear

// Meta analysis again of Hib RCT PAFs //
qui	    metan adlnrr adlnrrse `if', random title("`pat' Meta analysis of adjusted rr for `st'") nograph
		local par  `r(ES)' 
		local parl  `r(ci_low)'
		local paru  `r(ci_upp)'
		
		clear 
		set obs 1
		gen adlnrr = `par'
		gen adlnrrse = (`paru' - `parl') / (2*1.96)

		gen _0id = _n

		forval i = 1/1000 {
			gen draw`i' = rnormal(adlnrr, adlnrrse)
		}

		gen mrg = 1
		
// Use that value and adjust for age distribution //
		merge 1:m mrg using `agescalar', keepusing(age pred_median)

		qui foreach var of varlist draw1-draw1000 {
				replace `var' = (1 - exp(`var')) / pred_median
			}
				
		keep age adlnrr adlnrrse draw1-draw1000
		tostring age,force replace
		replace age = ".01" if age == ".0099999998"
		replace age = ".1" if age == ".1000000015"
		egen adve = rowmean(draw*)
		label variable adve "Adjusted VE for Hib"
		gen age_group_id = _n+1
		
		saveold "$j/temp/user/LRI/MidFiles/hib_age_study_paf.dta", replace

		tempfile madve
		save `madve'
				
		levelsof age, local(ages) c

// Return to Hib vaccine coverage, prep for uncertainty by taking 1000 draws //
		use location_id year_id fcovmean fcovsd using `hib_cov', clear
		drop if fcovmean == .

		// This takes a long time //
		run "$j\Project\Causes of Death\CoDMod\Models\B\codes\small codes\gen draws for a file.do" fcovmean fcovsd
		gen mrg = 1
		saveold "$j/temp/user/LRI/MidFiles/hib_fcov_draws.dta", replace

		tempfile main_i
		save `main_i'

// Get 1000 draws for optimal VE //		
		clear 
		set obs 1
		forval i = 1/1000 {
			gen optv`i' = `vi'
		}
		gen mrg = 1
		tempfile optve
		save `optve'
		
// Everything is prepped. For each age group in GBD, estimate 1000 draws of Hib Paf //
// and append those files to master dataframe //
qui		foreach ag of local ages { 
			di in red "`ag' " _c
			local cnt = `cnt' + 1 
			use `madve' if age == "`ag'", replace
			gen mrg = 1
			cap erase `madveuse'
			tempfile madveuse
			save `madveuse'
			
			use `main_i', clear
			
			merge m:1 mrg using `optve', nogen

			merge m:1 mrg using `madveuse', nogen

			keep if inlist(year_id, 1990, 1995, 2000, 2005, 2010, 2015)
			
// PAF estimation //
qui 		forval i =1/1000 {
				replace v`i' = 1 if v`i' > 1
				replace v`i' = 0 if v`i' < 0
				replace draw`i' = draw`i' * (1 - v`i' * optv`i') / (1 - draw`i' * v`i' * optv`i')
			}
			egen paf_mean = rowmean(draw*)
			egen paf_sd = rowsd(draw*)
			egen float paf_lower = rowpctile(draw*), p(2.5)
			egen float paf_upper = rowpctile(draw*), p(97.5)

			save "$j/temp/user/LRI/By Age/Hib/paf_`ag'_`date'.dta", replace
			
	if `cnt'== 1 {
		tempfile byage
		save `byage'
	}
	else {
		append using `byage'
		save `byage', replace 
	}
}

cap drop optv1-optv1000
cap drop v1-v1000
save "$j/temp/user/LRI/By Age/Hib/hib_paf_draws.dta", replace
