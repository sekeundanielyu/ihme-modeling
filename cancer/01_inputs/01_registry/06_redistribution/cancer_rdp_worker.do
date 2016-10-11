
// Purpose:		Formats for redistribution, runs redistribution, and then reformats it back to CoD format

** **************************************************************************
** ANALYSIS CONFIGURATION
** **************************************************************************
// Set application preferences
	// Clear memory and set memory and variable limits
		clear all
		set mem 10G 
		set maxvar 32000

	// Set to run all selected code without pausing
		set more off

	// Set graph output color scheme
		set scheme s1color
	
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global j "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" global j "J:"

** ****************************************************************
** DEFINE LOCALS
** ****************************************************************
// accept arguments
	args split_group data_type rdp_folder map_folder

// Temporary folder
	capture mkdir "`rdp_folder'/split_`split_group'"
	capture mkdir "`rdp_folder'/split_`split_group'/_logs"
	capture mkdir "`rdp_folder'/split_`split_group'/intermediate"
	capture mkdir "`rdp_folder'/split_`split_group'/final"
	local temp_folder "`rdp_folder'/split_`split_group'"

// Input folder
	local input_folder "`rdp_folder'/_input_data"

// Log
	capture log close
	log using "`temp_folder'/_logs/split_`split_group'.log", text replace
	
display "`username' `data_name' `code_version' `split_group'"	

// Get date
	local date = date(c(current_date), "DMY") 
	local timestamp = string(year(`date'),"%02.0f")	+ "_" + string(month(`date'),"%02.0f") + "_" + string(day(`date'),"%02.0f")
	
** ****************************************************************
** GET RESOURCES
** ****************************************************************
// Set source label tag to 0 (we don't have this in cancer but do in CoD)
	local source_label_tag = 0
				
** ****************************************************************
** RUN PROGRAM
** ****************************************************************
// enable pause feature if troubleshooting	
	if `troubleshooting' pause on	
	
// Get data
	import delimited "`input_folder'/split_`split_group'.csv", varnames(1) case(preserve) clear
	
// Reformat string variables to remove leading apostrophe
	foreach var of varlist * {
		capture replace `var' = subinstr(`var',"'","",1)
	}

// Collapse data down
	collapse (sum) cases*, by(gbd_iteration source NID registry location_id national subdiv year_start year_end sex coding_system acause split_group) fast

// Save a before so we can merge things on later
	// Rename
		foreach i of numlist 1/26 {
			capture gen cases`i' = 0
			rename cases`i' orig_cases`i'
		}
	// ensure that registry is set as a string (prevents errors in the event that registries were mapped to numbers to avoid special character errors)
		capture tostring registry, replace

	// Save
		save "`temp_folder'/before_data.dta", replace

	// Rename back
		foreach i of numlist 1/26 {
			rename orig_cases`i' cases`i'
		}

	// calculate the pre-rdp total for later comparison
		capture summ(cases1)
		local pre_rdp_total = r(sum)

// Reshape age wide
	egen uid = group(gbd_iteration source NID registry location_id national subdiv year_start year_end sex coding_system acause), missing
	reshape long cases, i(uid) j(gbd_age)
	drop uid

// // Verify that split group needs redistribution
	local noGarbage = 0

	// Verify that the split group contains data that are not zeros. If non-zero data exists, drop causes that have 0 cases. 
		count if cases == 0 | cases == .
		if r(N) != _N drop if cases == 0 | cases == .
		else local noGarbage = 1
	
	// Verify that the split group contains un-mapped codes by testing if any data begins with a capital letter or a number
		count if substr(acause, 1, 1) == upper(substr(acause, 1, 1))  | real(substr(acause, 1, 1)) != .
		if r(N) == 0 local noGarbage = 1

// Convert GBD age to age groups
	gen age = .
	replace age = 0 if gbd_age == 2
	replace age = 1 if gbd_age == 3
	replace age = (gbd_age - 6) * 5 if (gbd_age - 6) * 5 >= 5 & (gbd_age - 6) * 5 <= 80
	drop if age == .
	drop gbd_age

// Merge on location hierarchy metadata
	merge m:1 location_id using "`map_folder'/location_hierarchy.dta", keep(1 3) keepusing(location_id ihme_loc_id global dev_status super_region region country subnational_level1 subnational_level2) assert(2 3) nogen
	drop ihme_loc_id

