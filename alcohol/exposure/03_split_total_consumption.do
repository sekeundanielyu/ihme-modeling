** 03_split_total_consumption_nats.do
** Take DisMod results for age breakdown of consumption, covariates estimate of total per capita consumption, and prevalence of drinkers
** Parallel by just nationals, creates subnational splits of all-age consumption in lpc

clear all
set more off
cap restore, not
set maxvar 10000

if c(os) == "Unix" {
		global prefix "/home/j"
		local location_id `1'
		local prescale_dir "`2'"
		di "`prescale_dir'"
		local postscale_dir "`3'"
		di "`postscale_dir'"
		local post_split "`postscale_dir'"
		di "`post_split'"
		local st_gpr "`5'"
		di "`st_gpr'"
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local location_id = 102
		local prescale_dir "J:\WORK\05_risk\risks\drugs_alcohol\data\exp\prescale"
		local postscale_dir "J:\WORK\05_risk\risks\drugs_alcohol\data\exp\postscale"
		local post_split "`postscale_dir'"
		local st_gpr "$prefix/WORK/05_risk/risks/drugs_alcohol/data/exp/stgpr/alcohol_lpc.dta"
	}


** get subnational locations
insheet using "$prefix/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/locations.csv", clear
isid location_id
keep if parent_id == `location_id'
levelsof location_id, local(subs)
	
** NOTE ALL BELOW STEPS ARE ALSO BY DRAW
** Note that we are using two different denominators here:
	** 1. Dismod model is consumption among drinkers
	** 2. alc_lpc covariate is per capita consumption among everyone in the country 15+ years of age
	** So the denominators need to be handled carefully, thus we make these on the same scale by getting total consumption and fractions of total consumption instead of per capita
	

** 1. Bring in prevalence of drinkers (postscaled) for all of the subnational units we have here, multiply prevalences by population to get total drinkers by age/sex/year/location (should be for ages 15 and over)
clear
tempfile nat_w_subs

foreach sub in `subs' {
	append using "`postscale_dir'/prevalences_`sub'"
	save `nat_w_subs', replace
}

keep if modelable_entity_id == 3364
save `nat_w_subs', replace

** Get populations

tempfile pop
quietly include "$prefix/WORK/10_gbd/00_library/functions/get_demographics.ado"
get_demographics, gbd_team(cov) make_template get_population clear

keep if age_group_id >= 8
save `pop', replace

** Merge with prevalences and multiply through to get drinkers

merge 1:m location_id year_id age_group_id sex_id using `nat_w_subs', nogen keep(3)

forvalues i = 0(1)999 {
	gen total_drinkers_`i' = draw_`i'*pop_scaled
	drop draw_`i'
}

** get subnat populations across ages/sexes for later use
isid location_id year_id age_group_id sex_id
bysort location_id year_id: egen tot_pop = sum(pop_scaled)

save `nat_w_subs', replace
clear

** 2. Bring in DisMod results for consumption, multiply these results by the number of drinkers to get total consumption in g/day by age/sex, then collapse (sum) across age and sex to get total consumption by location/year

tempfile dismod

foreach sub in `subs' {
	append using "`prescale_dir'/3360_dismod_output_`sub'.dta"
	save `dismod', replace
}

forvalues i = 0(1)999 {
	rename draw_`i' lpc_`i'
}

merge 1:m location_id year_id sex_id age_group_id using "`nat_w_subs'", nogen assert(3)

set type double
forvalues i = 0(1)999 {
	gen pop_consumption_`i' = lpc_`i'* total_drinkers_`i'
	** get consumption among all subnats
	bysort year_id: egen total_pop_consumption_`i' = sum(pop_consumption_`i') 
}

** 3. Find relative proportion of consumption in a given subnational unit out of the total of the subnational units by year

forvalues i = 0(1)999 {
	** get consumption in subnat of choice
	bysort year_id location_id: egen pop_cons_loc_`i' = sum(pop_consumption_`i') 
	** drop unnecessary vars
	drop total_drinkers_`i' lpc_`i' pop_consumption_`i' 
}

drop age_group_id pop_scaled sex_id
duplicates drop 
isid location_id year_id

forvalues i = 0(1)999 {
	** get proportion of total in subnat of choice
	gen prop_consumption_`i' = pop_cons_loc_`i'/total_pop_consumption_`i'
	** drop unnecessary vars
	drop total_pop_consumption_`i' pop_cons_loc_`i'
}

** now just get all-age proportions to apply to national
duplicates drop
rename tot_pop tot_pop_subs

save `nat_w_subs', replace

** 4. Bring in national alc_lpc from ST-GPR results (draws), multiply each draw by total population in the country (ages 15+) to get national consumption
use `pop', clear 
bysort location_id year_id: egen tot_pop = sum(pop_scaled)
drop age_group_id sex_id pop_scaled
duplicates drop
tempfile totpop
save `totpop', replace

use "`st_gpr'", clear
keep if location_id == `location_id'

merge 1:m year_id location_id using `totpop', nogen keep(3)

forvalues i = 0(1)999 {
	gen national_consumption_`i' = (draw_`i')*tot_pop
	drop draw_`i'
}

** 5. Now we have total consumption in the national unit, split into subnationals- merge the relative proportions in the subnational units to the national consumption in step 4
drop location_id
merge 1:m year_id using `nat_w_subs', nogen keep(3)
isid location_id year_id

forvalues i = 0(1)999 {
	replace national_consumption_`i' = national_consumption_`i' * prop_consumption_`i'
	rename national_consumption_`i' sub_consumption_`i'
	drop prop_consumption_`i'
}

** 6. Now that we've multiplied the total consumption by the subnational proportions, we get total consumption by subnational, to turn this back into a per capita number, divide by total population (ages 15+)

forvalues i = 0(1)999 {
	gen per_capita_consumption_`i' = sub_consumption_`i'/tot_pop_subs
	drop sub_consumption_`i'
}

rename per_capita_consumption* draw*
keep me_name location_id year_id draw*

** 7. We should now have liters per capita of alcohol consumption for all of the subnational units, where the per capita is population 15+, save these results- they'll be compiled in later step	

	foreach sub in `subs'{
		preserve
		keep if location_id==`sub'
		save "`post_split'/split_total_consumption_`sub'.dta", replace
		restore
	}

