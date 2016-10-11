** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
// Purpose:		Adjust remission to account for ectomy overlap 

** ****************************************************************
** Load Functions
** ****************************************************************	 

// Generate all-ages estimate
capture program drop adjust_for_sequelae
program define adjust_for_sequelae
	syntax ,  procedure_id(string) varname(string) data_type(string) acause(string)

	// Save copy of original estimates 
		tempfile all_stages
		save `all_stages', replace

	// Load procedures
		local proportion_file "$modeled_procedures_folder/`procedure_id'/modeled_`data_type'_`procedure_id'.dta"
		
	// Separate remission data and merge with proportions
		keep if age <= 80 
		if "`data_type'" == "prevalence" keep if stage == "in_remission"
		merge 1:1 location_id year age sex using `proportion_file', keep(1 3) nogen 
	
	// Subtract procedures from total
		forvalues i = 0/999 {
			replace `varname'`i' = `varname'`i' - procedures_`i'
		}
		tempfile adjusted_remission
		save `adjusted_remission', replace

	// // If adjusting prevalence, recombine with original dataset
		if "`data_type'" == "prevalence" {
			use `all_stages', clear
			replace stage = "unadjusted_remission" if stage == "in_remission"
			append using `adjusted_remission'
		}

	// Alert user that adjustment has completed
		noisily di "Data Adjusted for Sequelae"

end

** ***************
** END
** **************
