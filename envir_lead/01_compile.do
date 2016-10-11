// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Modified:		--
// Project:		RISK
// Purpose:		Compile all blood lead data to send to Annette

** **************************************************************************
** RUNTIME CONFIGURATION
** **************************************************************************
// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		set mem 12g
		set maxvar 32000
	// Set to run all selected code without pausing
		set more off
	// Set graph output color scheme
		set scheme s1color
	// Remove previous restores
		capture restore, not
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
			global hprefix "H:"
		}
		
// Close previous logs
	cap log close
	
// Create timestamp for logs
	local c_date = c(current_date)
	local c_time = c(current_time)
	local c_time_date = "`c_date'"+"_" +"`c_time'"
	display "`c_time_date'"
	local time_string = subinstr("`c_time_date'", ":", "_", .)
	local timestamp = subinstr("`time_string'", " ", "_", .)
	display "`timestamp'"
	
// Create macros to contain toggles for various blocks of code:
	local compile 1
	
// Store filepaths/values in macros
	local code 						"$hprefix/code/lead"
	local data_raw					"$prefix/WORK/05_risk/risks/envir_lead_blood/data/exp/raw"
	local data_prepped				"$prefix/WORK/05_risk/risks/envir_lead_blood/data/exp/prepped"
	local isodat  					"$prefix/DATA/IHME_COUNTRY_CODES/IHME_COUNTRYCODES.DTA" // NOTE: MAKE THIS A SQL PULL	
	local data_lit_review_2013		"$prefix/DATA/Incoming Data/WORK/05_risk/0_ongoing/lead/lead_exp_extraction_GBD_2013_subnat.xlsx"
	local data_lit_review_2010		"$prefix/Project/GBD/RISK_FACTORS/Data/lead/sources/blood_lead_sources_combined_08_30_subnat.xlsx"
	 
