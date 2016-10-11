** **************************************************************************
** RUNTIME CONFIGURATION
** **************************************************************************
// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
	// Set to run all selected code without pausing
		set more off
	// Remove previous restores
		capture restore, not
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}
		
// Close previous logs
	cap log close
	
// Create timestamp for logs
	local c_date = c(current_date)
	local c_time = c(current_time)
	local c_time_date = "`c_date'"+"_" +"`c_time'"
	display "`c_time_date'"
	local time_string = subinstr("`c_time_date'", ":", "_", .)
	local timestamp = subinstr("`time_string'", " ", "_", .)
	display "`timestamp'"
	
// Define working risk
	local risk "diet"

//should the fao data be brought back in and formatted?
local prep_data 1

//get locations 
run "J:/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
get_location_metadata, location_set_id(9)
keep if end_date==. & location_set_id==9 //most recent locations epi set for countries we estimate for that are most detailed subnational
keep if is_estimate==1
//keep the maximumed version
qui sum location_set_version_id
keep if location_set_version_id==`r(max)'
rename location_name countryname
drop if inlist(countryname, "Distrito Federal", "North Africa and Middle East", "South Asia")
**dropping the US state of Georgia
drop if location_id == 533
tempfile locations
save `locations', replace

if `prep_data' == 1{
// Bring in FAO data
	insheet using "`fao_dir'`fao_file'.csv", comma clear

// For diet exposure, only interested in grams/day. Save measures in grams per day and in kcal per day. The kcal per day measures will be used to generate an energy adjustment scalar to standardize to 2000 kcal/day
	keep if unit == "Kg" | unit == "kcal/capita/day"


// Keep only FAO itemcodes that we've mapped to GBD categories
	merge m:1 itemcode using `FAO_codebook' // Merge on the codebook that binds items to covariates
	drop if _m!=3
	drop _m
	drop if unit == "kcal/capita/day" & covariate != "total" // We don't care about kcals in this analysis, except for the total category which is used to create a scalar to standardize to 2000 kcal/day.
	
	// drop observations where value is missing so that when summing by covariate, overall estimate does not go to 0
		drop if value == . 
		
	// Aggregate all values by summing them across country-years into buckets for each different covariate
		collapse (sum) value, by(country year covariate) fast
		rename country countryname
//because stata hates csvs, save as dta for future use
	 save `out_dir'`fao_file'.dta, replace
}

if `prep_data' !=1 {
	use `out_dir'`fao_file'.dta, replace
}


**rename countrynames to match ihme location_names
rename countryname location_name
**remove "China" because it is a combination of ALL of China
drop if location_name == "China"
replace location_name = "Russia" if location_name == "Russian Federation"
replace location_name = "Vietnam" if location_name == "Viet Nam"
replace location_name = "United States" if location_name == "United States of America"
replace location_name = "Iran" if location_name == "Iran (Islamic Republic of)"
replace location_name = "China" if location_name == "China, mainland"
replace location_name = "Venezuela" if location_name == "Venezuela (Bolivarian Republic of)"
replace location_name = "Tanzania" if location_name == "United Republic of Tanzania"
replace location_name = "Taiwan" if location_name == "China, Taiwan Province of"
replace location_name = "Syria" if location_name == "Syrian Arab Republic"
replace location_name = "South Korea" if location_name == "Republic of Korea"
replace location_name = "North Korea" if location_name == "Democratic People's Republic of Korea"
replace location_name = "Cote d'Ivoire" if location_name == "Côte d'Ivoire"
replace location_name = "Cape Verde" if location_name == "Cabo Verde"
replace location_name = "Bolivia" if location_name == "Bolivia (Plurinational State of)"
replace location_name = "Macedonia" if location_name == "The former Yugoslav Republic of Macedonia"
replace location_name = "Brunei" if location_name == "Brunei Darussalam"
replace location_name = "Laos" if location_name == "Lao People's Democratic Republic"
replace location_name = "The Bahamas" if location_name == "Bahamas"
replace location_name = "The Gambia" if location_name == "Gambia"
replace location_name = "Moldova" if location_name == "Republic of Moldova"
replace location_name = "Hong Kong Special Administrative Region of China" if location_name == "China, Hong Kong SAR"
replace location_name = "Macao Special Administrative Region of China" if location_name == "China, Macao SAR"
replace location_name = "Ethiopia" if location_name == "Ethiopia PDR"
replace location_name = "Sudan" if location_name == "Sudan (former)"
rename location_name countryname
	
