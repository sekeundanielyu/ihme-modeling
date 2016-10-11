/* Producing a square dataset for Exposures to Occupational Risks by economic activity
12/18/15
*/

clear all
set more off

** Set directories
	if c(os) == "Windows" {
		global j "J:"
	}
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}

**File Locations
local rawdata	"J:/WORK/05_risk/risks/occ/occ_overall/2013/01_exp/02_nonlit/02_inputs/05_other" 
local outdata	"J:/WORK/05_risk/risks/occ/raw/occ_ea"

**Producing the Square
quietly adopath + J:/WORK/10_gbd/00_library/functions

*Get all years, age groups, and sexes
quietly get_demographics, gbd_team("cov") make_template clear
keep location_id year_id age_group_id sex_id
tempfile square
save `square', replace

*Get all locations
quietly include "J:/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
get_location_metadata, location_set_id(9) clear

	*Only want National and subnational
keep if level >= 3
keep location_id ihme_loc_id
merge 1:m location_id using `square'
	
	*Drop pesky location GBR_4749
drop if _merge == 1			
drop _merge
drop age_group_id

sort ihme_loc_id year_id sex_id
duplicates drop location_id year_id sex_id, force

save `square', replace

*Bring in exposure data to merge with square
use "`rawdata'/logit_econ_act_forspacetime_03Feb2015_1", clear
append using "`rawdata'/logit_econ_act_forspacetime_03Feb2015_2.dta"

rename sex sex_id
rename year year_id

*Collapse duplicates
duplicates tag location_name year sex, gen(dup)
preserve
keep if dup>=1
collapse (mean) logit_exp_*, by(location_name location_id year sex)
tempfile temp
save `temp', replace

restore
drop if dup>=1
drop dup
merge 1:m location_id year sex using `temp'
drop _merge

*Now merge with square file
merge m:1 location_id year_id sex_id using `square'
keep if _merge!=1
drop _merg

*only keep variables needed for ST-GPR
keep location_id survey natlrep ihme_loc_id year_id sex_id nid logit_exp_cat1-logit_exp_cat9
gen age_group_id = 22
save "`outdata'/master.dta", replace

*Let's go get covariates!
clear
quietly include "J:/WORK/10_gbd/00_library/functions/get_covariate_estimates.ado"

	*Use LDI as a template to merge on the others after ln transforming
quietly get_covariate_estimates, covariate_name_short("LDI_pc")
keep if year_id>=1980
keep location_id year_id mean_value
rename mean_value ln_ldi_pc
replace ln_ldi_pc = ln(ln_ldi_pc)
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

*Get education and perform a weighted average by population sizes
clear
tempfile educ
quietly get_covariate_estimates, covariate_name_short("education_yrs_pc")
keep if year_id>=1980
drop if age_group_id==2 | age_group_id==3 | age_group_id==4 | age_group_id==5 | age_group_id==6 | age_group_id==7 
save `educ', replace

	*Get populations to prepare to aggregate education, weighting on population groups
quietly include "J:/WORK/10_gbd/00_library/functions/get_demographics.ado"
quietly get_demographics, gbd_team(cov) make_template get_population clear
merge 1:m location_id year_id sex_id age_group_id using `educ'
keep if _merge==3

bysort location_id year_id sex_id: egen double pop_total = total(pop_scaled)
gen weighted_educ = (pop_scaled/pop_total)*(mean_value)
bysort location_id year_id sex_id: egen educ_total = total(weighted_educ)

rename educ_total education_yrs_pc
keep location_id year_id sex_id education_yrs_pc
duplicates drop

	*Merge education with estimates
merge 1:m location_id year_id sex_id using "`outdata'/master.dta"
drop _merge

*Merge other covariates with estimates
merge m:1 location_id year_id using `temp', update replace
keep if _merge==3
drop _merge

*Convert dataset from wide to long and remove transformations
gen id = _n
reshape long logit_exp_cat, i(id) j(category_id)
decode category_id, gen(categories)
drop category_id
rename logit_exp_cat data
replace data = invlogit(data)

*Run lowess to calculate variance using a 5-year window. 
	
lowess data year, by(location_id sex_id categories) gen(lowess_hat) nograph 

*Use lowess estimates as mean to generate variance

	gen residual = lowess_hat - data
	gen sd = .

	foreach year of numlist 1970/2015 {
		bysort location_id categories sex_id: egen temp = sd(residual) if inrange(year_id, `year'-5, `year'+5)
		replace sd = temp if year_id == `year'
		drop temp
	}	

	foreach year of numlist 1970/1975 {
		bysort location_id categories sex_id: egen temp = sd(residual) if inrange(year_id, 1970, `year'+10-(`year'-1970))
		replace sd = temp if year_id == `year'
		drop temp
	}

	foreach year of numlist 2010/2015 {
		bysort location_id categories sex_id: egen temp = sd(residual) if inrange(year_id, `year'-10+(2015-`year'), 2015)
		replace sd = temp if year_id == `year'
		drop temp
	}

	replace sd = . if data == . 

*Get all of the final variables needed for ST-GPR
replace age_group_id=22
gen variance = sd^2
rename sd standard_deviation
gen sample_size = .

replace ihme_loc_id="CHN_44533" if location_id==44533
drop if ihme_loc_id==""

*Export data by categories for both male and female
replace categories="Electricity_Gas_Water" if categories=="Electricity/Gas/Water"
replace categories="Transport_Communication" if categories=="Transport/Communication"
replace categories="Business_Services" if categories=="Business Services"
replace categories="Social_Services" if categories=="Social Services"

save "`outdata'/master_occ_ea.dta", replace
preserve

tempfile sex_id

keep if sex_id==1
replace sex_id=3

save `sex_id', replace

levelsof categories, local(cats)
foreach category of local cats {
	use `sex_id', clear
	keep if categories == "`category'"
	gen me_name = "occ_ea_"+lower("`category'")
	local location = "`outdata'/occ_ea_"+lower("`category'")+"_male.dta"
	save "`location'", replace
}

restore

keep if sex_id==2
replace sex_id=3

save `sex_id', replace

levelsof categories, local(cats)
foreach category of local cats {
	use `sex_id', clear
	keep if categories == "`category'"
	gen me_name = "occ_ea_"+lower("`category'")
	local location = "`outdata'/occ_ea_"+lower("`category'")+"_female.dta"
	save "`location'", replace
}
