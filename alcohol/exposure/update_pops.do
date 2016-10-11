
** pull populations when we rerun exposure code

clear all
set more off
cap restore, not

if c(os) == "Unix" {
		global prefix "/home/j"
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}


clear
do "$prefix/WORK/10_gbd/00_library/functions/get_demographics.ado"
get_demographics, gbd_team(cov) make_template get_population clear

save "$prefix/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/population.dta", replace

