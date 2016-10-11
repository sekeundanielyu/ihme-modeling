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
	args mi_cause_name local_id use_gbd_2010_mi_estimates

// Input Data
	local mi_filepattern = "model_output_with_draws"
	local mi_storage_folder "$formatted_mi_folder/`mi_cause_name'"
	local formatted_mi_data = "`mi_storage_folder'/formatted_mi_draws_`local_id'.dta"
	
** ****************************************************************
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/format_mi_`mi_cause_name'"
	capture mkdir "`log_folder'"

// Start Logs
	capture log close _all	
	capture log using "`log_folder'/`local_id'.log", text replace

** ****************************************************************
** GET GBD RESOURCES 
** ****************************************************************
// Get name of mi model
	use "$parameters_folder/causes.dta", clear
	levelsof sex if mi_cause_name == "`mi_cause_name'" & model == 1, clean local(sexes)
	tempfile causes
	save `causes', replace

// Get location-specific variables
	use "$parameters_folder/locations.dta", clear
	levelsof ihme_loc_id  if location_id == `local_id', local(ihme_loc_id) clean
	levelsof developed if location_id == `local_id', local(dev_status) clean
	levelsof super_region_id if location_id == `local_id', local(sr_id) clean
	if "`ihme_loc_id'" == "" {
		noisily di "Error: location_id `local_id' does not have an MI model"
		exit, clear
	}

	// set group_id based on the development status. this will indicate which lower bound to use (see 'Format MI Draws' section)
		local group_id = `dev_status'

		// handle exception for thyroid cancer 
			if "`mi_cause_name'" == "neo_thyroid" {
				if `sr_id' == 64 local group_id = 1 
				else local group_id = 0
			}

		// set exceptions
			if "`mi_cause_name'" == "neo_liver" & `local_id' == 48 {
				local exception = 1
				local exception_lower_bound = 0.6
			}
			else local exception = 0

// Ensure presence of output folder
	make_directory_tree, path("`mi_storage_folder'")

** ****************************************************************
** Define Functions
** ****************************************************************
capture program drop run_mi
program define run_mi
	args mi_cause_name merge_loc sexes 
	
	// alert user
	noisily di "ALERT: problem with mi model output. Re-running `mi_cause_name' MI model for `merge_loc'"
	
	// get model number and super region required to re-run 
	preserve
		import delimited using "$cancer_folder/03_models/01_mi_ratio/03_results/06_model_selection/model_selection.csv", clear delim(",") varnames(1)
		capture levelsof best_model if acause == "`mi_cause_name'", clean local(modnum)
		import delimited using "$cancer_common_folder/data/modeled_locations.csv", clear delim(",") varnames(1)
		capture levelsof super_region_id if ihme_loc_id == "`merge_loc'", clean local(sr)
	restore

	// re-run model for the location of interest
	foreach process in gpr finalize {
		foreach sx in `sexes' {
			if `sx' == 1 local sex_name = "male"
			if `sx' == 2 local sex_name = "female"
			!python "$mi_model_process" `modnum' "`mi_cause_name'" "`sex_name'" `sr' "`merge_loc'" 1000 "`process'"
		}
	}

end

capture program drop get_mi_data
program define get_mi_data
	args sexes mi_cause_name merge_loc mi_filepattern

	// compile mi draws for all modeled sexes
	clear
	local firstLoop = 1
	quietly foreach sx in `sexes' {
		noisily di "Appending sex `sx'"
		// Determine name of sex
			if `sx' == 1 local sex_name = "male"
			if `sx' == 2 local sex_name = "female"
			if `sx' == 1 & "`mi_cause_name'" == "neo_breast" local sex_name = "female"
	
		// import data
			local mi_draws = "$mi_ratio_folder/`mi_cause_name'/`sex_name'/`merge_loc'_`mi_filepattern'.csv"
			capture confirm file "`mi_draws'"
			if _rc run_mi `mi_cause_name' `merge_loc' "`sx'" 
			import delimited using "`mi_draws'", clear
					
		// Ensure presence of sex variable. Also resets sex variable if single sex model is used for both sexes
			capture drop sex
			gen int sex = `sx'
		
		// add to dataset
		if `firstLoop' tempfile mi_data
		else append using  `mi_data'
		save `mi_data', replace
		
		// turn off firstLoop
		local firstLoop = 0 
	}

end 

