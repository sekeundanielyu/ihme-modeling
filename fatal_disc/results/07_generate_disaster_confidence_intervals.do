// Purpose: generate confidence intervals for type-specific disaster deaths


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
global outdir ""

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

run "create_connection_string.ado"
create_connection_string
local conn_string `r(conn_string)'

run "get_location_metadata.ado"

*******************************************************************************
** IMPORTS
*******************************************************************************

// bring in confidence intervals
use "UCDP_ci_for_disaster_Africa.dta", clear
keep region_id low_per_diff high_per_diff
duplicates drop
tempfile confidence
save `confidence', replace


// Population for 1970 - 2015
use "population_gbd2015.dta", clear
keep if sex_id == 3
keep if age_group_id >= 2 & age_group_id <= 21

collapse (sum) pop, by(location_id year) fast
rename pop mean_pop

tempfile population
save `population', replace

// GBD region names
get_location_metadata, location_set_id(35) clear
keep location_id region_id region_name
tempfile regions
save `regions', replace

// Get compiled and prioritized data with exceptions implemented
use "disaster_with_exceptions.dta", clear

*******************************************************************************
** GENERATE CONFIDENCE INTERVALS AND CHANGE TO RATE-SPACE
*******************************************************************************

merge m:1 location_id using `regions'
	assert _m != 1
	keep if _m == 3
	drop _m

merge m:1 year location_id using `population'
	assert _m != 1 if year >= 1950
	keep if _m == 3
	drop _m

rename numkilled disaster
rename mean_pop pop

// merge in confidence intervals dataset
merge m:1 region_id using `confidence'
	assert _m != 1
	drop if _m != 3
	drop _m

// Australia data: don't trust it, so use world mean CI for that one; otherwise, use the regional CI
egen temp_low = mean(low_per_diff)
egen temp_high = mean(high_per_diff)

drop temp*

// add in the regional CIs for countries that weren't in the UCDP CI file
sort region_id low_per_diff
carryforward low_per_diff, replace
sort region_id high_per_diff
carryforward high_per_diff, replace
assert low_per_diff != .
assert high_per_diff != . 

// disaster rate
gen double disaster_rate = disaster/pop

assert low_per_diff <= high_per_diff

replace l_disaster_rate = disaster_rate*low_per_diff if l_disaster_rate == .
replace u_disaster_rate = disaster_rate*high_per_diff if u_disaster_rate == .

// if the l_disaster rate is infinitesimally greater than disaster_rate (happened once), make it equal
gen lminb = l_disaster_rate-disaster_rate
replace l_disaster_rate= disaster_rate if (lminb<.00000001) & (lminb>0)
drop lminb

// make sure that disaster rate is between the lower and upper bounds
assert disaster_rate >= l_disaster_rate
assert disaster_rate <= u_disaster_rate

drop low_per_diff high_per_diff

compress
// get average of duplicated country-years across EMDAT and the online supplement
// the exception is for PHL 2013: want to use the online supplement, not EMDAT, because it was 62 deaths.  If it's no longer 62 deaths, then compare it to the online supplement and determine if we still need to use the supplement or if EMDAT is more reasonable now
di in red "If it's no longer 62 deaths, then compare it to the online supplement and determine if we still need to use the supplement or if EMDAT is more reasonable now"
drop if iso3 == "PHL" & year == 2013 & source == "Online supplement" & disaster == 6437

duplicates tag iso3 location_id year cause, gen(dup)
// Keep high of EMDAT vs Online supplement dups
local vtype : type disaster
bysort iso3 location_id year cause : egen `vtype' max = max(disaster)
drop if disaster != max & dup > 0
drop if disaster == max & dup > 0 & source != "EMDAT"	// Prefer EMDAT over online supplement if deaths are the same


drop dup
	


// save in our folder
save "formatted_disaster_data_rates_with_cis.dta", replace
save "formatted_disaster_data_rates_with_cis_`timestamp'.dta", replace

