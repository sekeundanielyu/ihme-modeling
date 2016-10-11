
// Purpose:	Finalize formatting for upload into database and use by models

** **************************************************************************
** CONFIGURATION (autorun)
** 		Sets application preferences (memory allocation, variable limits) 
** 		Accepts/Sets Arguments. Defines the J drive location.
** **************************************************************************
// Clear memory and set memory and variable limits
	clear all
	set maxvar 32000
	set more off

// Accept Arguments
	args group_folder data_name data_type 	
	
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"	
		
	if "`group_folder'" != "" & "`group_folder'" != "none" local data_folder = "$j/WORK/07_registry/cancer/01_inputs/sources/`group_folder'/`data_name'"  // autorun
	else local data_folder = "$j/WORK/07_registry/cancer/01_inputs/sources/`data_name'"  // autorun
		
** ****************************************************************
** Set Macros
**	Data Types, Folder and Script Locations
** ****************************************************************
// Metric variable
	if "`data_type'" == "inc" local metric_name = "cases"
	if "`data_type'" == "mor" local metric_name = "deaths"

// Input Folder
	local input_folder = "`data_folder'/data/intermediate"

// Output folder
	local output_folder "`data_folder'/data/final"
	local archive_folder "`output_folder'/_archive"
	capture mkdir "`output_folder'"
	capture mkdir "`archive_folder'"
	
** ****************************************************************
** Create Log if running on the cluster
** 		Get date. Close open logs. Start Logging.
** ****************************************************************
// Get date
	local today = date(c(current_date), "DMY")
	local today = string(year(`today')) + "_" + string(month(`today'),"%02.0f") + "_" + string(day(`today'),"%02.0f")

if c(os) == "Unix" {
	// Log folder
		local log_folder "/ihme/gbd/WORK/07_registry/cancer/logs/01_inputs/finalize_prep"
		cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs"
		cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs/01_inputs"
		cap mkdir "`log_folder'"

	// Start Log
		capture log close
		capture log using "`log_folder'/08_finalize_`data_type'_`today'.log", replace
}

** ******************************************************************
**  COMPILE
** ******************************************************************
// Get POP data
	capture confirm file "`input_folder'/04_age_sex_split_`data_type'_pop.dta"
	if !_rc {
		use "`input_folder'/04_age_sex_split_`data_type'_pop.dta", clear
		count if pop1 != .
		if r(N) == 0 local merge_pop = 0
		else local merge_pop = 1
	}
	else BREAK

	// Reformat Identifiers
		replace location_id = . if location_id == 0
		replace NID = . if NID == 0
		tostring(subdiv), replace
		replace subdiv = "" if subdiv == "0"
	
	// Save
		compress
		tempfile pop_data
		save `pop_data', replace

// Get RDP data
	capture confirm file "`input_folder'/07_redistributed_`data_type'.dta"
	if !_rc use "`input_folder'/07_redistributed_`data_type'.dta", clear
	else BREAK
	compress

// Change "cases" back to "deaths" for mortality data
	if "`data_type'" == "mor" {
		quietly foreach var of varlist *cases* {
			local nn = subinstr( "`var'", "cases", "deaths", .)
			rename `var' `nn'
		}
	}	

// Reformat Identifiers
	replace location_id = . if location_id == 0
	replace NID = . if NID == 0
	replace subdiv = "" if subdiv == "0" | subdiv == "."

// Drop RDP remnants
	drop if acause == "rdp_remnant"
	
// Collapse data if more than one code type was formatted
	keep `metric_name'* source iso3 subdiv location_id registry year* sex acause  gbd_iteration national NID coding_system
	collapse (sum) `metric_name'*, by(source iso3 subdiv location_id registry year* sex acause gbd_iteration national NID coding_system)
 
// Merge with pop data
	if `merge_pop' merge m:1 iso3 subdiv location_id national source NID registry year_start year_end sex using `pop_data', keep(1 3) nogen keepusing(pop*)
	else {
		foreach n of numlist 2 7/22 {
			gen pop`n' = 0
		}
	}
	
// Remove Negative, NULL, and Decimal Values
	quietly foreach var of varlist `metric_name'* pop* {
		count if `var' < 0 
		if r(N) {
			pause on
			di "ERROR: Some values for `var' are less than zero."
			pause
			pause off
			replace `var' = 0 if `var' < 0
		}
	}
	foreach n of numlist 1 3/6 23/26 91/94{
		capture drop `metric_name'`n'
		capture drop pop`n'
	}
	
// recalculate totals
	egen pop1 = rowtotal(pop*)
	egen `metric_name'1 = rowtotal(`metric_name'*)
	drop if `metric_name'1 == 0 & pop1 == 0
	capture drop pop0
	
// Check for duplicates 
capture drop tag
duplicates tag source iso3 subdiv location_id registry sex acause year_start year_end coding_system, gen(tag)
count if tag != 0
if r(N) > 0  {
	pause on
	noisily di in red "Pausing script. Duplicate entries exist for the same source iso3 subdiv location_id registry sex acause and year."
	pause
	pause off
}
drop tag
	
// SAVE
	compress
	save "`output_folder'/for_compilation_`data_type'.dta", replace
	save "`output_folder'/_archive/for_compilation_`data_type'_`today'.dta", replace
	
capture log close

** **************************************************************************
** END pre_compile.do
** **************************************************************************


