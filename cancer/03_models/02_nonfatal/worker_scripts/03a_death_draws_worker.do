// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Pull in results from CODEm/CoDCorrect by year for the cause & sex in question

** **************************************************************************
** Configuration
** 		
** **************************************************************************
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"

// Set STATA workspace 
	set more off
	capture set maxvar 32000
	
// Set common directories, functions, and globals (shell, finalize_worker, finalization_folder...)
	run "$j/WORK/07_registry/cancer/03_models/02_yld_estimation/01_code/subroutines/set_paths.do"

** ****************************************************************
** SET MACROS FOR CODE
** ****************************************************************
// Accept or default arguments
	args CoD_model local_id

// Set and ensure presence of output directory
	local output_folder =  "$mortality_folder/`CoD_model'"
	capture make_directory_tree, path("`output_folder'")

** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/death_draws_`CoD_model'"
	capture mkdir "`log_folder'"

// Start Logs	
	capture log using "`log_folder'/`local_id'.log", text replace

** ****************************************************************
** GET RESOURCES
** ****************************************************************
// CoDCorrect version and years
	use "$parameters_folder/constants.dta", clear
	local max_year = max_year[1]
	local min_year = min_year[1]
	local codcorrect_version = codcorrect_version[1] 

// Define location of CoDcorrect 04_outputs
	local death_draws_location = "[filepath]/codcorrect/`codcorrect_version'/draws"

// Get causes
	use "$parameters_folder/causes.dta", clear
	keep if acause == "`CoD_model'"
	levelsof(cause_id), clean local(cause_id)
	keep cause_id acause
	duplicates drop
	tempfile causes
	save `causes', replace

// load summary functions
	run "$summary_functions"

** **************************************************************************
** Get codCorrect draws, Reformat, Summarize, and Save
** **************************************************************************
// Get death draws from CoDCorrect
	clear
	gen year = .
	tempfile master_data
	save `master_data', replace
	quietly forvalues year = `min_year'/`max_year' {
		// Check for draws file
			local death_draws_file = "`death_draws_location'/death_`local_id'_`year'.dta"
			capture confirm file "`death_draws_file'"
			if _rc continue

		// if file exists, load it
			use "`death_draws_file'", clear
			noisily display "Appending `death_draws_file'..."
		
		// Keep only relevant data
			keep if cause_id == `cause_id'
		
		// rename columns and add acause
			rename (year_id sex_id age_group_id) (year sex age)	
			merge m:1 cause_id using `causes', keep(1 3) assert(2 3) nogen
		
		// Append data
			append using `master_data'
		
		// Save
			tempfile master_data
			save `master_data', replace	
	}

// Keep only relevant information
	keep location_id year sex age acause draw_*

// Reformat age
	replace age = 0 if age == 2
	replace age = .01 if age == 3
	replace age = .1 if age == 4
	replace age = 1 if age == 5
	replace age = (age -5)*5 if age > 5

// Reformat death draws
	noisily display "Reformating..."
	quietly forvalues i = 0/999 {
		rename draw_`i' death_`i'
	}
	
// Generate all-ages data
	all_age, relevant_vars("location_id year sex age acause") data_var("death_")

// Generate Age-Standardized Rate
	asr, relevant_vars("location_id year sex age acause") data_var("death_")

// Keep only relevant information
	keep location_id year sex age acause death_*
	order location_id year sex age acause death_*
	sort location_id year sex age

// Save draws
	compress
	save "`output_folder'/death_draws_`local_id'.dta", replace

capture log close


** *******
** END
** *******
