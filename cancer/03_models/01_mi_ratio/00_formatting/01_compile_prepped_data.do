
// Purpose:	Compile all cancer incidence and mortality data into two files

** **************************************************************************
** Configuration
** 		Sets application preferences (memory allocation, variable limits) 
** 		Accepts/Sets Arguments. Defines the J drive location.
** **************************************************************************
// Clear memory and set memory and variable limits
	clear all
	set mem 1G
	set maxvar 32000
	set more off
	
// Accept Arguments
	args today main_dir sourcesDirectory 
	
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"
	
** ****************************************************************
** Set Locals
** ****************************************************************
	// Set arguments if no arguments are passed
	if "`sourcesDirectory'" == "" {
		// Get date
		local today = date(c(current_date), "DMY")
		local today = string(year(`today')) + "_" + string(month(`today'),"%02.0f") + "_" + string(day(`today'),"%02.0f")

		// Set locals
		local main_dir = "$j/WORK/07_registry/cancer/02_database/01_mortality_incidence"
		local sourcesDirectory = "$j/WORK/07_registry/cancer/01_inputs/sources"
	}
	// Set directories
		local database_folder "`main_dir'/data/raw"
		global tempFolder = "$j/temp/registry/cancer/02_database/01_mortality_incidence"
		cap mkdir "$j/temp/registry/cancer/02_database"
		cap mkdir "$tempFolder"

** ****************************************************************
** Create Log if running on the cluster
** 		Get date. Close open logs. Start Logging.
** ****************************************************************
if c(os) == "Unix" {
	// Log folder
	local log_folder "/ihme/gbd/WORK/07_registry/cancer/logs/02_database/01_mortality_incidence"
	cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs"
	cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs/02_database"
	cap mkdir "`log_folder'"
	
	// Begin Log
	capture log close compile
	log using "`log_folder'/01_CbT_`today'.log", replace name(compile)
}

** **************************************************************************
** COMPILE
** **************************************************************************
// launch scripts to create compiled versions of the data at each stage
if c(os) == "Unix" {
	local compile_at_step = "$j/WORK/07_registry/cancer/01_inputs/programs/useful_scripts/code/compileData_atAny_prepStep.do"
	foreach step in "00_formatted 01_standardized_format 02_subtotals_disaggregated 03_mapped 04_age_sex_split 05_acause_disaggregated 06_pre_rdp 07_redistributed" {
		!/usr/local/bin/SGE/bin/lx24-amd64/qsub -P proj_cancer_prep -pe multi_slot 8 -l mem_free=16g -N "compile_`step'" "`programs_folder'/shellstata13.sh" "`compile_at_step'" "`step'"
	}
}

// Get alphabetized list of source folders
local sources_folders: dir "`sourcesDirectory'" dirs "*", respectcase
local sources_folders: list sort sources_folders  // sorts folders in alphabetical order

// For each data type...
foreach dataType in "inc" "mor" {

	global newLoop = 1
	
	// // For each group folder in '01_inputs/sources' look for "for_compilation..." and append it
	foreach folder in `sources_folders' {

		// skip marked folders
		if "`folder'" == "" | substr("`folder'", 1, 1) == "_" | regexm(substr("`folder'", 1, 1), "[0-9]$")  | substr("`folder'", 1, 1) == "." {   
			continue
		}
		
		// get list of subfolders. skip folder if it's at the wrong level (if it may contain source data) 
		local subfolders: dir "`sourcesDirectory'/`folder'" dirs "*", respectcase 
		local subfolders: list sort subfolders
		foreach source in `subfolders'{
			// skip erroneous folders
			if "`source'" == "" | substr("`source'", 1, 1) == "_" | regexm(substr("`source'", 1, 1), "[0-9]$")  | substr("`source'", 1, 1) == "." {
				continue
			}
	
			// check for "for_compilation..." of the data type
			clear 
			local checkFile "`sourcesDirectory'/`folder'/`source'/data/final/for_compilation_`dataType'.dta"
			capture confirm file "`checkFile'"
			
			// if found, append and save
			if !_rc{
				noisily display "FOUND `source'_`dataType'!"
				use "`sourcesDirectory'/`folder'/`source'/data/final/for_compilation_`dataType'.dta", clear
				if $newLoop == 0 {
					di "appending"
					quietly append using "$tempFolder/tempData"
					save "$tempFolder/tempData", replace
				}
				else {
					save "$tempFolder/tempData", replace
					global newLoop = 0
				}
			}
		}	
	}
	
	// Save
		use "$tempFolder/tempData", clear
		duplicates drop
		compress
		save "`database_folder'/compiled_cancer_`dataType'.dta", replace
		capture saveold "`database_folder'/compiled_cancer_`dataType'.dta", replace
		save "`database_folder'/_archive/compiled_cancer_`dataType'_`today'.dta", replace
		capture saveold "`database_folder'/_archive/compiled_cancer_`dataType'_`today'.dta", replace
}

** ****************************************************************
** CLOSE
** ****************************************************************		
	capture log close compile

** ****************************************************************
** End compile_by_type.do
** ****************************************************************		
