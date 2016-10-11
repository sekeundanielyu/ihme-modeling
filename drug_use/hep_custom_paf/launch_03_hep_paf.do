/// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 		May 2016 
// Project:		RISK
// Purpose:		Format PAFs for central machinery. 
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

// Local repo 
	local repo `1'
	
// Create macros for settings, files and filepaths 
	** Switch  between lower case "b" and "c" to generate PAFs for each type of Hepatitis  
	//local viruses "C B"
	** Set version number (increases by 1 for each run)
	local version 2
	** Countries for which we are producing subnational estimates
	//global subnational_locations "GBR", "MEX", "CHN" 
	** Year range for cohort analysis (assume genesis of IV drug use was 1960)
	local startyr 1960
	local endyr 2015
	
// Create macros for settings, files and filepaths 
	
	local sexes "1 2"
	local years "1990 1995 2000 2005 2010 2015"

	local code_dir "`repo'/drug_use/04_paf"

// Save ISO3s with subnational location ids in a local
	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & most_detailed == 1

	keep ihme_loc_id location_id location_ascii_name super_region_name super_region_id region_name region_id
	
	rename ihme_loc_id iso3 
	tempfile country_codes
	save `country_codes', replace

	qui: levelsof location_id, local(locations)

	// Test locations
	//local locations 4758	

// Loop through each iso3 and sex and launch jobs

		foreach iso3 of local locations {
			foreach sex of local sexes {
				
						!qsub -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors -N "idu_`iso3'_`sex'" -pe multi_slot 4 -l mem_free=20G ///
						"`code_dir'/stata_shell.sh" ///
						"`code_dir'/03_hep_paf.do" ///
						"`iso3' `sex' `version'" 
					}
				}
				
		
	
