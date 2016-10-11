/*
Purpose:	Grab locations given certain parameters
How To:		get_locations // will get you 2015 results at lowest level 
			get_locations, gbd_year(2015) level(lowest) gbd_type(gbd) reporting(no) subnat_only()
			get_locations, subnat_only(KEN)
			Options (all are optional):
				gbd_year (2010, 2013, 2015): 
					Specify year of GBD that you want locations for . 
					Default: 2015
				level (lowest, country, countryplus, region, super, global, all):  
					Do you want all of the levels, or just the lowest-level possible, countries, regions, super-regions, or global 
					countryplus will grab all of the countries AND all of the subnationals (estimates and non-estimates together)
					estimate will grab all of the countries AND all of the subnationals WHERE is_estimate == 1 (so excludes the reporting aggregates like England, China total, etc.)
					Default: countryplus (country along with subnational ids, e.g. CHN and CHN_####)
				gbd_type: 
					What type of GBD computation do you want locations for? (gbd, epi, cod)
					Default: gbd
				reporting (yes/no):
					Do you want the reporting or computation versions of the locations?
					Default: no (aka use computation version)
					Note: Reporting only available with gbd_type = "gbd" -- CoD and Epi don't have reporting
				subnat_only (iso3):
					Do you want only the subnational locations for one specific country? If so, write the iso3 of the country here.
					Default: nothing
*/

cap program drop get_locations
program define get_locations
	version 12
	syntax , [gbd_year(string)] [level(string)] [gbd_type(string)] [reporting(string)] [subnat_only(string)] 

