use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\covariates\LDI_pc_v3680.dta", clear
rename map_id iso3
rename year_id year
drop if iso3 == ""
rename mean_value LDI

tempfile ldi
save `ldi', replace

use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\covariates\educ_yrs_age_std_pc_v3827.dta", clear
rename mean_value mean_yrs_educ
rename map_id iso3 
rename year_id year
drop if iso3 == ""

// keep females, relevant agegroups, and right years
keep if sex_id==2 & year>=1980 & year<=2015
rename mean_yrs_educ edu

tempfile edu
save `edu', replace


use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\output\crosswalked_modern_contra_marital_status.dta", clear

merge m:1 iso3 year using `ldi', nogen keep(1 3) keepusing(LDI)

sort iso3 year agegroup
encode wb_income_group_short, gen(wbincome_code)

merge m:1 iso3 year using `edu', nogen keep(1 3) keepusing(edu)

	save "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\output\master_modern_contra_with_covariates.dta", replace
