// Purpose: Sometimes high-quality VR is chosen over EMDAT but it is clearly wrong. We think this is likely due to the
// impact of the disaster on the VR system. For example, in Colombia in 1995 there was a volcano explosion with a 
// consensus impact of around 20,000 deaths, but this does not show up in the VR system at all.


*******************************************************************************
** SET-UP
*******************************************************************************

clear all
set more off

if c(os) == "Windows" {
	global prefix "J:"
}
else {
	global prefix ""
	set odbcmgr unixodbc
}

global datadir ""


// Set the timestamp
local date = c(current_date)
local date = c(current_date)
local today = date("`date'", "DMY")
local year = year(`today')
local month = month(`today')
local day = day(`today')
local time = c(current_time)
local time : subinstr local time ":" "", all
local length : length local month
if `length' == 1 local month = "0`month'"	
local length : length local day
if `length' == 1 local day = "0`day'"
local date = "`year'_`month'_`day'"
local timestamp = "`date'_`time'"


*******************************************************************************
** IMPORTS
*******************************************************************************
// Import subnational weights for War from VR 
odbc load, exec("SELECT lhh.parent_id, lhh.ihme_loc_id, d.year_id, SUM(d.cf_final*o.mean_env_hivdeleted) AS deaths FROM cod.cm_data d INNER JOIN cod.cm_data_version dv ON d.data_version_id = dv.data_version_id INNER JOIN mortality.output o ON d.location_id = o.location_id AND d.age_group_id = o.age_group_id AND d.sex_id = o.sex_id AND d.year_id = o.year_id INNER JOIN mortality.output_version ov ON ov.output_version_id = o.output_version_id AND ov.is_best=1 INNER JOIN shared.location_hierarchy_history lhh ON lhh.location_id = d.location_id AND lhh.location_set_version_id=75 AND SUBSTRING_INDEX(SUBSTRING_INDEX(lhh.path_to_top_parent, ',', 4), ',', -1) IN(95, 102) AND is_estimate=1 WHERE d.cause_id = 730 AND d.age_group_id=22 AND d.year_id>=2001 GROUP BY lhh.ihme_loc_id, d.year_id") dsn(strConnection) clear
bysort parent_id year: egen nat_deaths = total(deaths)
gen weight = deaths/nat_deaths
rename year_id year
keep ihme_loc_id year weight
gen iso3 = substr(ihme_loc_id, 1, 3)
tempfile subnat_vr_weights
save `subnat_vr_weights'

// Import exceptions
// Put in git repository so that changes can be tracked. needs to be csv 
// so that tracked changes are visible in stash etc.
import delimited using "war_exceptions_overrides.csv", clear
keep ihme_loc_id year cause deathnumberbest low high source nid
collapse (sum) deathnumberbest, by(ihme_loc_id year cause low high source nid) fast
rename (source nid) (source_new nid_new)
isid ihme_loc_id year

// drop the us and gbr for 2014-2015 that are pretty small and dont match with VR
drop if inlist(ihme_loc_id, "GBR", "USA") & deathnumberbest < 70 & inlist(year, 2014, 2015)

// SPLIT COUNTRIES THAT NEED SUBNATIONAL ESTIMATION
gen split = 0
replace split = 1 if inlist(ihme_loc_id, "GBR", "USA")

tempfile all_data
save `all_data', replace

keep if split == 1
rename ihme_loc_id iso3
merge 1:m iso3 year using `subnat_vr_weights'
	assert _m != 1
	drop if _m == 2
	drop _m
assert weight != .

foreach var in deathnumberbest low high {
	replace `var' = `var' * weight
}

tempfile sub_split
save `sub_split', replace

// APPEND SPLIT DATA BACK
use `all_data', clear
drop if split == 1
append using `sub_split'

replace cause = "war"

tempfile adjustments
save `adjustments', replace

// Grab data before confidence intervals
use "war_compiled_prioritized.dta", clear
// save original column names
ds
local vars = "`r(varlist)'"


*******************************************************************************
** IMPORTS
*******************************************************************************

merge m:1 ihme_loc_id year cause using `adjustments', assert(1 3)
// now, there are ofen multiple entries for an ihme_loc_id-year-cause
// this merge just determined what to drop from the data
drop if _merge==3
append using `adjustments'
// I'll call _merge = 4 "new data"
replace _merge=4 if _merge==.

** replace if there is an adjustment (merge 3)
** or totally new location-year-cause (merge 2)
replace war_deaths_best = deathnumberbest if _merge==4
replace war_deaths_low = low if _merge==4
replace war_deaths_high = high if _merge==4
replace source = source_new if _merge==4
replace nid = nid_new if _merge==4
replace sex = "both" if _merge==4

assert war_deaths_best != .
assert war_deaths_low <= war_deaths_best if war_deaths_low != .
assert war_deaths_best <= war_deaths_high if war_deaths_high != . & war_deaths_high != 0
assert ihme_loc_id != ""
assert year != .
assert cause != ""
assert sex != ""
assert nid != .
assert source != ""

isid ihme_loc_id year cause nid

** get rid of mexico cartels ( this is the UCDP non-state dataset)
drop if nid==231049 & year>=2008 & regexm(ihme_loc_id, "MEX")

// keep original variables and save
keep `vars'
save "war_with_exceptions.dta", replace
save "war_with_exceptions_`timestamp'.dta", replace
