//
// putting imputed ITN numbers in the right format so the code will work for the UHC index

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

use "$prefix/temp/X/sdg/data/itn_adjustedforPAR.dta", clear
rename itncc_par itn_draw_mean
drop par itncc endemic

// just keep the locations we need (get rid of subnats to increase efficiency)
merge m:1 location_name using "$prefix/temp/X/sdg/data/locs_needed.dta"
keep if _m==3
drop _m

forvalues n = 0/999 {
	gen itn_draw_mean_`n' = itn_draw_mean
}

drop itn_draw_mean

export delimited "$prefix/temp/X/sdg/data/itn_final_draws.csv", replace