// Merge to GBD iso3 codes and IHME countrynames, then drop countries if they don't appear within IHME analyses
	merge m:1 countryname using `locations'
	keep if _merge == 3
	drop _merge

**this is where the nutrient data should be appended in
preserve
	use "SUA_USDA_nutrients.dta", clear
	**getting rid of non-GBD nutrients
	drop if metc == .
	rename location_name countryname
	rename mean value
	**removing "diet_" to create the covariate variable
	gen covariate = substr(ihme_risk, 6, .)
	replace covariate = "saturated_fats" if covariate == "satfat"
	gen nutrients_data = 1
	drop risk

	tempfile nutrients
	save `nutrients', replace
restore
		
// Want to adjust so that all measurements are equivalent to 2000 kcal/day consumption
	preserve
	// break out the total kcal per day food availability data
	keep location_name location_id covariate value year
	
	keep if covariate == "total"
	
	generate energy_adj_scalar = .
	
	// 2000 calories is the reference diet used
	
		replace energy_adj_scalar = 2000 / value
		
	// Generate a total diet calories variable to merge onto everything else as a comparison
	
		generate total_calories = value
	
	tempfile energy_adj_scalar_data
	save `energy_adj_scalar_data', replace
	
	restore
	
	merge m:1 location_id year using `energy_adj_scalar_data', keep(3) //note, not all country years have total data, keep only those that do
	drop _m

	**remove the saturated fats created based solely off of total food items
	drop if covariate == "saturated_fats"

	**this is where nutrient data should be appended in with the energy scalar already calculated...
	append using `nutrients'

	**fixing NID
	replace nid = 239249 if nutrients_data == 1
	replace nid = 200195 if nutrients_data != 1

// Convert kilograms per year into grams per day and apply the scalar to get 2000 kcal/day standardized value
	generate grams_daily = .
	replace grams_daily = value * 1000 / 365 * energy_adj_scalar if nutrients_data != 1 & covariate != "total" 
	replace grams_daily = value * energy_adj_scalar if nutrients_data == 1
	**the fats have already been energy adjusted before they were turned into percents (refer to "USDA_defs_to_FAO.do")
	replace grams_daily = value if covariate == "saturated_fats" | covariate == "transfat" | covariate == "pufa" | covariate == "mufa"
	**no adjustment for total calories
	replace grams_daily = . if covariate == "energy" | covariate == "total"
	replace grams_daily = . if grams_daily == 0
// Convert kilograms per year into grams per day without adjustment for comparison
	generate grams_daily_unadj = .
	replace grams_daily_unadj = value * 1000 / 365 if nutrients_data != 1 & covariate != "total" 
	replace grams_daily_unadj = value if nutrients_data == 1
	**fats are only energy adjusted (as modeled)
	replace grams_daily_unadj = . if covariate == "saturated_fats" | covariate == "transfat" | covariate == "pufa" | covariate == "mufa"
	replace grams_daily_unadj = . if grams_daily_unadj == 0
	
// Final modifications and export
	gen iso3 = ihme_loc_id
	drop if iso3 == "PSE" // bad data, all values are zero (Palestine Territory)
	rename covariate gbd_cause
	gen risk = gbd_cause
	gen countryname_ihme = countryname
	gen ihme_country = countryname

**removing obvious outliers from data
	replace grams_daily = . if iso3 == "GIN" & year == 2013 & gbd_cause == "pufa"
	replace grams_daily = . if iso3 == "GIN" & year == 2013 & gbd_cause == "saturated_fats"
	**Problematic estimates from MNE
	drop if iso3 == "MNE" & nutrients_data == 1
	drop nutrients_data
	
	compress
	
	order iso3 countryname_ihme year gbd_cause grams*
	save `out_dir'/FAO_all.dta, replace
	
//save a subset of the file that has the location information for variance estimation (used in paralellizing on cluster)
keep iso3 location_name location_id ihme_loc_id
duplicates drop
save `out_dir'/FAO_locyears.dta, replace

