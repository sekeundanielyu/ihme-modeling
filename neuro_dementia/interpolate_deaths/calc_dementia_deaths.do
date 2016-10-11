	
** **************************************************************************
** PREP STATA
** **************************************************************************
	
	// prep stata
	clear all
	set more off
	set maxvar 32000

	// Set OS flexibility 
	if c(os) == "Unix" {
		local j "/home/j"
		set odbcmgr unixodbc
		local h "~"
	}
	else if c(os) == "Windows" {
		local j "J:"
		local h "H:"
	}
	sysdir set PLUS "`h'/ado/plus"

	//interpolate rates
	args code_folder save_folder loc
	
	local location_id loc
	di "`code_folder' `save_folder' `loc' `location_id'"
	
	// interpolate dismod dementia prevalence for all years
	!/ihme/code/central_comp/anaconda/envs/tasker/bin/python `code_folder'/interp_loc.py --modelable_entity_id 1943 --measure_id 15 --location_id `loc' --outpath "`save_folder'interp_`loc'.csv"
	
	import delim using "`save_folder'interp_`loc'.csv", clear
	
	drop if !inrange(age_group_id,2,21)
	forvalues j=0/999 {
		quietly replace draw_`j' = 0 if age_group_id<13 //under 40 don't die of dementia
	}

	cap gen cause_id = 543
	export delim using "`save_folder'interp_`loc'.csv", replace

	