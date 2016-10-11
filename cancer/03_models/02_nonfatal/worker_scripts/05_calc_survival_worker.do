// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Calculate prevalence for individual cause, sex, and location for cancer nonfatal modeling
 
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

// folders
	local access_to_care = "$atc_folder/`acause'/access_to_care_draws_`local_id'.dta"
	local lambda_values = "$scalars_folder/lambda_values.dta"
	local survival_curves = "$scalars_folder/survival_curves.dta"
	local total_incidence = "$incidence_folder/`acause'/incidence_draws_`local_id'.dta"
	local output_folder = "$survival_folder/`acause'"

** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/survival_`acause'_"
	capture mkdir "`log_folder'"

// Start Logs	
	capture log using "`log_folder'/`local_id'.log", text replace

** ****************************************************************
** GET RESOURCES
** ****************************************************************	
// maximum survival months
	use "$parameters_folder/constants.dta"
	local max_survival_months = max_survival_months[1]

// load summary functions
	run "$summary_functions"
	
** **************************************************************************
** Combine incidence and access to care to calculate incremental survival rate
** **************************************************************************
// // Get incidence
	// Get data
		capture confirm file "`total_incidence'"
		if _rc do "$incidence_worker" `acause' `local_id'
		use "`total_incidence'", clear
		
	// Keep relevant data
		keep if age <= 80

// Merge with access to care variable	
	merge m:1 location_id year sex acause using "`access_to_care'", keep(1 3) assert(2 3) nogen 

// // Transform access to care into survival
	// merge with survival curves
		display "Merging with survival curves..."
			// Specially Handle Exceptions
			if regexm("`acause'", "neo_leukemia_")  replace acause = "neo_leukemia"
			if regexm("`acause'", "neo_liver_")  replace acause = "neo_liver"
			if "`acause'" == "neo_nmsc" replace acause = "neo_nmsc_scc"

			// Merge
			joinby acause sex using "`survival_curves'"

			// Revert Specially Handled Causes
			if regexm("`acause'", "neo_leukemia_") | regexm("`acause'", "neo_liver_") | "`acause'" == "neo_nmsc" replace acause = "`acause'"  

	// Only keep survival if less than or equal to our set maximum survival months
		keep if survival_month <= `max_survival_months'

	// Calculate relative survival percentage
		quietly forvalues i = 0/999 {
			gen double survival_relative_`i' = (access_to_care_`i' * (survival_best - survival_worst)) + survival_worst
		}
	// merge with lambda values
		display "Merging on lambda values"
		merge m:1 location_id year sex age using "`lambda_values'", keep(1 3) assert(2 3) nogen

	// Calculate absolute survival
		display "Calculating absolute survival"
		quietly forvalues i = 0/999 {
			gen double survival_abs_`i' = survival_relative_`i' * exp(lambda * survival_year)
			replace survival_abs_`i' = 0 if survival_abs_`i' == .
			replace survival_abs_`i' = 1 if survival_abs_`i' > 1 | survival_abs_`i' == .
		}

// Calculate incremental survival rate
	sort location_id sex age year survival_years
	di "Calculating incremental survival..."
	quietly forvalues i = 0/999 {
		display "        draw_`i'"
		bysort location_id sex age year: gen double mortality_incremental_`i' = survival_abs_`i' - survival_abs_`i'[_n+1]
		replace mortality_incremental_`i' = 0 if mortality_incremental_`i' < 0 | mortality_incremental_`i' == .
		// fill in the most-years survived lines with remaining survivors
		bysort location_id sex age year: egen total_die_`i' = total(mortality_incremental_`i')
		replace mortality_incremental_`i' = (1 - total_die_`i') if survival_month == `max_survival_months'
	}

// Save Draws
	capture rm "`output_folder'/survival_draws_`local_id'.dta"
	save "`output_folder'/survival_draws_`local_id'.dta", replace

// Calculate summary statistics
	calculate_summary_statistics, data_var("survival_abs")

	egen median_survival_abs = rowmedian(survival_abs*)
	egen sd_survival_abs = rowsd(survival_abs*)

	keep location_id sex age year survival_year median mean lower upper sd
	keep if survival_year == 5 | survival_year == 10

// Save
	compress
	save "`output_folder'/survival_summary_`local_id'.dta", replace
	

** **************************************************************************
** END
** **************************************************************************

