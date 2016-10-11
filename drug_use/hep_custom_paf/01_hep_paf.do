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

// Local repo 
	local repo `1'
	
// Specify settings		
	** Switch  between lower case "b" and "c" to generate PAFs for each type of Hepatitis  
	local viruses "C B"
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
	local rr_dir "/share/epi/risk/temp/drug_use_pafs/hepatitis_`virus'"
	local data_dir "/share/epi/risk/temp/drug_use_pafs"

// Save ISO3 with subnational location ids in a local for launching parallelized jobs
	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & most_detailed == 1

	keep ihme_loc_id location_id location_ascii_name super_region_name super_region_id region_name region_id
	
	rename ihme_loc_id iso3 
	tempfile country_codes
	save `country_codes', replace

	qui: levelsof location_id, local(locations)
	
	// PARTITION JOBS (start with sex = 1 & virus = "C"; next sex = 2 & virus = "C") 
	//local sexes 2
	//local viruses "C"

/*
// 1.) Prepare year coefficient from IDU DisMod model to project IDU prevalence for years prior to 1990
		local beta 0.049
		local lower 0.017
		local upper 0.082

	// 1,000 draws from normal distribution
		local sd = ((ln(`upper')) - (ln(`lower'))) / (2*invnormal(.975))
		clear
		set obs 1
		forvalues d = 0/999 {
			gen beta_`d' = exp(rnormal(ln(`beta'), `sd'))
		}
		
	// Make identifier for merge with Dismod model
		gen x = 1
		order x beta_*
		
	// Save draws of year coefficient for PAF calculation
		save "`data_dir'/year_coef_draws.dta", replace 	
*/

// 2.) Parallelize on location, sex and 10 groups of 100 draws
	// Loop through each iso3, sex and draw group to launch jobs

	foreach virus of local viruses {

		cap mkdir "`data_dir'/hepatitis_`virus'/v`version'"
		cd "`data_dir'/hepatitis_`virus'/v`version'"

		foreach iso3 of local locations {
			foreach sex of local sexes {
				forvalues draw_num = 99(100)999 {
					local draw_num = `draw_num'
					//local d = `draw_num' - 99
					capture confirm file "`data_dir'/hepatitis_`virus'/v`version'/paf_`iso3'_`sex'_draw_`draw_num'.dta"
					if _rc != 0 {
						!qsub -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors -P proj_custom_models -N "hepatitis_pafs_`iso3'_`sex'_hep`virus'_`draw_num'" -pe multi_slot 4 ///
						"`code_dir'/stata_shell.sh" ///
						"`code_dir'/02_hep_paf.do" ///
						"`virus' `iso3' `sex' `draw_num' `version'" 
					}
				}
			}	
		}
	}

	

