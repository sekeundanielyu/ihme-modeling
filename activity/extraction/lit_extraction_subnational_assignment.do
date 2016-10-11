// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 			June 29, 2015
// Project:		RISK
// Purpose:		Re-do literature extractions with subnational assignment for physical activity 
** *****************************************************************************************************************

// Bring in literature extraction from GBD 2013 and update for those countries that we are now making subnational estimates 

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
	local data_dir "J:/WORK/05_risk/risks/activity/data/exp/raw"
	
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
	
	rename location_name site_new
	keep if regexm(iso3, "IND|BRA|ZAF|SWE|JPN|CHN|SAU") 
	drop iso3 
	
	tempfile countrycodes
	save `countrycodes', replace	

** ***********************************************************************************************
// Literature Extraction Spreadsheet (Long Format) from GBD 2013
** ***********************************************************************************************
	insheet using "`data_dir'/report_extraction_longformat.csv", comma names clear
	tempfile all 
	save `all', replace 
	
// save all sources without subnationals (which are being updated)
	drop if regexm(iso3, "IND|BRA|ZAF|SWE|JPN|HKG|XCO|SAU") | regexm(source_name, "China") 
	tempfile all_but_subnationals 
	save `all_but_subnationals', replace 
	
	use `all', clear 
	keep if regexm(iso3, "IND|BRA|ZAF|SWE|JPN|HKG|XCO|SAU") | regexm(source_name, "China") 
	
	gen site_new = site + ", " + representation if nid == 67200 
	replace site_new = strproper(site_new)

	tempfile subnationals
	save `subnationals', replace
	
// Update China iso3 codes
	
	// Bring in GBD 2013 subnational China locations 
	odbc load, exec("select local_id as iso3, name as country from locations") dsn(codmod) clear
	keep if regexm(iso3, "^X")
	
	merge 1:m iso3 using `subnationals', nogen keep(2 3 4 5)
	save `subnationals', replace
	
	// Bring in 2015 subnational China locations 
	
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
	rename location_name country
	keep if regexm(iso3, "CHN")
	
	merge 1:m country using `subnationals', force nogen keep(2 3 4 5)
	replace site_new = country if site_new == ""
	drop country
	
	
// Only replacing location_id (not iso3 code)
	merge m:m site_new using `countrycodes', nogen keep(1 3 4 5) update replace 
	drop location_type 
	
	// For those sources that represent multiple subnatoinal units, create a location_id column and list all of the location_ids that are represented by this source 
	
	tostring location_id, replace
	replace location_id = "43901, 43937" if site_new == "Tamil Nadu, Mixed" 
	replace location_id = "43905, 43941" if site_new == "Uttarakhand, Mixed"
	replace location_id = "43894, 43930" if site_new == "Mizoram, Mixed" 
	replace location_id = "43872, 43908" if site_new == "Anhra Pradesh, Mixed" 
	replace location_id = "43891, 43927" if site_new == "Maharashtra, Mixed" 
	replace location_id = "43888, 43924" if site_new == "Kerala, Mixed" 
	replace location_id = "43890, 43926" if site_new == "Madhya Pradesh, Mixed" 
	
	replace iso3 = "CHN" if regexm(iso3, "CHN") 
	replace location_id = "354" if iso3 == "HKG" 
	replace iso3 = "CHN" if iso3 == "HKG" 
	
// Look at site variable to see where data was conducted 
	replace location_id = "44543" if regexm(site, "Riyadh") 
	replace location_id = "4775" if regexm(site, "Sao Paolo") 
	
	// Ghaziabad is a city in Uttar Pradesh and Nagpur is a city in Maharashtra
	replace location_id = "43904, 43891" if regexm(site, "Ghaziabad and Nagpur") 
	
	
// replace file paths 

	replace file = "J:/DATA/BRA/SURVEILLANCE_SYSTEM_OF_RISK_FACTORS_FOR_CHRONIC_DISEASES_BY_TELEPHONE_INTERVIEWS_VIGITEL/2008/BRA_VIGITEL_2008_REP_QUEST_Y2013M11D11.pdf" if nid == 130971
	replace file = "J:/DATA/BRA/SURVEILLANCE_SYSTEM_OF_RISK_FACTORS_FOR_CHRONIC_DISEASES_BY_TELEPHONE_INTERVIEWS_VIGITEL/2009/BRA_VIGITEL_2009_REP_QUEST_Y2013M01D08.pdf" if nid == 130972
	replace file = "J:/DATA/BRA/SURVEILLANCE_SYSTEM_OF_RISK_FACTORS_FOR_CHRONIC_DISEASES_BY_TELEPHONE_INTERVIEWS_VIGITEL/2010/BRA_VIGITEL_2010_REP_QUEST_Y2013M01D08.pdf" if nid == 130973
	replace file = "J:/DATA/BRA/SURVEILLANCE_SYSTEM_OF_RISK_FACTORS_FOR_CHRONIC_DISEASES_BY_TELEPHONE_INTERVIEWS_VIGITEL/2011/BRA_VIGITEL_2011_REP_QUEST_Y2013M01D08.pdf" if nid == 130978

	replace file = "J:/DATA/SWE/NATIONAL_SURVEY_PUBLIC_HEALTH/2012/SWE_NATIONAL_SURVEY_PUBLIC_HEALTH_2012_PHYSICAL_ACTIVITY_EN_Y2013M11D12.xlsx" if nid == 128836

	sort file 

	save `subnationals', replace 

// Replace old extraction file 

	use `all_but_subnationals', clear
	tostring location_id, replace 
	save `all_but_subnationals', replace 

	append using `subnationals'
	
	save `all', replace 
	

// Save!

	outsheet using "`data_dir'/report_extraction_longformat_revised.csv", comma names replace 
