	
** **************************************************************************
** PREP STATA
** **************************************************************************
	
	// prep stata
	clear all
	set more off

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
	
	run "`j'/WORK/10_gbd/00_library/functions/get_demographics.ado"

** **************************************************************************
** RUN PARALLEL PROCESSES
** **************************************************************************
	//set locals
	local code_folder /ihme/code/epi/strUser/nonfatal/neuro
	local save_folder /share/scratch/users/strUser/dementia_2/
	
	cap mkdir `save_folder'
	
	// get locations we want to run
	get_demographics, gbd_team(cod)
	local location_ids = r(location_ids)
	
	// submit by locations
	
	foreach loc of local location_ids {
		!qsub -N "dementia_`loc'" -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors -l mem_free=8 -pe multi_slot 4 -P "proj_custom_models" "`j'/WORK/10_gbd/00_library/functions/utils/stata_shell.sh" "`code_folder'/calc_dementia_deaths.do" "`code_folder' `save_folder' `loc'"
	}
