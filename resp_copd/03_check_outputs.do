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
	
	args output folder_name

	di "`output' `folder_name'"
	
	//me_ids for folder creation
	local asympt 3065
	local mild 1873
	local moderate 1874
	local severe 1875
	local years 1990 1995 2000 2005 2010 2015
	local types asympt mild moderate severe

	get_best_model_versions, gbd_team(epi) id_list(1872 3062 3063 3064) clear
	levelsof model_version_id, local(best_model) clean
	
	qui do /home/j/WORK/10_gbd/00_library/functions/save_results.do
	foreach ttt of local types{
		di "SAVING RESULTS"
		save_results, modelable_entity_id(``ttt'') description(`ttt' COPD model `best_model' ) in_dir("`output'`folder_name'/``ttt''/") metrics(prevalence incidence) mark_best(yes)

	}
	