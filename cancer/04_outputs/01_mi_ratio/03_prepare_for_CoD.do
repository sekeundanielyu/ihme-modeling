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

if "$today" == "" {
	// Get date
		local today = date(c(current_date), "DMY")
		global today = string(year(`today')) + "_" + string(month(`today'),"%02.0f") +"_"+ string(day(`today'),"%02.0f")
}		
	
	if "$directory" == "" global directory = "$j/WORK/07_registry/cancer/04_outputs/01_mortality_incidence" 

	global code_folder = "$directory/code"
	global subroutines = "$code_folder/subroutines"
	local incidence_input_folder = "$j/WORK/07_registry/cancer/02_database/01_mortality_incidence/data/intermediate"
	local input_folder = "$directory/data/intermediate"
	local output_folder = "$directory/data/final"
	local cod_output_folder = "$j/WORK/03_cod/01_database/03_datasets/Cancer_Registry/data/intermediate"
	global temp_folder = "`input_folder'/temp"

** ****************************************************************
** CREATE LOG
** ****************************************************************
// Create Log Folder if necessary
	local log_folder "$directory/logs"
	capture mkdir "`log_folder'"
	
// Begin Log
	capture log close drops
	** log using "$directory/logs/03_PCU_$today.log", replace name(drops)

** ****************************************************************
** GET ADDITIONAL RESOURCES: POPULATION DATA
** ****************************************************************
// Set subnationally modeled iso3s
	use "$j/WORK/07_registry/cancer/00_common/data/subnationally_modeled.dta"
	di "Subnational Data"
	levelsof subnationally_modeled_iso3, clean local(subnationally_modeled_iso3s)
	levelsof location_id, clean local(subnationally_modeled_id)

// get population data
	do "$j/WORK/07_registry/cancer/00_common/code/get_pop_and_env_data.do"
	
// get location ids
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
		replace path_to_top_parent = substr(path_to_top_parent, strpos(path_to_top_parent, ",") +1, .)  // drops global
		replace path_to_top_parent = substr(path_to_top_parent, strpos(path_to_top_parent, ",") +1, .)  // drops super region
		replace path_to_top_parent = substr(path_to_top_parent, strpos(path_to_top_parent, ",") +1, .)  // drops region
		drop if strpos(path_to_top_parent, ",") != 0
	// keep only relevant data and save
		keep iso3 year sex age pop
		reshape wide pop, i(iso3 year sex) j(age)
		tempfile nat_pop
		save `nat_pop', replace

** ****************************************************************************
**  PREPARE UPLOAD
** *****************************************************************************	
// Get Data
	use "`input_folder'/02_CoD_incidence_data.dta", clear

// Estimate the number of cases for the median year ( total_cases/num_years ) 
	foreach n of numlist 2 7/22 {
		replace cases`n' = cases`n'/year_span
	}
	
// Drop data that is not modeled, if remaining
	drop if year < 1970
	keep if inlist(sex, 1, 2)
		
// // Verify population
	// Replace missing population info with "NA" entry
		foreach n of numlist 2 7/22 {
			replace pop`n' = . if pop`n' == 0
		}
		drop pop1
		egen pop1 = rowtotal(pop*), missing
	
// // Combine registry data from the same source-year-location
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
		collapse (sum) cases* pop*, by(source year location_id iso3 subdiv registry sex acause NID national dev_status region) fast
	
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
		collapse (sum) cases* pop*, by(iso3 location_id subdiv sex year acause registry source NID dev_status region national) fast
		// ensure population consistency
		foreach var of varlist pop* {
			bysort location_id year sex: egen new`var' = mean(`var')
		}
		drop pop*
		rename newpop* pop*

// Mark sub-nationally modeled subnational data
	gen subMod = 0
	foreach sub_mod in `subnationally_modeled_iso3s' {
		replace subMod = 1 if iso3 == "`sub_mod'"
	}	

// Drop special-case subnationally modeled data: data are not nationally representative but encompass multiple subdivs
	replace subdiv = "" if upper(subdiv) == "NA"
	drop if subMod == 1 & subdiv == "" & national == 0
	