// Rename variables
	rename acause cause
	rename cases freq

// create a map to revert causes from non-decimal form. then remove decimals from causes to enable rdp
	preserve
		keep cause
		duplicates drop
		gen rdp_cause = subinstr(cause, ".", "", .)
		save "`temp_folder'/rdp_cause_map.dta", replace
	restore
	replace cause = subinstr(cause, ".", "", .)
	
// Save intermediate file for RDP
	saveold "`temp_folder'/intermediate/for_rdp.dta", replace
	if `noGarbage' {
		keep location_id gbd_iteration source NID registry national subdiv year_start year_end sex coding_system split_group age cause freq
		saveold "`temp_folder'/final/post_rdp.dta", replace
	}
	
// Get code_version
	levelsof(coding_system), local(code_version) clean
	
// Prep resources for redistribution (and afterwards)
	// Get source label if needed
		if `source_label_tag' == 1 {
			levelsof(source_label), local(source_label) clean
		}

	// Get packagesets_ids
		use "$j/WORK/00_dimensions/03_causes/temp/packagesets_`code_version'.dta", clear
		if `source_label_tag' == 1 {
			keep if source_label == "`source_label'"
		}
		count
		if `r(N)' == 0 {
			display in red "THERE AREN'T ANY SOURCE LABELS TAGGED `source_label' IN $j/WORK/00_dimensions/03_causes/temp/packagesets_`code_version'.dta"
			display in red "Failing redistribution now... bye-bye"
			BREAK
		}
		else if `r(N)' > 1 {
			display in red "THERE TOO MANY CODE SYSTEMS IN $j/WORK/00_dimensions/03_causes/temp/packagesets_`code_version'.dta `source_label'"
			display in red "Failing redistribution now... bye-bye"
			BREAK
		}
		levelsof(package_set_id), local(package_set_id) clean

// Run redistribution (no magic tables for cancer)
	local magic_table = 0
	if !`noGarbage' {
		!python "$j/WORK/07_registry/cancer/01_inputs/programs/redistribution/code/redistribution_cancer.py" "`rdp_folder'" "`map_folder'" `package_set_id' `split_group' `magic_table'
	}	

// Get redistributed data
	use "`temp_folder'/final/post_rdp.dta", clear
	compress
	noisily di "`data_name' `data_type'"

// rename freq
	rename freq cases

// Replace lingering ZZZ with CC code
	replace cause = "cc_code" if cause == "ZZZ"
	
// Convert age groups to GBD age
	tostring(age), replace format("%12.2f") force
	destring(age), replace
	gen gbd_age = .
	replace gbd_age = (age/5) + 6 if age * 5 >= 5 & age <= 80
	replace gbd_age = 2 if age == 0
	replace gbd_age = 3 if age == 1
	drop age
	rename gbd_age age

