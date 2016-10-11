** Compile alc lpc with age group splits for all locations in one file
** Do some transformations, resave files in GBD 2013 format for quick PAF run


clear all
set more off
cap restore, not

if c(os) == "Unix" {
		global prefix "/home/j"
		local postscale_dir "`1'"
		di "`postscale_dir'"
		local temp_dir "`2'"
		di "`temp_dir'"
		local pop_file "`3'"
		di "`pop_file'"
		local location_id "`4'"
		di "`location_id'"
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local postscale_dir "J:\WORK\05_risk\risks\drugs_alcohol\data\exp\postscale"
		local temp_dir "/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/temp"
		local pop_file "J:/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/population.dta"
		local location_id 102
	}


** Grab each of the alc lpc files from the postscale dir

use "/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/exp/postscale/alc_lpc_`location_id'.dta"
cap drop pop_scaled
cap drop total_pop
tempfile lpc
save `lpc', replace

** now we have all of the consumption data, we need populations to split consumption between men and women
** if alc_lpc files are consumption with total pop as denominator, then we can just multiply out here to get total consumption
use "`pop_file'", clear
keep if location_id == `location_id'
keep if age_group_id >= 8
keep location_id year_id age_group_id sex_id pop_scaled

merge 1:1 location_id year_id age_group_id sex_id using `lpc'
drop if _m == 1
drop _m 
assert pop_scaled != .
save `lpc', replace

sort location_id year_id sex_id
foreach var of varlist alc_lpc* {
	** draws of total consumption
	replace `var' = `var' * pop_scaled
	** total consumption by location year sex
	by location_id year_id sex_id: egen `var'_tot = total(`var')
	** fraction of location year sex consumed by age group
	replace `var' = `var'/`var'_tot
}
drop alc_lpc*tot
rename alc_lpc_* draw_*
keep location_id sex_id year_id age_group_id draw* pop_scaled

gen AGE_CATEGORY = 1 if age_group_id < 12
replace AGE_CATEGORY = 2 if age > 11 & age < 17
replace AGE_CATEGORY = 3 if age > 16

** need mean as well in order for there to be an analytical mean for PAFs
** the arithmetic works out so they're all percentages of 1, so we're all set
egen mean_frac = rowmean(draw_*)

** loop over age-sex-year combinations to save files
levelsof age_group_id, local(ages)
levelsof sex_id, local(sexes)
levelsof year_id, local(years)

order location_id year_id age_group_id sex_id pop_scaled mean_frac

save "`temp_dir'/loc_agefrac/alc_age_frac_`location_id'.dta", replace

	
	
	