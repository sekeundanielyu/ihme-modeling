** 1/14/16
** Quick job to run get_location_metadata from 00_master script if ever need to update hierarchy

clear all
set more off
cap restore, not

if c(os) == "Unix" {
		global prefix "/home/j"
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

qui do "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado"

get_location_metadata, location_set_id(9) 
drop if is_estimate == 0
keep location_id location_name parent_id level location_type

** CHN_44533 exists in the alcohol_lpc data, but not in the DisMod data- may need to figure out how to incorporate into our estimation process properly

export delimited "$prefix/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/locations.csv", delim(",") replace

