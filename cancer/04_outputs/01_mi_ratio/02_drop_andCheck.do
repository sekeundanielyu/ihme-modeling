** *************************************************************************
// Purpose:	Drop redundant or unmatched cancer data according to defined rules. Alert user of errors.
** *************************************************************************

** **************************************************************************
** Configuration
** 		Sets application preferences (memory allocation, variable limits) 
** 		Accepts/Sets Arguments. Defines the J drive location.
** **************************************************************************
// Clear memory and set memory and variable limits
	clear all
	set more off
	
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix"{
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" global j "J:"
	
// Accept Arguments
	args today username
	if "`username'" == "" local username = "cmaga"
	
** **************************************************************************
** SET DATE AND DIRECTORIES
** **************************************************************************	
// Set date	
	if "$today" == "" {
		local today = date(c(current_date), "DMY")
		global today = string(year(`today')) + "_" + string(month(`today'),"%02.0f") +"_"+ string(day(`today'),"%02.0f")
		}		

// Set folders	
	if "$directory" == "" global directory = "$j/WORK/07_registry/cancer/04_outputs/01_mortality_incidence"

	global code_folder = "$directory/code"
	global subroutines = "$code_folder/subroutines"
	local incidence_input_folder = "$j/WORK/07_registry/cancer/02_database/01_mortality_incidence/data/intermediate"
	local input_folder = "$directory/data/intermediate"
	local output_folder = "$directory/data/final"
	global temp_folder = "$j/temp/registry/cancer/04_outputs/01_mortality_incidence"
		
	global dropped_list = "`input_folder'/dropped_data/02_dropped_data_$today.dta"
	capture rm "$dropped_list"
	
// make temp folder
	global temp_folder = "$j/temp/registry/cancer/04_outputs/01_mortality_incidence"
	cap mkdir "$j/temp/registry/cancer/04_outputs"
	cap mkdir "$temp_folder"
	if "$j" == "J:"	global keepBest_temp = "$temp_folder"
	else global keepBest_temp = "/ihme/gbd/WORK/07_registry/cancer/04_outputs/01_mortality_incidence/mi_KB_temp"
	capture mkdir "$keepBest_temp"

** ****************************************************************
** Create log if running on the cluster
** ****************************************************************
if c(os) == "Unix" {
	// Log folder
		local log_folder "/ihme/gbd/WORK/07_registry/cancer/logs/04_database/01_mortality_incidence"
		cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs"
		cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs/04_database"
		cap mkdir "`log_folder'"
		
	// Begin Log
		capture log close drops
		log using "`log_folder'/02_PCI_$today.log", replace name(drops)
}

** ****************************************************************
** GET EXTRA RESOURCES
** ****************************************************************
// Create a list of subnationally modeled iso3s
	use "$j/WORK/07_registry/cancer/00_common/data/subnationally_modeled.dta", clear 
	di "Subnational Data"
	levelsof subnationally_modeled_iso3, clean local(subnationally_modeled_iso3s)
	global subnationally_modeled_iso3s = "`subnationally_modeled_iso3s'"

** ****************************************************************
** DEFINE PROGRAMS
** ****************************************************************	
global recordDropReason "$subroutines/recordDropReason.do" 
global runKeepBest "$subroutines/KeepBestCoD.do" 

// Define AlertIfAllDropped: Alerts user if all data is dropped for the given id .
program AlertIfAllDropped 
	args id section uid
	
	capture count if groupid == `id' & toDrop == 0
	if r(N) == 0 {
		pause on
		di in red "All registries dropped for `uid' (id `id') during `section'"
		pause
		pause off
	}

end

// // Define callKeepBest: calls the KeepBest Script. 
program callKeepBest
	
	args section

	// Sort
		noisily di "Preparing Variables..."
		sort source
		sort uid
		
	// Run KeepBest
		do $runKeepBest `section'	
		use "$keepBest_temp/kept_best.dta", clear
		drop uid
end

** ****************************************************************************
** PART 1: Load Data, Drop Known Errors, Drop Known Deaths
** *****************************************************************************	
// Get Data
	use "`incidence_input_folder'/02_registries_refined.dta", clear	
	capture drop tag
	
// Drop Mortality data	
	drop if dataType == 3
	drop dataType
	
// Drop GLOBOCAN data (estimates should not be used)
	drop if regexm(source, "GLOBOCAN") | registry == "Globocan Estimate"

// Keep Only the Data of Interest (only mapped, malignant causes - no benign causes)
	keep if substr(acause,1,4) == "neo_"
	drop if regexm(acause,"benign")
	foreach n of numlist 91/94 {
		capture drop pop`n'
		capture drop cases`n'
	}
	
// Drop if all entries are missing or if zero cases are reported by a CI5 source
	drop cases1
	egen cases1 = rowtotal(cases*), missing
	gen toDrop = 1 if cases1 == . | (cases1 == 0 & substr(source, 1, 3) == "CI5")
	// Drop data
	gen dropReason = "no data"
	egen uid = concat(iso3 subdiv registry year sex), punct("_")
	noisily di "Removing data-years with no actual data"
	run "$recordDropReason" "preliminary drop and check" "$directory" "$dropped_list" "$today"
	drop if toDrop == 1
	drop toDrop uid dropReason
	
