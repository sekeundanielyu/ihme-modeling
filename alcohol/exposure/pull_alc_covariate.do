** pull alcohol covariate when running exposure step to pull

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
qui do "$prefix/WORK/10_gbd/00_library/functions/get_covariate_estimates.ado"
get_covariate_estimates, covariate_name_short("alcohol_lpc")

save "$prefix/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/alcohol_lpc_covariate.dta", replace

