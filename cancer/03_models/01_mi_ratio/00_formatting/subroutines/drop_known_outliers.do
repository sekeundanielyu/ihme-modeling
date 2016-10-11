// Purpose: Remove known outliers from MI input
** ***************
// for US, drop city-level data if state-level data are available
	gen stateLevel = 1 if registry == subdiv & iso3 == "USA" 
	bysort iso3 location_id year acause sex: egen has_stateLevel = total(stateLevel)
	drop if  iso3 == "USA" & has_stateLevel != 0 & registry != subdiv // City data are included in state-level data
	drop if registry == "Greater Georgia" 	// Greater Georgia overlaps with Rural Georgia and Atlanta. After 2010, Rural Georgia and Atlanta cover the whole of Georgia
	drop stateLevel has_stateLevel
	
** *****
** END
** ******
