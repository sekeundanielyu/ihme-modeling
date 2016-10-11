// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Purpose:		Submit case draws for age-sex splitting


** **************************************************************************
** CONFIGURATION
** **************************************************************************
	** ****************************************************************
	** Prepare STATA for use
	**
	** This section sets the application preferences.  The local applications
	**	preferences include memory allocation, variables limits, color scheme,
	**	defining the J drive (data), and setting a local for the date.
	**
	** ****************************************************************
		// Set application preferences
			// Clear memory and set memory and variable limits
				clear all
				set mem 5G
				set maxvar 32000

			// Set to run all selected code without pausing
				set more off

			// Set graph output color scheme
				set scheme s1color

			// Define J drive (data) for cluster (UNIX) and Windows (Windows)
				if c(os) == "Unix" {
					global prefix "/home/j"
					set odbcmgr unixodbc
				}
				else if c(os) == "Windows" {
					global prefix "J:"
				}
			
			// Get timestamp
				local date = c(current_date)
				local today = date("`date'", "DMY")
				local year = year(`today')
				local month = month(`today')
				local day = day(`today')
				local time = c(current_time)
				local time : subinstr local time ":" "", all
				local length : length local month
				if `length' == 1 local month = "0`month'"	
				local length : length local day
				if `length' == 1 local day = "0`day'"
				global date = "`year'_`month'_`day'"
				global timestamp = "${date}_`time'"


		** ****************************************************************
		** SET LOCALS
		**
		** Set data_name local and create associated folder structure for
		**	formatting prep.
		**
		** ****************************************************************
			// username
				global username strUser
			
			// gbd cause (acause)
				local acause whooping
			
			// Version
				local version v8
				
						
			// Is this for death or cases
				local metric "cases"
				if "`metric'" == "death" local metric_folder "COD_prep"
				if "`metric'" == "cases" local metric_folder "EPI_prep"	
				
			// Code folder
				local code_folder "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015/code"
				
			// Input folder
				local input_folder "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015/`version'/results/for_age_sex_split"
				
			// Output folder
				local output_folder "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015/`version'/results/age_sex_split_files"
				
			// Temp folder
				capture mkdir "/ihme/scratch/users/${username}"
				capture mkdir "/ihme/scratch/users/${username}/`metric_folder'"
				capture mkdir "/ihme/scratch/users/${username}/`metric_folder'/`acause'"
				local clustertmp_folder "/ihme/scratch/users/${username}/`metric_folder'/`acause'"
				capture mkdir "`clustertmp_folder'/01_initial_data"
				capture mkdir "`clustertmp_folder'/99_final_format"


		** ****************************************************************
		** CREATE LOG
		** ****************************************************************
			capture log close
			** log using "`log_folder'/05_agesex_split_`metric'_`today'.log", replace


		** ****************************************************************
		** GET GBD RESOURCES
		** ****************************************************************

		
** **************************************************************************
** RUN PROGRAGM
** **************************************************************************
	// Get data
		use "`input_folder'/`metric'_draws.dta"

	// Split apart into smaller chunks by iso3 code to do the final formatting
		levelsof(ihme_loc_id), local(ihme_loc_ids) clean
		preserve
		foreach ihme_loc_id of local ihme_loc_ids {
			capture rm "`clustertmp_folder'/01_initial_data/`ihme_loc_id'_input.dta"
			capture rm "`clustertmp_folder'/99_final_format/`ihme_loc_id'_formatted.dta"
			capture confirm file "`clustertmp_folder'/99_final_format/`ihme_loc_id'_formatted.dta"
			if _rc {
				display "Submitting `ihme_loc_id'"
				keep if ihme_loc_id == "`ihme_loc_id'"
				save "`clustertmp_folder'/01_initial_data/`ihme_loc_id'_input.dta", replace
				!qsub -pe multi_slot 5 -l mem_free=10g -N "COD_`acause'_`ihme_loc_id'_agesex_split" -P "proj_custom_models" "`code_folder'/shellstata.sh" "`code_folder'/format_for_agesplit.do" "${username} `acause' `metric' `ihme_loc_id'"
			}
			restore
			drop if ihme_loc_id == "`ihme_loc_id'"
			preserve
		}
		restore
		
	// Append together
		clear
		foreach ihme_loc_id of local ihme_loc_ids {
			local checkfile "`clustertmp_folder'/99_final_format/`ihme_loc_id'_formatted.dta"
			capture confirm file "`checkfile'"
			while _rc {
				display "`ihme_loc_id' formatted not found, checking again in 30 seconds"
				sleep 30000
				capture confirm file "`checkfile'"
			}
			display "`ihme_loc_id' formatted found!"
			append using "`checkfile'"
		}
		
	// Save 
		compress
		save "`output_folder'/`metric'_draws.dta", replace
	
	capture log close


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
