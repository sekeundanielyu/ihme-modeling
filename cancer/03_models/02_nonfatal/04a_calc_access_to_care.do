// *********************************************************************************************************************************************************************
// Purpose:		By cause/sex: Append together all-ages calculated MI ratios for all locations and generate Access to Care variable, for calculating YLDs

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
// Accept arguments
	args acause

	// set arguments if none sent 
	if "`acause'" == "" local acause neo_nmsc
	
// output_folder
	local output_folder = "$atc_folder/`acause'"
	capture make_directory_tree, path("`output_folder'")

** ****************************************************************
** GET RESOURCES
** ****************************************************************	
// Get countries
	use "$parameters_folder/locations.dta", clear
	tempfile locations
	save `locations', replace
	capture levelsof(location_id) if model == 1, local(local_ids) clean

// load summary functions
	run "$summary_functions"

** **************************************************************************
** Part 1: Get Deaths and Incidence to Calculate Age Standardized MI
** **************************************************************************
// Get deaths
	clear
	tempfile death_draws
	quietly {
		noisily di "Appending death draws..."
		foreach local_id of local local_ids {
			noisily display "    `local_id'"
			local death_file = "$mortality_folder/`acause'/death_draws_`local_id'.dta"
			check_for_output, locate_file("`death_file'") sleepInterval(10) timeout(4) failScript("`code_folder'/subroutines/03a_death_draws_worker.do") scriptArguments("`acause' `local_id'")
			append using "`death_file'"
			if regexm("`acause'", "neo_nmsc") {
				keep if inlist(year, 1990, 1995, 2000, 2005, 2010, 2015)
			}
			keep if age == 98
		}
		duplicates drop
	}
	save `death_draws', replace

// Get incidence
	clear
	tempfile incidence_draws
	quietly {
		noisily di "Appending incidence draws... "
		foreach local_id of local local_ids {
			noisily display "    `local_id'"
			local incidence_file = "$incidence_folder/`acause'/incidence_draws_`local_id'.dta"
			check_for_output, locate_file("`incidence_file'") sleepInterval(10) timeout(4) failScript("`code_folder'/subroutines/03b_calc_incidence_worker.do") scriptArguments("`acause' `local_id'")
			append using "`incidence_file'"
			keep if age == 98
		}
		duplicates drop
	}
	merge 1:1 location_id year sex age acause using `death_draws', assert(3) nogen

** **************************************************************************
** Part 2: Calculate Age-Standardized MI, then generate access to care
** **************************************************************************
quietly {
	noisily di "Calculating access to care..."
	forvalues i = 0/999 {
	noisily display "    draw `i'..."
	// Calculate age-standardized mi ratio 
	 	gen double mi_`i' = death_`i' / incidence_`i'

	// Get minimum and maximum mi for each draw 
		mata a = .
		mata st_view(a, ., "mi_`i'")
		mata st_store(1,st_addvar("double","max_mi_`i'"), colmax(a))
		replace max_mi_`i' = max_mi_`i'[1]
		mata st_store(1,st_addvar("double","min_mi_`i'"), colmin(a))
		replace min_mi_`i' = min_mi_`i'[1]
	
	// Calculate access to care
		gen double access_to_care_`i' = (1 - (mi_`i' - min_mi_`i')/(max_mi_`i' - min_mi_`i'))

	// Clean up
		drop max_mi_`i' min_mi_`i' mi_`i' death_`i' incidence_`i'
	
	}
}

** **************************************************************************
** Part 3: Format and Save
** **************************************************************************
// Drop irrelevant variables and sort
	keep location_id year sex acause access_to_care_*
	order location_id year sex acause access_to_care_*
	sort location_id year sex 	

// Save individual atc file for each location
	compress
	save "`output_folder'/access_to_care_all.dta", replace
	levelsof (location_id), clean local(atc_local_ids)
	preserve
	quietly {
		noisily di "Saving access to care..."
		foreach local_id of local atc_local_ids {
			noisily display "    `local_id'"
			keep if location_id == `local_id'
			save "`output_folder'/access_to_care_draws_`local_id'.dta", replace
			restore, preserve
		}
	}
	restore
	use "`output_folder'/access_to_care_all.dta", clear

// Calculate summary statistics
	calculate_summary_statistics, data_var("access_to_care")

// Reformat
	keep location_id year sex acause mean_access_to_care lower_access_to_care upper_access_to_care
	order location_id year sex acause mean_access_to_care lower_access_to_care upper_access_to_care
	sort location_id year sex
	
// Save summary
	compress
	save "`output_folder'/access_to_care_summary.dta", replace

	
capture log close
	

** *************
** END
** *************
