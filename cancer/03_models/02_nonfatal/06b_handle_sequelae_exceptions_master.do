// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Calculate prevalence of sequela that cannot be easily calculated otherwise

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
** Generate Log Folder and Start Logs
** ****************************************************************
// Log folder
	local log_folder "$log_folder_root/sequelae_adjustment"
	make_directory_tree, path("`log_folder'")

// Start Logs	
	capture log close _all
	log using "`log_folder'/_master.txt", text replace

** ****************************************************************
** Set Values
** ****************************************************************
// Accept arguments
	args resubmission

// Set lists of relevant modelable entity ids
	local procedure_me_id = 1724	
	local sequelae = "1725 1726"	

// set output folder
	local output_folder = "$sequelae_adjustment_folder"
	make_directory_tree, path("$sequelae_adjustment_folder")

// set location of draws download
	local draws_file = "`output_folder'/`procedure_me_id'_draws.dta"

// get measure_ids
	use "$parameters_folder/constants.dta", clear
	local prevalence_measure = prevalence_measure_id[1]

// Import function to retrieve epi estimates 
	run "$get_draws"

** **************************************************************************
** 
** **************************************************************************
// // download data from dismod
if !`resubmission' {
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(`procedure_me_id') source(dismod) measure_ids(`prevalence_measure') clear
	keep location_id year_id sex_id age_group_id draw*
	order location_id year_id sex_id age_group_id draw*
	compress
	save "`draws_file'", replace
}

// // Submit jobs
	local submission_cause = substr("`acause'", 5, .)
	foreach sequela in `sequelae' {
		$qsub -pe multi_slot 3 -l mem_free=6g -N "seqW_`sequela'" "$shell" "$sp_sequelae_calc_worker" "`sequela' `resubmission'"
	}	

// // compile formatted downloads (generated at beginning of the worker script) for adjustment of remission prevalence.
	// combine data
		noisily di "Generating total sequelae data..."
		clear
		local num_checks = 0
		quietly foreach sequela in `sequelae' {
			local sequela_data = "`output_folder'/`sequela'_data.dta"
			capture confirm file "`sequela_data'"
			while _rc {
				sleep 1000
				capture confirm file "`sequela_data'"
				local num_checks = `num_checks' + 1
				if `num_checks' > 3600 {
					do "$sp_sequelae_calc_worker" `sequela' 1
					capture confirm file "`sequela_data'"
					if _rc {
						noisily di "ERROR: Error during download"
						BREAK
					}
				}
			}
			noisily di "    appending sequela `sequela' data..."
			append using "`output_folder'/`sequela'_data.dta"
		}

	// calculate the total number of procedures
		rename draw_* procedures_*
		keep location_id year_id sex_id age_group_id procedures_*
		fastcollapse procedures_*, type(sum) by(location_id year_id sex_id age_group_id)

	// format 
		drop if age_group_id > 21
		convert_from_age_group
		drop age_group_id
		rename (year_id sex_id) (year sex)

	// save
		compress
		save "`output_folder'/total_`procedure_me_id'_sequelae.dta", replace

// // Check for completion of upload
	noisily di "Verifying success of uploads... "
	foreach sequela in `sequelae' {
		local checkfile = "`output_folder'/`sequela'/sequela_`sequela'_uploaded.dta"
		check_for_output, locate_file("`checkfile'") timeout(1) failScript("$sp_sequelae_calc_worker") scriptArguments("`sequela' 1") 
	}

// close log
	capture log close

** ************
** END
** ************
