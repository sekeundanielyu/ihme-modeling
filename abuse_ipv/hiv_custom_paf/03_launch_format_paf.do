// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 		May 2016
// Project:		RISK
// Purpose:		launch script do file - parallelize calculation of population attributable fraction of hepatitis C and hepatitis B prevalence due to IV drug use, by country, sex and groups of 100 draws
** **************************************************************************
** RUNTIME CONFIGURATION
** **************************************************************************
// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		set mem 12g
		set maxvar 32000
	// Set to run all selected code without pausing
		set more off
	// Set graph output color scheme
		set scheme s1color
	// Remove previous restores
		cap restore, not
	// Reset timer (?)
		timer clear	
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}
	// Close previous logs
		cap log close

** Set version number (increases by 1 for each run)
	local repo `1'
	local version 2

	local code_dir "`repo'/abuse_ipv/04_paf/hiv"

// Save ISO3 with subnational location ids in a local for launching parallelized jobs
	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & most_detailed == 1

	keep ihme_loc_id location_id location_ascii_name super_region_name super_region_id region_name region_id
	
	rename ihme_loc_id iso3 
	tempfile country_codes
	save `country_codes', replace

	qui: levelsof location_id, local(locations)

	//local locations 482
	//local locations "482 483 484 485 486 487 488 489 490"

// 2.) Parallelize on location

		foreach iso3 of local locations {
			
			!qsub -o /share/temp/sgeoutput/output -e /share/temp/sgeoutput/errors -P proj_custom_models -N "ipv_pafs_`iso3'" -pe multi_slot 4 ///
			"`code_dir'/stata_shell.sh" ///
			"`code_dir'/04_format_paf.do" ///
			"`version' `iso3'" 
					
		}
				
		
	
