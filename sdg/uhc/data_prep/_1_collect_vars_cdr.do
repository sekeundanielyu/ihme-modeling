//
// july 8 2016
****************************************************************************************
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
*****************************************************************
// bring in data
*****************************************************************

import delimited "$prefix/temp/X/sdg/data/CDR_5yr_moving_average.csv", clear
tempfile cdr
save `cdr', replace

drop mean_cdr
rename mean_cdr_new mean_cdr
drop parent
order location_id year mean_cdr

// just keep the locations we need 
merge m:1 location_id using "$prefix/temp/X/sdg/data/locs_needed.dta", keep(2 3)
drop _m map_id super_region_name region_name location_name_short
replace year = 1990 if year ==.

encode location_name, gen(location_encoded)

tsset location_encoded year
tsfill, full
tsappend, add(1)

sort location_encoded year
bysort location_encoded: carryforward location_name ihme_loc_id local_id location_id, replace
sort location_encoded mean_cdr
bysort location_encoded : carryforward location_name ihme_loc_id local_id location_id mean_cdr, replace

sort location_encoded location_id year
bysort location_encoded: carryforward location_name ihme_loc_id local_id location_id mean_cdr, replace
drop location_encoded

*****************************************************************
// Fix Taiwan by replacing with US values
*****************************************************************

preserve

keep if location_name=="United States"
replace location_name="Taiwan"
rename mean_cdr mean_cdr_taiwan 

tempfile taiwan
save `taiwan', replace

restore

merge 1:1 location_name year using `taiwan', nogen 

replace mean_cdr = mean_cdr_taiwan if location_name=="Taiwan" 
drop mean_cdr_taiwan


*****************************************************************
// Fix South Sudan by replacing with 0.4625 from 2011-2014 and use Sudan's values for other years
*****************************************************************
replace mean_cdr = 0.4625 if location_id==435 & year >=2011

preserve

keep if location_name=="Sudan"
replace location_name="South Sudan"
rename mean_cdr mean_cdr_ss

tempfile ssudan
save `ssudan', replace

restore

merge 1:1 location_name year using `ssudan', nogen

replace mean_cdr = mean_cdr_ss if location_name=="South Sudan" & mean_cdr ==.
drop mean_cdr_ss

*****************************************************************
// Replace UK countries with UK general values
*****************************************************************

preserve

keep if location_name=="United Kingdom"
replace location_name="England"
rename mean_cdr mean_cdr_england

tempfile england
save `england', replace

restore

preserve

keep if location_name=="United Kingdom"
replace location_name="Scotland"
rename mean_cdr mean_cdr_scotland

tempfile scotland
save `scotland', replace

restore


preserve

keep if location_name=="United Kingdom"
replace location_name="Northern Ireland"
rename mean_cdr mean_cdr_ni

tempfile ni
save `ni', replace

restore

preserve

keep if location_name=="United Kingdom"
replace location_name="Wales"
rename mean_cdr mean_cdr_wales

tempfile wales
save `wales', replace

restore

merge 1:1 location_name year using `england', nogen
replace mean_cdr = mean_cdr_england if location_name=="England" & mean_cdr ==.
drop mean_cdr_england

merge 1:1 location_name year using `scotland', nogen
replace mean_cdr = mean_cdr_scotland if location_name=="Scotland" & mean_cdr ==.
drop mean_cdr_scotland

merge 1:1 location_name year using `ni', nogen
replace mean_cdr = mean_cdr_ni if location_name=="Northern Ireland" & mean_cdr ==.
drop mean_cdr_ni

merge 1:1 location_name year using `wales', nogen
replace mean_cdr = mean_cdr_wales if location_name=="Wales" & mean_cdr ==.
drop mean_cdr_wales

rename mean_cdr mean_draw

forvalues n = 0/999 {
	gen cdr_draw_mean_`n' = mean_draw
}
drop mean_draw

export delimited "$prefix/temp/X/sdg/data/who_cdr_imputed_draws.csv", replace

