// Purpose: GBD 2015 Onchocerciasis Estimates
// Description:	Extrapolate EG draws for APOC and OCP data
//                      The data used here are the original draws of numbers of cases provided for GBD 2010 (1990, 2005, and 2010),
//                      plus exponentially interpolated/extrapolated figures for 1995, 2000, and 2013.

// LOAD SETTINGS FROM MASTER CODE

	// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

	// gbd version (i.e. gbd2013)	
	local gbd = "gbd2015"
	// timestamp of current run (i.e. 2014_01_17)
	local date = "2016_01_04"
	//local envir (dev or prod)
	local envir = "dev"
	// directory for steps code
	local code_dir "C:/Users/wangav/Documents/NTDs/Oncho/04_models/`gbd'/01_code/`envir'"
	// directory for external inputs
	local in_dir "C:/Users/wangav/Documents/NTDs/Oncho/04_models/`gbd'/02_inputs"
	// directory for output:
	local out_dir "C:/Users/wangav/Documents/NTDs/Oncho/04_models/`gbd'/04_outputs"
	// temporary directory for output:
	local tmp_dir "C:/Users/wangav/Documents/NTDs/Oncho/04_models/`gbd'/04_outputs/oncho_temp"
	// directory for standard code files
	adopath + "J:/WORK/10_gbd/00_library/functions"
	
log using "`out_dir'/OcpApocExtrap.log", replace
	
	capture mkdir "`tmp_dir'/03_outputs/"
	capture mkdir "`tmp_dir'/03_outputs/01_draws/"
	capture mkdir "`tmp_dir'/03_outputs/01_draws/ntd_oncho/"
// ************************************************************************
//make directories to save draws:
	cap mkdir "`out_dir'/ocp"
	cap mkdir "`out_dir'/apoc"
	
  // Load and save geographical names
   //DisMod and Epi Data 2015
   clear
   get_location_metadata, location_set_id(9)

  // Prep country codes file
  duplicates drop location_id, force
  tempfile country_codes
  save `country_codes', replace

    keep ihme_loc_id location_id location_name
	tempfile codes
	save `codes', replace
  
// Pull in the OCP file: "GBD 2013 onchocerciasis OCP draws.csv" from folder `in_dir'.
	insheet using "`in_dir'/GBD 2013 onchocerciasis OCP draws.csv", clear double
	// quick fixes to help the merge data
	replace location_name = "Guinea-Bissau" if location_name == "Guinea Bissau"
	joinby location_name using "`codes'", unmatched(none)

	tempfile ocp_2013
	save `ocp_2013', replace

// Perform interpolation and extrapolation from GBD 2013 OCP data to get 2015 values:
	use "`ocp_2013'", replace
	replace blindcases = "0" if blindcases == "Inf"
	cap destring blindcases, replace
	
	//create empty draws to fill in
	preserve
	keep if year == 2013
	replace year = 2015 if year == 2013
	foreach var of varlist wormcases mfcases blindcases vicases osdcases1acute osdcases1chron osdcases2acute osdcases2chron osdcases3acute osdcases3chron {
	quietly replace `var' = .
    }
	tempfile missingyr
	save `missingyr', replace
	restore
	
	append using `missingyr'
	
	reshape wide wormcases mfcases blindcases vicases osdcases1acute osdcases1chron osdcases2acute osdcases2chron osdcases3acute osdcases3chron, i(ihme_loc_id age sex year) j(draw)
	tempfile ocpreshaped
	save `ocpreshaped', replace
	
	// Interpolate / extrapolate for years for which we don't have results	
	egen panel = group(location_id age sex)
	tsset panel year
	tsfill, full
	bysort panel: egen pansex = max(sex)
	bysort panel: egen panage = max(age)
	replace sex = pansex
	drop pansex
	replace age=panage
	drop panage
	tempfile ocpfilled
	save `ocpfilled', replace

	foreach cause in wormcases mfcases blindcases vicases osdcases1acute osdcases1chron osdcases2acute osdcases2chron osdcases3acute osdcases3chron {	
	  use `ocpfilled', clear
	  preserve
	  keep location_id ihme_loc_id location_name year age sex panel `cause'*
        forvalues i=0/999 {
		bysort panel: ipolate `cause'`i' year, gen(draw_`i') epolate
		replace draw_`i' = 0 if draw_`i' < 0
		replace draw_`i' = round(draw_`i')
		}
		keep if inlist(year, 1990, 1995, 2000, 2005, 2010, 2013, 2015)
		bysort panel: replace location_id = location_id[_n-1] if location_id ==.
		drop `cause'*
		sort location_id panel year sex
		order location_* year age sex draw*
		reshape long draw_, i(ihme_loc_id age sex year) j(draw)
		rename draw_ `cause'
		tempfile `cause'_draws
		quietly save ``cause'_draws', replace
		save "`out_dir'/ocp/`cause'_draws.dta", replace
	  restore
	  }	
		
	use "`wormcases_draws'", replace
	joinby ihme_loc_id age sex year draw using "`mfcases_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`blindcases_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`vicases_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`osdcases1acute_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`osdcases1chron_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`osdcases2acute_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`osdcases2chron_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`osdcases3acute_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`osdcases3chron_draws'", unmatched(none)
	
	save "`in_dir'/ocp_draws_gbd2015.dta", replace
		
