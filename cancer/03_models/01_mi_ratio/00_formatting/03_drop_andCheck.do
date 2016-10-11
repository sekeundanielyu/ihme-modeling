
// Purpose:	Drop redundant or unmatched cancer data according to defined rules. Alert user of errors.
			
** **************************************************************************
** Configuration
** 		Sets application preferences (memory allocation, variable limits) 
** 		Accepts/Sets Arguments. Defines the J drive location.
** **************************************************************************
// Clear memory and set memory and variable limits
	clear all
	set more off
	
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
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
		local start_time = c(current_time)
		local archive_time = subinstr("`c(current_time)'",":","",.)
		global archive_time = substr("`archive_time'", 1, length("`archive_time'") -2)
	}		
	
// Set folders
	if "$directory" == "" global directory = "$j/WORK/07_registry/cancer/02_database/01_mortality_incidence" 
	global code_folder = "$directory/code"
	global subroutines = "$code_folder/subroutines"
	local output_folder = "$directory/data/intermediate"
	global dropped_list = "`output_folder'/dropped_data/03_dropped_data_$today.dta"
	capture rm "$dropped_list"

// make temp folder
	global temp_folder = "$j/temp/registry/cancer/02_database/01_mortality_incidence"
	cap mkdir "$j/temp/registry/cancer/02_database"
	cap mkdir "$temp_folder"
	if "$j" == "J:"	global keepBest_temp = "$temp_folder"
	else global keepBest_temp = "/ihme/gbd/WORK/07_registry/cancer/02_database/01_mortality_incidence/mi_KB_temp"
	capture mkdir "$keepBest_temp"
	
** ****************************************************************
** Create Log if running on the cluster
** 		Get date. Close open logs. Start Logging.
** ****************************************************************
// Get date
	local today = date(c(current_date), "DMY")
	local today = string(year(`today')) + "_" + string(month(`today'),"%02.0f") + "_" + string(day(`today'),"%02.0f")

if c(os) == "Unix" {
// Log folder
	local log_folder "/ihme/gbd/WORK/07_registry/cancer/logs/02_database/01_mortality_incidence"
	cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs"
	cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs/02_database"
	cap mkdir "`log_folder'"
	
// Begin Log
	capture log close drops
	log using "`log_folder'/03_DaC_$today.log", replace name(drops)
}

** ****************************************************************
** GET EXTRA RESOURCES
** ****************************************************************
// Create a list of subnationally modeled iso3s
	use "$j/WORK/07_registry/cancer/00_common/data/subnationally_modeled.dta", clear
	di "Subnational Data"
	levelsof subnationally_modeled_iso3, clean local(subnationally_modeled_iso3s)	
	
** ****************************************************************
** DEFINE PROGRAMS
** ****************************************************************	
global recordDropReason "$subroutines/recordDropReason.do" 
global runKeepBest "$subroutines/KeepBest.do" 

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

// // Define callKeepBest: calls the KeepBest script. 
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
		
// // Define AlertIfOverlap Function: pauses the script if redundancies are present 
program AlertIfOverlap
	duplicates tag sex iso3 subdiv registry acause year, gen(overlap)
	gsort -overlap +sex +iso3 +subdiv +registry +acause +year 

	// Alert user if tags remain
	capture inspect(overlap)
	if r(N_pos) > 0 {
		sort overlap sex iso3 acause year registry source
		display in red "Alert: Redundant Registry-Years are Present"
		pause on
		pause
		pause off
	}
	drop overlap

end

** ****************************************************************************
** PART 1: Load Data and Drop Known Errors
** *****************************************************************************	
// Get Data
	use "`output_folder'/02_registries_refined.dta", clear	
	capture drop tag
	foreach n of numlist 91/94 {
		capture drop pop`n'
		capture drop deaths`n'
		capture drop cases`n'
	}
	duplicates drop
	
// Keep Only the Data of Interest
	keep if substr(acause,1,4) == "neo_"
	drop if regexm(acause,"benign")

// Drop if missing all data from the data type, or if CI5 and data sums to zero
	foreach v of varlist cases* deaths*{
		replace `v' = . if `v' < 1
	}
	
// Recalculate metric totals
	drop cases1 deaths1 pop1
	egen cases1 = rowtotal(cases*), missing
	egen deaths1 = rowtotal(deaths*), missing
	egen pop1 = rowtotal(pop*)
	
// Change data type if data type from "both" if all entries are missing from one of the metrics
	replace dataType = 3 if dataType == 1 & cases1 == .
	replace dataType = 2 if dataType == 1 & deaths1 == .
	
// Drop if missing all entries from the data type
	drop if (dataType == 2 & cases1 == .) | (dataType == 3 & deaths1 == .)
	
