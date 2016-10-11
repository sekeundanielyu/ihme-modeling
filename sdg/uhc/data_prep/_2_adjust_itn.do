// 
// sdg
// adjust itn numbers for endemic and certification
// july 13 2016


// prep stata
clear all
set more off
set type double, perm

if c(os) == "Unix" {
	global prefix "/home/j"
	set odbcmgr unixodbc
}
else if c(os) == "Windows" {
	global prefix "J:"
}
****************************************************************
****************************************************************


// Now use inclusion/exclusion criteria
import delimited "$prefix/temp/X/sdg/data/malaria_exclusions_Tracy.csv", clear

tempfile inclusions
save `inclusions', replace


//we want three simplified categories: 
// 1) malaria endemic "always" where they have malaria every year from 1980-2015;
// 2) malaria-free "always" where they never have malaria during those years these will all get 100%, perfect coverage)
// 3) those that change from 1 to 0 during the 1980-1999 (pre-ITN) time period. (these will all get 100%, perfect coverage)

gen endemic_always = 1 // assume everyone has malaria
forvalues y = 1980/2015 {
	replace endemic_always = 0 if year`y' ==0 // change those with a 0 (no malaria) in ANY year to 0
}

gen nonendemic_always = 1 // assume everyone has NO malaria
forvalues y = 1980/2015 {
	replace nonendemic_always = 0 if year`y' ==1 // change those with a 1 in ANY year (has malaria) 
}
 // 1 means have malaria, 0 means don't, so if we take the max of year1980 and 1998 and it equals 1 they have malaria in that time period 
 // if sum of 1980&1998 >sum of 1999 and 2015, then they got rid of malaria without use of ITN and they should get 100%
 
 gen pre_itn = max(year1980, year1998)
 gen post_itn = max(year1999, year2015)
 
 gen no_itn_need = 0
	replace no_itn_need = 1 if pre_itn ==1 & post_itn ==0
 
gen full_cov = 0
	replace full_cov = 1 if nonendemic_always==1 | no_itn_need==1


reshape long year, i(location_i) j(var) 
rename year include
rename var year_id
keep location_i year_id location_name full_cov include
rename location_i location_id

tempfile coverage
save `coverage', replace

// bring in ITN draws
import delimited "$prefix/temp/X/sdg/data/itn_draws.csv", clear
drop _m
merge 1:1 location_id year_id using `coverage'
keep if _m==3
drop _m

// just keep the locations we need (get rid of subnats to increase efficiency)
merge m:1 location_name using "$prefix/temp/X/sdg/data/locs_needed.dta"
keep if _m==3
drop _m 

forvalues y = 1/1000 {
	replace itn_coverage_prop_draw_`y' =1 if full_cov ==1
}
replace itn_coverage_prop =1 if full_cov ==1

tempfile pre_par
save `pre_par', replace

//bring in par
import delimited "$prefix/temp/X/sdg/data/malaria_par_prop_v3170.csv", clear
rename mean_val par
keep location_id location_name year_id age_group_id sex_id par

merge 1:1 location_name location_id year_id using `pre_par'
drop _m

forvalues n = 1/1000 {
		gen risk_adj_itn_draw_`n' = .
		replace risk_adj_itn_draw_`n' = itn_coverage_prop_draw_`n' / par
		replace risk_adj_itn_draw_`n' = 1 if itn_coverage_prop_draw_`n' ==1
		replace risk_adj_itn_draw_`n' = 0 if itn_coverage_prop_draw_`n' ==0
		}


// just keep the locations we need (get rid of subnats to increase efficiency)
merge m:1 location_name using "$prefix/temp/crmcn/sdg/data/locs_needed.dta"
keep if _m==3
drop _m
drop itn_coverage_prop*

*export delimited "$prefix/share/scratch/projects/sdg/input_data/uhc_expanded/malaria/itn_draws.csv", replace
export delimited "$prefix/temp/X/sdg/data/hack_adjusted_itn_draws.csv", replace
