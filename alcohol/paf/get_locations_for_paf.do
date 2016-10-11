/*
Small stata do file to get IHME locations
12/14/15
*/

clear all
set more off

// Set directories
if c(os) == "Windows" {
	global prefix "J:"
	set mem 3000m
}
if c(os) == "Unix" {
	global prefix "/home/j"
	set mem 8g
} 

clear
include "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado"

get_location_metadata, location_set_id(9)
keep if level >= 3 & is_estimate == 1 & most_detailed==1
keep location_id parent_id level is_estimate most_detailed location_name super_region_id super_region_name region_id region_name ihme_loc_id
export delimited using "$prefix/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/paf_locations.csv", replace

clear
exit, STATA
end
