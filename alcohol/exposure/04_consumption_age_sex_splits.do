** Get age-sex splitting of total per capita alcohol consumption (liters per capita)
** Parallel by all locations

clear all
set more off
cap restore, not


if c(os) == "Unix" {
		global prefix "/home/j"
		local location_id `1'
		local prescale_dir "`2'"
		di "`prescale_dir'"
		local postscale_dir "`3'"
		di "`postscale_dir'"
		local stgpr_subs "`4'"
		di "`stgpr_subs'"
		local pop_file "`5'"
		di "`pop_file'"
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local location_id = 6
		local prescale_dir "J:\WORK\05_risk\risks\drugs_alcohol\data\exp\prescale"
		local postscale_dir "J:\WORK\05_risk\risks\drugs_alcohol\data\exp\postscale"
		local stgpr_subs "J:/WORK/05_risk/risks/drugs_alcohol/data/exp/stgpr/resplit_subnats/alcohol_lpc_postsub.dta"
		local pop_file "J:/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/population.dta"
	}

	
	
** NOTE ALL BELOW STEPS ARE ALSO BY DRAW
** Note that we are using two different denominators here:
	** 1. Dismod model is consumption among drinkers
	** 2. alc_lpc covariate is per capita consumption among everyone in the country 15+ years of age
	** So the denominators need to be handled carefully, thus we make these on the same scale by getting total consumption and fractions of total consumption instead of per capita
	
	
** 1. Bring in prevalence of drinkers (from post-scaled dir), multiply by populations to get number of drinkers by age/sex/year (should be just ages 15+)
tempfile population
use "`pop_file'", clear
keep if location_id == `location_id'
keep if age_group_id >= 8
keep location_id year_id age_group_id sex_id pop_scaled
save `population', replace

use "`postscale_dir'/prevalences_`location_id'.dta", clear
keep if modelable_entity_id == 3364
merge 1:1 location_id year_id sex_id age_group_id using `population', nogen keep(3)

forvalues i = 0(1)999 {
	gen total_drinkers_`i' = draw_`i'*pop_scaled
	drop draw_`i'
}

tempfile proportions
save `proportions', replace

** 2. Multiply these numbers of drinkers by the average consumption amounts from DisMod, this yields total consumption by age-sex-year-draw in grams/day
use "`prescale_dir'/3360_dismod_output_`location_id'.dta", clear
merge 1:1 year_id sex_id age_group_id using `proportions', nogen keep(3)

forvalues i = 0(1)999 {
	gen total_consumption_`i' = draw_`i'*total_drinkers_`i'
	drop draw_`i' total_drinkers_`i'
}

** 3. Transform these consumption amounts to relative proportions (so find total by year-draw, then divide the age-sex-year-draw-specific amount by the year-draw total)
forvalues i = 0(1)999 {
	bysort year_id: egen total_loc_consumption_`i' = sum(total_consumption_`i')
	replace total_consumption_`i' = total_consumption_`i'/total_loc_consumption_`i'
	drop total_loc_consumption_`i'
}

isid location_id year_id sex_id age_group_id
save `proportions', replace

** 4. Bring in alc_lpc results, multiply by population 15+ to get total consumption in location at draw level
use "`stgpr_subs'", clear
keep if location_id == `location_id'

tempfile gpr
save `gpr'

use `population', clear
bysort location_id year_id: egen total_pop= sum(pop_scaled)
duplicates drop location_id year_id, force

merge 1:1 location_id year_id using `gpr', nogen keep(3)

forvalues i = 0(1)999{
	gen overall_consumption_`i' = draw_`i'*total_pop
	drop draw_`i'
}

drop age_group_id sex_id
isid location_id year_id

** 5. Merge on the relative proportions, multiply them out to get total consumption by age-sex-year-draw
merge 1:m location_id year_id using `proportions', nogen keep(3)

forvalues i = 0(1)999{
	gen consumption_`i' = overall_consumption_`i'*total_consumption_`i'
	drop overall_consumption_`i' total_consumption_`i'
}

** 6. Divide by total populations in each age group (not drinker populations) to get alc_lpc by age-sex-year-draw

forvalues i = 0(1)999{
	gen alc_lpc_`i' = consumption_`i'/pop_scaled
	drop consumption_`i'
}

** 7. Save file in postscale_dir
save "`postscale_dir'/alc_lpc_`location_id'.dta", replace