// prep stata
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	
	clear
	
	// This adds in the modeling levels used for the three levels of subnational analysis used in 45q15 and 5q0 among others
		insheet using "strPath/modeling_hierarchy.csv", comma clear
		keep location_id level_1 level_2 level_3 level_all
		tempfile locs_temp
		save `locs_temp'
	
	// Set defaults for options, along with recoding of options
		if "`gbd_year'" == "" local gbd_year "2015"
		if "`gbd_type'" == "" local gbd_type "mortality" // Default to GBD locations
		if "`level'" == "" local level = "countryplus" // Default to using subnationals and country-level regardless of is_estimate level
		if "`reporting'" == ""  local reporting "no" // Default to using Computation locations
		
		if "`reporting'" == "yes" & "`gbd_type'" != "gbd" {
			di in red "Reporting versions are only available for gbd_type gbd"
			di in red "Will pull locations for `gbd_type' Computation version for `gbd_year'"
		}
		
		if "`reporting'" == "yes" & "`gbd_type'" == "GBD" local report_string = "Reporting"
		else local report_string = "Computation"
		
	// Set GBD round and set_ids based on gbd_year and gbd_type
		if "`gbd_year'" == "2016" local gbd_round = 4
		if "`gbd_year'" == "2015" local gbd_round = 3
		if "`gbd_year'" == "2013" local gbd_round = 2
		if "`gbd_year'" == "2010" local gbd_round = 1
		
		if "`gbd_type'" == "gbd" & "`reporting'" == "yes" local best_set = 1
		if "`gbd_type'" == "gbd" & "`reporting'" == "no" & `gbd_year' >= 2015 local best_set = 35
		if "`gbd_type'" == "gbd" & "`reporting'" == "no" & `gbd_year' < 2015 local best_set = 2
		if "`gbd_type'" == "mortality" local best_set = 21
		if "`gbd_type'" == "sdi"  local best_set = 40
			
	// Refer to standard function for defining database connections, for use in connecting to shared DB
		quiet run "strPath/create_connection_string.ado"
		create_connection_string, server("strDB") database("strDB") user("strUser") password("strPass")
		local conn_string = r(conn_string)
	
	// Check to see if the location_set_version_id actually exists
		#delimit ;
		odbc load, exec("
			SELECT location_set_version_id, gbd_round_id, location_set_id 
            FROM shared.location_set_version_active 
            WHERE location_set_id = `best_set'
            AND gbd_round_id = `gbd_round'
		") `conn_string' clear;
		#delimit cr
		
		if _N == 0 {
			di in red "No location_set_version_id exists for this combination of gbd_type `gbd_type' and gbd_year `gbd_year'"
			BREAK
		}
		
		qui levelsof location_set_version, local(version_id) c
		
	// Import GBD2013 local_ids to get GBD2013 local_ids to help merges
	// We don't restrict this to only GBD2015 pulls because we want the file structure to be the same regardless of the year input into it (even if it's redundant)
		#delimit ;
		odbc load, exec("
		SELECT 
			location_id, local_id as local_id_2013
		FROM
			shared.location_hierarchy_history
		WHERE
			location_set_version_id = 11
		") `conn_string' clear;
		#delimit cr
				
		tempfile tempmap_2013
		qui save `tempmap_2013'
		
	// Import the GBD2015 locations
	di in red "Pulling locations for GBD 2015 `report_string', gbd_type `gbd_type', at `level' level (version `version_id')"

	// Bring in all results for the given location_set_version_id number
		if "`gbd_type'" != "sdi" {
			#delimit ;
			odbc load, exec("
			SELECT 
				location_id, location.location_name as location_name_accent, location.location_ascii_name as location_name, location_type, 
				level, super_region_id, super_region_name, region_id, region_name, ihme_loc_id, local_id, parent_id, location_set_version_id, is_estimate, location.path_to_top_parent
			FROM
				shared.location_hierarchy_history
			JOIN 
				shared.location using(location_id) 
			WHERE
				location_set_version_id = `version_id'
			") `conn_string' clear;
			#delimit cr
		}
		else {
			#delimit ;
			odbc load, exec("
			SELECT 
				master.location_id, location.location_name as location_name_accent, location.location_ascii_name as location_name, location_type, 
				level, super_region_id, super_region_name, region_id, region_name, mort.ihme_loc_id, local_id, parent_id, location_set_version_id, is_estimate, location.path_to_top_parent
			FROM
				shared.location_hierarchy_history as master
			JOIN 
				shared.location using(location_id) 
			LEFT JOIN (SELECT location_id,ihme_loc_id from shared.location_hierarchy_history 
						WHERE location_set_version_id = shared.active_location_set_version(21,`gbd_round') 
						) mort 
				ON mort.location_id=master.location_id 
			WHERE
				location_set_version_id = `version_id'
			") `conn_string' clear;
			#delimit cr
		}
		
		drop location_set_version_id
		
	qui replace location_name = "Global" if location_name_accent == "Global" // We don't want LN to be Earth
	
	// If level is specified, only keep geographies at that level
	// NOTE: We don't use level 6, which is deprivation levels, because Mortality doesn't need that level of detail for Uk
	// Instead, for subnational/lowest, we use level 5, which is the standard GBR non-split levels
		if "`level'" == "country" local level_target = 3
		if "`level'" == "region" local level_target = 2
		if "`level'" == "super" local level_target = 1
		if "`level'" == "global" local level_target = 0
		
		if !inlist("`level'","all","lowest","countryplus","subnational","estimate") qui keep if level == `level_target'
		if "`level'" == "subnational" qui keep if level == 4 | level == 5
	// If we want the lowest geographies (at subnational if available, country if not), do something a bit more tricky
		if "`level'" == "lowest" | ("`level'" == "countryplus" & "`gbd_type'" != "sdi") | "`level'" == "estimate" {
			qui {
				// Keep only subnational or country locations
					keep if level == 3 | level == 4  | level == 5 
				if "`level'" == "lowest"{
					// Drop all parent country locations
					// Inlist didn't properly drop locations so we are going to just loop over parents (not too many, so not a big hassle)
						levelsof parent_id if level == 4 | level == 5 , local(parent_drop) c
						foreach parent_country of local parent_drop {
							drop if location_id == `parent_country'
						}
				}
			}
		}
		
	// If level == "estimate", let's keep if is_estimate = 1
		qui if "`level'" == "estimate" keep if is_estimate == 1
		
	
	// If the subnat_only option is specified, only keep subnationals for the specified country
	if "`subnat_only'" != "" {
		if !inlist("`level'","lowest","subnational","countryplus","estimate") {
			di in red "Cannot specify a non-subnational level and expect a subnational-restricted list. Specify lowest level option."
			BREAK
		}
		else {
			di in red "Keeping only country level and subnational units from `subnat_only'"
			qui keep if regexm(ihme_loc_id,"`subnat_only'") 
		}
	}
		
	// Bring back the old location ids from GBD2013 for use in data manipulation
	qui merge 1:1 location_id using `tempmap_2013', keep(1 3) nogen 
	order location_name ihme_loc_id local_id local_id_2013 location_id level parent_id region* super* location_type location_name_accent
	qui replace local_id_2013 = "XEN" if location_name == "England"

	// Add in modeling IDs
	qui { 
		merge 1:1 location_id using `locs_temp', keep(1 3) nogen 
		foreach i in 1 2 3 all {
			replace level_`i' = 0 if level_`i' == .
		}
	}
	
	// end program
	end
