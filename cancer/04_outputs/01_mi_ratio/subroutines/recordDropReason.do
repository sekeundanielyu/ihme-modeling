** *************************************************************************
// Purpose: saves a list of the data dropped by the script that calls it
** *************************************************************************

// accept arguments
	args section directory dropped_list today

// check for problems
	if "`today'" == "" BREAK
	
// set locals/globals
	if "$dropped_list" == "" global dropped_list = "`dropped_list'"
	local drop_folder = substr("$dropped_list", 1, length("$dropped_list") - strpos(reverse("$dropped_list"), "/"))
	global archive_dropped = "`drop_folder'/_archive/Dropped_data_$today.dta"

// save all data in memory
	tempfile tempKeepBest
	save `tempKeepBest', replace
	
// keep only the data that will be dropped
	drop if toDrop == 0
	capture confirm variable groupid
	if _rc != 0 keep iso3 source subdiv registry year year_span uid gbd_iteration national dropReason
	else keep iso3 source subdiv registry year year_span uid groupid gbd_iteration national dropReason
	
	duplicates drop
	// create list and save
	gen section = "`section'"
	capture confirm file "$dropped_list"
	if _rc {
		save "$dropped_list", replace
		save "$archive_dropped", replace
	}
	else {
		append using "$dropped_list"
		save "$dropped_list", replace
		save "$archive_dropped", replace
	}
		
// restore all data
	use `tempKeepBest', clear


** *************************************************************************