if `compile' == 1 {

// Prep countryname data to merge on iso3
	use `isodat', clear
	duplicates drop iso3, force
	tempfile countrynames
	save `countrynames'

// Start by bringing and tempfiling the new data
	import excel using "`data_lit_review_2013'", firstrow clear
	
	// Drop extraneous variables
		drop row_id source file_name file_location gbd_cause gbd_region exposure_report response_rate
			
	// Save and tempfile
		tempfile new_data
		save `new_data', replace
		
// Bring in and prep old data for merge
	import excel `data_lit_review_2010', sheet("Sheet1") firstrow case(lower) clear

	// Modifications
		
		// Drop NHANES data from the USA because I extracted it myself (will append later)
			drop if nhanes_usa == 1
			
		// Exclude outliers
			drop if exclude == 1

		// clean up countrynames
			rename l countryname
			replace countryname = "Colombia" if countryname == "Columbia"
			replace countryname = "Micronesia" if strmatch(countryname, "Micronesia*")
			replace countryname = "Philippines" if countryname == "Phillipines"
		// merge on countrycodes	
			merge m:1 countryname using "$prefix/Usable/Common Indicators/Country Codes/countrycodes_official.dta", ///
				keepusing(countryname_ihme iso3 gbd_region ihme_indic_country) keep(match) nogen
			drop if  ihme_indic_country == 0
			drop  ihme_indic_country
			drop whoregion
			
		// Recode urbanicity/subnationality
			gen subnational = (setting != "Combined")
			gen national = (setting == "Combined")
			gen urbanicity = inlist(setting, "Urban", "NA") // Sets as 1 if urban
			replace urbanicity = 0 if setting == "Suburbs"
			replace urbanicity = 2 if setting == "Combined"
		
		// Recode sex
			gen sex_numeric = 1 if sex == "Male"
			replace sex_numeric = 2 if sex == "Female"
			replace sex_numeric = 3 if sex == "Both" | sex == "NA"
			drop sex
			rename sex_numeric sex
			
		// Recode year
			split year, parse("-")
				destring year*, ignore("?") force replace
				drop year
				rename year1 year_start
				rename year2 year_end
				replace year_end = year_start if year_end == .
				drop if year_start == . & year_end == .
			gen less_than = strmatch(ageyears, "*<*")
			gen greater_than = strmatch(ageyears, "*>*")
				replace ageyears = subinstr(ageyears, "<", "", .)
				replace ageyears = "0-" + ageyears if less_than == 1				
				replace ageyears = subinstr(ageyears, ">", "", .)
				replace ageyears = ageyears + "-80" if greater_than == 1
				drop less_than greater_than
			replace ageyears = "0-1" if ageyears == "Infant"
				replace ageyears = "0-5" if ageyears == "Child" | ageyears == "Children" | strmatch(ageyears, "Primary*") | ageyears == "Preschool age"
				replace ageyears = "0-6" if ageyears == "0-6y"
				replace ageyears = "4-6" if ageyears == "Kindergarden age"
				replace ageyears = "10-19" if ageyears == "Adolescents" | ageyears == "Secondary school age" | ageyears == "Teenage child"
				replace ageyears = "5-18" if ageyears == "School Age" | ageyears == "School children"
				replace ageyears = "20-80" if ageyears == "Adult" | ageyears == "adult"
				replace ageyears = "0-100" if ageyears == "NA"
				replace ageyears = "0-80" if strmatch(ageyears, "Com*") | strmatch(ageyears, "*+*") | strmatch(ageyears, "*adult age")
			
			split ageyears, parse("-")
				destring ageyears*, force replace
				rename ageyearsoragegroup1 age_start
				rename ageyearsoragegroup2 age_end
				drop ageyears
				replace age_end = age_start if age_end == .
				drop if age_start == . & age_end == .
				
			// Calculate SE
				// Destring and rename all components
					destring samplesize, force replace
					destring standarddeviationugdl, force replace
					rename meanbloodleadlevelugdl exp_mean
					rename standarddeviationugdl std_deviation
					rename samplesize sample_size
					
				// First create for all that have the proper components
					generate std_error = std_deviation / sqrt(sample_size)
				
				// Now estimate those that are missing
				
					// Assume sample size is 50 if missing
						replace sample_size = 50 if sample_size == .

					// Calculate CV and use average CV for dataset to estimate the standard deviation
						generate cv = (std_error * sqrt(sample_size)) / exp_mean
						summ cv
						local mean_cv = r(mean)
						replace std_deviation = `mean_cv' * exp_mean if std_deviation == .
						
					// Estimate using these imputed parameters
						replace std_error = std_deviation / sqrt(sample_size) if std_error == .
					
			// Rename variables and generate necessary variables
				rename unit exposure_units
				rename citation field_citation
				gen exposure_type = "blood lead"
				gen risk = "lead"
				gen source_type = 5
				
			// Drop extraneous variables
				drop setting authorsource zotero pdfsaved possible checked countryname_ihme cv countryname gbd_region
				
		// Tempfile and save
			tempfile old_data
			save `old_data', replace
			
// Finally bring in and prep the NHANES data
	// First tempfile all years
		local years "1988_1994 1999_2000 2001_2002 2003_2004 2005_2012"
		
		foreach year in `years' {
			use `data_raw'/NHANES_`year'_blood_lead_mean.dta, clear
			generate field_citation = "Centers for Disease Control and Prevention (CDC). National Center for Health Statistics (NCHS). National Health and Nutrition Examination Survey Data. Hyattsville, MD: U.S. Department of Health and Human Services, Centers for Disease Control and Prevention, `year'"
			generate data_type = 7
			generate source_type = 2
			// drop extraneous variables
				drop file_name file_location 
			tempfile `year'data
			save ``year'data', replace
		}
	
	// Now append all years
		// create seed (you can't append to any empty dataset in stata)
		clear
		set obs 1
		gen seed = .
	// Tempfile the seed
		tempfile all_NHANES
		save `all_NHANES', replace
		
		foreach year in `years' {
			use `all_NHANES'
			
			append using ``year'data'
			save `all_NHANES', replace
		}
		
	// Kill the seed (don't need anymore)
		drop in 1
		drop seed	
		
	// Modifications
		destring year*, force replace

	// Save
		save `all_NHANES', replace
			
			
