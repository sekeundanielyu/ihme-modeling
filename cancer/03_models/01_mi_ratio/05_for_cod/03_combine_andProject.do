
// Purpose:	Combine data for CoD upload. Recalculate national numbers for developed countries. Combine with MI result to generate death numbers that will be sent to CoD database

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
	if "`username'" == "" local username = "[name]"
	
** **************************************************************************
** SET DATE AND DIRECTORIES
** **************************************************************************

if "$today" == "" {
	// Get date
		local today = date(c(current_date), "DMY")
		global today = string(year(`today')) + "_" + string(month(`today'),"%02.0f") +"_"+ string(day(`today'),"%02.0f")
}		
	
	if "$directory" == "" global directory = "$j/WORK/07_registry/cancer/04_outputs/01_mortality_incidence" 

	global code_folder = "$directory/code"
	global subroutines = "$code_folder/subroutines"
	local data_folder = "$directory/data/intermediate"
	global temp_folder = "$j/temp/registry/cancer/04_outputs/01_mortality_incidence"
	global dropped_list = "`data_folder'/dropped_data/02_dropped_data_$today.dta"

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
		capture log close pC
		log using "`log_folder'/03_CaP_$today.log", replace name(pC)
}

** ****************************************************************
** Get additional resources
** ****************************************************************
// Import record_drop_reason function
global recordDropReason "$subroutines/recordDropReason.do" 

// Get development dev_status	
	import delimited using "$j/WORK/07_registry/cancer/00_common/data/modeled_regions_and_super_regions.csv", clear varnames(1)
	keep location_id gbd_non_developing
	gen dev_status = "G1" if gbd_non_developing == 1
	replace dev_status = "G0" if gbd_non_developing == 0
	drop gbd_non_developing
	duplicates drop
	tempfile dev_stats
	save `dev_stats', replace

// Set subnationally modeled iso3s
	use "$j/WORK/07_registry/cancer/00_common/data/subnationally_modeled.dta"
	di "Subnational Data"
	levelsof subnationally_modeled_iso3, clean local(subnationally_modeled_iso3s)
	levelsof location_id, clean local(subnationally_modeled_id)

// // Get location ids (national and subnational)
	// get population data
		use "$j/WORK/07_registry/cancer/00_common/data/all_populations_data.dta"

	// get all location ids
		preserve
			keep location_id iso3
			sort iso3 location_id
			duplicates drop
			bysort iso3: gen parent = _n == 1
			keep if parent == 1
			duplicates drop
			drop parent
			gen subdiv = ""
			tempfile location_ids
			save `location_ids', replace
		restore
		
	// save subnational population data for subnational to national estimation
		preserve
			gen keeper = 0
			foreach sub_mod in `subnationally_modeled_id' {
				replace keeper = 1 if regexm(path_to_top_parent, ",`sub_mod',")
			}
			keep location_id iso3 year sex age pop
			reshape wide pop, i(location_id iso3 year sex) j(age)
			tempfile subnat_pop
			save `subnat_pop', replace
		restore	

	// get subnational population data for national to subnational estimation
		preserve
			gen child_id = location_id
			rename location_id orig_location_id
			gen location_id = .
			// create location_id to match national location_id for all subnationals
			foreach sub_mod in `subnationally_modeled_id' {
				replace location_id = `sub_mod' if regexm(path_to_top_parent, ",`sub_mod',")
			}
			drop if location_id == .
			keep location_id child_id iso3 year sex age pop
			reshape wide pop, i(location_id child_id iso3 year sex) j(age)
			tempfile nat_toSubnat_pop
			save `nat_toSubnat_pop', replace
		restore	
	
	// // save national pop data
		// keep only national data by removing each subsection of path_to_top_parent up to country, then checking for a remaining comma (global, super region, region, country, subnational)
		replace path_to_top_parent = substr(path_to_top_parent, strpos(path_to_top_parent, ",") +1, .)  
		replace path_to_top_parent = substr(path_to_top_parent, strpos(path_to_top_parent, ",") +1, .)  
		replace path_to_top_parent = substr(path_to_top_parent, strpos(path_to_top_parent, ",") +1, .)  
		drop if strpos(path_to_top_parent, ",") != 0
		// keep only relevant data and save
		keep iso3 year sex age pop
		reshape wide pop, i(iso3 year sex) j(age)
		tempfile nat_pop
		save `nat_pop', replace

