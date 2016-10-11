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

***********************************************
***NON-EXCLUSIVE BREASTFEEDING ST-GPR OUTPUT***
***********************************************
** Be sure to update data_ids and model_ids

**exclusive breastfeeding**
use "`GPR'/ebf/0to5/added_subnat_ebfrate0to5.dta", clear
forvalues n = 0/999 {
	rename draw_`n' exp_cat4_`n'
}

tempfile ebf
save `ebf', replace

**predominant breastfeeding**
use "`GPR'/predbf/0to5/added_subnat_predbfrate0to5.dta", clear
forvalues n = 0/999 {
	rename draw_`n' exp_cat3_`n'
}

tempfile predbf
save `predbf', replace

**partial breastfeeding**
use "`GPR'/partbf/0to5/added_subnat_partbfrate0to5.dta", clear
forvalues n = 0/999 {
	rename draw_`n' exp_cat2_`n'
}

tempfile partbf
save `partbf', replace

**any breastfeeding**
use "`GPR'/abf/0to5/added_subnat_abfrate0to5.dta", clear
forvalues n = 0/999 {
	rename draw_`n' abf_`n'
}

merge 1:1 location_id year_id sex_id using `ebf', keep(match) nogen
merge 1:1 location_id year_id sex_id using `predbf', keep(match) nogen
merge 1:1 location_id year_id sex_id using `partbf', keep(match) nogen

*** Scale draws to ABF
forvalues n = 0/999 {
	gen exp_cat1_`n' = 1-abf_`n'
	quietly gen scale_`n' = abf_`n'/(exp_cat2_`n'+exp_cat3_`n'+exp_cat4_`n')
	forvalues m = 2/4 {
		**editting this to include all categories
		quietly replace exp_cat`m'_`n' = scale_`n'*exp_cat`m'_`n'
	}
}
drop abf* scale* me_name
compress
**export delimited "`output_folder'/all_cats_0to5.csv", replace
save "`output_folder'/all_cats_0to5.dta", replace