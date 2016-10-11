
// Purpose:	Merge incidence and mortality data from the same source and refine string values

** **************************************************************************
** Configuration
** 		Sets application preferences (memory allocation, variable limits) 
** 		Accepts/Sets Arguments. Defines the J drive location.
** **************************************************************************
// Clear memory and set memory and variable limits
	clear all
	set maxvar 32000
	set more off
	
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" global j "J:"


** **************************************************************************
** SET DATE AND DIRECTORIES
** **************************************************************************
// Accept Arguments
args today directory skipMerge
			
// // SET  LOCALS	
	// Set arguments if no arguments are passed
	if "`today'" == "" {
		// Get date
		local today = date(c(current_date), "DMY")
		local today = string(year(`today')) + "_" + string(month(`today'),"%02.0f") +"_"+ string(day(`today'),"%02.0f")
	}	
		// Directory
	if "`directory'" == "" 	local directory = "$j/WORK/07_registry/cancer/02_database/01_mortality_incidence" 
	
// set output_folder
	local output_folder = "`directory'/data/intermediate"

// Preferred registry names
	local preferred_registry_names = "$j/WORK/07_registry/cancer/00_common/data/preferred_registry_names.dta"

// Location IDs Script
	local get_location_ids = "$j/WORK/07_registry/cancer/00_common/code/get_location_ids.do"	
	
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
	capture log close refine
	log using "`log_folder'/02_MaR_`today'.log", replace name(refine)
}

** ****************************************************************
** GET EXTRA RESOURCES
** ****************************************************************
// Set subnationally modeled iso3s
	use "$j/WORK/07_registry/cancer/00_common/data/subnationally_modeled.dta"
	di "Subnational Data"
	levelsof subnationally_modeled_iso3, clean local(subnationally_modeled_iso3s)

** ****************************************************************
** DEFINE PROGRAMS
** ****************************************************************
 // set program to generate merge_source variable
program generate_merge_source  
	
	// generate merge_source
	gen locationOfYear = strpos(source, "_1")
	replace locationOfYear = strpos(source, "_2") if (strpos(source, "2") < strpos(source, "1")) | locationOfYear == 0
	gen merge_source = substr(source, 1, locationOfYear - 1)
	replace merge_source = source if merge_source == ""
	drop locationOfYear
	
	// check for duplicates
	duplicates tag merge_source iso3 subdiv registry sex acause year*, gen(tag)
	count if tag != 0
	if r(N) > 0 {
		noisily di "Error in merge process."
		noisily di "Please ensure that all data from the same source shares a common naming schema"
		noisily di "and that there is no data redundancy from a single source (by iso3, subdiv, registry, sex, acause, and year)."
		BREAK
	}
	drop tag
	
end

** ****************************************************************
** MERGE DATA
** ****************************************************************	
// // Get INC data and Reformat to enable merge
	use "`directory'/data/raw/compiled_cancer_inc.dta", clear
	keep acause source iso3 subdiv location_id NID registry sex year* gbd_iteration national cases* pop*
	collapse(sum) cases* (mean) pop*, by(acause source iso3 subdiv location_id NID registry sex year* gbd_iteration national)
	
	// Drop Duplicates and Save
	rename NID nidINC
	generate_merge_source		// NOTE: generates merge_source variable
	rename source sourceINC
	gen dataINC = 1
	tempfile incData
	save `incData', replace

// // Get MOR data
	use "`directory'/data/raw/compiled_cancer_mor.dta", clear
	keep acause source iso3 subdiv location_id NID registry sex year* gbd_iteration national deaths* pop*
	collapse(sum) deaths* (mean) pop*, by(acause source iso3 subdiv location_id NID registry sex year* gbd_iteration national)

	// Drop Duplicates and Merge
	rename NID nidMOR
	generate_merge_source 	 // NOTE: generates merge_source variable
	rename source sourceMOR
	gen dataMOR = 1
	
// Merge data from the same source
	merge 1:1 merge_source iso3 subdiv location_id registry sex acause year* gbd_iteration national using `incData', nogen
	rename merge_source source
	replace source = sourceMOR if sourceINC == "" 
	replace source = sourceINC if sourceMOR == "" 
	
// Add dataType Variable
	replace dataINC = 0 if dataINC == .
	replace dataMOR = 0 if dataMOR == .
	replace dataINC = 1 if dataINC >= 1
	replace dataMOR = 1 if dataMOR >= 1
	gen dataType = 1 if dataINC == 1 & dataMOR == 1
	replace dataType = 2 if dataINC == 1 & dataMOR < 1
	replace dataType = 3 if dataINC < 1 & dataMOR == 1
	drop dataINC dataMOR
	duplicates drop

// Save
	compress
	save "`output_folder'/01_merged.dta", replace
	saveold "`output_folder'/_archive/01_merged_`today'.dta", replace

** ****************************************************************
** REFINE
** ****************************************************************	
// Generate year_average and Calculate span
	gen year_span = year_end - year_start + 1
	gen year = floor((year_start + year_end)/2)

// round data to a small decimal to ensure that duplicative data are dropped
	foreach v of varlist cases* deaths* pop* {
		replace `v' = round(`v', 0.000000001)
	}
		
// Correct causes
	replace acause = "neo_leukemia_ll_acute" if acause == "neo_leukemia_all"
	replace acause = "neo_leukemia_ll_chronic" if acause == "neo_leukemia_cll"
	replace acause = "neo_leukemia_ml_acute" if acause == "neo_leukemia_aml"
	replace acause = "neo_leukemia_ml_chronic" if acause == "neo_leukemia_cml"
	
// Reformat subdivisions
	gen raw_subdiv = subdiv
	replace subdiv = itrim((strproper(subdiv)))

// // Reformat Registry Names
	// Alert if registry information is missing
		count if registry == ""
		if r(N) > 0 {
			pause on
			noisily di "Error: some registry entries are missing!"
			pause
			pause off
		}
	
	// // Remove Country Names from Registry Names and Mark national data
		// Get country names
		preserve
			do "`get_location_ids'"
			keep location_id country
			tempfile country_names
			save `country_names', replace
		restore
		
		// mark registries equal to the name of the country as national registries
			merge m:1 location_id using `country_names', keep(1 3) nogen
			replace national = 1 if registry == country
			drop country
	
		// Format National registries
			replace registry = "National Registry" if regexm(registry, "National")
			replace national = 1 if registry == "National Registry"
			replace registry = "National Registry" if national == 1
		
	// merge with preferred registry names, if listed
		replace subdiv = "." if subdiv == ""
		merge m:1 iso3 subdiv registry using `preferred_registry_names', keep(1 3) nogen
		replace registry = preferred_registry if preferred_registry != ""
		drop preferred
		replace subdiv = "" if subdiv == "." | upper(subdiv) == "NA"
	
	// Flag GLOBOCAN data for removal in drop_andCheck.do
		replace registry = "GLOBOCAN Estimate" if regexm(source, "GLOBOCAN")
	
	// Remove extra spaces
		replace registry = trim(itrim(registry)) 

	// Alert if registry information is missing
		count if registry == ""
		if r(N) > 0 {
			pause on
			noisily di "Error: some registry entries are missing!"
			pause
			pause off
		}

// Drop extraneous data before save
	drop raw_* 
	duplicates drop

** ****************************************************************
** SAVE and CLOSE
** ****************************************************************		
	compress
	save "`output_folder'/02_registries_refined.dta", replace
	save "`output_folder'/_archive/02_registries_refined_`today'.dta", replace 
	capture log close refine

** ****************************************************************
** End merge_andRefine.do
** ****************************************************************		
