// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Create lambda values from mortality team's life tables. 

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
// Define relevant directories
	local output_file = "$scalars_folder/lambda_values.dta"
	local long_term_copy =  "$long_term_copy_scalars/lambda_values.dta"

** ****************************************************************
** GET GBD RESOURCES
** ****************************************************************
// Get location data
	use "$parameters_folder/locations.dta", clear
	keep location_id location_type
	tempfile location_map
	save `location_map', replace

** **************************************************************************
** RUN PROGRAM
** **************************************************************************	
// Get most recent version of life table from mortality team
	import delimited using "[filepath]/03_models/5_lifetables/results/lt_loc/with_shock/result/compiled_summary_lt_v45.csv", clear

// Merge with location information
	merge m:1 location_id using `location_map', keep(3) assert(1 3) nogen

// Keep only the data that we need
	// age
	keep if year >= 1980
	keep if age >= 5 & age < 31
	replace age = 80 if age == 30
	replace age = 0 if age == 28
	replace age = 1 if age == 5
	replace age = (age -5)*5 if age > 4 & age < 80

	// variables
	keep location_id sex year age nlx	
	
// Calculate lambda values
	
	// Rename and sort 
	rename (sex_id age_group_id) (sex age)	
	gsort  +location_id +sex +year -age

	// Remove "NA" values from nlx, if present
	capture confirm numeric variable nlx
	if _rc {
		destring nlx, generate (nLx) force
		list nlx if nLx>=.
		drop nlx
	}
	else rename nlx nLx

	// Calculate lambda
	bysort location_id sex year: gen lambda = (ln(nLx/nLx[_n+1]))
	replace lambda = lambda/5 if age > 5
	replace lambda = lambda/4 if age == 5
	replace lambda = lambda/1 if age == 1
	drop nLx 
	
	// Expand age group for under 1 
	preserve
		keep if age == 0
		tempfile young
		save `young', replace
	restore
	replace age = 0.1 if age == 0
	append using `young'
	replace age = 0.01 if age == 0
	append using `young'

	// Reformat age
	tostring(age), replace format("%12.2f") force
	destring(age), replace
	
// Save
	compress
	save "`output_file'", replace
	save "`long_term_copy'", replace


** **********
** END
** **********
