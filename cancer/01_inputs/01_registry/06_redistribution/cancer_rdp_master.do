
// Purpose:		submit redistribution to IHME cluster

** **************************************************************************
** CONFIGURATION
** **************************************************************************
// Clear memory and set memory and variable limits
	clear all
	set mem 10G
	set maxvar 32000

// Set to run all selected code without pausing
	set more off

// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" global j "J:"

** ****************************************************************
** DEFINE LOCALS
** ****************************************************************
args group_folder data_name data_type resubmit


local troubleshooting = 0
local location_set_version_id 38

// Main Folders
	local data_folder = "$j/WORK/07_registry/cancer/01_inputs/sources/`group_folder'/`data_name'"
	local programs_folder = "$j/WORK/07_registry/cancer/01_inputs/programs"
	local map_folder = "/ihme/gbd/WORK/07_registry/cancer/01_inputs/rdp/maps"

// Input file
	local input_file "`data_folder'/data/intermediate/06_pre_rdp_`data_type'.dta"

// Output folders
	local output_folder "`data_folder'/data/intermediate"
	capture mkdir "`output_folder'"
	capture mkdir "`output_folder'/_archive"

// Bad Code storage
	local bad_code_folder = "$j/temp/registry/cancer/01_inputs/_rdp_problem_codes"
	cap mkdir "$j/temp/registry/cancer/01_inputs"
	cap mkdir "`bad_code_folder'"

// // Temporary folder
	// define temp_folder
	local temp_folder "/ihme/gbd/WORK/07_registry/cancer/01_inputs/rdp/`group_folder'/`data_name'/`data_type'"
	
	// ensure that the temporary filepath exists
	capture mkdir "/ihme/gbd/WORK/07_registry/cancer/01_inputs"
	capture mkdir "/ihme/gbd/WORK/07_registry/cancer/01_inputs/rdp"
	capture mkdir "/ihme/gbd/WORK/07_registry/cancer/01_inputs/rdp/`group_folder'"
	capture mkdir "/ihme/gbd/WORK/07_registry/cancer/01_inputs/rdp/`group_folder'/`data_name'"
		
	// ensure that temp folder and subfolders are present
	capture mkdir "`temp_folder'"
	capture mkdir "`temp_folder'/_input_data"
	capture mkdir "`temp_folder'/_logs"
	capture mkdir "`temp_folder'/_maps"

** **************************************************************************
** Create Log
** 		Get date. Close open logs. Start Logging.
** **************************************************************************
// Log folder
	local log_folder "/ihme/gbd/WORK/07_registry/cancer/logs/01_inputs/rdp"
	cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs"
	cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs/01_inputs"
	cap mkdir "`log_folder'"

// Start Log
	capture log close
	capture log using "`log_folder'/rdp_master_`data_type'_`timestamp'.log", text replace

** ****************************************************************
** Verify that RDP needs to be run
** ****************************************************************
// Get data
	use "`input_file'", clear
		
// Determine if there are any garbage codes. If there are, proceed running redistribution, if not, just resave the data set
	count if acause !="_neo"
	if r(N) == 0 {
		save "`output_folder'/07_redistributed_`data_type'.dta", replace
		save "`output_folder'/_archive/07_redistributed_`data_type'_`timestamp'.dta", replace
		exit, clear
	}
	
** ****************************************************************
** RUN PROGRAM
** ****************************************************************
if `troubleshooting' pause on
	
// save a copy of the input acauses
	preserve
		keep location_id iso3 subdiv registry year* sex acause
		duplicates drop
		save "`temp_folder'/input_acause_list.dta", replace
	restore	

// save total events for later verification
	capture summ(cases1)
	local pre_rdp_total = r(sum)
			
// Merge with location hierarchy
	drop iso3
	capture drop region 
	capture drop dev_status
	capture confirm file "`map_folder'/location_hierarchy.dta"
	if _rc di "Missing map data. Run .../redistribution/code/get_rdp_resources.do"
	merge m:1 location_id using "`map_folder'/location_hierarchy.dta", keep(3) keepusing(location_id ihme_loc_id global dev_status super_region region country subnational_level1 subnational_level2) nogen

