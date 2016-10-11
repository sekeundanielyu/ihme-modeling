*** compile populaiton numbers for under five age groups

*** by sim
clear all
set more off
set memory 6000m

	if (c(os)=="Unix") {
		global root "StrPath"
		set odbcmgr unixodbc
		qui do "StrPath/get_locations.ado"
	} 
	if (c(os)=="Windows") { 
		global root "J:"
		qui do "StrPath/get_locations.ado"
	}

	
get_locations, level(estimate)
keep if level_all == 1
keep ihme_loc_id 
levelsof ihme_loc_id, local(locs)

clear
tempfile compiled
save `compiled', replace emptyok
foreach loc of local locs {
	di "`loc'"
	append using "StrPath/u5_agessex_`loc'.dta"
}	
	
drop if year>2015
drop if year<1950

saveold "StrPath/u5_agesex_summary.dta", replace
saveold "StrPath/u5_agesex_summary.dta", replace

