// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 		      July 23, 2015
// Project:		RISK
// Purpose:		Subnational assignment for physical activity literature sources
** *****************************************************************************************************************

// Bring in literature extraction from GBD 2013 and update for those countries that we are now making subnational estimates 
// For now, we are tagging a source with each place that it's representative of and then we can have all possible information available when a decision is made about how exactly we are treating subnational sources

// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		set mem 12g
	// Set to run all selected code without pausing
		set more off
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}
		
		
// Set up locals 
	local data_dir "J:/WORK/05_risk/risks/abuse_ipv_exp/data/exp/01_tabulate/prepped"
	
// Bring in country codes and location id
	clear
	#delim ;
	odbc load, exec("SELECT ihme_loc_id, location_name, location_id, location_type
	FROM shared.location_hierarchy_history 
	WHERE (location_type = 'admin0' OR location_type = 'admin1' OR location_type = 'admin2')
	AND location_set_version_id = (
	SELECT location_set_version_id FROM shared.location_set_version WHERE 
	location_set_id = 9
	and end_date IS NULL)") dsn(epi) clear;
	#delim cr
	
	rename ihme_loc_id iso3 
	
	// Fix weird symbols that import as question marks 
	replace location_name = subinstr(location_name, "?", "o", .) if regexm(iso3, "JPN")
	replace location_name = subinstr(location_name, "?", "a", .) if regexm(iso3, "IND")
	replace location_name = "Chhattisgarh" if location_name == "Chhattasgarh"
	replace location_name = "Chhattisgarh, Rural" if location_name == "Chhattasgarh, Rural" 
	replace location_name = "Chhattisgarh, Urban" if location_name == "Chhattasgarh, Urban" 
	replace location_name = "Jammu and Kashmir" if location_name == "Jammu and Kashmar" 
	replace location_name = "Jammu and Kashmir, Rural" if location_name == "Jammu and Kashmar, Rural"
	replace location_name = "Jammu and Kashmir, Urban" if location_name == "Jammu and Kashmar, Urban" 
	
	tempfile countrycodes
	save `countrycodes', replace	

** ***********************************************************************************************
// Literature Extraction Spreadsheet from GBD 2010
** ***********************************************************************************************

	insheet using "`data_dir'/gbd2010_ipv_exp.csv", comma names clear 
	tempfile all 
	save `all', replace 
	
	drop if regexm(iso3, "BRA|CHN|IND|JPN|KEN|MEX|ZAF|HKG") 
	tempfile all_but_subnationals
	save `all_but_subnationals'
	
	use `all', clear 
	keep if regexm(iso3, "BRA|CHN|IND|JPN|KEN|MEX|ZAF|HKG")
	
	gen location_id = ""
	
	// WHO MCS  
	  // Brazil (Sao Paulo and Pernambuco)
		replace location_id = "4775, 4766" if iso3 == "BRA" & linkauth == "WHO MCS" 
		
	  // Japan (Kanagawa) 
		replace location_id = "35437" if iso3 == "JPN" & linkauth == "WHO MCS" 
	
	// International Violence Against Women Survey 
		replace iso3 = "CHN_354" if iso3 == "HKG" 
		
	// ENDIREH (Encuesta Nacional Sobre la Dinamica de las Relaciones) 
		// 2003 survey conducted in 11 states: Baja California, Coahuila, Chiapas, Chihuahua, Hidalgo, Michoacan, Nuevo Leon, Quintana Roo, Sonora, Yucatan, Zacatecas 
		replace location_id = "4644, 4647, 4649, 4650, 4655, 4658, 4661, 4665, 4668, 4673, 4674" if iso3 == "MEX" & startyr == 2003
		
	// Bring in all of the other sources

	append using `all_but_subnationals'
	
	// Save revised version 
	
	outsheet using "`data_dir'/gbd2010_ipv_exp_revised.csv", comma names replace
		
** ***********************************************************************************************
// Literature Extraction Spreadsheet from GBD 2013
** ***********************************************************************************************
	
	insheet using "`data_dir'/gbd2013_ipv_exp.csv", comma names clear 
	
	// Add Bihar and Rajasthan specific lifetime IPV numbers (before we had just extracted national)
	
	gen location_id = ""
	
	expand 2 if nid == 19963, gen(dup) 
	replace parameter_value = 63.5 if dup == 1 & age_start == 25
	replace sample_size = 1367 if age_start == 25 & dup == 1
	replace location_id = "48375, 43911" if sample_size == 1367 // Bihar urban rural
	replace parameter_value = 60.3 if dup == 1 & age_start == 20
	replace sample_size = 315 if age_start == 20 & dup == 1
	replace location_id = "48375, 43911" if sample_size == 315 // Bihar urban rural
	
	expand 2 if nid == 19963 & dup == 0, gen(new) 
	replace parameter_value = 47.9 if new == 1 & age_start == 25 
	replace sample_size = 1590 if age_start == 25 & new == 1
	replace location_id = "43899, 43935" if sample_size == 1590 // Rajasthan urban rural 
	replace parameter_value = 46.0 if new == 1 & age_start == 20
	replace sample_size = 337 if age_start == 20 & new == 1
	replace location_id = "43899, 43935" if sample_size == 337 // Rajasthan urban rural
	
	replace representation = "subnational" if dup == 1 | new == 1
	replace url = "http:/jiv.sagepub.com/content/26/10/1963.full.pdf" if nid == 19963 
	
	// Save revised version 
	
	outsheet using "`data_dir'/gbd2013_ipv_exp_revised.csv", comma names replace
	