// save registry separately to ensure that any remaining special characters do not cause a problem in the redistribution code
	capture rm file "`temp_folder'/_maps/registries.dta"
	preserve
		keep location_id ihme_loc_id subdiv registry
		duplicates drop
		gen registry_id = _n
		tostring registry_id, replace
		save "`temp_folder'/_maps/registries.dta", replace
	restore
	merge m:1 location_id ihme_loc_id subdiv registry using "`temp_folder'/_maps/registries.dta", assert(3) nogen
	drop registry
	rename registry_id registry

// Generate groups to split
	if inlist("`data_name'", "_US_king_county_ICD10", "_US_king_county_ICD9", "_US_Counties") {
		egen split_group = group(country subdiv national source NID coding_system year_start year_end sex), missing
	}
	else {
		egen split_group = group(country subdiv national source NID coding_system year_start year_end), missing
	}
	
// Save a temporary copy
	save "`temp_folder'/_input_data/split_group_data", replace

// Reformat
	// Drop location hierarchy info to save space
		 drop ihme_loc_id global dev_status super_region region country subnational_level1 subnational_level2
	// Keep only the variables we need
		order gbd_iteration source NID registry location_id national subdiv year_start year_end sex coding_system acause cases* split_group
		keep gbd_iteration source NID registry location_id national subdiv year_start year_end sex coding_system acause cases* split_group
		
	// Add apostrophe to all string variables
		foreach var of varlist * {
			capture replace `var' = "'" + `var'
		}
		
// Split groups and submit jobs
	summ split_group
	local split_min = `r(min)'
	local split_max = `r(max)'
	if `split_max' > 1 di "Submitting scripts..."
	forvalues sg = `split_min'/`split_max' {
		// Remove old file
		if !`resubmit' {
			capture rm "`temp_folder'/split_`sg'/final/redistributed_split_`sg'.dta"
			capture rm "`temp_folder'/split_`sg'/final/redistributed_split_`sg'_collapsed.dta"
			capture rm "`temp_folder'/split_`sg'/final/redistributed_split_`sg'_complete.txt"
			capture rm "`temp_folder'/split_`sg'/final/post_rdp.dta"
			capture rm "`temp_folder'/split_`sg'/bad_codes.dta"
		}
		// Save 
			outsheet using "`temp_folder'/_input_data/split_`sg'.csv" if split_group == `sg', comma names replace
			
		// Determine memory requirement
			capture count if split_group == `sg' & (!regexm(acause, "[a-zA-Z]") | inlist(substr(acause, 1, 2), "'C", "'D"))  // count the number of entries that are not mapped to a gbd cause
			local garbage_quant = r(N)
			local memory = `garbage_quant'/4	// approximate required memory usage
			if `memory' < 6 local memory = 6 
			local slots = ceil(`memory'/2)+1
			local mem = `slots'*2
		
		// Submit job
			local checkfile = "`temp_folder'/split_`sg'/final/redistributed_split_`sg'_collapsed.dta"
			capture confirm file "`checkfile'"
			if !_rc & !`resubmit' {
				di "ERROR REMOVING OUTPUTS"
				BREAK
			}
			if `split_max' > 1 & _rc {
				noisily display "Submitting split `sg' (of `split_max') using `slots' slots"
				capture !/usr/local/bin/SGE/bin/lx24-amd64/qsub -P proj_cancer_prep -pe multi_slot `slots' -l mem_free=`mem'g -N "rdpW_`data_name'_`data_type'_`sg'" "`programs_folder'/shellstata13.sh" "`programs_folder'/redistribution/code/cancer_rdp_worker.do" "`sg' `data_type' `temp_folder' `map_folder'"
			}
	}