// // save the non-estimated data
	tempfile pre_nat_calc
	save `pre_nat_calc', replace			
			
// // // Adjust national numbers
	// // Generate National Numbers for developed country-years with no national data	
		// keep relevant data: non-national data, for developed countries or subnationally modeled countries, with population
			keep if national == 0 & (dev_status == "G1" | subMod == 1) & !inlist(pop1, ., 0)
			
		// Collapse to combine registries from the same iso3/subdivision regardless of source. Preserve source information by changing the source name of sources that will be combined
			// combine registries by iso3
				sort year iso3 sex source acause
				egen uid = concat(year iso3 sex source), punct("_")
				bysort uid source registry: gen registry_count = _n == 1
				replace registry_count = 0 if registry_count != 1
				bysort uid: egen combined_registries = total(registry_count)
				replace registry = "Combined Registries" if combined_registries > 1
				replace NID = 103215 if registry == "Combined Registries" // "Record to be researched"
				drop uid combined_* registry_count
				collapse (sum) cases* pop*, by(source year iso3 registry sex acause NID dev_status region) fast
			
			// combine sources by iso3
				egen uid = concat(year iso3 sex), punct("_")
				bysort uid source: gen source_count = _n == 1
				replace source_count = 0 if source_count != 1
				bysort uid: egen combined_sources = total(source_count)
				replace registry = "Combined Registries" if combined_sources > 1
				replace source = "Combined Sources" if combined_sources > 1	
				replace NID = 103215 if source == "Combined Sources"  // "Record to be researched"
				drop uid combined_* source_count
				collapse (sum) cases* pop*, by(source year iso3 registry sex acause NID dev_status region) fast
				// ensure population consistency
					// NOTE: find better method?
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
			
		// merge with national population, then recalculate cases based on the rate and national population for nationally modeled, developed countries. 
			merge m:1 iso3 year sex using `nat_pop', keep(1 3) nogen
			foreach n of numlist 2 7/22 {
				gen recalculated_cases`n' = rate`n'*pop`n'
				replace recalculated_cases`n' = . if iso3 == "DEU" & !inlist(year, 1980, 1985, 1988)
				replace cases`n' = recalculated_cases`n' if recalculated_cases`n' != .
			}
			
		// recalculate cases1
			drop cases1
			egen cases1 = rowtotal(cases*), missing
			gen projected_national = 1
			
		// keep only recalculated data and give them unique identifiers
			egen recalc_total = rowtotal(recalculated_cases*), missing
			drop if recalc_total == . | recalc_total == 0
			replace source = "Calculated from " + source 
			gen national = 1
		
		// replace location_id
			merge m:1 iso3 using `location_ids', keep(3) nogen
			
		// drop irrelevant variables and save 
			drop recalc_total recalculated* rate* 
			tempfile calc_nat
			save `calc_nat', replace
		
	// // project existing national data onto GBD population and add the national estimates 
		use `pre_nat_calc', clear
		preserve
			// combine the existing national data
				keep if national == 1 & pop1 != .
				duplicates tag year location_id sex acause, gen(combined_source)
				replace registry = "Combined Registries" if combined_source != 0
				replace source = "Combined Sources" if combined_source != 0
				drop combined_*
				collapse (sum) cases* pop*, by(source year location_id iso3 sex acause NID national dev_status region subMod) fast	
				
			// calculate rate 
			foreach n of numlist 2 7/22 {
				gen double rate`n' = cases`n'/pop`n'
			}
			rename pop* registry_pop*
			
			// project rate onto the envelope national data
				merge m:1 iso3 year sex using `nat_pop', keep(3) nogen
				foreach n of numlist 2 7/22 {
					gen recalculated_cases`n' = rate`n' * pop`n'
					replace cases`n' = recalculated_cases`n' if recalculated_cases`n' != .
				}	
			
			// note estimation in source
				replace source = "Adjusted from " + source if !regexm(source, " from ")
			
			// mark as existing data
				gen existing_national = 1
				gen recalculated_national = 1
			
			// drop irrelevant variables
				drop recalculated_cases* rate*
		
			// save
				tempfile projected_national
				save `projected_national', replace
		restore
		
	// combine estimates with the rest of the data
		gen existing_national = 1 if national == 1
		drop if national == 1 & pop1 != .
		append using `projected_national'
	
	// add the estimated national data, then drop new data if raw data is present (ensures that there are not duplicates)
		// drop data from which national numbers were calculated, but keep subnationally modeled data
		drop if national == 0 & dev_status == "G1" & pop1 != . & subMod != 1
		append using `calc_nat'
		replace existing_national = 0 if existing_national != 1
		bysort location_id year sex : egen has_existing = total(existing_national)
		drop if has_existing > 0 & national == 1 & existing_national != 1

	// save data
		save "$temp_folder/03_first_save.dta", replace	

// // // Merge data with MI results to generate death estimates
	// check population
		preserve
			reshape long deaths pop, i(iso3 location_id subdiv sex year acause source national NID) j(age)
			bysort location_id year age sex: egen double avg_pop = mean(pop)
			count if !inrange(pop, avg_pop-1, avg_pop +1)
			if r(N) > 0 BREAK
		restore
			
	// drop irrelevant variables and save
		drop existing_national has_existing projected_national recalculated_national registry_pop*
		
	// Check and drop duplications
		sort year location_id sex
		bysort year location_id sex source: gen source_count = _n == 1
		replace source_count = 0 if source_count != 1
		bysort year location_id sex: egen problem_source = total(source_count)	
		count if problem_source > 1
		if r(N) > 0 BREAK
		drop source_count problem_source
		
	// merge
		merge m:1 iso3 sex year acause using "`input_folder'/01_MI_model_results.dta", keep(3) nogen 
		local result_nums = ""
		foreach v of varlist MIm_result_* {
			local result_nums = "`result_nums' " + subinstr("`v'", "MIm_result_", "", .)
		}
		foreach n in `result_nums'{
			gen deaths`n' = cases`n' * MIm_result_`n' if MIm_result_`n' != .
			replace deaths`n' = . if MIm_result_`n' == .
		}
		foreach n of numlist 2 7/22 {
			capture gen deaths`n' = 0
		}
		egen deaths1 = rowtotal(deaths*), missing

	// Save
		order iso3 location_id subdiv sex year acause deaths* cases* MIm*
		compress
		save "`output_folder'/03_CoD_input.dta", replace
		save "`output_folder'/_archive/03_CoD_input_$today.dta", replace

** ************************************
** END	
** ************************************
