//// Create cholera files for draws runs, launched by 'launch_draws.do' on cluster ////
// This file is performed 1000 times as it produces a single draw for 
// cholera fatal and non-fatal PAFs which are then saved centrally for DALYNator //

clear all
set more off

// Set J //
if c(os)=="Unix" global j "/home/j"
else global j "J:"
local project 		cholera_Draws

/// Is this a local test run? ///
gen test = 0

if test == 0 {
	local iter `1'
}
else {
	local iter 1
}


cap log close

//// Prepare necessary covariates, location data ////
// Get countries //
include "$j/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
get_location_metadata, location_set_id(9) clear
gen iso3 = ihme_loc_id
tempfile countries
save `countries'

// Get covariates // 
use "$j/temp/Cholera/MidFiles/covariates.dta", clear
tempfile hs
save `hs'

//// Start main process ////
cap log close
log using "$j/temp/Cholera/Logfiles/logfile_`iter'.smcl", replace

use "$j/temp/Cholera/MidFiles/population_data.dta", clear
keep if inlist(year_id, 1990, 1995, 2000, 2005, 2010, 2015)
tempfile pop
save `pop'

local iter2 = `iter' - 1
use age_group_id sex_id location_id measure_id year_id draw_`iter2' if age_group_id <= 21 & measure_id==6 using "$j/temp/Cholera/MidFiles/inc_prev_draws.dta", clear
gen measure = "incidence"
rename draw_`iter2' meanincidence
merge 1:1 age_group_id year_id sex_id location_id using `pop', keep(3) nogen
tempfile inc
save `inc'

use age_group_id sex_id location_id measure_id year_id draw_`iter2' if age_group_id <= 21 & measure_id==5 using "$j/temp/Cholera/MidFiles/inc_prev_draws.dta", clear
gen measure = "prevalence"
rename draw_`iter2' meanprevalence
merge 1:1 age_group_id sex_id location_id year_id using `inc', nogen keep(3)
keep meanincidence meanprevalence pop location_id age_group_id sex_id year_id

reshape wide meanincidence meanprevalence pop,i( location_id age_group_id sex_id ) j(year_id)

cap foreach v in mean* pop {
		forval i = 1990/2015 {
			cap gen `v'`i' = .
		}
}
aorder
order location_id age_group_id sex_id  mean*  pop*
reshape long meanincidence meanprevalence pop,i( location_id age_group_id sex_id ) j( year_id)

foreach var of varlist meanincidence meanprevalence pop {
		gen ln`var' = ln(`var')
		by location_id age_group_id sex_id, sort : ipolate ln`var' year_id , generate(int_`var') epolate
		replace `var' = exp(int_`var') if `var' == .
		drop ln`var' int_`var'
}


merge m:1 location_id using `countries', keep(3) nogen
drop if super_region_id == .
drop if region_id == .
tempfile prv_pop
save `prv_pop'
preserve
//save "$j/temp/Cholera/MidFiles/prv_file.dta", replace

/// Load age pattern from DisMod proportion model at global level

use age_group_id draw_`iter' using "$j/temp/Cholera/MidFiles/age_pattern_draws.dta", clear
merge m:m age_group_id using "$j/temp/GEMS/age_mapping.dta", nogen keep(3)
rename draw_`iter'  shp
tempfile shape
save `shape'

restore

merge m:1 age_group_id using `shape', nogen

replace shp = shp
tempfile prv
save `prv'

/// Load Odds Ratios from GEMS, apply to Cholera Data ///
use modelable_entity_id age_group_id lnor_`iter' using "$j/temp/GEMS/Regressions/fixed_effects.dta", clear
keep if modelable_entity_id == 1182
rename lnor_`iter' lnor
merge m:m age_group_id using "$j/temp/GEMS/age_mapping.dta", nogen
tempfile coefs
save `coefs'
gen pf = 1-exp(-lnor)
replace pf = 0 if pf<0
mkmat pf, matrix(coefs) rownames(age_group_id)
mat list coefs

/// Import Proportion data from literature ///
use nid-sample_size extractor is_outlier cv_inpatient cv_community draw_`iter' using "$j/temp/Cholera/MidFiles/latest_cholera_data.dta", clear
drop if cv_suspected == 1
keep if is_outlier==0
keep if measure == "proportion"

replace location_id = 11 if location_name=="Indonesia"

rename mean meas_value_old
rename draw_`iter' meas_value
replace meas_value = logit(meas_value)

mixed meas_value cv_inpatient_sample || location_name:
replace meas_value = invlogit( meas_value + (0 - cv_inpatient_sample)*_b[cv_inpatient_sample])

