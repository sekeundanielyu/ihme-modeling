// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:	Load and format sequela durations for use in prevalence estimation

** **************************************************************************
** Configuration
** 		
** **************************************************************************
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"

// Set STATA workspace 
	clear all
	set more off
	set maxvar 32000
	
// Set common directories, functions, and globals (shell, finalize_worker, finalization_folder...)
	run "$j/WORK/07_registry/cancer/03_models/02_yld_estimation/01_code/subroutines/set_paths.do"
			
** ****************************************************************
** SET MACROS
** ****************************************************************
	local output_file = "$scalars_folder/sequela_durations.dta" 
	local long_term_copy = "$long_term_copy_scalars/sequela_durations.dta"

** **************************************************************************
** RUN PROGRAM
** **************************************************************************	
// Format	
	use "$cancer_storage/02_database/03_sequela_duration/data/final/sequela_durations.dta", clear
	gen st_in_remission = 0
	rename (primary disseminated terminal) (st_primary st_disseminated st_terminal)
	reshape long st_, i(acause) j(stage) string
	rename st_ sequela_duration

// Save
	compress
	save "`output_file'", replace
	save "`long_term_copy'", replace


** **********
** END
** **********
