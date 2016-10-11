/// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 		12 December 2014
// Project:		RISK
// Purpose:		Extract DHS for IPV
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
		cap restore, not
	// Reset timer (?)
		timer clear	
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
		
// Set locals for relevant files and folders
	local data_dir "/WORK/05_risk/risks/abuse_ipv_exp/data/exp/01_tabulate/"
	
// Countrycodes 

// Bring in country codes and location id
	clear
	#delim ;
	odbc load, exec("SELECT ihme_loc_id, location_name, location_id, location_type
	FROM shared.location_hierarchy_history 
	WHERE (location_type = 'admin0' OR location_type = 'admin1' OR location_type = 'admin2' OR location_type = 'nonsovereign')
	AND location_set_version_id = (
	SELECT location_set_version_id FROM shared.location_set_version WHERE 
	location_set_id = 9
	and end_date IS NULL)") dsn(epi) clear;
	#delim cr
	
	rename ihme_loc_id iso3 
	
	// Fix weird symbols that import as question marks 
	replace location_name = subinstr(location_name, "?", "o", .) if regexm(iso3, "JPN")
	replace location_name = subinstr(location_name, "?", "a", .) if regexm(iso3, "IND")
	replace location_name = "Chhattisgarh" if location_name == "Chhattasgarh"
	replace location_name = "Chhattisgarh, Rural" if location_name == "Chhattasgarh, Rural" 
	replace location_name = "Chhattisgarh, Urban" if location_name == "Chhattasgarh, Urban" 
	replace location_name = "Jammu and Kashmir" if location_name == "Jammu and Kashmar" 
	replace location_name = "Jammu and Kashmir, Rural" if location_name == "Jammu and Kashmar, Rural"
	replace location_name = "Jammu and Kashmir, Urban" if location_name == "Jammu and Kashmar, Urban" 
	
	keep if regexm(iso3, "IND") 
	
	tempfile countrycodes
	save `countrycodes', replace	
	

// Bring in master compiled dataset
	use "`data_dir'/raw/dhs/compiled_raw_revised.dta", clear
	
// Remove archived Zambia file that is a duplicate
	drop if regexm(file, "ARCHIVE")

// Recode variables to be consistent across country-years (0=not exposed, 1 = exposed)
	drop s516_*
	unab varlist : d105* s1205* d106 d107 d108 s720* s704 s712 s516* s515*
	// local varlist s720kx
	foreach var of local varlist {
		replace `var' = lower(`var')
		replace `var' = "0" if inlist(`var', "never", "no", "not at all", "No")
		replace `var' = "1" if regexm(`var', "2|yes|Yes|sometimes|often|partner|boyfriend|not in last 12 months")
		replace `var' = "" if inlist(`var', "dk", "no response given", "no answer", "missing")
		tab `var'
		destring `var', replace
	}


	gen exposure = . 

	*** BOL 2008 
			//  s1205* 

		foreach var of varlist s1205* {
			replace exposure = 1 if `var' == 1 & regexm(file, "BOL") & regexm(file, "2008") 
			replace exposure = 0 if `var' == 0 & exposure != 1 & regexm(file, "BOL") & regexm(file, "2008")
		}

	*** ADD MALI 2006 AND HND 2005_2006 HERE
			// d106 d107 d108

		foreach var of varlist d106 d107 d108 { 
			replace exposure = 1 if `var' == 1 & (regexm(file, "MLI_DHS5_2006") | regexm(file, "HND_DHS5_2005"))
			replace exposure = 0 if `var' == 0 & exposure != 1 & (regexm(file, "MLI_DHS5_2006") | regexm(file, "HND_DHS5_2005"))
		}


	*** ADD ZMB 2001/2002 HERE 
			// s720*

		foreach var of varlist s720c s720fi s720fj s720fk s720ha s720hb s720hk s720hl s720ka s720kb s720kp s720kq { 
			replace exposure = 1 if `var' == 1 & regexm(file, "ZMB") 
			replace exposure = 0 if `var' == 0 & exposure != 1 & regexm(file, "ZMB") 
		}

	** ADD IND 1998 / 1999 HERE 
			// s515 s516*


		replace exposure = 1 if s515 == 1 & regexm(file, "IND") & (s516h == 1 | s516i == 1 | s516j == 1)
		replace exposure = 0 if s515 == 0 & exposure != 1 & regexm(file, "IND") 


	** ADD ZAF 1998
			// s704 s712

		replace exposure = 1 if s704 == 1 | s712 == 1 
		replace exposure = 0 if (s704 == 0 | s712 == 0) & exposure != 1 
		replace exposure = . if (s704 == . | s712 == .) & exposure != 1 & regexm(file, "ZAF") 

	// save "J:/WORK/05_risk_old/02_models/abuse_ipv/01_exp/01_tabulate/data/raw/dhs/partway.dta", replace



	// use "J:/WORK/05_risk_old/02_models/abuse_ipv/01_exp/01_tabulate/data/raw/dhs/partway.dta",clear 
	
// Construct exposure variable for those that have d105* series

	** create country-year group identifier
	egen group = group(file)

	tempfile all 
	save `all', replace 

	// New Surveys (BOL, ZAF, IND, ZMB, MLI) added that have different IPV variables
	keep if inlist(group, 5, 23, 28, 39, 71, 72)

	gen exclude = 1 if regexm(v502, "Never|never")
	drop if exclude == 1

	tempfile new 
	save `new', replace
	
	// Old surveys that were included in GBD 2013 that are all d105* 
	use `all', clear
	drop if inlist(group, 5, 23, 28, 39, 71, 72)  
	drop if regexm(file, "BOL_DHS4") 

	** Individual is exposed if answers "yes" to one or more violence questions
	egen exposure_new = rowtotal(d105*), miss
	replace exposure_new = 1 if exposure_new >=1 & exposure_new != . 
	** Generate individual-level count of missing responses
	egen individual_missingness = rowmiss(d105*)	
	** Generate country-year level count of missing responses (the number of questions asked vary so we want to keep track of what proportion of questions that were asked were answered by each individual)
	foreach var of varlist d105* {
		bysort group: egen sum`var' = total(`var'), miss
	}
	egen group_missingness = rowmiss(sum*)
	** Exclude individuals who did not answer all questions that were asked
	gen dif = individual_missingness - group_missingness
	gen exclude = 1 if regexm(v502, "Never|never")
	
