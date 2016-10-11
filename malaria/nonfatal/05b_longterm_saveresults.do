//A checker to make sure all of the jobs finished

//prepare stata
	clear
	set more off
	
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		local prefix "/home/j"
		set odbcmgr unixodbc
		local code "/ihme/code/epi/dccasey/nonfatal/COPD"
		local stata_shell "/ihme/code/epi/dccasey/nonfatal/stata_shell.sh"
	}
	else if c(os) == "Windows" {
		local prefix "J:"
		local code "C:\Users\dccasey\Documents\Code\nonfatal\COPD"
	}
	adopath+ "`prefix'/WORK/10_gbd/00_library/functions/"
	
	args output ver_desc
	di "Output: `output'"
	di "Version: `ver_desc'"

	local orig_meid 1446
	
	get_best_model_versions, gbd_team(epi) id_list(`orig_meid') clear
	levelsof model_version_id, local(best_model) clean	
	
	qui do /home/j/WORK/10_gbd/00_library/functions/save_results.do
	
	di "SAVING RESULTS"
	di "`best_model' `output'`ver_desc'"
	save_results, modelable_entity_id(9795) description("Long term malaria with exclusions from version `ver_desc' and `best_model'" ) in_dir("`output'`ver_desc'/") metrics(prevalence incidence) mark_best(yes)
	
	

	