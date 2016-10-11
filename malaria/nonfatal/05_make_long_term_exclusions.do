//Master Script for Updated Malaria long term Exclusions
//About: takes a dismod model, applies malaria exclusions and resaves in a different me id
//prepare stata
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
		local prefix "/home/j"
		set odbcmgr unixodbc
	}
	else{
		local prefix J:/
	}
	adopath + `prefix'/WORK/10_gbd/00_library/functions/
	
	//set locals
	local code "/ihme/code/general/strUser/malaria/nonfatal"
	local stata_shell "/ihme/code/general/strUser/malaria/stata.sh"
	local stata_mp_shell  "/ihme/code/epi/strUser/nonfatal/stata_shell.sh"
	local output "/share/scratch/users/strUser/malaria_longterm/"
	
	local main_model_version v53
	
	local ver_desc = "`main_model_version'"
	local folder_name = "`ver_desc'"
	local generate_files 0
	
	//make directories
	cap mkdir "`output'"
	cap mkdir "`output'`ver_desc'"
	
	
	//report outputs 
	local test_clust -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors

	
	//Zero out exclusions
	if `generate_files' == 1{
		
		get_demographics, gbd_team(epi) clear
		//launch the jobs
		local jobs
		foreach location_id of global location_ids {
			! qsub -N ltm_`location_id' -pe multi_slot 1 -P proj_custom_models -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors "`stata_shell'" "`code'/05a_longterm_excl_tocsv.do" "`location_id' `output' `ver_desc'"
			local jobs `jobs' ltm_`location_id'
			
		}
			//di `jobs'
			! qsub -N saver_ltm -hold_jid "`jobs'" -pe multi_slot 8 -P proj_custom_models -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors "`stata_mp_shell'" "`code'/05b_longterm_saveresults.do" "`output' `ver_desc'"
	}
	else{
	
		do "`code'/05b_longterm_saveresults.do" "`output'" "`ver_desc'"
	}
	clear
	
	