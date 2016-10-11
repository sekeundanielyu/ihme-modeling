/*
AUTHOR: Andrea Stewart

DATE: 23 Jan 2014

PURPOSE: Get the GBD 2013 iso3 list with whether or not each country is located in a "High-Income" superregion
*/

cap program drop get_countries
program define get_countries
	version 12.1
	syntax , prefix(string) 
	
// if you are on the cluster set the correct odbc manager
if "$prefix" == "/home/j" set odbcmgr unixodbc

** pull the list of iso3 codes that the results are saved at
** get the country &subnational codes from the sql server and store them in memory
odbc load, exec("SELECT DISTINCT loc.local_id AS iso3,loc.location_id AS location_id,loc.type AS location_type,parents.local_id AS parent_iso3 FROM locations loc LEFT JOIN locations_indicators indic ON loc.location_id = indic.location_id LEFT JOIN locations_hierarchy to_admin0 ON loc.location_id = to_admin0.descendant AND to_admin0.version_id = 2 AND to_admin0.type = 'gbd' LEFT JOIN locations parents ON to_admin0.ancestor = parents.location_id AND parents.type in ('admin0') WHERE loc.type in ('admin1','admin0','urbanicity') AND indic.indic_epi = 1 AND parents.local_id IS NOT Null") dsn(epi) clear
** first get the list of parent country iso3s, minus those that have subnational estimates
preserve
duplicates tag parent_iso3, gen(dup_iso)
keep if dup_iso==0
gen location=parent_iso3
keep location parent_iso3
gen child_iso3=parent_iso3
tempfile solo_countries
save `solo_countries', replace

restore
** now get the subnational identifiers as "[iso3]_[location_id]"
keep if iso3!=parent_iso3
tostring location_id, replace
gen subnats=parent_iso3+ "_" + location_id
keep subnats parent_iso3 iso3
rename iso3 child_iso3
rename subnats location
append using `solo_countries'

levelsof location, local(iso3s) clean
global iso3s `iso3s'

tempfile country_map
save `country_map', replace

** bring in the map from iso to superregion
odbc load, exec("SELECT DISTINCT subreg.location_id,COALESCE(reg_analytic.location_id,reg.location_id) AS region,COALESCE(sr_analytic.location_id,sr.location_id) AS super_region,subreg.local_id AS iso3,COALESCE(reg_analytic.name,reg.name) AS region_name,COALESCE(sr_analytic.name,sr.name) AS super_region_name FROM locations subreg LEFT JOIN locations_indicators indic ON subreg.location_id = indic.location_id LEFT JOIN locations_hierarchy subreg_to_reg ON subreg.location_id = subreg_to_reg.descendant AND subreg_to_reg.type = 'gbd' AND subreg_to_reg.version_id = 2 LEFT JOIN locations reg ON subreg_to_reg.ancestor = reg.location_id LEFT JOIN locations_metadata md_reg ON subreg.location_id = md_reg.location_id AND md_reg.key_id = 2 LEFT JOIN locations reg_analytic ON md_reg.key_value = reg_analytic.location_id LEFT JOIN locations_hierarchy reg_to_sr ON subreg.location_id = reg_to_sr.descendant AND reg_to_sr.type = 'gbd' AND subreg_to_reg.version_id = 2 LEFT JOIN locations sr ON reg_to_sr.ancestor = sr.location_id LEFT JOIN locations_metadata md_sr ON subreg.location_id = md_sr.location_id AND md_sr.key_id = 3 LEFT JOIN locations sr_analytic ON md_sr.key_value = sr_analytic.location_id WHERE subreg.type = 'admin0' AND indic. indic_cod = 1 AND reg.type = 'region' AND sr.type = 'superregion'") dsn(epi) clear
keep iso3 super_region_name
gen high_income=0
replace high_income=1 if super_region_name=="High-income"
keep iso3 high_income

rename iso3 parent_iso3

merge 1:m parent_iso3 using `country_map', keep(3) nogen



end