// Append datasets
	use `old_data', clear
	append using `new_data', force
	append using `all_NHANES'
		
	// Merge names and regions
		merge m:1 iso3 using `countrynames', ///
		keepusing(countryname_ihme iso3 gbd_region ihme_indic_country) keep(match) nogen
		rename countryname_ihme iso3_display
		drop if  ihme_indic_country == 0
		drop  ihme_indic_country
		
	// Modifications
	
		gen iso3_parent = iso3
		replace iso3_child = "." if iso3_child == ""
		replace iso3 = iso3_child if iso3_child != "." // replace with subnational iso3 values
			drop iso3_child
	
		replace nid = 103215 if nid == . // this is the NID that signifies citation is currently unknown
	
	// Order variables
		order nid field_citation gbd_region iso3 iso3_display site national subnational urbanicity sex year_start year_end age_start age_end exp_mean std_error exp_lower exp_upper  std_deviation sample_size geometric_mean exposure_type exposure_units
	// Keep only blood lead (drops bone lead)
		
		drop if exposure_type != "blood lead"

// Save and output file in DTA and CSV for Annette
		save `data_prepped'/blood_lead_full_database.dta, replace
		
// Normalize all units to ug/dL to prep for DisMod
	foreach var of varlist exp_mean exp_lower exp_upper std_error std_deviation {
		replace `var' = `var' / 10 if exposure_units != "ug/dL"
	}
		replace exposure_units = "ug/dL"
	
	replace exposure_definition = "unknown test" if exposure_definition == "" | exposure_definition == "."
	gen case_diagnostics = "originally: " + exposure_units + "." + " detected with: " + exposure_definition
	drop exposure_units exposure_definition
	
// Deal with missing variables in a systematic way
	local missing_variables "page_num table_num site notes cantfind"
		foreach var of varlist `missing_variables' {
			replace `var' = "." if `var' == ""
		}

// Recode improperly coded variables
	// Nationality
		rename national national_type
		replace national_type = 3 if national_type == 0
		drop subnational
	// Urbanicity
		gen urbanicity_type = .
		replace urbanicity_type = 1 if national_type == 1
		replace urbanicity_type = 3 if urbanicity == 0
		replace urbanicity_type = 2 if urbanicity == 1
		replace urbanicity_type = 0 if urbanicity_type == .
			drop urbanicity
	// Study type
		replace data_type = 16 if data_type == . // already coded NHANES as household survey, didn't extract this for the rest of them
		replace source_type = 1 if source_type == . // already coded NHANES as household survey and old data as "expert"
		
	
	gen healthstate = "envir_lead"
	
// Make changes to variable names so that this can be uploaded to epi database
	gen parameter_type = "prevalence"
	rename exp_mean mean
	rename exp_lower lower
	rename exp_upper upper
	rename std_error standard_error
	rename std_deviation standard_deviation
	rename exposure_type case_definition
	gen orig_uncertainty_type = "SE"
		replace orig_uncertainty_type = "CI" if lower != .
	gen orig_unit_type = 1
	gen grouping = "risks"
	gen acause = "_none"
	rename field_citation citation
	
// Covariates
	rename geometric_mean add1
	
// Drop extraneous variables
	drop risk subnational_id cantfind nhanes_usa risk
	
// Final ordering 
	order acause grouping healthstate study_status nid page_num table_num source_type data_type iso3 sex year_start year_end age_start age_end parameter_type mean lower upper standard_error standard_deviation sample_size orig*
	order notes, last

// save as a .DTA/.CSV as well to feed into spacetime-GPR as well
	save "`data_raw'/gbd2013_lead_exp.dta", replace
	outsheet using "`data_raw'/gbd2013_lead_exp.csv", comma replace
	
	levelsof iso3_parent, local(isos)
	global isos = "`isos'"

}

cap log close		