// Drop if data is from CI5 and the total number of cases or deaths is zero or NULL
	drop if dataType == 1 & upper(substr(source, 1, 3)) == "CI5" & (cases1 == . | cases1 == 0)
	drop if dataType == 1 & upper(substr(source, 1, 3)) == "CI5" & (cases1 == . | cases1 == 0)
	
// Replace any remaining missing entries with "0"
	foreach v of varlist cases* deaths* pop* {
		replace `v' = 0 if `v' == .
	}
	
// Drop GLOBOCAN Estimates (estimates should not be used)
	drop if regexm(source, "GLOBOCAN") | registry == "Globocan Estimate"
	
// Drop data with known errors
	do  "$subroutines/drop_known_outliers.do"
	
** ****************************************************************************
** PART 2:  Drop Within-Source Duplications
** *****************************************************************************		
// Keep within-source redundancies with the smallest year-span 
	// Find redundancies
	sort dataType source iso3 location_id subdiv sex registry acause year
	egen uid = concat(dataType source iso3 location_id subdiv sex registry acause year), punct("_")
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
// // Keep National Data where possible
	// Generate uid
	quietly {
		sort iso3 source registry year sex acause dataType
		egen uid = concat(iso3 year sex acause dataType), punct("_")	
		sort uid
		gen toDrop = 0
		gen dropReason = ""
	}

	// Keep national data in lieu of any other data if the country is not modeled subnationally
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
	
	// compress and save
		compress
		save "$temp_folder/03_first_save.dta", replace

** ****************************************************************
** PART 4: Merge Incidence-only and Mortality-only Data by registry-year where possible
** ****************************************************************
// // Separate INC-only: check for redundancy and rename identifiers
	// Keep INC-only
		use "$temp_folder/03_first_save.dta", clear	
		keep if dataType == 2
		drop *MOR deaths*
		
	// Drop registry-cause-years that are missing all data
		sort iso3 registry year sex
		egen uid = concat(iso3 subdiv registry year sex), punct("_")
		gen toDrop = 0
		replace toDrop = 1 if cases1 == .
		if r(N) >0 {
			gen dropReason = "incidence dataset contained no incidence for this location-sex-year-cause " if toDrop == 1
			// Record drop reason, then drop
			run "$recordDropReason" "1" "$directory" "$today"
			drop if toDrop == 1
			drop uid dropReason
		}
		drop toDrop
		
	// Save file for use with leukemia data in part 4b
		preserve
			keep if regexm(acause, "neo_leukemia_")
			capture count
			if r(N) > 0	{
				save "$temp_folder/leukemia_data.dta", replace
				local prioritize_leukemia = 0
			}
			else prioritize_leukemia = 1
		restore
		
	// Run KeepBest
		callKeepBest "INC Only"
		
	// Alert user of remaining data overlaps 
		AlertIfOverlap
	
	// Finalize INC-only
		drop source dataType
		capture rename gbd_iteration gbdINC
		save "$temp_folder/INConly.dta", replace 

// // MOR-only: check for redundancy and rename identifiers
	// Keep Mor-only
		use "$temp_folder/03_first_save.dta", clear	
		keep if dataType == 3
		drop *INC cases* pop*
		
	// Drop registry-cause-years that are missing all data
		sort iso3 registry year sex
		egen uid = concat(iso3 subdiv registry year sex), punct("_")
		gen toDrop = 0
		replace toDrop = 1 if deaths1 == .
		if r(N) >0 {
			gen dropReason = "mortality dataset contained no information for this location-sex-year-cause " if toDrop == 1
			// Record drop reason, then drop
			run "$recordDropReason" "1" "$directory" "$today"
			drop if toDrop == 1
			drop uid dropReason
		}
		drop toDrop
		
	// Run KeepBest
		callKeepBest "MOR Only"
		
	// Alert user of remaining data overlaps
		AlertIfOverlap
		
	// Finalize MOR-only
		drop source dataType
		capture rename gbd_iteration gbdMOR
		save "$temp_folder/MORonly.dta", replace 
		** use "$temp_folder/MORonly.dta", clear
	
// // Merge INC-only/MOR-only and keep only matching registries
	// merge
		merge 1:1 iso3 registry subdiv sex year* acause national using "$temp_folder/INConly.dta"
	
	// Record drop reason, then drop un-merged data
		gen toDrop = 0
		replace toDrop = 1 if _merge != 3
		capture count if toDrop == 1
		if r(N) > 0 {
			noisily di "Removing Unmatched Data..."
			gen dropReason = "uid does not have matching inc/mor data" if toDrop == 1
			egen uid = concat(iso3 registry year sex), punct("_")
			gen dataType = .
			capture drop gbd_iteration
			gen gbd_iteration = round((gbdINC + gbdMOR)/2)
			gen source = sourceINC if deaths1 == . & cases1 != .
			replace source = sourceMOR if cases1 == . & deaths1 != .
			run "$recordDropReason" "1" "$directory" "$dropped_list" "$today"
			drop if toDrop == 1
			drop dropReason uid source dataType gbd_iteration
		}
		drop toDrop
	
