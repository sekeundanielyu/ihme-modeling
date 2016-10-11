
// Purpose:	Drop redundant or unmatched cancer data according to defined rules.

** **************************************************************************
// SET MACROS AND DIRECTORIES
** **************************************************************************
// Accept Arguments
args section directory dropped_list today keepBest_temp

** ****************************************************************
** DEFINE MACROS if none sent
** ****************************************************************	
if "$directory" == "" global directory = "`directory'"
if "$directory" == "" global directory = "$j/WORK/07_registry/cancer/02_database/01_mortality_incidence"
if "$recordDropReason" == "" global recordDropReason "$directory/code/subroutines/recordDropReason.do" 
if "$today" == "" global today = "`today'"
if "$dropped_list" == "" global dropped_list = "`dropped_list'"
if "$keepBest_temp" == "" global keepBest_temp = "/ihme/gbd/WORK/07_registry/cancer/02_database/01_mortality_incidence/mi_KB_temp"

** ****************************************************************
** RUN SCRIPT
** ****************************************************************	
// Check sources
	capture program drop check_sources
	program check_sources
		capture drop num_sources
		sort uid
		bysort uid: egen num_sources = total(source_check) if dropReason == ""
	end
	
// Get data type
	levelsof dataType, clean local(dataType)

// Change gbd_iteration of CI5_X_Appendix (reduces complication in "preferred sources" section)
	replace gbd_iteration = 2013 if regexm(source, "CI5_X_Appendix")	
	
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
		
	// drop combined sources if non-combined sources are present
		local dropReason = "dataset has matching data from the same source (`cause')"
		bysort uid: gen has_non_combined = 1 if !regexm(source, " & ")
		replace toDrop = 1 if regexm(source, " & ") & has_non_combined == 1 & num_sources > 1 
		replace dropReason = "`dropReason'" if toDrop == 1 & dropReason == ""
		drop has_non_combined
		check_sources
			
	//  Keep Preferred datasets if preferred data is present (excellent data).
		local preferred_datasets = "usa_seer_1973_2008 SEER SWE_NCR_1990_2010 NORDCAN aut_2007_2008_inc EUREG_GBD2015 BRA_SPCR_2011" 	
		foreach preferred_data in `preferred_datasets' {
			local dropReason = "dataset has `preferred_data' data for same registry (`cause')"
			gen preferred = 1 if regexm(upper(source), upper("`preferred_data'"))
			replace preferred = 0 if preferred != 1
			bysort uid: egen has_preferred = total(preferred) if num_sources > 1
			replace toDrop = 1  if preferred != 1 & has_preferred > 0 & num_sources > 1
			replace dropReason = "`dropReason'" if toDrop == 1 & dropReason == ""
			drop preferred has_preferred
			check_sources
		}				

	// Drop CoD VR data
		local dropReason = "dropped in favor of non-CoD (`cause')"
		replace toDrop = 1 if regexm(upper(source), "COD_VR") & num_sources > 1
		replace dropReason = "`dropReason'" if toDrop == 1 & dropReason == ""
		check_sources

		
	// Keep the most recently formatted dataset(s) 
		local dropReason = "dataset has more recently formatted data for the same registry (`cause')"
		bysort uid: egen max_gbd = max(gbd_iteration)
		replace toDrop = 1 if gbd_iteration != max_gbd & num_sources > 1
		replace dropReason = "`dropReason'" if toDrop == 1 & dropReason == ""
		drop max_gbd
		check_sources

			
	// Drop CI5 Appendix Data 
		local dropReason = "dataset has non CI5 Appendix data for the same registry (`cause')"
		replace toDrop = 1 if (regexm(source, "CI5_Appendix") | regexm(source, "CI5_X_Appendix")) & dataType != 1 & num_sources > 1
		replace dropReason = "`dropReason'" if toDrop == 1 & dropReason == ""
		check_sources

		
	// Drop CI5 Data
		local ci5_sources = "ci5_1995_1997_inc ci5_period_i_ ci5_period_ix CI5_X_2003_2007 ci5_plus"
		foreach ci5_source in `ci5_sources' {
			local dropReason = "dataset has non-`ci5_source' data for the same registry (`cause')"
			replace toDrop = 1 if regexm(source, "`ci5_source'") & num_sources > 1
			replace dropReason = "`dropReason'" if toDrop == 1 & dropReason == ""
			check_sources
		}

	// Keep data with smallest year span 
		local dropReason = "dropped in favor of data with smaller year span from same registry (`cause')"
		bysort uid: egen min_span = min(year_span)
		replace toDrop = 1  if year_span != min_span & num_sources > 1
		replace dropReason = "`dropReason'" if toDrop == 1 & dropReason == ""
		drop min_span
		check_sources
		
	 // Drop CI5 Appendix Data 
		local dropReason = "dataset has non CI5 Appendix data for the same registry (`cause')"
		replace toDrop = 1 if (regexm(source, "CI5_Appendix") | regexm(source, "CI5_X_Appendix")) & num_sources > 1
		replace dropReason = "`dropReason'" if toDrop == 1 & dropReason == ""
		check_sources
		
	// Keep preferred sources in case of exceptions
		local preferred_in_exception = "SVN_2008_2009 tto_1995_2006_inc" 	
		foreach preferred_data in `preferred_in_exception' {
			local dropReason = "dataset has `preferred_data' data for same registry (`cause')"
			gen preferred = 1 if regexm(upper(source), upper("`preferred_data'"))
			replace preferred = 0 if preferred != 1
			bysort uid: egen has_preferred = total(preferred) if num_sources > 1
			replace toDrop = 1  if preferred != 1 & has_preferred > 0 & num_sources > 1
			replace dropReason = "`dropReason'" if toDrop == 1 & dropReason == ""
			drop preferred has_preferred
			check_sources
		}	
		
	// Verify 
		check_sources
		count if num_sources > 1 & num_sources != .
		if r(N) != 0 {
			pause on
			noisily di "Error: Some data not dropped for some uids in `cause'!" 
			pause
			pause off
		}
		count if num_sources == 0
		if r(N) > 0 {
			pause on
			noisily di "Error: All data dropped for some uids in `cause'!" 
			pause
			pause off
		}
		count if (toDrop == 1 & dropReason == "") | (toDrop == 0 & dropReason != "")
		if r(N) > 0 {
			pause on
			noisily di "Error: Drop label error in in `cause'!" 
			pause
			pause off
		}
		
	// Record drop reasons, then drop
		count if toDrop == 1
		if r(N) > 0 {
			do "$recordDropReason" "`cause' KeepBest" "$directory" "$dropped_list" "$today"
			drop if toDrop == 1
		}
	
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
	
	save "$keepBest_temp/kept_best.dta", replace
		
** ******
** End
** ******
	
