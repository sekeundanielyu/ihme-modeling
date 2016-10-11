/*
Small stata do file to get IHME covariates
5/4/16
*/

clear all
set more off

** Set directories
if c(os) == "Windows" {
	global j "J:"
	set mem 1g
}
if c(os) == "Unix" {
	global j "/home/j"
	set mem 2g
	set odbcmgr unixodbc
}

local outputs "`1'"

quietly include "$j/WORK/10_gbd/00_library/functions/get_covariate_estimates.ado"

quietly get_covariate_estimates, covariate_name_short("LDI_pc")
keep if year_id>=1980
keep location_id year_id mean_value
rename mean_value ln_ldi_pc
replace ln_ldi_pc = ln(ln_ldi_pc)
tempfile temp
save `temp', replace
	
	**Add on remaining covariates
local covariates "prop_urban coastal_prop mean_temperature latitude pop_dens_under_150_psqkm_pct pop_dens_150_300_psqkm_pct pop_dens_300_500_psqkm_pct pop_dens_500_1000_psqkm_pct pop_dens_over_1000_psqkm_pct pop_under100m_prop pop_100mto500m_prop pop_500mto1500m_prop pop_1500mplus_prop vehicles_4wheels_pc pop_0to15lat_prop pop_15to30lat_prop pop_30to45lat_prop pop_45pluslat_prop"
foreach cov of local covariates{
	clear
	get_covariate_estimates, covariate_name_short("`cov'")
	keep if year_id>=1980
	keep location_id year_id mean_value
	rename mean_value `cov'
	merge m:1 location_id year_id using `temp', nogen
	save `temp', replace
}

quietly export delimited using "`outputs'/covariates.csv", replace

clear
tempfile educ
quietly get_covariate_estimates, covariate_name_short("education_yrs_pc")
keep if year_id>=1980
drop if age_group_id==2 | age_group_id==3 | age_group_id==4 | age_group_id==5 | age_group_id==6 | age_group_id==7 
save `educ', replace

	*Get populations to prepare to aggregate education, weighting on population groups
quietly include "$j/WORK/10_gbd/00_library/functions/get_demographics.ado"
quietly get_demographics, gbd_team(cov) make_template get_population clear
merge 1:m location_id year_id sex_id age_group_id using `educ'
keep if _merge==3

bysort location_id year_id sex_id: egen double pop_total = total(pop_scaled)
gen weighted_educ = (pop_scaled/pop_total)*(mean_value)
bysort location_id year_id sex_id: egen educ_total = total(weighted_educ)

rename educ_total education_yrs_pc
gen cv_education_yrs_pc = education_yrs_pc
keep location_id year_id sex_id cv_education_yrs_pc education_yrs_pc
duplicates drop

quietly export delimited using "`outputs'/educ_covariate.csv", replace

clear
exit, STATA
end