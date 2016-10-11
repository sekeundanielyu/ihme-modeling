// Purpose: generate confidence intervals for type-specific disaster deaths


	clear all
	set more off
	
		if c(os) == "Windows" {
			global prefix ""
		}
		else {
			global prefix ""
			set odbcmgr unixodbc
		}
	
	global datadir ""
	global outdir ""
	
	// Set the timestamp
	local date = c(current_date)
	local date = c(current_date)
	local today = date("`date'", "DMY")
	local year = year(`today')
	local month = month(`today')
	local day = day(`today')
	local time = c(current_time)
	local time : subinstr local time ":" "", all
	local length : length local month
	if `length' == 1 local month = "0`month'"	
	local length : length local day
	if `length' == 1 local day = "0`day'"
	local date = "`year'_`month'_`day'"
	local timestamp = "`date'_`time'"
	
	do "create_connection_string.ado"
	create_connection_string
	local conn_string `r(conn_string)'
	
	do "get_location_metadata.ado"
	
	// Locations_ids
	get_location_metadata, location_set_id(35) clear
	keep if location_type == "admin0" | location_type == "nonsovereign"
	keep location_id ihme_loc_id
	rename ihme_loc_id iso3
	tempfile locations
	save `locations', replace
	
	// Location names
	get_location_metadata, location_set_id(35) clear
	keep location_id location_ascii_name
	rename location_ascii_name location_name
	isid location_id
	tempfile location_names
	save `location_names', replace

	
	*************************************************************************************
	*************************************************************************************
	// bring in formatted data
	use "formatted_type_specific_disaster_deaths.dta", clear
	
	append using "formatted_type_specific_technological_deaths.dta"
	
	append using "formatted_disaster_supp_data_rates_with_cis.dta"
		// drop Hajj from this online source, we use other source
		drop if iso3 == "SAU" & year == 2015 & cause == "Other" & source == "Online supplement 2015"
	
	drop if numkilled == 0
	
	tempfile disaster
	save `disaster', replace
	
	// Check duplicates with VR
	append using "VR_shocks_disaster.dta"
	replace cause = "inj_disaster" if inlist(cause, "Earthquake", "Flood", "Landslide", "Natural disaster", "Other Geophysical", "Other hydrological", "storm", "Volcanic activity")
	replace cause = "inj_fires" if inlist(cause, "Fire", "Wildfire")
	replace cause = "inj_mech_other" if inlist(cause, "Collapse", "Explosion", "Other")
	replace cause = "inj_non_disaster" if inlist(cause, "Cold wave", "Heat wave")
	replace cause = "inj_poisoning" if inlist(cause, "Chemical spill", "Gas leak", "Poisoning")
	replace cause = "inj_trans_road_4wheel" if inlist(cause, "Road")
	replace cause = "inj_trans_other" if inlist(cause, "Air", "Rail", "Water")
	replace cause = "nutrition_pem" if inlist(cause, "Drought", "Famine")
	replace cause = "inj_mech_other" if cause == "Oil spill"
	
	// Drop all heat/cold wave events
	drop if cause == "inj_non_disaster"
	
	collapse (sum) numkilled l_disaster_rate u_disaster_rate, by(iso3 location_id year cause source nid) fast
	foreach var in l_disaster_rate u_disaster_rate {
		replace `var' = . if `var' == 0
		assert `var' < 1 if `var' != .
	}
	
	
	rename location_id lid
	merge m:1 iso3 using `locations', keepusing(location_id) assert(2 3) keep(3) nogen
	replace location_id = lid if lid != .
	drop lid
	
	// Quick data checks
	assert nid != .
	assert source != ""
	assert location_id != .
	assert iso3 != ""
	assert numkilled != .
	
	// Duplicates check. Can only have 1 source per location year cause
	duplicates tag iso3 location_id year cause, gen(dup)
	gen priority = 0
	// Create a tag if VR is among duplicates for a location-year-cause group
	gen is_vr = 1 if source == "VR"
	replace is_vr = 0 if source != "VR"
	bysort iso3 location_id year cause : egen vr = max(is_vr)
	
	// Keep shocks data if no duplicates
	replace priority = 1 if dup == 0 & source != "VR"
	// Keep non-duplicate shocks-only causes from VR
	replace priority = 1 if dup == 0 & source == "VR" & cause == "inj_disaster"
	// Keep certain sources regardless
	replace priority = 1 if dup > 0 & source == "Hajj Wiki"
	
	// Drop non-duplicate CoDem run causes from VR
	drop if priority == 0 & dup == 0 & source == "VR" & cause != "inj_disaster"
	
	// For ALL causes keep VR duplicates from all high quality VR countries (List provided by strName)
	// Generate high vs low quality VR indicator
	preserve
	import excel "high_quality_vr_countries.xlsx", clear firstrow
	levelsof ihme_loc_id, local(isos) clean
	restore
	gen vr_quality = 0
	foreach iso of local isos {
		replace vr_quality = 1 if iso3 == "`iso'"
	}
	
	// High Quality VR Countries: De-duplication varies by cause
		// inj_disaster: Use VR duplicate if deaths greater than shocks duplicate
		replace priority = 1 if vr_quality == 1 & source == "VR" & cause == "inj_disaster"
		
		// For CoDem run causes, find the difference between the VR duplicate and the average of the surrounding VR years. Use this difference as the shocks number
		//gen indic = 1 if cause != "inj_disaster" & dup > 0
		// Get list of location-cause-years with VR duplicates. Use this list to find shock difference in VR
			preserve
			keep if cause != "inj_disaster" & dup > 0 & vr_quality == 1
			keep if source != "VR"
			keep iso3 location_id year cause numkilled
			rename numkilled deaths_shocks
			collapse (sum) deaths_shocks,by(iso3 location_id year cause) fast
			isid iso3 location_id year cause
			drop if year == 2015
			tempfile dups
			save `dups', replace
			
			use "VR_shocks_disaster.dta", clear
			
				// Some issues with multiple VR sources for some of IND & PSE. Drop Vital Statistics India, use mean for PSE
				duplicates tag iso3 location_id year cause, gen(dup)
				drop if dup > 0 & nid == 32468
				bysort iso3 location_id year cause: egen mean = mean(numkilled)
				replace numkilled = mean if dup > 0 & iso3 == "PSE"
				duplicates drop iso3 location_id year cause, force
				drop dup
			
			merge 1:1 iso3 location_id year cause using `dups', keepusing(deaths_shocks) assert(1 3)
			gen shock = 1 if _m == 3
			replace shock = 0 if _m == 1
			drop _merge
			// Drop location-causes without any duplicates
				bysort location_id cause : egen no_shock = max(shock)
				drop if no_shock == 0
				drop no_shock
				sort iso3 location_id cause year
			// Gen shock difference for common case. T is shock year, and surrounding years are non-shock
				local vtype : type numkilled
				gen `vtype' shock_diff = numkilled - (numkilled[_n-1] + numkilled[_n+1]) / 2 if shock == 1
			// Tag end cases next. If t-1 or t+1 are from different location-cause group
				gen end_case = 0
				by iso3 location_id cause : replace end_case = 1 if ((location_id[_n-1] != location_id) | (cause[_n-1] != cause)) & shock == 1
				by iso3 location_id cause : replace end_case = 2 if ((location_id[_n+1] != location_id) | (cause[_n+1] != cause)) & shock == 1
				by iso3 location_id cause : replace end_case = 3 if ((location_id[_n-1] != location_id) | (cause[_n-1] != cause)) & ((location_id[_n+1] != location_id) | (cause[_n+1] != cause)) & shock == 3
			// Create vars for nearest non-shock year within location-cause group.
				egen group = group(iso3 location_id cause)
				bysort group : gen id = _n
				gen t_1 = 0
				gen t_2 = 0
				// First assume all adjacent years (as long as within group) are non-shock
				replace t_1 = id[_n-1] if group[_n-1] == group & shock == 1
				replace t_2 = id[_n+1] if group[_n+1] == group & shock == 1
				
			//For each group, we have ids for all observations. We also have shock indicator, thus we can compare a list of all ids and a list of ids that are shocks. For each shock id, find the next smallest and next largest non-shock id.
				levelsof group, local(groups)
				qui sum group
				local countdown = r(max)
				foreach g of local groups {
					quietly {
					n display `countdown'
					local --countdown
					levelsof id if group == `g' & shock == 1, local(shocks)
					foreach shock of local shocks {
						// Find next smallest non-shock id, replace t_1 = -1 if none
						sum id if group == `g' & id < `shock' & shock == 0
						if missing(r(max)) {
							replace t_1 = -1 if group == `g' & id == `shock' & shock == 1
						}
						else {
							replace t_1 = `r(max)' if group == `g' & id == `shock' & shock == 1
						}
						// Find next largest non-shock id, replace t_2 = -1 if none
						sum id if group == `g' & id > `shock' & shock == 0
						if missing(r(min)) {
							replace t_2 = -1 if group == `g' & id == `shock' & shock == 1
						}
						else {
							replace t_2 = `r(min)' if group == `g' & id == `shock' & shock == 1
						}
					}
					}
				}
			// Apply shock difference corrections
				qui sum group
				local countdown = r(max)
				foreach g of local groups {
					quietly {
					n display `countdown'
					local --countdown
					levelsof id if group == `g' & shock == 1, local(shocks)
					foreach shock of local shocks {
						levelsof t_1 if group == `g' & id == `shock', local(t_1)
						levelsof t_2 if group == `g' & id == `shock', local(t_2)
						
						// Case 1: There are two adjacent non-shock years
						if `t_1' != -1 & `t_2' != -1 {
							levelsof numkilled if group == `g' & id == `t_1', local(vrt_1)
							levelsof numkilled if group == `g' & id == `t_2', local(vrt_2)
							replace shock_diff = numkilled - (`vrt_1' + `vrt_2') / 2 if group == `g' & id == `shock'
						}
						// Case 2: There is only one adjacent non-shock year before, none after
						else if `t_1' != -1 & `t_2' == -1 {
							levelsof numkilled if group == `g' & id == `t_1', local(vrt_1)
							replace shock_diff = numkilled - `vrt_1' if group == `g' & id == `shock'							
						}
						// Case 3: There is only one adjacent non-shock year after, none before
						else if `t_1' == -1 & `t_2' != -1 {
							levelsof numkilled if group == `g' & id == `t_2', local(vrt_2)
							replace shock_diff = numkilled - `vrt_2' if group == `g' & id == `shock'
						}
						// Case 4: There are no adjacent non-shock years
						else if `t_a' == -1 & `t_2' == -1 {
							replace shock_diff = 0 if group == `g' & id == `shock'
						}
					}
					}
				}
			// Check end cases have been properly accounted for
				assert t_1 == -1 if end_case == 1
				assert t_2 == -1 if end_case == 2
			
			// Remove shocks with shock diff <= 0
				replace shock = -1 if shock_diff <= 0
				
			// Merge back with shocks data
				keep iso3 location_id year cause shock_diff shock source nid
				drop if shock == 0
				rename shock_diff numkilled
				
				tempfile shock_diff
				save `shock_diff', replace
			
			restore
			// First merge to drop original duplicates (more than 1 due to multiple sources)
			merge m:1 iso3 location_id year cause using `shock_diff', keep(1) assert(1 3) nogen
			// Second merge to add shock_diffs with correct source and nid
			merge m:1 iso3 location_id year cause using `shock_diff', assert(1 2) nogen
			drop if shock == -1
			replace vr_quality = 1 if shock == 1
			replace priority = 1 if shock == 1
			replace dup = 0 if shock == 1
			drop shock
			
		
	
	// Low Quality VR Countries: De-duplication varies by cause
		// inj_disaster low quality VR countries, use whatever source has higher death count
		local var_type : type numkilled	// Make sure var types are the same so scientific accuracy maintained
		bysort iso3 location_id year cause : egen `var_type' high_deaths = max(numkilled)
		replace priority = 1 if cause == "inj_disaster" & vr_quality == 0 & numkilled == high_deaths
		// check process
		assert priority == 0 if cause == "inj_disaster" & vr_quality == 0 & numkilled < high_deaths
	
		// For CoDem run causes just look at duplicates with VR and decide if any VR points need to be outliered. Drop VR and keep shocks numbers regardless.
		replace priority = 1 if dup > 0 & vr_quality == 0 & cause != "inj_disaster" & source != "VR"
		replace priority = 0 if dup > 0 & vr_quality == 0 & cause != "inj_disaster" & source == "VR"
		// Keep Hajj Wiki over other non-VR sources
		replace priority = 0 if dup > 0 & vr_quality == 0 & cause == "inj_mech_other" & source != "Hajj Wiki" & vr == 0
		// Find potential outliers: LQVR CoDem causes with more than 50 shocks deaths, with duplicate VR data points
		// Create the 50 death minimum threshold
		sort iso3 location_id year cause source
		local vtype : type numkilled
		bysort iso3 location_id year cause : egen `vtype' death_threshold = max(numkilled) if source != "VR"
		carryforward death_threshold, replace
		bysort iso3 location_id year cause : assert death_threshold == death_threshold[1]	// Check death_threshold is constant for each group
		
		** BROWSE TO SEE WHAT DUPLICATES TO OUTLIER
		** br if dup > 0 & death_threshold > 50 & vr_quality == 0 & cause != "inj_disaster" & vr == 1
		// Count number of points to check in CoDVis
			count if dup > 0 & death_threshold > 50 & vr_quality == 0 & cause != "inj_disaster" & source == "VR"
			// Export potential outlier list
			preserve
			keep if dup > 0 & death_threshold > 50 & vr_quality == 0 & cause != "inj_disaster" & vr == 1
			collapse (sum) numkilled, by(iso3 location_id year cause is_vr) fast
			
			reshape wide numkilled, i(iso3 location_id year cause) j(is_vr)
			
			rename numkilled0 deaths_shocks
			rename numkilled1 deaths_vr
			
			
			merge m:1 location_id using `location_names', keepusing(location_name) keep(3) assert(2 3) nogen
			
			sort cause iso3 year
			
			export excel using "outliers_`date'.xlsx", replace firstrow(var)
			
			restore
			
		
	
	
	drop if dup > 0 & priority == 0
	drop dup priority death_threshold high_deaths
	isid iso3 location_id year cause nid
	
	
	gen sex = "both"

	save "disaster_compiled_prioritized_`timestamp'", replace
	save "disaster_compiled_prioritized.dta", replace

