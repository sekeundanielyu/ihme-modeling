** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** Purpose:		Aggregates mortality, incidence, or prevalence data at the draw level to create estimates for parent locations			
**
** *********************************************************************************************************************************************************************
** ****************************************************************
** Configuration
** ****************************************************************
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"
	
// Set common directories, functions, and globals (shell, finalize_worker, finalization_folder...)
	run "$j/WORK/07_registry/cancer/03_models/02_yld_estimation/01_code/subroutines/set_paths.do"
	
// load summary functions
	run "$summary_functions"

** ****************************************************************
** Accept & Set Arguments	
** ****************************************************************
// accept arguments
	args data_type data_var output_folder use_available_aggregates

** ****************************************************************
** GET RESOURCES	
** ****************************************************************
// Get list of location ids
	use "$parameters_folder/locations.dta", clear
	capture levelsof(parent_type) if model == 1, local(parent_types) clean
	noisily di "`parent_types'"
	tempfile locations
	save `locations', replace	

// Ensure presence of regional scalars
	local regional_scalars = "$scalars_folder/regional_scalars.dta"
	capture confirm file "`regional_scalars'"
	if _rc {
		noisily di "ERROR: regional scalars not defined"
		BREAK
	}

// set relevant variables based on data type
	if "`data_type'" == "prevalence" local relevant_vars = "location_id year sex age acause stage"
	else local relevant_vars = "location_id year sex age acause"

** ****************************************************************
** Aggregate data for each level of each parent type, then save	
** ****************************************************************
// Aggregate for each level of each parent type
foreach pt of local parent_types {
	// load IHME written mata function to speed up collapse
		run "$j/WORK/10_gbd/00_library/functions/fastcollapse.ado"

	noisily display "Beginning `pt' aggregation..."
	use `locations', clear
	capture levelsof(parent_id) if parent_type == "`pt'" & model == 1, local(parent_ids) clean
	foreach pid of local parent_ids {
		// Skip if output file present
			if `use_available_aggregates' {
				capture confirm file "`output_folder'/`data_type'_summary_`pid'.dta"
				if !_rc {
					noisily display "     Found output for `pt' `pid'"
					continue
				}
			}
		// Compile data
			noisily display "     Aggregating `pt' `pid'..."
			use `locations', clear
			capture levelsof(location_id) if parent_type == "`pt'" & parent_id == `pid' & model == 1, local(child_ids) clean
			clear
			foreach cid of local child_ids {
				noisily display "          Location `cid'"
				local add_me = "`output_folder'/`data_type'_draws_`cid'.dta"
				append using "`add_me'"
			}
			replace location_id = `pid'
			fastcollapse `data_var'*, type(sum) by("`relevant_vars'")
		
		// Apply regional scalars if region
			if "`pt'" == "region" {
				noisily display "     Applying regional scalars..."
				// Drop all-age group
					keep if age <= 80
				// Merge with regional scalars
							merge m:1 location_id year sex age using `regional_scalars', keep(1 3) 
							count if _merge == 1
							if r(N) BREAK
							drop _merge
				// Scale data
					foreach var of varlist `data_var'* {
						replace `var' = `var' * scaling_factor
					}

				// Regenerate all-ages data
					all_age, relevant_vars("`relevant_vars'") data_var("`data_var'")
			}

		// Generate Age-Standardized Rate
			asr, relevant_vars("`relevant_vars'") data_var("`data_var'")

		// Save
			compress
			save "`output_folder'/`data_type'_draws_`pid'.dta", replace

		// Calculate summary statistics
			noisily display "     Calculating summary statistics..."
			fastrowmean `data_var'*, mean_var_name(mean_`data_type')
			fastpctile `data_var'*, pct(2.5 97.5) names(lower_`data_type' upper_`data_type')

		// Reformat
			keep `relevant_vars' mean_* lower_* upper_*
			order `relevant_vars' mean_* lower_* upper_*
			sort location_id year sex age
		
		// Save
			compress
			save "`output_folder'/`data_type'_summary_`pid'.dta", replace
	}
}

** ****************************************************************
** END
** ****************************************************************