// Drop deaths
	drop deaths* *MOR
	replace source = sourceINC if sourceINC != ""
	rename nidINC NID
	
// Drop known outliers
	do "$subroutines/gbd_2015_known_outliers.do"
	
** ****************************************************************************
** PART 2:  Drop Within-Source Duplications
** *****************************************************************************		
// Keep within-source redundancies with the smallest year-span
	// Find redundancies
	sort source iso3 location_id subdiv sex registry acause year
	egen uid = concat(source iso3 location_id subdiv sex registry acause year), punct("_")
	duplicates tag uid, gen(duplicate)
	bysort uid: egen smallestSpan = min(year_span)
	
	// Mark non-best data
	gen toDrop = 0 if duplicate == 0
	replace toDrop = 0 if year_span == smallestSpan & duplicate > 0
	replace toDrop = 1 if year_span != smallestSpan & duplicate > 0
	gen dropReason = "data in same source has smaller year span" if toDrop == 1
	
	// Drop data
	noisily di "Removing Within-Source Redundancy"
	run "$recordDropReason" "drop within source redundancy" "$directory" "$dropped_list" "$today"
	drop if toDrop == 1
	
	drop uid duplicate toDrop dropReason smallestSpan
		
** ****************************************************************************
** PART 3: Keep National Data
**  			Keep subnational data if present. Then keep remaining national data if present. (see KeepNational above)
** *****************************************************************************			
// // Keep national data where possible
	// create uid
	quietly {
		sort iso3 source registry year sex acause
		egen uid = concat(iso3 year sex), punct("_")	
		sort uid
		gen toDrop = 0
		gen dropReason = ""
	}

	// mark national data if present. Mark non-national data if national data are present
	// make exceptions for sub-nationally modeled data
	bysort uid: egen has_national = total(national)
	foreach subMod in `subnationally_modeled_iso3s' {
		di "`subMod'"
		replace has_national = 0 if iso3 == "`subMod'"
	}
	replace toDrop = 1 if has_national > 0 & national != 1

	// record drop reason and drop data
	capture count if toDrop == 1
	if r(N) > 0 {
		noisily di "Removing Redundant Data..."
		run "$recordDropReason" "Keep National" "$directory" "$dropped_list" "$today"
		drop if toDrop == 1
	}
	drop uid dropReason toDrop has_national

// // Drop national data if subnational data cover national 
	// 
		gen subnat = 1 if subdiv != ""
		bysort iso3 year sex acause: egen has_subnat = total(subnat)
		drop if inlist(iso3, "USA", "SWE") & national == 1 & has_subnat > 0
		drop subnat has_subnat

	// compress and save
		compress
		save "$temp_folder/02_first_save.dta", replace

** ****************************************************************
** PART 4: Compare Registry-Years and Drop Remaining Redundant data
** ****************************************************************                       
// // Mark and Drop Other Redundancies: Create UID and run KeepBest
	sort iso3 registry year sex
	egen uid = concat(iso3 registry year sex), punct("_")
	callKeepBest "KeepBest"
	compress
	save "$temp_folder/02_second_save.dta", replace 

** ****************************************************************
** Part 5: Check for Remaining Redundancy and Save
** ****************************************************************			
// Check Redundancy
	// tag duplicates
	duplicates tag sex iso3 registry acause year, gen(overlap)
	gsort -overlap +sex +iso3 +registry +acause +year 

	// Alert user if tags exist
	capture inspect(overlap)
	if r(N_pos) > 0 {
		sort overlap sex iso3 acause year registry source
		display in red "Alert: Redundant Registry-Years are Present"
		pause on
		pause
		pause off
	}
	drop overlap
	
// // Check for source redundancies by only iso3-year
	// create uids
	egen uid = concat(iso3 subdiv year sex acause), punct("_")
	capture drop groupid
	egen groupid = group(uid)
	capture levelsof groupid, clean local(uids) 
	
	// check each uid for duplicates
	foreach id in `uids' {
		// skip sub-nationally moelded data
		if regexm(substr(uid_group, 1, 3), "$subnationally_modeled_iso3s") continue
		// count if more than one source exists per group id
		bysort groupid: gen nSources = _n == 1 & groupid == `id'
		capture count if nSources == 1
		if r(N) > 1 { 
			global problemGroups = "$problemGroups `uid'"
		}
		drop nSources
	}
	
	// Alert user if redundancies exist
	if "$problemGroups" != "" {
		di "Possible redundancies exist for the following uids: $problemGroups"
		pause on
		pause
		pause off
	}
	drop uid groupid

	
// SAVE
	compress
	saveold "`input_folder'/02_CoD_incidence_data.dta", replace
	save "`input_folder'/_archive/02_CoD_incidence_data_$today.dta", replace

** *******
** END
** *******

