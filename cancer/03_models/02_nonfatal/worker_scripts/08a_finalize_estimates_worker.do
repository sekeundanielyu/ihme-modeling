// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Reformats final incidence and prevalence estimates, then convert to rate space (#events/population) for upload into Epi

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
	
// Set common directories, functions, and globals ()
	run "$j/WORK/07_registry/cancer/03_models/02_yld_estimation/01_code/subroutines/set_paths.do"

** ****************************************************************
** Accept Arguments 
** ****************************************************************
	args acause local_id

** ****************************************************************
** 
** ****************************************************************
// output folder 
	local output_folder = "$finalize_estimates_folder/`acause'"

// Set data types to finalize
	local types = "prevalence incidence"  

** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/finalize_`acause'"
	capture mkdir "`log_folder'"

// Start Logs	
	capture log using "`log_folder'/finalize_`acause'_`local_id'.txt", text replace

** ****************************************************************
** GET RESOURCES
** ****************************************************************
// get list of modelable entity ids
	use "$parameters_folder/modelable_entity_ids.dta", clear
	keep if inlist(stage, "primary", "in_remission", "disseminated", "terminal")
	levelsof modelable_entity_id if acause == "`acause'", clean local(me_ids)
	tempfile m_ids
	save `m_ids', replace

// get measure_ids
	// get measure_ids
	use "$parameters_folder/constants.dta", clear
	local incidence_measure = incidence_measure_id[1]
	local prevalence_measure = prevalence_measure_id[1]

** **************************************************************************
** FINALIZE BY TYPE
** **************************************************************************
quietly foreach type in `types' { 
	noisily di "`type'"
	// Import Data
			if "`type'" == "incidence"  local data_folder = "$adjusted_incidence_folder"
			if "`type'" == "prevalence" local data_folder = "$prevalence_folder"
			use "`data_folder'/`acause'/`type'_draws_`local_id'.dta", clear

	// // Create and format required variables
		// acause
			capture gen acause = "`acause'"			

		// age, sex, year
			convert_to_age_group
			gen sex_id = sex
			gen year_id = year

	// // change to rate space
	run $convert_andCheck_rates "`type'_"

	// Add modelable_entity_id
	if "`type'" == "incidence" {
		gen stage = "primary"
		merge m:1 acause stage using `m_ids', keep(1 3) nogen
		} 
	if "`type'" == "prevalence" merge m:1 acause stage using `m_ids', keep(1 3) nogen
	
	// Reep relevant variables
	keep modelable_entity_id location_id year_id sex_id age_group_id draw_*
	order modelable_entity_id, first

	// list modelable entities in final file
	levelsof modelable_entity_id, clean local(present_me_ids)

	// Save output file for each modelabe entity id
	foreach m in `present_me_ids' {
		// crash if any data were dropped
		capture count if modelable_entity_id == `m'
		if !r(N) BREAK
		
		// save
		noisily di "     Saving `type' model `m' for `acause' location `local_id'..."
		cap mkdir "`output_folder'/`m'"
		local output_file = "`output_folder'/`m'/``type'_measure'_`local_id'.csv"
		capture rm "`output_file'"
		outsheet if modelable_entity_id == `m' using "`output_file'", comma replace
	}		
}

// close log
capture log close

** ************
** END
** ************