// save combined data
	gen dataType = 1
	egen source = concat(sourceINC sourceMOR), punct(" & ")
	count if sourceINC == "" | sourceMOR == ""
	// alert user if source information is missing
	if r(N) > 0 {
		pause on
		di "ERROR: some source information was lost during the INConly/MORonly merge"
		pause
		pause off
	}
	drop _merge
	egen merge_gbd = rowmean(gbd*)
	drop gbd*
	rename merge_gbd gbd_iteration 
	compress
	save "$temp_folder/03_second_save.dta", replace

** ****************************************************************
** PART 5: Append Merged Incidence-only and Mortality-only Data where possible
** ****************************************************************				
// Append Merged INC/MOR Data to data of which INC/MOR are from the same source
	use "$temp_folder/03_first_save.dta", clear
	keep if dataType == 1 
	tab acause
	append using "$temp_folder/03_second_save.dta"
	replace dataType = 1
	tab acause
	compress
	save "$temp_folder/03_third_save.dta", replace

// Run KeepNational and KeepBest on the recombined data to eliminate redundancies
	use "$temp_folder/03_third_save.dta", clear
	sort iso3 registry year sex
	egen uid = concat(iso3 subdiv registry year sex), punct("_")		
	callKeepBest "INC & MOR"

// Save	
	compress
	save "$temp_folder/03_fourth_save.dta", replace

** ****************************************************************
** Part 4b (temporary): Add Leukemia Subtype Data if Prioritized
** ****************************************************************
if `prioritize_leukemia' == 1 {
	// collapse to national numbers
		use "$temp_folder/leukemia_data.dta", clear	
		callKeepBest "Only dropped for leukemia data. See part 4b of 03_drop_andCheck.do" 
		collapse (sum) cases* pop*, by(iso3 sex year acause sourceINC national)
		duplicates tag iso3 sex year acause, gen(has_national)
		drop if has_national != 0
		dro[p national
		
	// calculate rates
		foreach n of numlist 1 2 7/22 {
			gen rate`n' = cases`n'/pop`n'
		}
		drop cases* pop*
		tempfile leukemia_rates
		save `leukemia_rates', replace
		
	// Get leukemia subtype data
		use "$j/WORK/07_registry/cancer/01_inputs/sources/COD_VR/COD_VR/data/final/for_compilation_mor.dta", clear
		keep if substr(acause, 1, 13) == "neo_leukemia_"
		collapse (sum) deaths* pop*, by(iso3 sex year_start acause source)
		rename (year_start source) (year sourceMOR)
		
	// Merge with incidence
		merge 1:1 iso3 sex year acause using `leukemia_rates', keep(3) nogen
		foreach n of numlist 2 7/22 {
			gen cases`n' = rate`n'*pop`n'
		}
		drop rate
		gen subdiv = ""
		gen national = 1
		gen registry = iso3 + " National Registry"
		gen leukemia_data = 1
		gen source = sourceINC + " & " + sourceMOR
		gen registry = "Recombined Leukemia Subtype Data"
		
	// Add missing location information
		append using "$temp_folder/03_fourth_save.dta"
		duplicates tag iso3 sex year acause, gen(tag)
		drop if substr(acause, 1, 13) == "neo_leukemia_" & leukemia_data != 1
		drop tag leukemia_data
}
else use "$temp_folder/03_fourth_save.dta", clear 

** ****************************************************************
** Part 5: Check for Remaining Redundancy 
** ****************************************************************			
// Check again for Redundancy
	AlertIfOverlap

** ****************************************************************
** OUTPUT DATA
** ****************************************************************	
// Drop Irrelevant/Empty Columns
	capture drop pop_year
	foreach n of numlist 3/6 23/26 91/94{
		capture drop cases`n'
		capture drop deaths`n'
		capture drop pop`n'
	}
	
// Display runtime		
	local end_time = c(current_time)
	di "Program ran from `start_time' to `end_time'"
	
// Save
	compress
	save "`output_folder'/03_redundancies_dropped.dta", replace
	save "`output_folder'/_archive/03_redundancies_dropped_$today.dta", replace 
	capture log close drops
	
** ****************************************************************
** End drop_andCheck.do
** ****************************************************************		                                                                                                                                                                                                                         
