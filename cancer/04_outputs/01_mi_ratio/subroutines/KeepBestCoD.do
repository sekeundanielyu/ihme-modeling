** *************************************************************************
// Purpose:	Drop redundant or unmatched cancer data according to defined rules. Alert user of errors.

** **************************************************************************
// SET MACROS AND DIRECTORIES
** **************************************************************************
// Accept Arguments
args section directory dropped_list today keepBest_temp

** ****************************************************************
** DEFINE MACROS if none sent
** ****************************************************************	
if "$directory" == "" global directory = "`directory'"
if "$directory" == "" global directory = "$j/temp/registry/cancer/04_outputs/01_mortality_incidence"
if "$recordDropReason" == "" global recordDropReason "$directory/code/subroutines/recordDropReason.do" 

if "$today" == "" global today = "`today'"
if "$dropped_list" == "" global dropped_list = "`dropped_list'"

if "$keepBest_temp" == "" global keepBest_temp = "/ihme/gbd/cmaga/cancer/mi_KB_temp"	

** ****************************************************************
** RUN SCRIPT
** ****************************************************************	

// // Define KeepBest Function: Keeps only data designated as priority = 1 (national data). If there is no priority 1 data, then uses all data for that registry_year. Next, eliminates redundancies in order of reliability


// Check sources
	capture program drop check_sources
	program check_sources
		capture drop num_sources
		sort uid
		bysort uid: egen num_sources = total(source_check) if dropReason == ""
	end	
	
// Set variables
	gen toDrop = 0
	gen dropReason = ""
	capture levelsof acause, clean local(acauses)
	
// Save versions of all of the data
save "$keepBest_temp/before_KB.dta", replace
save "$keepBest_temp/all_data.dta", replace
	
// // Iterate through causes to keep the best data	
	foreach cause in `acauses' {
	
	// keep only data for the current cause
		keep if acause == "`cause'"
		
	// Check sources
		capture drop source_check
		sort uid source
		bysort uid source: gen source_check = _n == 1
		replace source_check = 0 if source_check != 1
		check_sources
			 
	// Deprioritize datasets with problems
		replace gbd_iteration = 0 if source == "NLD_NationalRegistry_1989_2012"

	//  Keep Preferred datasets if preferred data is present (excellent data). NOTE:  preferred data must be in order of preference
		local preferred_datasets = "SWE_NCR_1990_2010 usa_seer_1973_2008 SEER IND_PBCR_2009_2011 BRA_SPCR_2011 JPN_NationalCIS_1958_2013" 	
		foreach preferred_data in `preferred_datasets' {
			local dropReason = "dataset has `preferred_data' data for same registry"
			gen preferred = 1 if regexm(upper(source), upper("`preferred_data'"))
			replace preferred = 0 if preferred != 1
			bysort uid: egen has_preferred = total(preferred) if num_sources > 1
			replace toDrop = 1  if preferred != 1 & has_preferred > 0 & num_sources > 1
			replace dropReason = "`dropReason'" if toDrop == 1 & dropReason == ""
			drop preferred has_preferred
			check_sources
		}				

	// Keep the most recently formatted dataset(s)
		local dropReason = "dataset has more recently formatted data for the same registry"
		bysort uid: egen max_gbd = max(gbd_iteration)
		replace toDrop = 1 if gbd_iteration != max_gbd & num_sources > 1
		replace dropReason = "`dropReason'" if toDrop == 1 & dropReason == ""
		drop max_gbd
		check_sources	

	// Keep CI5 Data
		local ci5_sources = "ci5_plus ci5_1995_1997_inc ci5_period_i_ ci5_period_ix CI5_X_2003_2007"
		foreach ci5_source in `ci5_sources' {
			local dropReason = "dataset has `ci5_source' data for the same registry"
			replace toDrop = 1 if !regexm(source, "`ci5_source'") & num_sources > 1
			replace dropReason = "`dropReason'" if toDrop == 1 & dropReason == ""
			check_sources
		}	
		
	// Keep data with smallest year span (lowest priority, since it isn't necessarily linked with data quality)
		local dropReason = "dropped in favor of data with smaller year span from same registry"
		bysort uid: egen min_span = min(year_span)
		replace toDrop = 1  if year_span != min_span & num_sources > 1
		replace dropReason = "`dropReason'" if toDrop == 1 & dropReason == ""
		drop min_span
		check_sources
	
	// Keep preferred sources in case of exceptions
		local preferred_in_exception = "NORDCAN EUREG_GBD2015 aut_2007_2008_inc tto_1995_2006_inc" 	
		foreach preferred_data in `preferred_in_exception' {
			local dropReason = "dataset has `preferred_data' data for same registry"
			gen preferred = 1 if regexm(upper(source), upper("`preferred_data'"))
			replace preferred = 0 if preferred != 1
			bysort uid: egen has_preferred = total(preferred) if num_sources > 1
			replace toDrop = 1  if preferred != 1 & has_preferred > 0 & num_sources > 1
			replace dropReason = "`dropReason'" if toDrop == 1 & dropReason == ""
			drop preferred has_preferred
			check_sources
		}	

	// Verify that some data still remains	
		check_sources
		count if num_sources > 1 & num_sources != .
		if r(N) != 0 {
			pause on
			noisily di "Error: Some data not dropped for some uids!" 
			pause
			pause off
		}
		count if num_sources == 0
		if r(N) > 0 {
			pause on
			noisily di "Error: All data dropped for some uids!" 
			pause
			pause off
		}
		count if (toDrop == 1 & dropReason == "") | (toDrop == 0 & dropReason != "")
		if r(N) > 0 {
			pause on
			noisily di "Error: Drop label error!" 
			pause
			pause off
		}
		
	// Record drop reasons, then drop
		count if toDrop == 1
		if r(N) > 0 {
			run "$recordDropReason" "1" "$directory" "$dropped_list" "$today"
			drop if toDrop == 1
		}
		drop toDrop dropReason
		
	// Drop extraneous variables
		drop source_check num_sources
	// Save tempfile, then append changes to original data
		save "$keepBest_temp/`cause'.dta", replace
		use "$keepBest_temp/all_data.dta", clear
		drop if acause == "`cause'"
		append using "$keepBest_temp/`cause'.dta"
		save "$keepBest_temp/all_data.dta", replace
	}
	
	// Drop extraneous variables
		drop toDrop dropReason
		
	// Save
		save "$keepBest_temp/kept_best.dta", replace
		
** *********
** END
** *********
