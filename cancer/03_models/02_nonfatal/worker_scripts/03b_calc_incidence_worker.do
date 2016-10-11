// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Pull in results from CODEm/CoDCorrect by year for the cause/sex in question (runs the middle of the loop in 01_calculate_incidence)
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
	args acause local_id

// Input Data
	local mortality_file = "$mortality_folder/`acause'/death_draws_`local_id'.dta"
	
// Set folders
	local incidence_folder ="$incidence_folder"
	local output_folder "`incidence_folder'/`acause'"
	make_directory_tree, path("`output_folder'")
	
	
** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/total_incidence_`acause'"
	capture mkdir "`log_folder'"

// Start Logs	
	capture log close _all
	capture log using "`log_folder'/`local_id'.log", text replace

** ****************************************************************
** GET GBD RESOURCES 
** ****************************************************************
// Get causes
	use "$parameters_folder/causes.dta", clear
	keep if acause == "`acause'" & !inlist(mi_cause_name, "none", "")
	levelsof mi_cause_name if model == 1, clean local(mi_cause)
	levelsof sex if model == 1, clean local(sexes)
	tempfile causes
	save `causes', replace

// Get ihme_loc_id
	use "$parameters_folder/locations.dta", clear
	levelsof(ihme_loc_id) if location_id == `local_id', local(ihme_loc_id) clean
	if "`ihme_loc_id'" == "" {
		noisily di "Error: location_id `local_id' does not have an MI model"
		exit, clear
	}

// load summary functions
	run "$summary_functions"
 
** **************************************************************************
** Part 1: Open death draws and merge with MI draws
** **************************************************************************
// verify presence of mi draws
	local formatted_mi_data = "$formatted_mi_folder/`mi_cause'/formatted_mi_draws_`local_id'.dta"
	capture confirm file "`formatted_mi_data'"
	if _rc do "$format_mi_worker" `mi_cause' `local_id'

// open dataset
	capture confirm file "`mortality_file'"
	if _rc do "$mortality_worker" `acause' `local_id'
	use "`mortality_file'", clear
	capture rename local_id location_id

// Keep only what we need
	keep location_id year sex age acause death_*
	keep if location_id == `local_id' & age <= 80
			
// use only national MI ratios except for Hong Kong. Create a local to facilitate merge with national data 
	local merge_loc = substr("`ihme_loc_id'", 1, 3)
	if "`local_id'" == "354" local merge_loc = "`ihme_loc_id'" 

// Merge with MI ratios
	noisily display "Merging with MI ratios"
	gen ihme_loc_id = "`merge_loc'"
	replace acause = "`mi_cause'"		
	merge 1:1 ihme_loc_id year sex age acause using "`formatted_mi_data'", keep(1 3) assert(2 3)
	replace acause = "`acause'"
	keep location_id year sex age acause death_* mi_*

// Verify that there are no duplicates
	duplicates tag location_id year sex acause age, gen(tag)
	count if tag != 0
	if r(N) {
		di "duplicates"
		BREAK
	}
	drop tag

// Calculate incidence from deaths and MI ratio
	noisily display "Calculating incidence... "
	quietly forvalues i = 0/999 {
		// Generate incidence
		gen double incidence_`i' = death_`i' / mi_`i'
		drop death_`i' mi_`i'

	}

** **************************************************************************
** Part 2: Apply Restrictions, summarize, and save
** **************************************************************************
// Apply age-sex restricitons
	merge m:1 acause sex using `causes', keep(1 3) assert(2 3) keepusing(yld_age_start yld_age_end) nogen
	drop if age < yld_age_start | age > yld_age_end
	drop yld_age_*

// Rescale leukemia subcauses
	if inlist("`acause'", "neo_leukemia_ll_acute", "neo_leukemia_ll_chronic", "neo_leukemia_ml_acute", "neo_leukemia_ml_chronic") {
		// Save what we have so far
			keep location_id year sex age acause incidence_*
			save "`output_folder'/incidence_initial_`local_id'.dta", replace
		// Append in all subcause files
		clear
		foreach leukemia_subcause in "neo_leukemia_ll_acute" "neo_leukemia_ll_chronic" "neo_leukemia_ml_acute" "neo_leukemia_ml_chronic" {
			local input_file = "`incidence_folder'/`leukemia_subcause'/incidence_initial_`local_id'.dta"
			noisily di "Searching for `input_file'"
			capture confirm file "`input_file'"
			while _rc {
				sleep 30000
				capture confirm file "`input_file'"
			}
			noisily di "Found! Appending `input_file'"
			sleep 15000
			append using  "`input_file'"
		}
		// Generate percentages
		noisily di "Calculating subcause proportion..."
		foreach i of numlist 0/999 {
			noisily di "draw `i'"
			egen double prop_`i' = pc(incidence_`i'), by(location_id year sex age) prop
		}
		drop incidence_*
		// Drop other leukemia subcauses
		keep if acause == "`acause'"
		drop acause
		// Merge with leukemia parent
		local leukemia_parent_file = "`incidence_folder'/neo_leukemia/incidence_draws_`local_id'.dta"
		noisily di "Waiting for `leukemia_parent_file'"
		capture confirm file "`leukemia_parent_file'"
		while _rc {
			sleep 30000
			capture confirm file "`leukemia_parent_file'"
		}
		noisily di "Found! Merging on `leukemia_parent_file'"
		sleep 15000
		merge 1:1 location_id year sex age using "`leukemia_parent_file'", keep(1 3) assert(2 3) nogen
		replace acause = "`acause'"
		// Multiply by proportion
		noisily di "Recalculating incidence..."
		foreach i of numlist 0/999 {
			noisily di "draw `i'"
			replace incidence_`i' = incidence_`i' * prop_`i'
		}
		drop prop_*
	}

// Generate all-ages data
	all_age, relevant_vars("location_id year sex age acause") data_var("incidence_")

// Generate Age-Standardized Rate
	asr, relevant_vars("location_id year sex age acause") data_var("incidence_")

// Verify that there are no duplicates
	duplicates tag location_id year sex acause age, gen(tag)
	count if tag != 0
	if r(N) {
		di "duplicates"
		BREAK
	}
	drop tag

// Reformat and save draw-level data
	keep location_id year sex age acause incidence_*
	order location_id year sex age acause incidence_*
	sort location_id year sex age
	compress
	save "`output_folder'/incidence_draws_`local_id'.dta", replace

// Calculate summary statistics
	calculate_summary_statistics, data_var("incidence")

// Reformat
	keep location_id year sex age acause mean_incidence lower_incidence upper_incidence
	order location_id year sex age acause mean_incidence lower_incidence upper_incidence
	sort location_id year sex age

// Save summary
	compress
	save "`output_folder'/incidence_summary_`local_id'.dta", replace

capture log close

** *******
** END
** *******
