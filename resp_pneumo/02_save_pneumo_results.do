//A checker to make sure all of the jobs finished

//prepare stata
	clear
	set more off
	
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		local prefix "/home/j"
		set odbcmgr unixodbc
		local code "/ihme/code/epi/strUser/nonfatal/COPD"
		local stata_shell "/ihme/code/epi/strUser/nonfatal/stata_shell.sh"
	}
	else if c(os) == "Windows" {
		local prefix "J:"
		local code "C:\Users\strUser\Documents\Code\nonfatal\COPD"
	}
	adopath+ "`prefix'/WORK/10_gbd/00_library/functions/"
	
	args output ver_desc me meid orig_meid
	di "Output: `output'"
	di "Version: `ver_desc'"
	di "Modelable Entity: `me'"
	di "Target ME: `meid'"
	di "Starting ME: `orig_meid'"

	get_best_model_versions, gbd_team(epi) id_list(`orig_meid') clear
	levelsof model_version_id, local(best_model) clean	
	
	qui do /home/j/WORK/10_gbd/00_library/functions/save_results.do
	
	di "SAVING RESULTS"
	di "`meid' `best_model' `output'`ver_desc'/`meid'/"
	save_results, modelable_entity_id(`meid') description("Pneumo model `best_model' with proper zeros" ) in_dir("`output'`ver_desc'/`meid'/") metrics(prevalence incidence) mark_best(yes)
	
	

	