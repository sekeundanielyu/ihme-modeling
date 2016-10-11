
// Purpose:		Download epi-modeled liver cancer data by subcause

** *************************************************************************************************************
** Get Splits
** *************************************************************************************************************
// Clear memory and set memory and variable limits
	clear 
	set maxvar 32000

// Set to run all selected code without pausing
	set more off
// accept arguments and set ouput folder 
	args output_folder
	if "`output_folder'" == "" local output_folder "/ihme/gbd/WORK/07_registry/cancer/03_models/02_yld_estimation/liver_splits"
	capture mkdir "`output_folder'"

// get additional resources
	do "/home/j/WORK/10_gbd/00_library/functions/split_cod_model.ado"
	do "/home/j/WORK/10_gbd/00_library/functions/save_results.do"

// split liver cancer
	split_cod_model, source_cause_id(417) target_cause_ids(418 419 420 421) target_meids(2470 2471 2472 2473) output_dir("`output_folder'")

// save results
	
		save_results, cause_id(418) description(Liver cancer due to hepatitis B) in_dir("/ihme/gbd/WORK/07_registry/cancer/03_models/02_yld_estimation/liver_splits/418")
		save_results, cause_id(419) description(Liver cancer due to hepatitis C) in_dir("/ihme/gbd/WORK/07_registry/cancer/03_models/02_yld_estimation/liver_splits/419")
		save_results, cause_id(420) description(Liver cancer due to alcohol) in_dir("/ihme/gbd/WORK/07_registry/cancer/03_models/02_yld_estimation/liver_splits/420")
		save_results, cause_id(421) description(Liver cancer due to other causes) in_dir("/ihme/gbd/WORK/07_registry/cancer/03_models/02_yld_estimation/liver_splits/421")
	

** ******
** END
** ******
