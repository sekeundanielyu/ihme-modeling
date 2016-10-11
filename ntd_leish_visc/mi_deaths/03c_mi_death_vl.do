// **********************************************************************
// Purpose:		This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global
// Description:	Calculate mortality rate from incidence for DisMod years, and interpolate for non-DisMod years 
// Location: /home/j/WORK/04_epi/01_database/02_data/ntd_leish/1458_1459_1460_1461/04_models/gbd2015/01_code/dev/03c_mi_death_vl.do

// **********************************************************************
// LOAD SETTINGS FROM MASTER CODE (NO NEED TO EDIT THIS SECTION)

	// prep stata
	clear all
	set more off
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	if "`1'" != "" {
		// base directory on J 
		local root_j_dir `1'
		// base directory on share
		local root_tmp_dir `2'
		// timestamp of current run (i.e. 2014_01_17)
		local date `3'
		// step number of this step (i.e. 01a)
		local step_num `4'
		// name of current step (i.e. first_step_name)
		local step_name `5'
		// step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
		local hold_steps `6'
		// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
		local last_steps `7'
		// directory where the code lives
		local code_dir `8'
	}
	else if "`1'" == "" {
		// base directory on J 
		local root_j_dir "$prefix/WORK/04_epi/01_database/02_data/ntd_leish/1458_1459_1460_1461/04_models/gbd2015"
		// base directory on share
		local root_tmp_dir "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_leish/1458_1459_1460_1461/04_models/gbd2015"
		// timestamp of current run (i.e. 2014_01_17)
		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
		local date = subinstr("`date'"," ","_",.)
		// step number of this step (i.e. 01a)
		local step_num "03c"
		// name of current step (i.e. first_step_name)
		local step_name "mi_death_vl"
		// step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
		local hold_steps ""
		// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
		local last_steps ""
		// directory where the code lives
		local code_dir "$prefix/WORK/04_epi/01_database/02_data/ntd_leish/1458_1459_1460_1461/04_models/gbd2015/01_code/dev"
	}
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	
	// write log if running in parallel and log is not already open
	cap log using "`out_dir'/02_temp/02_logs/`step_num'.smcl", replace
	if !_rc local close_log 1
	else local close_log 0
	
	// check for finished.txt produced by previous step
	if "`hold_steps'" != "" {
		foreach step of local hold_steps {
			local dir: dir "`root_j_dir'/03_steps/`date'" dirs "`step'_*", respectcase
			// remove extra quotation marks
			local dir = subinstr(`"`dir'"',`"""',"",.)
			capture confirm file "`root_j_dir'/03_steps/`date'/`dir'/finished.txt"
			if _rc {
				di "`dir' failed"
				BREAK
			}
		}
	}	

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
 // Import functions
	run "$prefix/WORK/10_gbd/00_library/functions/get_demographics.ado"
    run "$prefix/WORK/10_gbd/00_library/functions/get_covariate_estimates.ado"
    run "$prefix/WORK/10_gbd/00_library/functions/get_best_model_versions.ado"
	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
	run "$prefix/WORK/04_epi/01_database/02_data/ntd_leish/1458_1459_1460_1461/04_models/gbd2015/01_code/prod/interpolate.ado"
	do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
	
 // Set directory for saving best model
	local root_tmp_dir "/ihme/gbd/WORK/04_epi/02_models/02_results/ntd_leish_visc/1458/04_models/gbd2015"
	capture mkdir "`root_tmp_dir'/03_steps/"
	capture mkdir "`root_tmp_dir'/03_steps/`date'"
	capture mkdir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	capture mkdir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'/03_outputs"
	capture mkdir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'/03_outputs/01_dismod_year_draws"
	local save_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'/03_outputs/01_dismod_year_draws"
	capture mkdir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'/03_outputs/01_draws"
	local save_dir_cod "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'/03_outputs/01_draws"
    local tmp_in_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'/02_inputs"
	capture mkdir "`tmp_in_dir'"
	capture mkdir "`tmp_in_dir'/mi_ratios"
	
