// Remove known outliers from cancer data
** ***************

// GBD2015 specific exceptions
	drop if inlist(iso3, "POL", "USA") & regexm(acause, "neo_nmsc") 
	drop if regexm(registry, "Aruba")   

// for US, drop city-level data if state-level data are available 
	gen stateLevel = 1 if registry == subdiv & iso3 == "USA" 
	bysort iso3 location_id year acause sex: egen has_stateLevel = total(stateLevel)
	replace registry = "Central California" if registry == "California" & source == "ci5_period_i_viii_with_skin_inc"
	drop if  iso3 == "USA" & has_stateLevel != 0 & registry != subdiv 
	drop if registry == "Greater Georgia" 
	drop stateLevel has_stateLevel
	drop if source == "USA_SEER_threeYearGrouped_1973_2012"

// Drop Brazil exceptions
 	merge m:1 iso3 registry using "$j/WORK/07_registry/cancer/01_inputs/sources/BRA/00_BRA_Documentation/BRA_registry_use.dta", keep(1 3) nogen
	drop if iso3 == "BRA" & !inrange(year, use_data_start_year, use_data_end_year) & use_data_start_year != . & use_data_end_year != .
	drop data_years_available use_data_start_year use_data_end_year

// Exceptions that will likely continue to apply after 2015
	drop if regexm(upper(source), "CI5") & regexm(lower(source), "appendix")  
	drop if source == "COL_2003_2010"
	drop if regexm(source, "NPCR") 

	
** *****
** END
** ******
