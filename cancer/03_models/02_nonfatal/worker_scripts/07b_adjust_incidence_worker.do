// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Subtract sequela incidence if necessary, which prevents double counting by the central model

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
** Set Macros and Directories
** ****************************************************************
// Accept or default arguments
	args acause local_id

//  folders
	local input_data = "$incidence_folder/`acause'/incidence_draws_`local_id'.dta"
	local output_data = "$adjusted_incidence_folder/`acause'/incidence_draws_`local_id'.dta"

** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/adjust_incidence_`acause'"
	capture mkdir "`log_folder'"

// Start Logs	
	capture log using "`log_folder'/`local_id'.log", text replace

** ****************************************************************
** GET RESOURCES
** ****************************************************************	
// get modelable entity id if data need to be adjusted for procedure-caused remission
	use "$parameters_folder/causes.dta", clear
	levelsof procedure_rate_id if acause == "`acause'" & to_adjust == 1, clean local(p_id)

** **************************************************************************
** Part 3: Adjust Incidence if Necessary, otherwise copy and paste data to indicate completion
** **************************************************************************
// If no adjustment is needed, copy data to indicate completion
	if "`p_id'" == "" copy "`input_data'" "`output_data'", replace

// If adjustment is required, adjust remission to remove remission status due to cancer treatment ("sequelae adjustment")
	if "`p_id'" != ""{
		// load relevant data
			use "`input_data'", clear
			drop if inlist(age, 98, 99)

		// subtract sequelae to prevent double-counting in central model
			do "$adjust_for_sequelae"
			adjust_for_sequelae, procedure_id("`p_id'") varname("incidence_") data_type("incidence") acause("`acause'")

		// Keep and sort relevant data
			keep location_id year sex age acause incidence_*
			order location_id year sex age acause
			sort location_id year sex age acause

		// Save draws
			compress
			save "`output_data'", replace
	} 

// close log		
	capture log close

** **************************************************************************
** END
** **************************************************************************
