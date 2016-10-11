** *************************************************************************
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
	local data_folder = "$directory/data/intermediate"
	local output_folder = "$directory/data/final"
	global temp_folder = "$j/temp/registry/cancer/04_outputs/01_mortality_incidence"

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
		log using "`log_folder'/04_VaP_$today.log", replace name(pC)
}

** ****************************************************************************
** Get additional resources
** *****************************************************************************
// get representation map ("national" status for special cases)
	import delimited using "$j/WORK/07_registry/cancer/04_outputs/01_mortality_incidence/maps/representation_map.csv", clear
	duplicates drop
	tempfile rep_stats
	save `rep_stats', replace

** ****************************************************************************
** Validate
** *****************************************************************************	
	use "`data_folder'/03_combined_andProjected.dta", replace	
	
	// drop irrelevant variables and save
		drop existing_national has_existing  registry_pop* orig_* projected_national
		capture drop recalculated_national

	// check for duplicates
		duplicates tag iso3 location_id sex year acause national, gen(tag)
		count if tag !=0
		if r(N) > 0 {
			di "Duplicate entries exists"
			BREAK
		}
		drop tag
		
	// check population
		preserve
			drop pop1
			keep pop* iso3 location_id sex year acause national
			reshape long pop, i(iso3 location_id sex year acause national) j(age)
			bysort location_id year age sex national: egen double avg_pop = mean(pop)
			count if !inrange(pop, avg_pop-1, avg_pop +1) & avg_pop != .
			if r(N) > 0 {
				di in red "ERROR: population is not consistent within the same location-age-sex-year"
				BREAK
			}
		restore	
		
	// set representation ("national", "is data representative of the location id") status based on map
		gen grouping = "national" if registry == "National Registry" | national == 1
		replace grouping = "subnational" if subMod == 1 & location_id > 250
		replace grouping = "national" if grouping == ""
		merge m:1 iso3 grouping using `rep_stats', keep(1 3) nogen
		replace national = 1 if representative == 1   // for unmerged rows, representative = .
		replace national = 0 if representative == 0
		drop grouping
		
	// Verify that there is no source redundancy
		sort year location_id sex acause
		bysort year location_id sex source acause: gen source_count = _n == 1
		replace source_count = 0 if source_count != 1
		bysort year location_id sex acause: egen problem_source = total(source_count)	
		count if problem_source > 1
		if r(N) > 0 BREAK
		drop source_count problem_source
		
** ****************************************************************************
**  Merge data with MI model results to generate death estimates
** *****************************************************************************	

// replace iso3 for locations using subnational models
	gen ihme_loc_id = iso3
	replace ihme_loc_id = iso3 + "_" + string(location_id) if location_id == 354

// convert sex for breast cancer only 
	gen is_male = 1 if acause == "neo_breast" & sex == 1
	replace sex = 2 if acause == "neo_breast"
	
// merge incidence data with MI model results
	merge m:1 ihme_loc_id sex year acause using "`data_folder'/01_MI_model_results.dta", keep(3) nogen 

// revert sex
	replace sex = 1 if is_male == 1
	drop is_male

// Reshape and Save tempfile
	keep iso3 location_id subdiv sex year acause source national NID pop* cases*  MI_model_result* modnum
	reshape long pop cases MI_model_result_, i(iso3 location_id subdiv sex year acause source national NID modnum) j(age)
	capture _strip_labels*

// Calculate deaths
	gen deaths = cases * MI_model

// Save
	order iso3 location_id subdiv sex year acause deaths* cases* MI_model*
	compress
	saveold "`output_folder'/04_CoD_input.dta", replace
	saveold "`output_folder'/_archive/04_CoD_input_$today.dta", replace

** ************************************
** END	
** ************************************
