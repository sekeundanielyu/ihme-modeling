// Purpose: Aggregate from granular Spectrum locations to aggregated locations (ex. Six Minor Territories in India)
// Launched from launch_subnat_split.do

** ***************************************************************************
** Set settings
// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
		local country = "`1'"
		local spec_dir = "`2'"
		di "`country'"
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local country = "IND_minor"
		local spec_dir = "strPath"
	}
	
	adopath + "strPath" // Grab fastcollapse

	if "`country'" == "IND_minor" local parent = "IND_44539"
	else local parent = "`country'"
	
** ***************************************************************************
** Set locals
// Get a list of all of the feeder "children" locations
	import delimited using "strPath/GBD_2015_countries.csv", varnames(1) clear
	keep if ihme_loc_id == "`parent'"
	gen child_loc_id = iso3 + "_" + subnat_id
	levelsof child_loc_id, local(children) c
	keep ihme_loc_id child_loc_id
	tempfile map
	save `map'
	

** ***************************************************************************
** Import all child data files
	cd "`spec_dir'"
	tempfile master
	save `master', emptyok
	foreach child in `children' {
		di "Importing `child'_ART_data"
		insheet using "`spec_dir'/stage_1/`child'_ART_data.csv", comma clear
		append using `master'
		save `master', replace
	}
	

** ***************************************************************************
** Aggregate from child data to parent
	fastcollapse *hiv* *births* *pop*, type(sum) by(run_num year sex age)

** ***************************************************************************
** Output
	outsheet using "`spec_dir'/stage_1/`country'_ART_data.csv", comma replace
		
			