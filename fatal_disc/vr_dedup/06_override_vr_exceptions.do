// Purpose: Sometimes high-quality VR is chosen over EMDAT but it is clearly wrong. We think this is likely due to the
// impact of the disaster on the VR system. For example, in Colombia in 1995 there was a volcano explosion with a 
// consensus impact of around 20,000 deaths, but this does not show up in the VR system at all.


*******************************************************************************
** SET-UP
*******************************************************************************

clear all
set more off

if c(os) == "Windows" {
	global prefix ""
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

// Import exceptions
// Put in git repository so that changes can be tracked. needs to be csv 
// so that tracked changes are visible in stash etc.
import delimited using "exceptions_overrides.csv", clear
keep location_id year cause numkilled_adj source nid ihme_loc_id
rename (source nid) (source_new nid_new)
tempfile adjustments
save `adjustments', replace

// Grab data before confidence intervals
use "disaster_compiled_prioritized.dta", clear
// save original column names
ds
local vars = "`r(varlist)'"


*******************************************************************************
** IMPORTS
*******************************************************************************

merge m:1 location_id year cause using `adjustments'

// make sure that there is a clean replacement location-year-cause 
duplicates tag location_id year cause if _merge==3, gen(dups)
assert dups==0 if _merge==3

** replace if there is an adjustment (merge 3)
** or totally new location-year-cause (merge 2)
replace numkilled = numkilled_adj if inlist(_merge, 2, 3)
replace source = source_new if inlist(_merge, 2, 3)
replace nid = nid_new if inlist(_merge, 2, 3)
replace iso3 = substr(ihme_loc_id, 1, 3) if inlist(_merge, 2, 3)
replace vr = 0 if inlist(_merge, 2, 3)
** this will be determined by the region
replace u_disaster_rate = . if inlist(_merge, 2, 3)
replace l_disaster_rate = . if inlist(_merge, 2, 3)

assert numkilled != .
assert iso3 != ""
assert location_id != .
assert year != .
assert cause != ""
assert nid != . if source != "NOAA"

// keep original variables and save
keep `vars'
save "disaster_with_exceptions.dta", replace
save "disaster_with_exceptions_`timestamp'.dta", replace
