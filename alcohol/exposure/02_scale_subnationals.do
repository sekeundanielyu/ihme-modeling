** Scale subnational prevalences of drinkers, former drinkers, and lifetime abstainers to the national prevalences
** Then scale these so they add to 100%
** Parallel by parent countries

** 3360       Alcohol Consumption (g/day)
** 3363       Proportion of drinking events that are binge amongst binge drinkers
** 3364       Proportion of current drinkers
** 3365       Proportion of lifetime abstainers
** 3366       Proportion of binge drinkers
** 3367       Proportion of former drinkers

clear all
set more off
cap restore, not
set maxvar 15000
set type double

if c(os) == "Unix" {
		global prefix "/home/j"
		local parent_id `1'
		local prescale_dir "`2'"
		local postscale_dir "`3'"
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local parent_id = 6
		local prescale_dir "J:/WORK/05_risk/risks/drugs_alcohol/data/exp/prescale/"
		local postscale_dir "J:/WORK/05_risk/risks/drugs_alcohol/data/exp/postscale/"
	}

** Use parent_id passed from master script to find both the national and subnational locations we need (location_id for national, parent_id for subnationals)
insheet using "$prefix/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/locations.csv", clear
tempfile master
save `master', replace

keep if parent_id == `parent_id'
levelsof location_id, local(subnat_locs)

** **************************
** BRING IN NATIONAL DATA*****
** **************************
** Bring in national and subnational data
** National data scaled to 100% already, so bring it in from postscale_dir
clear
tempfile national
use "`postscale_dir'/prevalences_`parent_id'.dta", clear
sort location_id year_id age_group_id sex_id 
** keep only necessary age groups (15-80+)
keep if age_group_id >= 8 & age_group_id <= 21
rename draw_* nat_*
save `national', replace


** ****************************
** BRING IN SUBNATIONAL DATA ***
** ****************************
** Subnational data not scaled, bring it in from prescale_dir
clear 
tempfile subnationals
save `subnationals', emptyok

foreach loc in `subnat_locs'{
	di "`loc'"
	append using "`prescale_dir'/prevalences_`loc'.dta"
}

save `subnationals', replace

sort location_id year_id age_group_id sex_id 


** keep only necessary age groups (15-80+)
keep if age_group_id >= 8 & age_group_id <= 21

** get necessary age groups for get_populations
levelsof age_group_id, local(ages)
save `subnationals', replace

** **********************
** GET POPULATIONS ******
** **********************

** subnats
clear
qui do "$prefix/WORK/10_gbd/00_library/functions/get_populations.ado"
get_populations, year_id(1990 1995 2000 2005 2010 2015) location_id("`subnat_locs'") sex_id(1 2) age_group_id("`ages'")

merge 1:m location_id year_id sex_id age_group_id using `subnationals'
assert _m != 2
keep if _m == 3
drop _m
isid location_id year_id sex_id age_group_id modelable_entity_id 
save `subnationals', replace

** national
clear
get_populations, year_id(1990 1995 2000 2005 2010 2015) location_id("`parent_id'") sex_id(1 2) age_group_id("`ages'")
merge 1:m location_id year_id sex_id age_group_id using `national'
assert _m != 2
keep if _m == 3
drop _m
** we're going to use pop in each category of national for scaling, generate now
forvalues i =0(1)999 {
	replace nat_`i' = pop_scaled*nat_`i'
}
isid location_id year_id sex_id age_group_id modelable_entity_id 
drop location_id
save `national', replace

** *********************
** SCALING *************
** *********************
use `subnationals', clear

** Find pop-weighted prevalences by modelable_entity_id
** First, weight by pops
forvalues i =0(1)999 {
	gen pop_draw_`i' = pop_scaled * draw_`i'
}

** Next, find total across geographies within sex, year, age, and modelable entity
forvalues i =0(1)999 {
	bysort sex_id year_id age_group_id modelable: egen long pop_total_`i' = total(pop_draw_`i') 
}

** merge in national to get scaling factor
merge m:1 sex_id year_id age_group_id modelable using `national', assert(3) nogen

** multiply draws by scaling factor
forvalues i = 0/999 {
	** if you want to check out the scaling factor, uncomment
	** gen scaling_factor_`i' = nat_`i'/pop_total_`i'
	replace draw_`i' = nat_`i'/pop_total_`i'*draw_`i'
}

** now the draws are scaled to the national level within drinking category (drinker,abstainer,former drinker)
** we have to now make them add to 1, this sacrifices the national scaling to some degree, but this is unavoidable 
cap drop nat_* 
cap drop scaling_factor_*
cap drop pop_total_*
cap drop pop_draw_*

forvalues i = 0(1)999 {
	bysort location_id sex_id year_id age_group_id: egen prev_total_`i' = total(draw_`i') 
}

forvalues i = 0/999 {
	replace draw_`i' = 1/prev_total_`i'*draw_`i'
}

** Clean up a bit
cap drop pop_total_* 
cap drop pop_draw_* 
cap drop cat_total_*
cap drop prev_total_*


isid age_group_id year_id location_id sex_id modelable_entity_id model_version_id
order modelable_entity_id model_version_id age_group_id year_id location_id sex_id

** loop and save subnationals by location in the postscale_dir
foreach loc in `subnat_locs' {
	preserve
	keep if location_id == `loc'
	save "`postscale_dir'/prevalences_`loc'.dta", replace
	restore
}

