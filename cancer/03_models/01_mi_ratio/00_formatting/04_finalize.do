
// Purpose: 	Drop duplicate or questionable data before MI ratio processing

** **************************************************************************
** Configuration
** 		Sets application preferences (memory allocation, variable limits) 
** 		Accepts/Sets Arguments. Defines the J drive location.
** **************************************************************************
// Clear memory and set memory and variable limits
	clear all
	set maxvar 32000
	set more off
	
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" global j "J:"


** **************************************************************************
** SET DATE AND DIRECTORIES (Manual Entry)
** **************************************************************************
// Declare location set version id 
	local location_set_version_id = 38
	
** **************************************************************************
** SET DATE AND DIRECTORIES
** **************************************************************************
// Accept Arguments
	args today directory
			
// Set date and directory if no arguments are passed
	if "`directory'" == "" {
		// Get date
		local today = date(c(current_date), "DMY")
		local today = string(year(`today')) + "_" + string(month(`today'),"%02.0f") + "_" + string(day(`today'),"%02.0f")
		
		// Set locals
		local directory = "$j/WORK/07_registry/cancer/02_database/01_mortality_incidence" 
	}
// Set folders
	local database_folder "`main_dir'/data/raw"
	local input_folder "`directory'/data/intermediate"
	local output_folder "`directory'/data/final"
	local temp_folder = "$j/temp/registry/cancer/02_database/01_mortality_incidence"
	local location_ids = "$j/WORK/07_registry/cancer/01_inputs/sources/00_Documentation/location_ids.dta"
	local outlier_folder ="$j/WORK/07_registry/cancer/03_models/01_mi_ratio/03_results/05_outliers/flagged_inputs"
		
** ****************************************************************
** Create Log if running on the cluster
** 		Get date. Close open logs. Start Logging.
** ****************************************************************
if c(os) == "Unix" {
	// Log folder
		local log_folder "/ihme/gbd/WORK/07_registry/cancer/logs/02_database/01_mortality_incidence"
		cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs"
		cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs/02_database"
		cap mkdir "`log_folder'"
		
	// Begin Log
		capture log close MI
		log using "`log_folder'/04_cMI_`today'.log", replace name(MI)
}

** ****************************************************************
** Get Additional Information
** **************************************************************** 
// Get cause restricitons
		use "$j/WORK/00_dimensions/03_causes/causes_all.dta", clear
		keep if cause_version == 2
		keep acause male female
		tempfile cause_restrictions
		save `cause_restrictions', replace

// Get data from hierarchy
		odbc load, exec("SELECT * FROM shared.location_hierarchy_history WHERE location_set_version_id = `location_set_version_id'") dsn([dsn]) clear
	// Keep only what we need
		keep ihme_loc_id region_id
		duplicates drop
		drop if region_id == .
		drop ihme_loc_id
		tempfile region_info
		save `region_info', replace
	
** ****************************************************************
** Prepare data
** **************************************************************** 
// Get Data
	use "`input_folder'/03_redundancies_dropped.dta", clear

// Save list of source-registries used
	preserve
		keep iso3 registry source* year
		duplicates drop
		save "`input_folder'/data_analysis/MI_data_list.dta", replace
	restore
	
// Drop data that are not modeled
	drop if year < 1970

// Ensure that "All Ages" Variables actually equal the sum of all ages
	aorder
	drop cases1 deaths1 pop1
	egen cases1 = rowtotal(cases*)
	egen deaths1 = rowtotal(deaths*)
	egen pop1 = rowtotal(pop*)
	
** ****************************************************************
** CHECK and FINALIZE DATA
** ****************************************************************
// Mark subnational data
	gen ihme_loc_id = iso3
	replace ihme_loc_id = ihme_loc_id + "_" + string(location_id) if subdiv != ""

// Mark data that should not be used for national calculation
	gen excludeFromNational = 1 if regexm(source, "NPCR") & gbd_iteration == 2015
	replace excludeFromNational = 0 if excludeFromNational != 1

// Collapse registries to create national/subnational numbers
	collapse(sum) cases* deaths* pop*, by(iso3 acause sex year excludeFromNational)

