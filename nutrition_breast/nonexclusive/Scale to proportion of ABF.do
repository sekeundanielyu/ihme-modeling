// /////////////////////////////////////////////////
// CONFIGURE ENVIRONMENT
// /////////////////////////////////////////////////

	if c(os) == "Unix" {
		global prefix "/home/j"
		set more off
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

// /////////////////////////////////////////////////
// CONFIGURATION COMPLETE 
// /////////////////////////////////////////////////
clear all
set more off
set maxvar 20000
capture restore, not

************************************************************************************************
**TO MODEL PREDOMINANT/PARTIAL/EXCLUSIVE as a proportion of ABF for age group 0to5 months
************************************************************************************************
**Prepare smoothing dataset bring in smoothed ABF estimates for 0 - 5 months**

use "$prefix/WORK/01_covariates/02_inputs/breastfeeding/02_Analyses/01_spacetime/data/Smoothing_dataset_updated.dta", clear
preserve
**This was modeled/created separately for the sole purpose of scaling the other indicators
import delimited "$prefix/WORK/05_risk/risks/nutrition_breast_nonexc/data/model_output/gpr/ABF/0to5/output_full.csv", clear
keep ihme_loc_id year_id gpr_mean
duplicates drop ihme_loc_id year_id, force
rename ihme_loc_id iso3
rename year_id year
tempfile ABF
save `ABF', replace
restore

merge m:1 iso3 year using `ABF', keepusing(gpr_mean)
drop _merge

**generate each BF category as a proportion of ABF for 0-5 months**
foreach ind in "predBF" "partBF" "EBF"{
gen `ind'rate0to5_prop = `ind'rate0to5/gpr_mean
rename `ind'rate0to5 actual_`ind'0to5 
rename `ind'rate0to5_prop `ind'rate0to5
	}

**running BF indicators as a proportion of ABF (relevant for non)
save "$prefix/WORK/01_covariates/02_inputs/breastfeeding/02_Analyses/01_spacetime/data/Smoothing_dataset_prop_updated.dta", replace
