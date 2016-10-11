** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** Purpose:		Loads functions to generate all-ages count and age-standardized rate			
**
** *********************************************************************************************************************************************************************
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"

// load IHME written mata functions which speed up collapse, pctile, and rowmean
	run "$j/WORK/10_gbd/00_library/functions/fastcollapse.ado"
	run "$j/WORK/10_gbd/00_library/functions/fastpctile.ado"
	run "$j/WORK/10_gbd/00_library/functions/fastrowmean.ado"

** ****************************************************************
** Generate all-ages estimate: generate "age = 99"/"all ages" data for the given variable type
** ****************************************************************	
capture program drop all_age
program define all_age 
	syntax , [ageFormat(string)] relevant_vars(string) data_var(string)
	//
		preserve
			keep if age <= 80
			replace age = 99
			fastcollapse `data_var'*, type(sum) by(`relevant_vars')
			tempfile all_age_data
			save `all_age_data', replace
		restore
		append using `all_age_data'

	// Keep relevant data
		keep `relevant_vars' `data_var'*
end 

** ****************************************************************
** Generate age-standardized rate: generate "age = 98"/"asr" data for the given variable type
** ****************************************************************	
capture program drop asr
program define asr
	syntax ,  [ageFormat(string)] relevant_vars(string) data_var(string) 

	// 
	drop if age == 98
	preserve
		keep if age <= 80
		merge m:1 age using "$j/WORK/02_mortality/04_outputs/02_results/age_weights.dta", keep(1 3) assert(2 3) nogen
		merge m:1 location_id year age sex using "$population_data", keep(1 3) assert(2 3) nogen					
		foreach var of varlist `data_var'* {
				qui replace `var' = `var' * weight / pop
		}
		replace age = 98
		fastcollapse `data_var'*, type(sum) by(`relevant_vars')
		tempfile asr_data
		save `asr_data', replace
	restore
	append using `asr_data'
end

** ****************************************************************
** Calculate Summary Statistics: generate mean
** ****************************************************************	

capture program drop calculate_summary_statistics
progra define calculate_summary_statistics
	syntax , data_var(string) [percentiles(string)]

	// set percentiles
	if "`percentiles'" != "" noisily display "Calculating summary statistics with the following lower and upper percentiles: `percentiles'"
	else {
		local percentiles = "2.5 97.5"
		noisily display "Calculating summary statistics with default lower and upper percentiles: `percentiles'"
	}	
	
	// Calculate summary statistics
		fastrowmean `data_var'*, mean_var_name(mean_`data_var')
		fastpctile `data_var'*, pct(`percentiles') names(lower_`data_var' upper_`data_var')

end

** ****************************************************************
** END
** ****************************************************************