// verify that there is the same amount of data for both sexes.
capture program drop check_mi_data
program define check_mi_data, rclass

	local bad_result = 0
	count if sex == 1
	local test = r(N)
	di `test'
	count if sex == 2
	if r(N) != `test'  {
		local bad_result = 1
		noisily di "ERROR: missing data for one of two sexes."
	}
	return scalar test_result = `bad_result'

end 

capture program drop get_previous_mi_ratios
program define get_previous_mi_ratios
	// accept arguments
	args loc_id mi_cause_name

	// import and keep relevant data
	use "$j/WORK/07_registry/cancer/03_models/01_mi_ratio/03_results/_archive/gbd_2013_mi_ratios.dta", clear
	keep if model == "minibig37"
	if regexm("`mi_cause_name'", "neo_leukemia") {
		keep if ihme_loc_id == "`loc_id'" & acause == "neo_leukemia"
		replace acause = "`mi_cause_name'"
	}
	else {
		keep if ihme_loc_id == "`loc_id'" & acause == "`mi_cause_name'"
	}
	// duplicate 2013 data forward to 2014 and 2015
	preserve
		keep if year == 2013
		tempfile most_recent
		save `most_recent', replace
	restore
	foreach year in 2014 2015 {
		replace year = `year' if year == 2013
		append using `most_recent'
	}

end

** **************************************************************************
** Format MI Draws
** **************************************************************************
// // Get MI Draws
	// use only national MI ratios except for Hong Kong 
		local merge_loc = substr("`ihme_loc_id'", 1, 3)
		if "`local_id'" == "354" local merge_loc = "`ihme_loc_id'" 

	// Load Estimates
	if `use_gbd_2010_mi_estimates' {
		get_previous_mi_ratios `merge_loc' `mi_cause_name'
	}
	else {
		// Get Data
			get_mi_data "`sexes'" `mi_cause_name' `merge_loc' `mi_filepattern'

		// verify that there is the same amount of data for both sexes. If not, re-run draws
			if inlist("`sexes'", "1 2", "2 1")  {
				check_mi_data
				if r(test_result) {	
					// re-run mi
					run_mi `mi_cause_name' `merge_loc' "`sexes'" 

					// re-import and re-check data
					get_mi_data "`sexes'" `mi_cause_name' `merge_loc' `mi_filepattern'
					check_mi_data
					if r(test_result) {
							noisily di "ERROR: still missing data for one of two sexes in `ihme_loc_id' `mi_cause_name'"
							BREAK	
					}
				}
			}

		// keep relevant data and format
			rename draw* mi_*
			recast double age
	}

// // Format MI Draws
	// Ensure that data are within acceptable boundaries for nonfatal estimation (mi lower bound)
		capture drop acause
		capture drop developed		
		gen mi_cause_name = "`mi_cause_name'"
		gen lower_bound_group = `group_id'

		// merge mi boundaries
		merge m:1 mi_cause_name lower_bound_group using "$parameters_folder/mi_range.dta", keep(1 3) assert(2 3) nogen

		// handle exceptions
		if `exception' {
			replace mi_lower_bound = `exception_lower_bound'
		}

		// apply mi boundaries
		quietly foreach n of numlist 0/999 {
			if `use_gbd_2010_mi_estimates' gen mi_`n' = mean_mi
			replace mi_`n' = mi_`n'
			replace mi_`n' = mi_lower_bound if mi_`n' < mi_lower_bound
		}

	// add under 5 age groups by expanding the youngest age category that is present
		count if age == 0
		if !r(N) {
			preserve
				keep if age == 5
				replace age = 0
				tempfile young
				save `young', replace
			restore
			append using `young'
		}
		else {
			preserve
				keep if age == 0
				tempfile young
				save `young', replace
			restore
		}

		foreach a of numlist 0.01 0.1 1 {
			count if age == `a'
			if !r(N) {
				replace age = `a' if age == 0
				append using `young'
			}
		}
		replace age = round(age, 0.01)

	// 
		if "`mi_cause_name'" == "neo_nasopharynx" {
			// Drop all MIs under 30
				drop if age < 30

			// Duplicate MI for age 30 to all younger ages
				preserve
					keep if age == 30
					tempfile young
					save `young', replace
				restore
				foreach age of numlist 0 0.01 0.1 1 5 10 15 20 25 {
					replace age = `age' if age == 30
					append using `young'
				}
		}
	// Save
		save "`formatted_mi_data'", replace

// close log
capture log close

** *******
** END
** *******
