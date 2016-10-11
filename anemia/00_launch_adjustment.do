//Launch the anemia adjustment
	clear all
	set more off
	
	macro drop _all
	set maxvar 32000
// Set to run all selected code without pausing
	set more off
// Remove previous restores
	cap restore, not
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		local j "/home/j"
		set odbcmgr unixodbc
		local code "/ihme/code/general/strUser/malaria/anemia"
		local stata_shell "/ihme/code/general/strUser/malaria/stata.sh"
	}
	else if c(os) == "Windows" {
		local j "J:"
		local code "C:\Users\strUser\Documents\Code\malaria\COPD"
	}
	qui adopath + `j'/WORK/10_gbd/00_library/functions/
	
	local base_folder "/share/scratch/users/strUser/malaria_draws/anemia"
	local ver_desc = "v6"
	local folder_name = "`ver_desc'"
	local make_adjustment 1
	local save_results 1
	
	local test_clust -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors

	cap mkdir `base_folder'
	cap mkdir `base_folder'/`folder_name'

	//get the covariates and save it for reading in by the child jobs
	get_covariate_estimates, covariate_name_short(malaria_pfpr) clear
	save "`base_folder'/`folder_name'/pfpr.dta", replace
	
	//load the locations and paralleize by location
	get_location_metadata, location_set_id(9) clear
	levelsof location_id, local(thelocs)
	keep if is_estimate == 1
	//local thelocs 190 182 183
	//local -P proj_custom_models 
	local jnames
	foreach location_id of local thelocs{
		! qsub -N c_`location_id' -pe multi_slot 1 -P proj_custom_models -l mem_free=4G -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors "`stata_shell'" "`code'/01_adjust_pfpr_agepattern.do" "`location_id' `base_folder' `ver_desc'"
		local jnames d_`location_id' `jnames'
	}
	
	clear
	
	