////////////////////////////////////////////////////////////////////////////////////////////////////
// Pull in the APOC file: "GBD 2013 onchocerciasis APOC draws.csv" from folder `in_dir'
	insheet using "`in_dir'/GBD 2013 onchocerciasis APOC draws.csv", clear
	replace location_name = "Equatorial Guinea" if location_name == "Eq.Guinea"
	replace location_name = "Democratic Republic of the Congo" if location_name == "RDC"
	replace location_name = "Central African Republic" if location_name == "CAR"
	joinby location_name using "`codes'", unmatched(none)	

	tempfile apoc_2013
	save `apoc_2013', replace
	
// Repeat interpolation and extrapolation from GBD 2013 APOC data to get 2015 values:
	use "`apoc_2013'", replace
	
	//create empty draws to fill in
	preserve
	keep if year == 2013
	replace year = 2015 if year == 2013
	foreach var of varlist wormcases mfcases blindcases vicases osdcases1acute osdcases1chron osdcases2acute osdcases2chron osdcases3acute osdcases3chron{
	quietly replace `var' = .
    }
	tempfile missingyr
	save `missingyr', replace
	restore
	
	append using `missingyr'
	
	reshape wide wormcases mfcases blindcases vicases osdcases1acute osdcases1chron osdcases2acute osdcases2chron osdcases3acute osdcases3chron, i(ihme_loc_id age sex year) j(draw)
	tempfile apocreshaped
	save `apocreshaped', replace
	
	// Interpolate / extrapolate for years for which we don't have results	
	egen panel = group(location_id age sex)
	tsset panel year
	tsfill, full
	bysort panel: egen pansex = max(sex)
	bysort panel: egen panage = max(age)
	replace sex = pansex
	drop pansex
	replace age=panage
	drop panage
	tempfile apocfilled
	save `apocfilled', replace

	foreach cause in wormcases mfcases blindcases vicases osdcases1acute osdcases1chron osdcases2acute osdcases2chron osdcases3acute osdcases3chron {	
	  use `apocfilled', clear
	  preserve
	  keep location_id ihme_loc_id location_name year age sex panel `cause'*
        forvalues i=0/999 {
		bysort panel: ipolate `cause'`i' year, gen(draw_`i') epolate
		replace draw_`i' = 0 if draw_`i' < 0
		replace draw_`i' = round(draw_`i')
		}
		keep if inlist(year, 1990, 1995, 2000, 2005, 2010, 2013, 2015)
		bysort panel: replace location_id = location_id[_n-1] if location_id ==.
		drop `cause'*
		sort location_id panel year sex
		//gen sequela = "`cause'"
		order location_* year age sex draw*
		reshape long draw_, i(ihme_loc_id age sex year) j(draw)
		rename draw_ `cause'
		tempfile `cause'_draws
		quietly save ``cause'_draws', replace
		save "`out_dir'/apoc/`cause'_draws.dta", replace
	  restore
	  }
	
	
	use "`wormcases_draws'", replace
	joinby ihme_loc_id age sex year draw using "`mfcases_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`blindcases_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`vicases_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`osdcases1acute_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`osdcases1chron_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`osdcases2acute_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`osdcases2chron_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`osdcases3acute_draws'", unmatched(none)
	joinby ihme_loc_id age sex year draw using "`osdcases3chron_draws'", unmatched(none)
	
	save "`in_dir'/apoc_draws_gbd2015.dta", replace

log close	
