// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Project:		SDG
// Purpose:		Prep modern contraceptive data to feed into 1-step GPR
// Source: 		do /homes/username/_code/sdg/unmet_need/01_prep.do

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
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
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

// Store filepaths/values in macros
	local gbd_functions		"$prefix/WORK/10_gbd/00_library/functions"
	local survey_sizes		"$prefix/WORK/01_covariates/02_inputs/education/update_2017/data/input_data/admin0/single_year"
	local data_raw 			"$prefix/Project/Coverage/Contraceptives/2015 Contraceptive Prevalence Estimates/gpr_data/output/master_met_need_with_covariates.dta"
	local modern_contra		"$prefix/Project/Coverage/Contraceptives/2015 Contraceptive Prevalence Estimates/gpr_data/input/modern_contra/results"
	local modern_contra_id	203 //run id for best modern contra model
	local final_output 		"$prefix/Project/Coverage/Contraceptives/2015 Contraceptive Prevalence Estimates/gpr_data/input/unmet_need/prepped"
	local logs 				"/clustertmp/risk_factors/radon/temp/logs/"
	local age_mapping 		"$prefix/WORK/05_risk/central/documentation/age_mapping.csv"

// Function library	
	include `gbd_functions'/get_covariate_estimates.ado
	include `gbd_functions'/get_demographics.ado
	include `gbd_functions'/get_location_metadata.ado

** **************************************************************************
** PREP 
** **************************************************************************
// Bring in pop to aggregate modern contra

	get_location_metadata, location_set_id(35) clear
	levelsof location_id, local(locs)
	local locs "`locs' 44533" //add mainland china, not sure why not in here
	get_demographics, gbd_team(cod) 
	get_populations, year_id($year_ids) location_id(`locs') sex_id($sex_ids) age_group_id($age_group_ids) clear

	tempfile pop
	save `pop', replace

// read in the modern contra results, will be used as a covariate for this model
insheet using "`modern_contra'/`modern_contra_id'/gpr_results.csv", clear

keep location_id year_id age_group_id sex_id gpr_mean
rename gpr_mean cv_modern_contra

duplicates drop location_id year_id age_group_id sex_id, force

merge 1:1 location_id year_id age_group_id sex_id using `pop', keep(mat) nogen

bysort location_id year_id sex_id: egen tot_pop = total(pop)

gen weighted_contra = cv_modern_contra * pop_scaled / tot_pop 
bysort location_id year_id sex_id: egen tot_contra = total(weighted_contra)

//only going to be using the aggregate of 15-49 and reporting it as reference age 30
keep if age_group_id == 11

drop cv_modern_contra weighted_contra
rename tot_contra cv_modern_contra

tempfile contra_results
save `contra_results', replace

// Bring in the location metadata 	
	get_location_metadata, location_set_id(9) clear
		keep location_id location_name* location_ascii_name level location_type* super_region* region* ihme_loc_id
		rename ihme_loc_id iso3
		// Keep if national or subnational
		keep if level >= 3

		tempfile location_metadata
		save `location_metadata', replace

// read in the data, luckily it should be all prepped with the proper covariates
use "`data_raw'", clear	

//merge on location ID and meta
	merge m:1 iso3 using `location_metadata', keep(mat) nogen

//clean up dataset
keep iso3 countryname_ihme survey filename year agegroup met_need_modern_prev met_need_modern_var LDI edu pop_ location_id sample_size

** **************************************************************************
** PREP TO RUN THROUGH ST/GPR
** **************************************************************************
// Create variables required for Patty's new 1 step ST-GPR setup
// Generate sex variable for merges
	gen sex_id = 2 // this model is only for females
// Generate me_idIM S
	gen me_name = "unmet_need"


// The new ST-GPR setup requires that your DV be called "data", now can do log transforms, so no need to transform your data beforehand	
	//rename log_mean data
	rename met_need_modern_prev data
	rename met_need_modern_var variance

	//custom covariates must be prefixed with cv_*
	rename edu cv_edu
	rename LDI cv_ln_gdp
	rename pop_ cv_pop

// ST-GPR wants iso3 to be called ihme_loc_id
	rename iso3 ihme_loc_id

// format year and age
	rename year year_id

	preserve
	insheet using `age_mapping', clear
	drop if age_group_id==22
	keep age_start age_group_id
	rename age_start agegroup

	tempfile age_map
	save `age_map'

	restore

	merge m:1 agegroup using `age_map', keep(match) nogen
	rename agegroup age_start

	// use sample size to impute variance if need
	gen standard_error = (data*(1-data))/sample_size
	replace variance = standard_error ^ 2 if variance ==. & sample_size !=.

	// impute sample size/variance as max if needed
	summ sample_size
	local min_ss = `r(min)'

	replace sample_size = `min_ss' if sample_size == . & data != .


	summ variance
	local max_var = `r(max)'

	replace variance = `max_var' if variance == . & data != .

// Use temporary NID for now - add this when you find
	gen nid = 103125 

// We are only modeling for age group 30 and (15-49 aggregate)
	keep if age_start == 30

// finally, merge on modern contra to use as a covariate
	//note that here we want to keep non matches from the using as well because we need this covariate to be square (its not going to be on the db)
	merge m:1 location_id year_id age_group_id sex_id using `contra_results'
	drop _m
	
// Clean up dataset
	preserve

	local identifier_variables "location_id year_id age_group_id sex_id" // identifiers
	local data_variables "data variance sample_size" // datapoint info
	local covariate_variables "cv_modern_contra" // covariates
	local metadata_variables "age_start nid me_name survey filename" // other useful metadata //location_ascii_name age_group_name_short citation

	keep `identifier_variables' `data_variables' `covariate_variables' `metadata_variables'
	order `identifier_variables' `data_variables' `covariate_variables' `metadata_variable'

	gsort `identifier_variables'

	compress // try to make this insane file a wee bit smaller
