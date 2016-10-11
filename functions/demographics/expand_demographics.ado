/*
Purpose:	Make a square dataset of all location/year/sex/age combinations used for Demographics
How To:		expand_demographics or expand_demographics, get_population
Arguments: 	Type: all (default), lowest, national: 
				All will get all locations including regional/global aggregates and IND states etc.
				Lowest will get lowest locations possible (all subnationals, no national aggregates)
				National will get national-level only (level 1 from get_locations)
			get_population/get_envelope: logical, whether to add envelope or population onto here

*/


cap program drop expand_demographics
program define expand_demographics
	version 12
	syntax , [type(string)] [get_population] [get_envelope]

// prep stata
	if c(os) == "Unix" global prefix "/home/j"
	else if c(os) == "Windows" global prefix "J:"
	
	clear
		

// Get locations
adopath + "strPath"

if "`type'" == "" | "`type'" == "all" get_locations, level(all)
if "`type'" == "lowest" get_locations, level(lowest)
if "`type'" == "national" {
    get_locations, level(all)
    keep if level_1 == 1 // These are all the countries processed as nationals in Mortality modeling
}
keep location_id ihme_loc_id location_name region_id region_name super_region_id super_region_name level 

expand 2
bysort location_id: gen sex_id = _n

expand 46
bysort location_id sex_id: gen year_id = _n + 1969

expand 20
bysort location_id sex_id year_id: gen age_group_id = _n + 1 // Generate NN through 80+ (age groups 2-21)

order location_id ihme_loc_id year_id sex_id age_group_id

if "`get_population'" != "" | "`get_envelope'" != "" {
	tempfile temp_map
	save `temp_map'
	if "`get_population'" != "" get_env_results, pop_only
	if "`get_envelope'" != "" get_env_results
	merge 1:1 location_id year_id sex_id age_group_id using `temp_map', keep(2 3)
	qui count if _m == 2
	if `r(N)' > 0 {
		di "Some results do not exist in the envelope!"
		BREAK
	}
	drop _m
}

// end program
end
    