gen order = _n
gen n_years = year_end-year_start + 1
expand n_years
bysort order: gen year = year_start + _n - 1

local n = _N
gen predo = .
qui forval i = 1/`n' {

		local age_start = age_start[`i']
		local age_end = age_end[`i']
		local is  = location_id[`i']
		local year =year[`i']
		local mean = meas_value[`i']
		if `age_start' >= 5 local coef_corr = coefs[5,1]
		else if `age_end' < 1 local coef_corr = coefs[1,1]
		else if `age_start' >= 1 & `age_end' <5 local coef_corr = coefs[4,1]
		else local coef_corr = coefs[1,1]
		if (`age_end' != 1 & `age_end' < 1) local age_end 1
		if (`age_end' != 5 & `age_end' < 5 & `age_end' > 1 ) local age_end 5
		
		preserve
		keep if _n == `i'
		use location_id meanincidence meanprevalence pop age_group_id year_id age_lower age_upper shp if year_id == `year' & location_id == `is' & age_upper >= `age_start' & age_lower <= `age_end' using `prv', clear 
		//di in red "`c(N)' ages:`age_start'-`age_end' `is' `year' `mean' and coef `coef_corr'; " _c
		if _N != 0 {
				replace meanprevalence = 1*10^-9 if meanprevalence < 0
				gen prv = meanprevalence * pop
				mean shp [pw=prv]
				local prop = _b[shp]
				local correction = `coef_corr' * `mean' / `prop'
				gen new_cases = `correction' * meanincidence * pop * shp
				qui total new_cases
				local expected = _b[new_cases]
		}
		else local expected 9999999
		restore
		replace predo = `expected' in `i'
 }				
	
/// Generate predicted, expected cases, model under-reporting to WHO ///
		gen year0 = year
		gen year_id = year
/// Case notifications don't have subnationals! ///		
		replace location_name = "India" if regex(location_name, "Urban")
		replace location_name = "India" if regex(location_name, "Rural")
		tostring location_id, generate(str_id)
		gen first_digit = substr(str_id, 1, 2)
		replace location_name = "Kenya" if first_digit== "35"

		merge m:m location_name year_id using "$j/temp/Cholera/MidFiles/case_notifications.dta", nogen keep(1 3)
		// keep if cases > 10
		format %28s location_name
		gen expected = predo if predo != 9999999
		gen under_reportpct = cases *100/ expected

		collapse expected [aw= 1/ standard_error^2], by(nid year_id location_name cases)
		gen under_reportpct = cases *100/ expected
		merge m:m location_name year_id using "$j/temp/Cholera/MidFiles/case_notifications.dta", nogen
		merge m:m location_name using `countries', keep(3) nogen
		tempfile main
		save `main'
		
		merge m:1 location_id year_id using `hs'

		drop _m

		gen multi = under_reportpct/100
		bysort location_id: egen maxyear= max(year_id)
		replace multi = 0.95 if super_region_name == "High-income" & under_report == . & year >2000 | multi > 0.95 & multi != . 
				
		gen lg = logit(multi)
		gen lnldi = ln(mean_ldi)
		
	replace mean_hsa = -3 if mean_hsa <-3
	regress lg mean_hsa if cases != . [aw = 1/cases]
	local hsa = _b[mean_hsa]
	bysort location_id: egen hsa = mean(mean_hsa)
	gen lg2 = lg + (1.69 - hsa) * `hsa'

	mixed lg2 if cases != .  || super_region_name: || region_name: || location_name:
		predict p*, reffect
		bysort super_region_name: egen s_re = mean(p1)
		replace s_re=0 if s_re==.
		bysort region_name: egen r_re = mean(p2)
		replace r_re=0 if r_re == .

	gen prp = _b[_cons] + s_re + r_re 
	replace prp = prp - (1.69-hsa)*`hsa'

	gen predict = invlogit(prp)

		drop r_re s_re //g_re g_yre  re
		tempfile main
		save `main'
		
use if pop != . using `prv_pop', clear

		rename meanincidence mean
		gen age = age_group_id
		drop *prevalence
		drop if sex_id==3
		tempfile pop
		save `pop', replace

		gen case = mean *pop
		collapse (sum) case pop,by(location_id year_id)
	merge 1:m location_id year_id using `main', nogen 
		drop region_name super_region_name
	merge m:1 location_id using `countries', keep(3) nogen
		gen lncases = ln(cases)
		gen true_cases = cases / predict 
		rename case inc
		gen prop = true_cases / inc
		//replace prop = 1 if prop > 1
		keep if year_id >=1990

		gen lnprop = logit(prop)
		gen lnsev = ln(mean_sev)
		mixed lnprop lnsev if prop < 0.1 & prop > 0.0001 || super_region_id: || region_id: ||location_id: lnsev
		predict ltr*,reffect
		bysort super_region_name: egen s_re = mean(ltr1) 
		replace s_re = 0 if s_re == .
		bysort region_name: egen r_re = mean(ltr2) 
		replace r_re = 0 if r_re == .
		replace ltr3 = 0 if ltr3 == .
		replace ltr4 = 0 if ltr4 == .

		gen finalprop = invlogit(_b[_cons] + s_re + r_re + (_b[lnsev]) * lnsev)
	
		gen overall = finalprop * inc
		table year_id, contents(sum overall)
		drop mean_ldi mean_hsa
tempfile master
save `master'


/// Apply age pattern again from DisMod ///

		use age_group_id draw_`iter' using "$j/temp/Cholera/MidFiles/age_pattern_draws.dta", clear
		cap drop sex_id
		rename draw_`iter' shp
		replace shp = 1-shp
		merge 1:m age_group_id using `pop', nogen

		gen ncases = mean * pop * shp
		drop shp
		gen sex = "Both"
		replace sex = "Female" if sex_id==2
		replace sex = "Male" if sex_id==1
		keep mean sex ncases pop location_id year_id age_group_id

		reshape wide mean ncases pop,i(location_id year_id age_group_id) j(sex) string
		reshape wide mean* ncases* pop*,i(location_id year_id) j(age_group_id) 
		egen totalmean= rowtotal(mean*)
		egen totalncases= rowtotal(ncases*)
		egen totalpop= rowtotal(pop*)
		tempfile inc
		save `inc'

use `master', clear

		cap drop _m
		drop if overall == .
		duplicates drop location_id year_id, force
	
	merge 1:1 location_id year_id using `inc',keep(1 3)

		foreach var of varlist ncases* {
				gen s_`var' = overall * `var' / totalncases
		}

		keep location_id year_id s_ncases* pop* mean* overall finalprop
		reshape long s_ncasesMale s_ncasesFemale ncasesMale ncasesFemale popMale popFemale meanMale meanFemale, i(location_id year_id) j(age_group_id) string
		rename pop oldpop
		
		reshape long s_ncases ncases pop mean, i(location_id year_id age_group_id) j(sex_id) string
		rename age_group_id age
		gen age_group_id = real(age)
		gen newprop = s_ncases/( mean* pop)
		keep if sex_id == "Female" | sex_id == "Male"
		rename sex_id sex
		gen sex_id = 1
		replace sex_id=2 if sex=="Female"
		merge m:1 location_id using `countries'
		cap drop _m
		sort location_id year_id sex_id age_group_id
		
tempfile morbidity
save `morbidity', replace

/// Morbidity has been saved, now import Case Fatality ///

use age_group_id location_id year_id sex_id draw_`iter2' using "/snfs2/HOME/Etiologies/Data/death_draws_full.dta", clear
rename draw_`iter2' d_diarrhea
tempfile mortality
save `mortality'

use age_group_id location_id year_id sex_id cf_`iter' using "/snfs2/HOME/Etiologies/Data/cholera_cf_draws.dta", clear
merge m:m age_group_id location_id year_id sex_id using `mortality', keep(3)

		cap drop _m
		merge m:m location_id year_id sex_id age_group_id using `morbidity'
		rename mean diarr_inc
		replace finalprop = 1 if finalprop>1
		sort location_name year_id sex_id age_group_id
		gen n_diarrhea = diarr_inc * pop
		gen s_ndeaths = (1-exp(-diarr_inc* cf_`iter' * finalprop)) * pop  
		
		table region_name year_id if inlist(year_id, 1990, 1995, 2000, 2005, 2010, 2015), c(sum n_diarrhea sum d_diarrhea sum s_ncases  sum s_ndeaths) row
		
		gen death_fr = 	s_ndeaths / d_diarrhea
		replace death_fr = 0 if death_fr < 0
		replace death_fr = 1 if death_fr > 1
		replace newprop = 0 if newprop <0
		replace newprop = 1 if newprop >1
		gen mortality_`iter' = death_fr
		gen morbidity_`iter' = newprop

		keep if most_detailed == 1
		keep age_group_id year_id sex_id location_id morbidity* mortality*
		sort location_id year_id sex_id age_group_id 
		keep if inlist(year_id, 1990, 1995, 2000, 2005, 2010, 2015)

save "$j/temp/Cholera/Final Draws/draws_`iter'", replace
log close