// Make exposure variable missing for all observations that are not part of the analysis
	drop if exclude == 1 

	append using `new'
	
// Replace 
	replace exposure = exposure_new if exposure_new != . 
	drop exposure_new
	//drop if exposure == . 

	tempfile new_and_old
	save `new_and_old', replace

// Calculate missingess 
	bysort file: gen total = _N 

	levelsof file, local(surveys)

	local count = 1 
	foreach survey of local surveys {
		preserve 
		keep if file == "`survey'" 
		count if exposure == .
		gen missingness = `r(N)' / total
		tempfile `count'
		save ``count'', replace
		local count = `count' + 1
		restore
		
	}

	local terminal = `count' - 1
	clear
	forvalues x = 1/`terminal' {
		di `x'
		qui: cap append using ``x'', force
	}


	keep file missingness
	collapse (first) missingness, by(file)
	tempfile missing 
	save `missing', replace

// Calculate mean and standard error of the exposure, by country/year/age/sex
	** First, generate country/year/age/sex variables

	use `new_and_old', clear 

	split file, parse("/") gen(file)
	rename file4 iso3
	rename file5 year
	split year, parse("_")
	rename (year1 year2) (year_start year_end)
	replace year_end = year_start if year_end == "" 
	gen age = v012
	gen sex = 2
	local bins = "10(5)75"
	egen age_group = cut(age), at(`bins')
	foreach var of varlist v021 v022 d005 {
		cap destring `var'
		replace `var' = . if `var' == -9999
		}
	** Must divide 8 digit weight by 1,000,000 to get the actual weight
	replace d005 = d005 / 1000000