// Reshape, Calculate MI, and Drop Data with NULL MI Ratio.
	reshape long cases deaths pop, i(iso3 acause sex year excludeFromNational) j(age)
	
	// Remove labels
		foreach var of varlist _all {
			capture _strip_labels `var' 
		}
		
	// re-apply sex restrictions, just in case
		merge m:1 acause using `cause_restrictions', keep(1 3) nogen
		drop if sex == 1 & male == 0
		drop if sex == 2 & female == 0
		drop male female
		
// Keep relevant data and save
	keep iso3 year sex age acause cases deaths pop excludeFromNational
	order iso3 year sex age acause cases deaths pop excludeFromNational
	duplicates drop
	compress
	saveold "`output_folder'/04_MI_ratio_model_input_`today'.dta", replace
	saveold "`output_folder'/_archive/04_MI_ratio_model_input_`today'.dta", replace 
	
** ****************************************************************
**  CALCULATE MI to GENERATE ANALYTICS
** ****************************************************************
// Generate MI Ratio and save information for later
	gen mi_ratio = deaths/cases
	local allMI = _N
		
// Drop undefined ratios
	drop if mi_ratio == .
	cap count if mi_ratio == .
	local nullMI = r(N)
		
// Flag US Data for Comparison
	gen USmi = mi_ratio if iso3 == "USA"
	bysort year sex age acause: egen MI_of_USA	= max(USmi)
	drop USmi
	
	gen UScases = cases if iso3 == "USA"
	bysort year sex age acause: egen casesUSA	= max(UScases)
	drop UScases
	
	gen USdeaths = deaths if iso3 == "USA"
	bysort year sex age acause: egen deathsUSA	= max(USdeaths)
	drop USdeaths

// Count and Drop Data Above or Below the Acceptable Range
	cap count if mi_ratio > 10
	local dataIssue = r(N)
	cap count if mi_ratio > 2
	local tooHigh = r(N)
	capture count if mi_ratio == 0
	local zeroValues = r(N)
	// Preserve a list of mi ratios that are below 0.1 for analysis by the PI before dropping mi ratios below 0.1
	preserve
		keep if mi_ratio <= 0.1
		save "`temp_folder'/MI_less_than_pt1.dta", replace
		joinby iso3 year using "`input_folder'/data_analysis/MI_data_list.dta", unmatched(master)
		save "`input_folder'/data_analysis/MI_less_than_pt1.dta", replace
	restore
	capture count if mi_ratio < 0.1
	local tinyValues = r(N)
	
// Count Abnormal Ratios
	capture count if mi_ratio > 1.5
	local above_1p5  = r(N)
	capture count if mi_ratio > 1.2
	local above_1p2  = r(N)
	capture count if mi_ratio - MI_of_USA < -0.1 & MI_of_USA != . & mi_ratio != 0
	local lower_than_US = r(N)
	
// Generate percentile by region for analysis 
	merge m:1 ihme_loc_id using `region_info', keep(1 3) nogen  
	replace region_id = 0 if region_id == .
	sort region_id sex age acause year mi_ratio
	bysort region_id sex age acause year: egen n = count(mi_ratio)
	bysort region_id sex age acause year: egen i = rank(mi_ratio), track
	gen regional_percentile = (i - 1) / (n - 1) 
	drop n i
	sort sex age acause year mi_ratio
	bysort sex age acause year: egen n = count(mi_ratio)
	bysort sex age acause year: egen i = rank(mi_ratio), track
	gen global_percentile = (i - 1) / (n - 1) 
	preserve
		keep iso3 acause sex year age mi_ratio region* global_percentile
		gen regional_lower_25percentile = mi_ratio if regional_percentile < 0.25
		gen regional_upper_75percentile = mi_ratio if regional_percentile > 0.75
		gen regional_between = mi_ratio if inrange(regional_percentile, 0.25, 0.75)
		gen global_lower_25percentile = mi_ratio if global_percentile < 0.25
		gen global_upper_75percentile = mi_ratio if global_percentile > 0.75
		gen global_between = mi_ratio if inrange(global_percentile, 0.25, 0.75)
		sort acause iso3 year sex age year region_id iso3 mi_ratio
		// keep only one cancer
		keep if acause == "neo_lung_cancer"
		// Reformat Ages
		rename age ageGroup
		merge m:1 ageGroup using "$j/WORK/07_registry/cancer/02_database/01_mortality_incidence/maps/age_groups.dta", keep(1 3) nogen
		drop ageGroup 
		// Export
		order acause iso3 year sex age year region_id iso3 mi_ratio
		order regional_percentile global_percentile, last
		export delimited  "`input_folder'/data_analysis/mi_ratio_percentiles.csv", replace
	restore
	
	// save version of data for analysis
		saveold "`input_folder'/data_analysis/MI_model_input_for_analysis_`today'.dta", replace
	
** ****************************************************************
**  Mark and save possible outliers
** ****************************************************************
	drop if mi > 4
	drop if mi < .01
	
	bysort acause age sex: egen mean_all_country = mean(mi)
	bysort acause age iso3 sex: egen mean_in_country = mean(mi)
	bysort acause age sex: egen sd_all_country = sd(mi)
	bysort acause age iso3 sex: egen sd_in_country = sd(mi)
	
	gen residual_all_country = abs(mi - mean_all_country)
	gen residual_in_country = abs(mi - mean_in_country)
	
	// Flag data points if they are greater than 2 standard deviations from the mean,

	gen flag_reason = ""
	replace flag_reason = "mi is greater than 1.5 sd from the all-country mean (for acause-age-sex)" if (residual_all_country > 1.5 * sd_all_country)
	replace flag_reason = "in-country sd is greater than 1.5x the all-country sd (for acause-age-sex)" if sd_in_country > 1.5*sd_all_country
	replace flag_reason = "in-country mean is less than 0.5x the all-country mean (for acause-age-sex)" if mean_in_country < 0.5*mean_all_country
	replace flag_reason = "in-country mean is less than all-country mean by more than 0.5 (for acause-age-sex)" if mean_in_country < mean_all_country - 0.5
	replace flag_reason = "in-country mean is greater than 2x the all-country mean (for acause-age-sex)" if mean_in_country > 2*mean_all_country
	replace flag_reason = "in-country mean is greater the all-country mean by more than 0.5 (for acause-age-sex)" if mean_in_country > mean_all_country + 0.5
	replace flag_reason = "mi is greater than 1.5 sd from the in-country mean (for acause-age-sex)" if residual_in_country > 1.5 * sd_in_country
	replace flag_reason = "mi is greater than 1.5x the in-country mean (for acause-age-sex)" if mi > 1.5 * mean_in_country
	replace flag_reason = "mi is less than 0.5x the in-country mean (for acause-age-sex)" if mi < 0.5 * mean_in_country
	replace flag_reason = substr(flag_reason, 3, .) if substr(flag_reason, 1, 2) == ", "
	gen flag = 1 if flag_reason != ""
	
	preserve
		keep if flag ==1
		drop flag resid*
		sort flag_reason iso3
		order sex acause year age iso3 flag mi mean* sd* cases deaths pop
		sort flag_reason sex acause iso3 age year
		compress
		save "`outlier_folder'/possible_outliers_for_`today'_dataset.dta", replace
	restore


** ****************************************************************
** End calculateMI
** ****************************************************************	