// get representation map ("national" status for exceptions)
	import delimited using "$j/WORK/07_registry/cancer/04_outputs/01_mortality_incidence/maps/representation_map.csv", clear
	duplicates drop
	tempfile rep_stats
	save `rep_stats', replace

** ****************************************************************************
**  Adjust incidence data, mark data to preserve some indication of the origin, then combine data from the same location
** *****************************************************************************	
// Get Data
	use "`data_folder'/02_CoD_incidence_data.dta", clear

// Run India special handling
	do "$subroutines/india_assign_rural_urban.do"

// Merge with development development status 
	merge m:1 location_id using `dev_stats', keep(3) nogen

// Estimate the number of cases for the median year ( total_cases/num_years ) 
	foreach n of numlist 2 7/22 {
		replace cases`n' = cases`n'/year_span
		replace pop`n' = pop`n'/year_span
	}
	drop cases1

// Drop data that is not modeled, if remaining
	drop if year < 1970
	keep if inlist(sex, 1, 2)
	
// replace missing NIDs
	replace NID = 103215 if NID == . | NID == 0

// Mark sub-nationally modeled subnational data
	gen subMod = 0
	foreach sub_mod in `subnationally_modeled_iso3s' {
		replace subMod = 1 if iso3 == "`sub_mod'"
	}		
	
// adjust national status
	gen grouping = "national" if registry == "National Registry" | national == 1
	replace grouping = "subnational" if subMod == 1 & location_id > 250
	replace grouping = "national" if grouping == ""
	merge m:1 iso3 grouping using `rep_stats', keep(1 3) nogen
	replace national = 1 if representative == 1 & grouping != "subnational" 
	replace national = 0 if representative == 0
	drop grouping representative

// Drop special-case subnationally modeled data: data are not nationally representative but encompass multiple subdivs
	replace subdiv = "" if upper(subdiv) == "NA"
	drop if subMod == 1 & subdiv == "" & national == 0	
	
// // Verify population
	// Replace missing population info with "NA" entry
		foreach n of numlist 2 7/22 {
			replace pop`n' = . if pop`n' == 0
		}
		drop pop1
		egen pop1 = rowtotal(pop*), missing
		capture drop pop0
		
	// drop non-national data that is missing population
		gen toDrop = 1 if pop1 == . & national != 1
		// Drop data
		gen dropReason = "no population data available"
		egen uid = concat(iso3 subdiv registry year sex), punct("_")
		noisily di "Removing non-national data with missing population"
		run "$recordDropReason" "combine and project" "$directory" "$dropped_list" "$today"
		drop if toDrop == 1
		drop toDrop uid dropReason

// // Combine registry data from the same year-location and source
	// tag data that will be combined
		sort year location_id sex source acause
		egen uid = concat(year location_id sex source), punct("_")
		bysort uid source registry: gen registry_count = _n == 1
		replace registry_count = 0 if registry_count != 1
		bysort uid: egen combined_registries = total(registry_count)
	
	// preserve NID and source for combined country-years
	preserve	
		keep if combined_registries != 0
		keep iso3 subdiv year national registry source NID
		duplicates drop
		sort iso3 subdiv year national registry source NID
		save "$temp_folder/02_combined_registries.dta", replace
	restore
		
	// collapse to create combined data
		replace registry = "Combined Registries" if combined_registries > 1
		replace NID = 103215 if registry == "Combined Registries" // "Record to be researched"
		drop uid combined_* registry_count
		collapse (sum) cases* pop*, by(source year location_id iso3 subdiv registry sex acause dev_status NID national subMod) fast
	
