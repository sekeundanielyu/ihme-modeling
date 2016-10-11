** 12/18/15
** Code parallel by location 

** modelable entity ids
** 3360       Alcohol Consumption (g/day)
** 3363       Proportion of drinking events that are binge amongst binge drinkers
** 3364       Proportion of current drinkers
** 3365       Proportion of lifetime abstainers
** 3366       Proportion of binge drinkers
** 3367       Proportion of former drinkers


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
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local location_id = 6
		local prescale_dir "J:\WORK\05_risk\risks\drugs_alcohol\data\exp\prescale"
		local postscale_dir "J:\WORK\05_risk\risks\drugs_alcohol\data\exp\postscale"
	}

** load get_draws function in order to use below	
quietly adopath + "$prefix/WORK/10_gbd/00_library/functions/"

** load in country identifier file to tell if location is subnational to see where it should be saved below at end
insheet using "$prefix/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/locations.csv", clear
keep if location_id == `location_id'
if (location_type != "admin0" & location_type != "nonsovereign") {
	local save_dir "`prescale_dir'"
	local indic_subnat = 1
}
else {
	local save_dir "`postscale_dir'"
	local indic_subnat = 0
}
di "`save_dir'"


** save the mutually exclusive and collectively exhaustive prevalence draws together
clear
tempfile compiled
save `compiled', emptyok

foreach model in 3364 3365 3367 {
	di "`model'"
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(`model') location_ids(`location_id') year_ids(1990 1995 2000 2005 2010 2015) sex_ids(1 2) source(dismod) status(best) clear
	keep if age_group_id >= 8 & age_group_id <= 21
	append using `compiled'
	save `compiled', replace
}


** if not subnational, squeeze prevalences of current drinkers, former drinkers, lifetime abstainers to 100% by draw, maintaining relative proportions
if (`indic_subnat' == 0) {
	sort location_id year_id sex_id age_group_id
	forvalues i = 0/999 {
		by location_id year_id sex_id age_group_id: egen prev_sum_`i' = total(draw_`i')
		replace draw_`i' = draw_`i'*1/prev_sum_`i'
		drop prev_sum_`i'
	}
}

** drop extraneous variables for our process
drop measure_id

** if the location is a subnational location that needs to be scaled, save in prescaled folder
** if the location is a national that doesn't need to be scaled, save in post-scaled folder from the get-go
save "`save_dir'/prevalences_`location_id'.dta", replace


** for non-scaled inputs, just pull
** 3360       Alcohol Consumption (g/day)
** 3363       Proportion of drinking events that are binge amongst binge drinkers
** 3366       Proportion of binge drinkers

foreach model in 3360 3363 3366 {
	di "`model'"
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(`model') location_ids(`location_id') year_ids(1990 1995 2000 2005 2010 2015) sex_ids(1 2) source(dismod) status(best) clear
	drop measure_id
	keep if age_group_id >= 8 & age_group_id <= 21
	if (`model' == 3360) save "`prescale_dir'/`model'_dismod_output_`location_id'.dta", replace
	if (`model' == 3363 | `model' == 3366) save "`postscale_dir'/`model'_dismod_output_`location_id'.dta", replace
}