// Check for completion & get files collapsed by acause
	clear
	local first_file = 1
	cap mkdir "`temp_folder'"
	// wait for buffer
	local buffer = (`split_max'/300)*60000
	sleep `buffer'

	// check for outputs
	forvalues sg = `split_min'/`split_max' {
		local checkfile = "`temp_folder'/split_`sg'/final/redistributed_split_`sg'_collapsed.dta"
		capture confirm file "`checkfile'"
		local numAttempts = 1
		while _rc {
			noisily display "Waiting for acause-level split `sg' (of `split_max')"
			local numAttempts = `numAttempts' + 1
			if _rc & `numAttempts' >= 6 {
				do "`programs_folder'/redistribution/code/cancer_rdp_worker.do" `sg' `data_type' `temp_folder' `map_folder'
				if !`first_file' use "`temp_folder'/temp_rdp.dta", clear
				else clear
			}
			if `sg' > `split_min' sleep 60000
			capture confirm file "`checkfile'"
		}
		noisily display "Appending split `sg' of `split_max'"
		append using "`temp_folder'/split_`sg'/final/redistributed_split_`sg'_collapsed.dta"
		quietly save "`temp_folder'/temp_rdp.dta", replace
		local first_file = 0
	}

// verify that all worker outputs are added and none were duplicated
	duplicates drop
	bysort split_group: gen nvals = _n == 1 
	count if nvals == 1
	if r(N) < `split_max' {
		if 	`troubleshooting' pause
		else BREAK
	}
	drop nvals

// re-merge with registry information
	rename registry registry_id
	merge m:1 registry_id using "`temp_folder'/_maps/registries.dta"
	count if _merge != 3
	if r(N) > 0 {
		if `troubleshooting' pause
		else BREAK
	}
	drop registry_id _merge
	
// Verify that metrics are within acceptable range
	preserve
		// verify calculations
			summ (orig_cases1)
			if !inrange(int(r(sum)), int(`pre_rdp_total') -1, int(`pre_rdp_total') +1) & !regexm(lower(source), "nordcan") {
				display "Error in `data_name' (`data_type'): Total number of 'original' events post-rdp does not equal number of 'original' events pre-rdp (`pre_rdp_total' before, `r(sum)' after')"
				if `troubleshooting' pause
				else BREAK
			}
			local pre_rdp_total = r(sum)

		// check the dataset total
			summ(cases1)
			local post_total = r(sum)
			local delta = round(`post_total') - round(`pre_rdp_total')
			if abs(`delta') > 0.0005 * round(`pre_rdp_total')  {
				noisily di in red "Error in `data_name' (`data_type'): Total cases before rdp does not equal total after. `pre_rdp_total' events before, `post_total' after. A difference of `delta' events"
				if `troubleshooting' pause
				else BREAK
			}
			summ(cases1) if substr(acause, 1, 4) == "neo_"
			local post_total_neo_ = r(sum)
			summ (orig_cases1) if substr(acause, 1, 4) == "neo_"
			local pre_rdp_total_neo_ = r(sum)
			if round(`pre_rdp_total_neo_') > round(`post_total_neo_') {
				noisily di in red "Error in `data_name' (`data_type'): Total mapped cases before rdp is less than total after. `pre_rdp_total_neo_' events before, `post_total_neo_' after."
				if `troubleshooting' pause
				else BREAK
			}
	restore

// keep only those causes appearing in the original dataseet
	merge m:1 location_id iso3 subdiv registry year* sex acause using "`temp_folder'/input_acause_list.dta", keep(1 3)
	gen cause = acause if _merge == 1 | substr(acause, 1, 4) != "neo_"
	replace acause = "rdp_remnant" if _merge == 1 |  substr(acause, 1, 4) != "neo_"
	drop _merge

// Save redistributed file
	save "`output_folder'/07_redistributed_`data_type'.dta", replace
	save "`output_folder'/_archive/07_redistributed_`data_type'_`timestamp'.dta", replace
	

// compile a list of codes that did not merge
	clear
	forvalues sg = `split_min'/`split_max' {
		capture append using "`temp_folder'/split_`sg'/bad_codes.dta"
	}
	if _N save "`bad_code_folder'/bad_codes_`timestamp'_`data_name'_`data_type'_.dta", replace


if `troubleshooting' pause off
capture log close

** *******************************************************************************************************
** *******************************************************************************************************
