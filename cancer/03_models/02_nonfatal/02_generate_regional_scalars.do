** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** Purpose:		used by 00_launch to create parameter files 

** *************************************************************************************************************
** 
** *************************************************************************************************************
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"

// Set STATA workspace 
	set more off
	capture set maxvar 32000
	
// Set common directories, functions, and globals (shell, finalize_worker, finalization_folder...)
	run "$j/WORK/07_registry/cancer/03_models/02_yld_estimation/01_code/subroutines/set_paths.do"

// Set outputs
	local output_file = "$scalars_folder/regional_scalars.dta"
	local long_term_copy = "$long_term_copy_scalars/regional_scalars.dta"

// Get location data
	use "$parameters_folder/locations.dta", clear

// Generate Regional scalars
	noisily di "Getting regional scalars.."
	local firstpass = 1
	levelsof(parent_id) if parent_type == "region" & model == 1, local(parent_ids) clean
	quietly foreach pid in `parent_ids' {
		// get regional scalar data
		clear
		foreach year of numlist 1980/$max_year {
			append using "$j/WORK/10_gbd/01_dalynator/02_inputs/region_scalars/18/`pid'_`year'_scaling_pop.dta"
		}

		// reformat variables
			rename (year_id age_group_id sex_id) (year age sex)
			replace age = 0 if age == 2
			replace age = .01 if age == 3
			replace age = .1 if age == 4
			replace age = 1 if age == 5
			replace age = (age -5)*5 if age > 5 

		// save
			if `firstpass' {
				tempfile regional_scalars
			}
			else append using `regional_scalars'
			save `regional_scalars', replace
			local firstpass = 0
		}

// Save
	save "`output_file'", replace
	save "`long_term_copy'", replace

** *************************************************************************************************************
** END
** *************************************************************************************************************
