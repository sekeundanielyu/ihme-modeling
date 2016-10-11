// 
// SDG paper
// July 25, 2016
// dealing with ITN numbers for UHC variable

/* steps:
0: bring in inclusion/exclusion to adjust accordingly and see how things match for endemicity in the draws we have
1: bring in Abie's draws for ITN coverage OUTSIDE Africa (proportion sleeping under bed net at night)
2: bring in PAR from coview for OUTSIDE Africa
3: Risk adjusted ITN coverage, so for each draw, divide by PAR
	risk adjusted ITN coverage = (coverage proportion) / PAR 
								= (# w/ ITN / # total pop) / (# at risk / # total pop)
[save]
5: bring in absolute population AR from MAP for Africa (for first run use Abie's numbers again)
6: bring in absolute population for Africa from IHME
7: PAR for Africa = MAP Pop AR estimates / IHME pop total
8: Look to see if there are any proportions over 1, and replace those to 1
9: bring in draws for Africa
10: Risk adjusted ITN coverage = (coverage*population) / PAR
[save]
*/
*****************************************************************************************
// prep stata
clear all
set more off
set type double, perm
set mem 2g
set maxvar 32000

if c(os) == "Unix" {
	global prefix "/home/j"
	set odbcmgr unixodbc
}
else if c(os) == "Windows" {
	global prefix "J:"
}
**************************************************************************************************
// First, bring in itn draws from Abie
import delimited "$prefix/temp/X/sdg/data/itn_outsideafrica_draws.csv", clear
drop if location_name=="Dem. Rep. of Congo" // there was a duplicate w diff spelling
egen itn_coverage_draw = rowmean(itn_coverage_draw_*)
drop itn_coverage_draw_*

// just keep the locations we need (get rid of subnats to increase efficiency)
merge m:1 location_name using "$prefix/temp/X/sdg/data/locs_needed.dta", keep(1 3)
drop _m // Abie's data is missing 105 locations, probably MAP and non-endemic
drop if location_name==""

tempfile abies_numbers
save `abies_numbers', replace

// add in Samir's draws
import delimited "$prefix/temp/X/sdg/data/_itn_maps_all_locs.csv", clear
drop if year_id >=2016 
egen itn_map = rowmean(itn_map_draw_*)
drop itn_map_draw_*
tempfile map_draws
save `map_draws', replace

// merge all draws together
merge 1:1 location_name year_id using `abies_numbers' // want to keep all for now but fill in map's draws on merged ones
replace location_name= trim(location_name)
drop if location_name==""
/*
encode location_name, gen(location_encoded)

tsset location_encoded year_id 
tsfill, full

// for anything that exists in both MAP and Abie's draws, replace value with Abie's draws
// use 2014 values for missing 2015 values (Abie's numbers didn't have 2015)

forvalues v = 0/999 {
	sort location_encoded year_id
	replace itn_coverage_draw_`v' = itn_map_draw_`v' if _m==3
	bysort location_encoded: carryforward itn_coverage_draw_`v', replace
	drop itn_map_draw_`v'
 }
 */
// sort location_encoded year_id
replace itn_coverage_draw = itn_map if (itn_coverage_draw ==. & itn_map !=.) | _m==3
// drop itn_map
/*
bysort location_encoded: carryforward itn_coverage_draw_`v', replace
	drop itn_map
	
drop location_name
decode location_encoded, gen(location_name)
drop location_encoded
*/
// rid ourselves of extraneous variables
drop _m super_region_name region_name

// just keep the locations we need (get rid of subnats to increase efficiency)
merge m:1 location_id using "$prefix/temp/X/sdg/data/locs_needed.dta"
keep if _m==3 // all locations are present (199)
drop _m

tempfile all_draws
save `all_draws'
******************************************************************************************
// bring in whatever means we have

import delimited "$prefix/temp/X/sdg/data/itn_coverage_prop_v3161", clear

merge 1:1 location_id year_id using `all_draws'


*****************************************************************************************
// Bring in inclusion/exclusion criteria
	// this data represents which countries we make estimates for and which we do not
import delimited "$prefix/temp/X/sdg/data/malaria_exclusions_Tracy.csv", clear