// Keep only necessary variables 
	// keep file iso3 year year_start year_end age sex age_group dv_selection missingness d005 v022 v021


	** Extract prevalence
	quietly do "j:/WORK/04_epi/01_database/01_code/02_central/01_code/dev/svy_subpop.ado"
	quietly do "j:/WORK/04_epi/01_database/01_code/02_central/01_code/prod/adofiles/svy_svyset.ado"
	
	levelsof file, local(surveys)
	// preserve
	tempfile original_data
	save `original_data'
	local tmp = 1
	foreach survey of local surveys {
		// restore,preserve
		use `original_data', clear 
		keep if file == "`survey'"
		svy_svyset, pweight(d005) psu(v021) strata(v022)

		if regexm("`survey'", "IND") {
			preserve 
			bysort file iso3 year_start year_end age_group sex subnational: svy_subpop exposure,tab_type("prop") replace
			
			tempfile `tmp'
			save ``tmp''
			local tmp = `tmp' + 1
		
			restore
			bysort file iso3 year_start year_end age_group sex: svy_subpop exposure,tab_type("prop") replace
			
			tempfile `tmp'
			save ``tmp''
			local tmp = `tmp' + 1
			
			}
			
		else {
		bysort file iso3 year_start year_end age_group sex: svy_subpop exposure,tab_type("prop") replace
		
		tempfile `tmp'
		save ``tmp''
		local tmp = `tmp' + 1
		
		}
		
	}

	clear
	forvalues i=1/`=`tmp'-1' {
		append using ``i''
	}
	
	tempfile new 
	save `new', replace 
	
		
// Format for Dismod
	** drop proportion unexposed
	drop *0
	
	** Rename to prepare for reshape
	rename exposure_1 parameter_value
	rename exposure_sample sample_size
	rename exposure_se standard_error
	
	** Format variables for epi 
	rename age_group age_start
	gen age_end = age_start + 4
	destring year_start year_end, replace
	
	** Specify study level covariates
	gen spouseonly = 0
	gen physvio = 0
	gen severe = 0
	gen sexvio = 0
	gen nointrain = 0
	gen notviostudy1 = 1
	gen currpart = 1
	gen pastyr = 0
	gen past2yr = 0
	gen pstatcurr = 0
	gen pstatall = 1
	drop if parameter_value == . | parameter_value == 1
	gen units = 1
	gen description = "DHS microdata"
	gen survey_name = "DHS"
	
	merge m:1 file using `missing' 
	keep if _m == 3 
	drop _m

	** Organize
	local keep iso3 subnational year_start year_end sex age_start age_end sample_size parameter_value standard_error spouseonly severe physvio sexvio nointrain notviostudy1 currpart pastyr past2yr pstatall pstatcurr units survey_name description file missingness
	keep `keep'
	order `keep'
	
	split file, gen(path) parse("/")
	gen path = path1 + "/" + path2 + "/" + path3 + "/" + path4 + "/" + path5
	drop path1-path6
	tempfile extraction
	save `extraction', replace
	
	** Match 
	
	keep if iso3 == "IND" 
	rename subnational location_name
	replace location_name = "India" if location_name == ""
	replace iso3 = ""
	
	merge m:1 location_name using `countrycodes', keep(3) nogen
	tostring location_id, replace
	replace iso3 = "IND" + "_" + location_id if location_name != "India"
	replace iso3 = "IND" if location_name == "India"
	
	tempfile india 
	save `india', replace 
	
	use `extraction', clear
	drop if iso3 == "IND" 
	append using `india'
	
	drop subnational location_type
	
	tempfile all 
	save `all', replace 
	
	** Get NIDs

		clear
		set debug on
		#delim ;
		odbc load, exec("SELECT fl.field_location_value location, fn.field_file_name_value filename, records.nid record_nid, records.file_id file_nid
		FROM
		(SELECT entity_id nid, field_internal_files_target_id file_id
		FROM ghdx.field_data_field_internal_files) records
		JOIN ghdx.field_data_field_location fl ON fl.entity_id = records.file_id
		JOIN ghdx.field_data_field_file_name fn ON fn.entity_id= records.file_id
		ORDER BY record_nid") dsn(ghdx) clear;
		#delim  cr

		rename location path
		collapse (first) record_nid, by(path)
	
		replace path = subinstr(path,"\","/",.)
		duplicates tag path, gen(dup) 
		drop if dup != 0 

		//gen file = path + "/" + filename
		//duplicates drop file, force
		
		merge 1:m path using `all', nogen keep(2 3 4 5)
		
		rename record_nid nid 
		
	
	save "`data_dir'/prepped/dhs_tabulation_currpart_revised.dta", replace