// Split up all draws of overall prevalence of sequelae into age/sex-specific estimates
	// Store model numbers as locals
	get_best_model_versions, gbd_team(epi) id_list(1458) clear
	local epi_model = model_version_id
	
	// Get demographics
	  get_demographics , gbd_team(cod) clear
	  
	// Get populations
	  get_populations , year_id($year_ids) location_id($location_ids) sex_id($sex_ids) age_group_id($age_group_ids) clear
	  save "`tmp_in_dir'/pops.dta", replace
	
  // Pull covariate for endemicity
    get_covariate_estimates, covariate_id(211) clear
	replace mean_value = 1 if mean_value >= 1
	replace mean_value = 0 if mean_value < 1
    duplicates drop location_id location_name, force
    rename mean_value leish_presence
    keep location_id leish_presence
	save "`tmp_in_dir'/leish_presence.dta", replace
  
  ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** **
  ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** **
  ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** **
  // MI RATIO PREP
  ** Get age groups
	create_connection_string
	local conn_string = r(conn_string)
	odbc load, exec ("SELECT age_group_id, age_group_years_start AS age FROM shared.age_group WHERE age_group_id BETWEEN 5 AND 21") `conn_string' clear
	tempfile age_groups
	save `age_groups', replace
	
  ** Get location parents
  get_location_metadata, location_set_id(35) clear
  tempfile lmd
  save `lmd', replace
  
  ** Organize previously saved draws of MI-ratio by country year sex
  local mi_folder "$prefix/WORK/04_epi/01_database/02_data/ntd_leish/archive_2013/04_models/gbd2013/02_inputs"
  use "`mi_folder'/mi_ratio_draws_2014_04_18.dta" if age <= 80, clear
  merge m:1 age using `age_groups', assert(1 3)
  expand 3 if age == 0, gen(exp)
  replace age_group_id = 0 if age_group_id == .
  bysort location_id year sex (age): replace age_group_id = _n+1
  count if age_group_id == 0
  assert `r(N)' == 0
  rename sex sex_id
  rename year year_id
  replace year_id = 2015 if year_id == 2013
  keep location_id year_id age_group_id sex_id mi*
  order location_id year_id age_group_id sex_id mi*
  sort location_id year_id age_group_id sex_id mi*
  tempfile drawfile
  save `drawfile', replace
    
  ** Save by location submit jobs
  foreach location_id of global location_ids {
    ** TEMPORARY: take parent for subnationals not present
    display in red "`location_id'"
    use `drawfile' if location_id == `location_id', clear

	** Save
	save "`tmp_in_dir'/mi_ratios/mi_ratio_`location_id'.dta", replace  

	** Submit
	!qsub -N "VL_custom_model_03c_lid_`location_id'" -P proj_custom_models -pe multi_slot 2 -l mem_free=4g "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh" "`code_dir'/`step_num'_`step_name'_parallel.do" "`location_id' `tmp_in_dir' `save_dir' `epi_model'"
  }
  ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** **
  ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** **
  ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** **
   
// Wait for results (check for the last file saved)
    foreach location_id of global location_ids {
		capture confirm file "`save_dir'/death_`location_id'_2015_2.csv"
		if _rc == 601 noisily display "Searching for `location_id' -- `c(current_time)'"
		while _rc == 601 {
			capture confirm file "`save_dir'/death_`location_id'_2015_2.csv"
			sleep 1000
		}
		if _rc == 0 {
			noisily display "`location_id' FOUND!"
		}
    }

// **********************************************************************
// Interpolate draws for non-dismod years  
 
  // Manual job submission for interpolation of small subset of countries that will fail (subnbecause the list of country names is pulled from the epi database
    interpolate_dismod, in_dir("`save_dir'") out_dir("`save_dir_cod'") measure_id(death)
  
    foreach location_id of global location_ids {
		capture confirm file "`save_dir_cod'/interpolated/death_`location_id'_2015_2.csv"
		if _rc == 601 noisily display "Searching for `location_id' -- `c(current_time)'"
		while _rc == 601 {
			capture confirm file "`save_dir_cod'/interpolated/death_`location_id'_2015_2.csv"
			sleep 1000
		}
		if _rc == 0 {
			noisily display "`location_id' FOUND!"
		}
    }
	
  save_results, cause_id(348) description("VL custom MI-ratio model*incidence from epi model `epi_model'. MI-ratio: glm binomial, covariates age sex log_ldi [GBD 2013 ratio]. Non-endemic countries: zero. Extrapolation to 1980.") in_dir("`save_dir_cod'/interpolated") move("yes")
    
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// CHECK FILES (NO NEED TO EDIT THIS SECTION)

	// write check file to indicate step has finished
		file open finished using "`out_dir'/finished.txt", replace write
		file close finished
		
	// if step is last step, write finished.txt file
		local i_last_step 0
		foreach i of local last_steps {
			if "`i'" == "`this_step'" local i_last_step 1
		}
		
		// only write this file if this is one of the last steps
		if `i_last_step' {
		
			// account for the fact that last steps may be parallel and don't want to write file before all steps are done
			local num_last_steps = wordcount("`last_steps'")
			
			// if only one last step
			local write_file 1
			
			// if parallel last steps
			if `num_last_steps' > 1 {
				foreach i of local last_steps {
					local dir: dir "`root_j_dir'/03_steps/`date'" dirs "`i'_*", respectcase
					local dir = subinstr(`"`dir'"',`"""',"",.)
					cap confirm file "`root_j_dir'/03_steps/`date'/`dir'/finished.txt"
					if _rc local write_file 0
				}
			}
			
			// write file if all steps finished
			if `write_file' {
				file open all_finished using "`root_j_dir'/03_steps/`date'/finished.txt", replace write
				file close all_finished
			}
		}
		
	// close log if open
		if `close_log' log close
	
	

	