** *************************************************************************************************************************************************** **
** 3/19/14
**
** This age splits under-5 shock deaths 
** 1. format the shock data like a normal CoD input dataset
** 2. run age splitting
** 3. format the data back to the way it was
** *************************************************************************************************************************************************** **


** *************************************************************************************************************************************************** **
** set up stata
	clear
	clear matrix
	clear mata
	capture restore, not
	set more off
	if c(os) == "Unix" {
		global j ""
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j ""
	}

	ssc install bygap
	
	local date = c(current_date)
	local today = date("`date'", "DMY")
	local year = year(`today')
	local month = month(`today')
	local day = day(`today')
	local time = c(current_time)
	local time : subinstr local time ":" "", all
	local length : length local month
	if `length' == 1 local month = "0`month'"	
	local length : length local day
	if `length' == 1 local day = "0`day'"
	global date = "`year'_`month'_`day'"
	global timestamp = "${date}_`time'"
	
** *************************************************************************************************************************************************** **
** define directories
	// file to start with
		global in_file1 "war_deaths_draws.dta"
		global in_file2 "disaster_deaths_draws.dta"
	// folder to save all the outputs		
		global out_dir ""

// ESTABLISH DIRECTORIES
	// What we call the data: same as folder name
		global data_name "_Shock"
	// output directory
		global out_dir ""
	// countrycodes directory
		global countrycodes "IHME_COUNTRY_CODES_Y2013M07D26.DTA"
	
** *************************************************************************************************************************************************** **
** prep countrycodes file for what we want to do with it
	use "$countrycodes", clear
	keep if indic_cod == 1
	keep iso3 location_id type gbd_country_iso3 gbd_analytical_region_local gbd_non_developing
	** make region a numerical code
	replace gbd_analytical_region_local = subinstr(gbd_analytical_region_local, "R", "", .)
	destring gbd_analytical_region_local, replace
	** remake dev_status into the format we use in RDP
	tostring gbd_non_developing, replace
	replace gbd_non_developing = "G" + gbd_non_developing if substr(gbd_non_developing, 1, 1)!="G"
	** give them normal names
	rename gbd_non_developing dev_status
	rename gbd_analytical_region_local region
	duplicates drop
	tempfile country_codes
	save `country_codes', replace
	gen replaceisos = iso3
	drop iso3
	tempfile replaceisos
	save `replaceisos'
	
** 1. format the shock data like a normal CoD input dataset

	// load the data
	use "$in_file1", clear
	append using "$in_file2"
	
	// store start information
	sum shocks
	local totalstart = `r(sum)'
	
	// First create a source variable, so we know the origin of each country year
		gen source = "_Shock"

		// if the source is different across appended datasets, give each dataset a unique source_label
		gen source_label = ""
	
	// APPEND - add new source_labels if needed
	
	// source_types: Burial; Cancer registry; Census; Hospital; Mortuary; Police; Sibling history, survey; Surveillance; Survey; VA National; VA Subnational; VR; VR Subnational
		gen source_type = "VR"

** ************************************************************************************************* **		 
// REMOVE DATA THAT SHOULD NOT BE INCLUDED IN FINAL DATASET

** ************************************************************************************************* **
// CHECK EACH VARIABLE

	// location_id (numeric) if it is a supported subnational site located in this directory: 
		merge m:1 iso3 using `country_codes'
		replace iso3 = gbd_country_iso3 if gbd_country_iso3!=""
		drop if _m == 2
		replace location_id = . if type != "admin1"
		gen national = 1 if type != "admin1"
		drop type _m
		
	// subdiv (string): if you can't find a location id for the specific locatation (e.g. rural, urban, Jakarta, Southern States...) enter it here, otherwise leave ""
		// THIS FIELD CANNOT HAVE COMMAS (OTHER CHARACTERS ARE FINE)
		rename sim subdiv
		tostring subdiv, replace
		
	// list (string): what is the tabulation of the cause list: ICDs are "10det" "10tab" "9det" "9BTL" "8A". if custom, give the source (e.g. DSP, VA-custom)
		gen list = "_Shock"
	// cause (string)
		// Format the cause list from the compiled datasets to be consistent accross them
		// NOTE: IF THIS DATASET DOES NOT COVER ALL DEATHS (FOCUSES ON JUST INJURIES OR SOMETHING) YOU MUST CREATE
		// A ROW FOR 'CC' (COMBINED CODE) FOR EACH COUNTRY-YEAR SO THAT CAUSE FRACTIONS CAN BE CALCULATED LATER. 
		// CC SHOULD REPRESENT ALL DEATHS ATTRIBUTED TO CAUSES OTHER THAN THOSE THAT ARE THE FOCUS OF THE STUDY.
		// THE NUMBERS FOR THIS SHOULD BE FOUND SOMEWHERE IN THE ORIGINAL DATA SOURCE. 
		gen cause = "war" if war == 1
		replace cause = "disaster" if war == 0
	// cause_name (string)
		// If the causes are just codes, we will need a cause_name to carry its labels, if available. Otherwise leave blank.
		gen cause_name = cause
	
	// year - we need to prep pre-1970 with 1970 populations
		replace subdiv = subdiv + ":" + string(year) if year<1970
		replace year = 1970 if year<1970
		
	// sex (numeric): 1=male 2=female 9=missing
		gen sex = 9

	// frmat (numeric): 
		gen frmat = 9
	
	// im_frmat (numeric): from the same file as above
		gen im_frmat = 8
	
	// age is wide, using the suffix "deaths"
		** format into WHO age codes before hitting the step.
		rename shocks deaths26 
		gen deaths1 = 0
		gen deaths2= 0
		gen deaths3 = 0
		gen deaths4 = 0
		gen deaths5 = 0
		gen deaths6 = 0
		gen deaths7 = 0
		gen deaths8 = 0
		gen deaths9 = 0
		gen deaths10 = 0
		gen deaths11 = 0
		gen deaths12 = 0
		gen deaths13 = 0
		gen deaths14 = 0
		gen deaths15 = 0
		gen deaths16 = 0
		gen deaths17 = 0
		gen deaths18 = 0
		gen deaths19 = 0
		gen deaths20 = 0
		gen deaths21 = 0
		gen deaths22 = 0
		gen deaths23 = 0
		gen deaths24 = 0
		gen deaths25 = 0
		gen deaths91 = 0
		gen deaths92 = 0
		gen deaths93 = 0
		gen deaths94 = 0

	// deaths (numeric): If deaths are in CFs or rates, find the proper denominator to format them into deaths	
	
		
		// fill in the deaths variables 
		aorder
		// make sure all deaths variables are present in data
			forvalues i = 1/26 {
				capture gen deaths`i' = 0
			}

		// recalculate deaths1
			 capture drop deaths1
			 foreach i of numlist 2/26 91/94 {
				capture gen deaths`i' = 0
			 }
			 aorder
			 egen deaths1 = rowtotal(deaths3-deaths94)

** ************************************************************************************************* ** 
// STOP! DO A QUICK VARIABLES CHECK
	// If any of the variables in our template are missing, create them now (even if they are empty)
	// All of the following variables should be present
		#delimit ;
		order		
		iso3 subdiv location_id national 
		source source_label source_type NID list 
		frmat im_frmat 
		sex year cause cause_name
		deaths1 deaths2 deaths3 deaths4 deaths5 deaths6 deaths7 deaths8 deaths9 deaths10 deaths11 deaths12 deaths13 deaths14 deaths15 
		deaths16 deaths17 deaths18 deaths19 deaths20 deaths21 deaths22 deaths23 deaths24 deaths25 deaths26 deaths91 deaths92 deaths93 deaths94 ;

	// Drop any variables not in our template of variables to keep
		keep		
		iso3 subdiv location_id national region dev_status
		source source_label source_type NID list 
		frmat im_frmat 
		sex year cause cause_name
		deaths1 deaths2 deaths3 deaths4 deaths5 deaths6 deaths7 deaths8 deaths9 deaths10 deaths11 deaths12 deaths13 deaths14 deaths15 
		deaths16 deaths17 deaths18 deaths19 deaths20 deaths21 deaths22 deaths23 deaths24 deaths25 deaths26 deaths91 deaths92 deaths93 deaths94 ;
		#delimit cr

** ************************************************************************************************* **
// SPECIAL TREATMENTS ACCORDING TO RESEARCHER REQUESTS
	// HERE YOU MAY POOL AGES, SEXES, YEARS
	
	// HERE YOU MAY HAVE SOURCE-SPECIFIC ADJUSTMENTS THAT ARE NOT IN THE PREP OR COMPILE
		** add acause since that's needed for splitting
		gen acause = "inj_war" if cause == "war"
		replace acause = "inj_disaster" if cause == "disaster"
** ************************************************************************************************* **
// SAVE AS FORMATTED AND MAPPED DATA
	collapse(sum) deaths*, by(region dev_status acause iso3 subdiv location_id national source source_label source_type NID list frmat im_frmat sex year cause cause_name) fast
	compress
	label drop _all
	saveold "01_mapped.dta", replace
	saveold "01_mapped_${timestamp}.dta", replace

// Now submit as if it were part of the CoD data process
	// feed it the macros it needs
	local sources "_Shock"
	local source "_Shock"
	global username dgonmed
	global temp_dir ""
	global source_dir ""
	global prog_dir ""
	
	! rm -rf "02_agesexsplit.dta"
	
	// submit the job
	qsub -pe multi_slot 6 -l mem_free=10g -N "" "shellstata12_${username}.sh" "split_agesex.do" "$username `source' $timestamp $temp_dir $source_dir"
	
	di "" "shellstata12_${username}.sh" "split_agesex.do" "$username `source' $timestamp $temp_dir $source_dir"
	
// Check that the file has completed
		noisily display in red "+++++++++++++++++++++| 02 AGE-SEX-SPLIT |+++++++++++++++++++++", _newline
		foreach source of local sources {
			capture confirm file "02_agesexsplit.dta"
			if _rc == 601 noisily display "Started searching for age-sex-split `source' at `c(current_time)'"
			while _rc == 601 {
				capture confirm file "02_agesexsplit.dta"
				sleep 10000
			}
			if _rc == 0 {
				noisily display "AGE-SEX-SPLIT: `source'"
			}
		}
		
	local source "_Shock"
// Now use the file!
	
		use "02_agesexsplit.dta", clear
		rename subdiv sim
		split sim, parse(:)
		destring sim2, replace
		replace year = sim2 if sim2 != .
		drop sim sim2
		rename sim1 sim
		destring sim, replace
		if (frmat == 2) {
			keep cause frmat im_frmat iso3 location_id sex sim year deaths*
		}
		else {
		di in red "deaths format has changed, re-examine code"
		}
		merge m:1 location_id using `replaceisos'
		drop if _m == 2
		replace iso3 = replaceisos if _m == 3
		drop _m
		
		// reformat the deaths to our conventions from WHO frmat 2 and im_frmat 2
		// we are only using this for under-5 shocks
		keep cause iso3 sex sim year deaths2 deaths3
		gen shocks = deaths2 + deaths3
		drop deaths*
		gen age = "under-5"
		drop cause
	
		saveold "age_sex_split_shocks_deaths_draws.dta", replace
	
	
	
	