// // Collapse to combine registries from the same iso3/subdivision regardless of source. Preserve source information by changing the source name of sources that will be combined
	// tag data that will be combined
		sort year location_id sex acause
		egen uid = concat(year location_id sex), punct("_")
		bysort uid source: gen source_count = _n == 1
		replace source_count = 0 if source_count != 1
		bysort uid: egen combined_sources = total(source_count)

	// preserve NID and source for combined country-years
	preserve	
		keep if combined_sources != 0
		keep iso3 year national source NID
		duplicates drop
		sort iso3 year national source NID
		save "$temp_folder/02_combined_sources.dta", replace
	restore
	
	// collapse to create combined data
		replace registry = "Combined Registries" if combined_sources > 1
		replace source = "Combined Sources" if combined_sources > 1
		replace NID = 103215 if source == "Combined Sources"  // "Record to be researched"
		drop uid combined_* source_count
		collapse (sum) cases* pop*, by(iso3 location_id subdiv sex year acause registry source dev_status NID national subMod) fast
		// ensure population consistency
		foreach p of varlist pop* {
			replace `p' = . if `p' == 0
			bysort location_id year sex: egen new`p' = mean(`p')
			replace `p' = 0 if `p' == .
		}
		drop pop*
		rename newpop* pop*
	
// // save the non-estimated data
	tempfile pre_nat_calc
	save `pre_nat_calc', replace			
			
** ****************************************************************************
**  Adjust national numbers
** *****************************************************************************	
// // Project rate onto national population for developed countries with no national data. Also combine non-developed, sub-nationally modeled data but do not project onto national population
	// keep relevant data: non-national data, for developed countries or subnationally modeled countries, with population
		keep if national == 0 & !inlist(pop1, ., 0) & (dev_status == "G1" | subMod == 1 | inlist(iso3, "COL", "CUB"))
		drop if regexm(source, "NPCR")  // The GBD 2015 NPCR data contains suppressed data that may invalidate calculations
		
	// Collapse to combine registries from the same iso3, regardless of source. Preserve source information by changing the source name of sources that will be combined
		// combine REGISTRIES by iso3
			sort year iso3 sex source acause
			egen uid = concat(year iso3 sex source), punct("_")
			bysort uid source registry: gen registry_count = _n == 1
			replace registry_count = 0 if registry_count != 1
			bysort uid: egen combined_registries = total(registry_count)
			replace registry = "Combined Registries" if combined_registries > 1
			replace NID = 103215 if registry == "Combined Registries" // "Record to be researched"
			drop uid combined_* registry_count
			collapse (sum) cases* pop*, by(source year iso3 registry sex acause NID dev_status subMod) fast
		
		// combine SOURCES by iso3
			egen uid = concat(year iso3 sex), punct("_")
			bysort uid source: gen source_count = _n == 1
			replace source_count = 0 if source_count != 1
			bysort uid: egen combined_sources = total(source_count)
			replace registry = "Combined Registries" if combined_sources > 1
			replace source = "Combined Sources" if combined_sources > 1	
			replace NID = 103215 if source == "Combined Sources"  // "Record to be researched"
			drop uid combined_* source_count
			collapse (sum) cases* pop*, by(source year iso3 registry sex acause NID dev_status subMod) fast
			
			// ensure population consistency
			foreach var of varlist pop* {
				bysort iso3 year sex: egen new`var' = mean(`var')
			}
			drop pop*
			rename newpop* pop*
		
		// check for duplicates
			duplicates tag iso3 year sex acause, gen(tag)
			count if tag != 0
			if r(N) > 0 {
				pause on
				di "Duplicates found when calculating national data!"
				pause
				pause off
			}
			drop tag
		
	// calculate rate 
		foreach n of numlist 2 7/22 {
			gen double rate`n' = cases`n'/pop`n'
		}
		rename pop* registry_pop*
		
	// keep record of pre-modified metrics
	foreach c of varlist cases* {
			gen orig_`c' = `c'
		}
		
	// merge with national population, then recalculate cases based on the rate and national population for nationally modeled, developed countries. 
		merge m:1 iso3 year sex using `nat_pop', keep(1 3) assert(2 3) nogen
		foreach n of numlist 2 7/22 {
			gen recalculated_cases`n' = rate`n'*pop`n'
			replace recalculated_cases`n' = . if iso3 == "DEU" & !inlist(year, 1980, 1985, 1988)
			replace cases`n' = recalculated_cases`n' if recalculated_cases`n' != .
		}
		
		// keep only recalculated data and give them unique identifiers
		egen recalc_total = rowtotal(recalculated_cases*), missing
		drop if dev_status == "G1" & (recalc_total == . | recalc_total == 0)
	
		gen projected_national = 1
		gen national = 1 if dev_status == "G1"
		replace national = 0 if dev_status == "G0"
	
		// replace location_id
		merge m:1 iso3 using `location_ids', keep(3) nogen
		
	// drop irrelevant variables and save 
		drop recalc_total recalculated* rate*
		tempfile projected_natnl
		save `projected_natnl', replace
	
	use `pre_nat_calc', clear
	preserve
		// combine the existing national data
			keep if national == 1 & pop1 != .
			duplicates tag year location_id sex acause, gen(combined_source)
			replace registry = "Combined Registries" if combined_source != 0
			replace source = "Combined Sources" if combined_source != 0
			drop combined_*
			collapse (sum) cases* pop*, by(source year location_id iso3 sex acause NID national dev_status subMod) fast	
			
		// calculate rate 
		foreach n of numlist 2 7/22 {
			gen double rate`n' = cases`n'/pop`n'
		}
		rename pop* registry_pop*
		
			// keep record of pre-modified metrics
			foreach c of varlist cases* {
				gen orig_`c' = `c'
			}
		
			// project rate onto the envelope national data
			merge m:1 iso3 year sex using `nat_pop', keep(3) assert(2 3) nogen
			foreach n of numlist 2 7/22 {
				gen recalculated_cases`n' = rate`n' * pop`n'
				replace cases`n' = recalculated_cases`n' if recalculated_cases`n' != .
			}	
				
		// mark as adjussted data
			gen adjusted_national = 1
		
		// drop irrelevant variables
			drop recalculated_cases* rate*
	
		// save
			tempfile envelope_adjusted
			save `envelope_adjusted', replace
	restore

	drop if national == 1 & pop1 != .
	append using `envelope_adjusted'
	gen existing_national = 1 if national == 1

// next add the projected national data, then drop new data if raw data is present (ensures that there are not duplicates)
	// drop data from which national numbers were projected unless the data are modeled subnationally. then append natonally projected data data
	drop if national == 0 & (dev_status == "G1" | inlist(iso3, "COL", "CUB") | subMod == 1) & pop1 != . & subMod != 1
	append using `projected_natnl'
	
	replace existing_national = 0 if existing_national != 1
	bysort location_id year sex acause: egen has_existing = total(existing_national)
	drop if has_existing > 0 & national == 1 & existing_national != 1
	drop if has_existing > 0 & projected_national == 1 & subMod == 1

	rename pop* temp_pop*
	merge m:1 iso3 year sex using `nat_pop', keep(1 3) assert(2 3) nogen
	foreach n of numlist 2 7/22 { 
		replace temp_pop`n' = pop`n' if temp_pop1 == . & national == 1
	}
	drop pop*
	rename temp_pop* pop*
	
// recalculate all ages numbers
	drop pop1
	egen cases1 = rowtotal(cases*), missing
	egen pop1 = rowtotal(pop*), missing

// save data
	save "`data_folder'/03_combined_andProjected.dta", replace	

** ************************************
** END	
** ************************************