// reformat acause 
	// convert back to cancer cause
		rename cause rdp_cause
		capture merge m:1 rdp_cause using "`temp_folder'/rdp_cause_map.dta", keep(1 3) assert(1 3)
		if _rc {
			di "ERROR, not all ICD codes converted back to decimal causes"
			if `troubleshooting' pause
			else BREAK
		}
		replace cause = rdp_cause if _merge == 1
		drop rdp_cause _merge
		
		//	merge with cause map
			replace cause = trim(itrim(cause))
			merge m:1 coding_system cause using "`map_folder'/cause_map_`data_type'.dta", keep(1 3)
			count if _merge == 1 & cause != "cc_code" & substr(cause, 1, 4) != "neo_"
			capture rm "`temp_folder'/bad_codes.dta"
			
			// if some codes don't merge, save them to a list 
			if `r(N)' > 0 {
				preserve
					display in red "The following causes are not in the cause map:"
					levelsof cause if _merge != 3 & cause != "cc_code" & !regexm(cause, "neo_")
					keep if _merge != 3 & cause != "cc_code" & !regexm(cause, "neo_")
					keep source cause coding_system split_group
					duplicates drop
					save "`temp_folder'/bad_codes.dta", replace
				restore
			}
			gen acause = gbd_cause if _merge == 3 & gbd_cause != "_gc"
			replace acause = cause if (_merge == 1 | gbd_cause == "_gc") 
			replace cause = "" if _merge == 3 & acause != ""
			count if acause == "" | acause == "_gc"
			if r(N) > 0 {
				di "ERROR, not all data mapped to causes"
				if `troubleshooting' pause
				else BREAK
			}
			rename _merge causeMap_merge
			drop gbd_cause
			
			save "`temp_folder'/mapped_rdp_result.dta", replace

	// Collapse
		collapse (sum) cases, by(acause location_id gbd_iteration source NID registry national subdiv year_start year_end sex coding_system split_group age) fast
	
	// Reshape
		egen uid = group(acause location_id gbd_iteration source NID registry national subdiv year_start year_end sex coding_system split_group), missing
		reshape wide cases, i(uid) j(age)
		drop uid
		
	// Merge with original data source
		merge 1:1 gbd_iteration source NID registry location_id national subdiv year_start year_end sex coding_system acause split_group using "`temp_folder'/before_data.dta"
		rename _merge beforeafter
		
	// Verify that metrics are within acceptable range		
		preserve
			// calculate totals
				summ (orig_cases1)
				if round(r(sum)) != round(`pre_rdp_total') {
					display "Error in `data_name' (`data_type', split `split_group'): Total number of 'original' events post-rdp does not equal number of 'original' events pre-rdp (`pre_rdp_total' before, `r(sum)' after')"
					if `troubleshooting' pause
					else BREAK
				}

			// check the dataset total
				egen cases1 = rowtotal(cases*)
				summ(cases1)
				local post_total = r(sum)
				local delta = round(`post_total') - round(`pre_rdp_total')
				if abs(`delta') > 0.005 * `pre_rdp_total'  {
					noisily di in red "Error in `data_name' (`data_type', split `split_group'): Total cases before rdp does not equal total after. `pre_rdp_total' events before, `post_total' after. A difference of `delta' events"
					if `troubleshooting' pause
					else BREAK
				}
				summ(cases1) if substr(acause, 1, 4) == "neo_"
				local post_total_neo_ = r(sum)
				summ (orig_cases1) if substr(acause, 1, 4) == "neo_"
				local pre_rdp_total_neo_ = r(sum)
				if (`pre_rdp_total_neo_') > round(`post_total_neo_') + 1 {
					noisily di in red "Error in `data_name' (`data_type', split `split_group'): Total mapped cases before rdp is less than total after. `pre_rdp_total_neo_' events before, `post_total_neo_' after."
					if `troubleshooting' pause
					else BREAK
				}
		restore	
		
	// Reformat cases variables
		// Make sure all cases variables exist
			foreach i of numlist 2/26 {
				capture gen cases`i' = 0
				replace cases`i' = 0 if cases`i' == .
			}
		// Recalculate aggregates
			aorder
			egen double cases1 = rowtotal(cases2-cases26)
			
	// Reformat hierarchies
		merge m:1 location_id using "`map_folder'/location_hierarchy.dta", keep(1 3) assert(2 3) keepusing(dev_status region_id ihme_loc_id) nogen
		rename region_id region
		split ihme_loc_id, p("_")
		rename ihme_loc_id1 iso3
		capture drop ihme_loc_id2
		capture destring(location_id), replace
		replace dev_status = subinstr(dev_status,"D","G",.)
		drop ihme_loc_id
		
	// Fill in 0s where needed
		foreach var of varlist cases* orig_cases* {
			replace `var' = 0 if `var' == .
		}
		
	// Get max before after 
		egen temp = max(beforeafter), by(sex coding_system acause iso3 subdiv location_id national source NID registry gbd_iteration year_start year_end region dev_status)
		replace beforeafter = temp	
	
	// Collapse to acause level
		collapse(sum) *cases*, by(sex coding_system acause iso3 subdiv location_id national source NID registry gbd_iteration year_start year_end region dev_status beforeafter) fast
		gen split_group = `split_group'
		order gbd_iteration source registry NID dev_status region iso3 location_id national subdiv year_start year_end sex coding_system acause cases* orig_cases* beforeafter split_group
		
	// Save
		capture _strip_labels*
		compress
		save "`temp_folder'/final/redistributed_split_`split_group'_collapsed.dta", replace	
		
	// Write text file for completion
		file open finish using "`temp_folder'/final/redistributed_split_`split_group'_complete.txt", write replace
		file write finish "Done!" _n
		file close finish
	
	if `troubleshooting' pause off
	capture log close
	
// ***************************
// End rdp_worker
// ***************************
