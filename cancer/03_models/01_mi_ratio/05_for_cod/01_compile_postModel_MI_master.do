
// Function:	Compiles MI Model result (MI_model_result) of all cause-models entered in the model selection document

** **************************************************************************
** Configuration
** 		Sets application preferences (memory allocation, variable limits) 
** 		Accepts/Sets Arguments. Defines the J drive location.
** **************************************************************************
// Set to run all selected code without pausing
	clear all
	set more off
	
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" 	global j "/home/j"
	else if c(os) == "Windows" global j "J:"
	
// Define Folder to check for data
	local input_directory = "/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/03_st_gpr"
	local temp_folder = "/ihme/gbd/WORK/07_registry/cancer/04_outputs/01_mortality_incidence/model_outputs"
	local output_directory = "$j/WORK/07_registry/cancer/04_outputs/01_mortality_incidence/data/intermediate"
	local output_file = "compiled_cause_output.csv"
	capture mkdir "`temp_folder'"

// Define filepath for MI output formatting script	
	local script = "$j/WORK/07_registry/cancer/04_outputs/01_mortality_incidence/code/01_compile_postModel_MI_worker.do"
	local shell = "$j/WORK/07_registry/cancer/00_common/code/shellstata13.sh"
	
** ****************************************************************
** Create log if running on the cluster
** ****************************************************************
// Log folder
	local log_folder "/ihme/gbd/WORK/07_registry/cancer/logs/04_database/01_mortality_incidence"
	cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs"
	cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs/04_database"
	cap mkdir "`log_folder'"
	
// Begin Log
	capture log close cMI
	log using "`log_folder'/01_cpMM.log", replace name(cMI)

** *************************************************************************	
** COMPILE DATA (Autorun)
** *************************************************************************	

// Get date
	local today = date(c(current_date), "DMY")
	local today = string(year(`today')) + "_" + string(month(`today'),"%02.0f") + "_" + string(day(`today'),"%02.0f")
	
// Determine which model numbers to use
	local model_selection =  "$j/WORK/07_registry/cancer/03_models/01_mi_ratio/03_results/06_model_selection/model_selection.csv"
	import delimited "`model_selection'", clear

// create alphabetical list of causes
	levelsof acause, clean local(cause_list)
	local cause_list: list sort cause_list

// save 	
	tempfile best_models
	save `best_models', replace

// remove old output
	capture rm "`output_directory'/01_MI_model_results.dta"
	
// submit format script for each cause
	foreach cause in `cause_list' { 
		use `best_models', clear
		// determine model number
		levelsof best_model if acause == "`cause'", clean local(modnum) 

		// determine sex(es)
		levelsof sex if acause == "`cause'", clean local(sex_input)
		if "`sex_input'" == "both" local sex_input = "female male"
		
		// remove previous outputs and 
		foreach s in `sex_input'{
			
				// break if file does not exist
					capture confirm file "`input_directory'/model_`modnum'/`cause'/`s'/`output_file'"
					if _rc {
						di "ERROR. `cause' `s' model `modnum' not found in `input_directory'/model_`modnum'."
						BREAK
					}
					else di "`cause' `s' model `modnum' found"
					
				// remove old file
					capture rm "`temp_folder'/model_`modnum'_`cause'_`s'_MI_model_output.dta"
					capture confirm file "`temp_folder'/model_`modnum'_`cause'_`s'_MI_model_output.dta"
					if !_rc {
						di "Error removing old file for `cause' `s' model `modnum'"
						BREAK
					}
					
				// submit format script
				if c(os) == "Windows"  {
					noisily di in red "Running format..."
					do "`script'" `cause' `s' `modnum' `input_directory' `temp_folder'
				} 
				if c(os) == "Unix" {
					!/usr/local/bin/SGE/bin/lx-amd64/qsub -P proj_cancer_prep -pe multi_slot 6 -l mem_free=12g -N "MIrslt_`cause'" "`shell'" "`script'" "`cause' `s' `modnum' `input_directory' `temp_folder' `output_file'"
				}
		}		
	}

// get results
	clear
	local first_iteration = 1
	foreach cause in `cause_list' {
		use `best_models', clear
		// determine model number
		levelsof best_model if acause == "`cause'", clean local(modnum) 
		
		// determine sex(es)
		levelsof sex if acause == "`cause'", clean local(sex_input)
		if "`sex_input'" == "both" local sex_input = "female male"
		
		foreach s in `sex_input'{
			// wait until file is found
				local attempts = 0
				capture confirm file "`temp_folder'/model_`modnum'_`cause'_`s'_MI_model_output.dta"
				while _rc {
					di "Waiting for `modnum'_`cause'_`s' to finish formatting. Checking again in 30 seconds..."
					sleep 30000
					local attempts = `attempts' + 1
					if `attempts' == 5 {
						preserve
							do "$j/WORK/07_registry/cancer/04_outputs/01_mortality_incidence/code/01_compile_postModel_MI_worker.do" `cause' `s' `modnum'
						restore
					}
					capture confirm file "`temp_folder'/model_`modnum'_`cause'_`s'_MI_model_output.dta"
				}
			
			// Add file
				di " Adding `modnum'_`cause'_`s'_MI_model_output..."
				if `first_iteration' == 1 {
					use "`temp_folder'/model_`modnum'_`cause'_`s'_MI_model_output.dta", clear
					tempfile outputs
					save `outputs', replace
					local first_iteration = 0
				}
				else {
					use `outputs', clear
					append using "`temp_folder'/model_`modnum'_`cause'_`s'_MI_model_output.dta", force
					save `outputs', replace
				}
			
		}
	}
	
// Edit Formatting for specific variables	
	use `outputs', clear
	save "`temp_folder'/temp_MI_model_outputs.dta", replace
	
// Remove Labels
	foreach var of varlist _all {
		capture _strip_labels `var' 
	}

// Reshape and save	
	drop if age == .
	keep MI_model_result_* acause ihme_loc_id year sex acause age modnum
	reshape wide MI_model_result_, i(ihme_loc_id year acause sex) j(age)
	saveold "`output_directory'/01_MI_model_results.dta", replace
	saveold "`output_directory'/_archive/01_MI_model_results_`today'.dta", replace
	saveold "`temp_folder'/01_MI_model_results_`today'.dta", replace

** ******
** END
** ******
