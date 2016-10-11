	
** **************************************************************************
** PREP STATA
** **************************************************************************
	
	// prep stata
	clear all
	set more off
	set maxvar 32000

	// Set OS flexibility 
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
		local h "~"
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local h "H:"
	}
	sysdir set PLUS "`h'/ado/plus"

	//interpolate rates
	args code_folder save_folder loc
	
	local location_id loc
	di "`code_folder' `save_folder' `loc' `location_id'"
	
	// interpolate dismod csmr for all years
	!python `code_folder'/interp_loc_ls_update.py --modelable_entity_id 9366 --measure_id 15 --location_id `loc' --outpath "`save_folder'interp_`loc'.csv"
	
	import delim using "`save_folder'interp_`loc'.csv", clear
	
	//drop if !inrange(age_group_id,2,21)
	capture drop v1 measure_id modelable_entity_id model_version_id
	forvalues j=0/999 {
		quietly replace draw_`j' = 0 if age_group_id < 11 
	}

	cap gen cause_id = 500
	export delim using "`save_folder'interp_`loc'.csv", replace