//Using this data, we will create three simplified categories: 
// 1) malaria endemic "always" where they have malaria every year from 1980-2015;
// 2) malaria-free "always" where they never have malaria during those years these will all get 100%, perfect coverage
// 3) those that change from 1 to 0 during the 1980-1999 (pre-ITN) time period. (these will all get 100%, perfect coverage)
	// this is because they became malaria free by some other means

gen endemic_always = 1 // assume everyone has malaria always
forvalues y = 1980/2015 {
	replace endemic_always = 0 if year`y' ==0 // change those with a 0 (no malaria) in ANY year to 0
}
gen nonendemic_always = 1 // assume everyone has NO malaria
forvalues y = 1980/2015 {
	replace nonendemic_always = 0 if year`y' ==1 // change those with a 1 in ANY year (has malaria) 
}

// 1 means have malaria, 0 means don't, so if we take the max of year1980 and 1998 and it equals 1 they have malaria in that time period 
// if (sum of 1980&1998) > (sum of 1999&2015), then they got rid of malaria without use of ITN and they should get 100%
gen pre_itn = max(year1980, year1999)
gen post_itn = max(year2000, year2015)
gen no_itn_need = 0
	replace no_itn_need = 1 if pre_itn ==1 & post_itn ==0
gen full_cov = 0
	replace full_cov = 1 if nonendemic_always==1 | no_itn_need==1

// reshape so it will match the other data we are going to merge
reshape long year, i(location_i) j(var) 
rename year include
rename var year_id
*keep location_i year_id location_name full_cov include
rename location_i location_id

tempfile coverage
save `coverage', replace

merge 1:1 location_id year_id using `all_draws'
keep if _m==3 | _m==1
drop _m
/*
forvalues y = 0/999 {
	replace itn_coverage_draw_`y' =1 if full_cov ==1
}	
*/
// just keep the locations we need (get rid of subnats to increase efficiency)
merge m:1 location_id using "$prefix/temp/X/sdg/data/locs_needed.dta"
keep if _m==3 // all locations are present (199)
drop _m
	
replace itn_coverage_draw = 1 if full_cov==1
/*
sort location_name itn_coverage year_id
bysort location_id: carryforward itn_coverage_draw, replace

sort location_name itn_coverage
bysort location_id: carryforward itn_coverage_draw, replace
*/
tempfile prepped_for_par
save `prepped_for_par', replace

*****************************************************************************************
//bring in par
import delimited "$prefix/temp/X/sdg/data/par_malaria_coview.csv", clear
rename mean_val par
keep location_id location_name year_id age_group_id sex_id par

merge 1:1 location_name location_id year_id using `all_draws'
	drop _m
	drop if year<1990
	tempfile draws_and_par
	save `draws_and_par', replace
// just keep the locations we need (get rid of subnats to increase efficiency)
merge m:1 location_id using "$prefix/temp/X/sdg/data/locs_needed.dta"
keep if _m==3 
drop _m location_name_short map_id ihme_loc_id local_id super_region_name region_name

gen risk_adj = .
	replace risk_adj = itn_coverage_draw / par
	replace risk_adj = 0.99 if risk_adj >1 & risk_adj !=.
	replace risk_adj = 0.99 if risk_adj <0
sort location_name itn_coverage

	replace risk_adj = 0.01 if risk_adj ==. | risk_adj <0.01
	
/* forvalues n = 0/999 {
	gen risk_adj_itn_draw_`n' = .
	replace risk_adj_itn_draw_`n' = itn_coverage_draw_`n' / par
	replace risk_adj_itn_draw_`n' = 0.99 if risk_adj_itn_draw_`n' >1 & risk_adj_itn_draw_`n' !=.
	replace risk_adj_itn_draw_`n' = 0.01 if risk_adj_itn_draw_`n' ==. | risk_adj_itn_draw_`n' <0.01
}
*/



*drop itn_coverage_draw par
sort location_name year_id 
drop sex_id age_group_id
save `draws_and_par', replace

**************************************************************************************

// just keep the locations we need (get rid of subnats to increase efficiency)
merge m:1 location_id using "$prefix/temp/X/sdg/data/locs_needed.dta"
keep if _m==3 // all locations are present (199)
drop _m location_name_short map_id ihme_loc_id local_id super_region_name region_name
tempfile full_data
save `full_data', replace
sort location_name year_id 
export delimited "$prefix/temp/X/sdg/data/itn_final_draws.csv", replace