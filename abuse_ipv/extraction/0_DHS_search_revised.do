// Date: May 11, 2015
// Purpose: Secondhand-smoke extraction from DHS

***********************************************************************************
** SET UP
***********************************************************************************

// Set application preferences
	clear all
	set more off
	cap restore, not
	set maxvar 32700
	
// change directory
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	cd "$prefix/WORK/04_epi/01_database/01_code/02_central/survey_juicer"

// import functions
	run "./svy_extract_admin/populate_codebooks.ado"
	run "./svy_extract_admin/make_mirror.ado"
	run "./svy_search/svy_search_assign.ado"
	run "./svy_extract/svy_extract_assign.ado"
	run "./svy_extract/svy_encode_apply.ado"
	run "./tabulations/svy_svyset.ado"
	run "./tabulations/svy_subpop.ado"
	run "./tabulations/svy_group_ages.ado"
	
	

***********************************************************************************
** RUN SEARCH
***********************************************************************************

// run search for variables (currently case sensative must fix this!!!!!)
	svy_search_assign , /// 
	job_name(ipv_search_vars_revised) /// 																					This is what your final file will be named
	output_dir($prefix/WORK/05_risk/risks/abuse_ipv_exp/data/exp/01_tabulate/raw/dhs) /// 							This is where your final file will be saved
	svy_dir($prefix/DATA/MACRO_DHS) ///																				This is the directory of the data you want to search through
	lookat("d105 D105 D105A D105B D106 v001 V001 v005 V005 mv005 v012 V012 mv012 v021 V021 mv021 v022 V022 mv022 v023 V023 psu primary sampling pweight strata stratum violence spouse Ever husband/partner s1205 partner s515 s516 beaten s906 s907 s720 s712 forced sexual intercourse")	/// 
	recur ///																					This tells the program to look in all sub directories
	variables /// 
	descriptions /// 
	// val_labels																							/// This tells the program to at variable names
	
	/*

***********************************************************************************
** CREATE MIRROR DIRECTORY
***********************************************************************************
	
// make a mirror directory of J:/DATA/MACRO_DHS
	make_mirror, ///
	data_root($prefix/DATA/MACRO_DHS) ///																	This is the directory that you want to make a copy ok
	mirror_location(/snfs3/WORK/05_risk/temp/explore/second_hand_smoke) //			This is where you want to save the copy
	
	
	
***********************************************************************************
** POPULATE CODEBOOKS
***********************************************************************************
		
// open search file for example purposes
	use "/snfs3/WORK/05_risk/temp/explore/second_hand_smoke/shs_dhs_search_vars.dta", clear  
		
// this section renames things so that they match the names required to produce an "ihme standard codebook"
	drop file
	rename filename file
	rename variable svy_var
	rename path directory

// this section creates the "map" between the variable name in the survey, and what we want it to be called
	gen ihme_var = ""  //													This creates an empty variable which we will fill
	replace ihme_var = "smoke_female" if svy_var == "v463z" //				This sets ihme_var equal to are standard name (smoke_female) any time the variable in the survey is equal to "v463z"
	replace ihme_var = "smoke_male" if svy_var == "mv463z" //					
	replace ihme_var = "amount_female" if svy_var == "v464" //					
	replace ihme_var = "amount_male" if svy_var == "mv464" //							
	replace ihme_var = "under_5" if svy_var == "v137" //
	replace ihme_var = "cluster" if svy_var == "v001" //
	replace ihme_var = "pweight_w" if svy_var == "v005" // 
	replace ihme_var = "pweight_m" if svy_var == "mv005" // 
	replace ihme_var = "psu" if svy_var == "v021" // 
	replace ihme_var = "strata" if svy_var == "v022" // 
	replace ihme_var = "age_m" if svy_var == "mv012" // 
	replace ihme_var = "age_f" if svy_var == "v012"
		
// set primary key
	gen unique_id = "id" // 													This makes the primary key for every file

// drop crude
	drop if regexm(directory,"CRUDE") // 									This drops anything from the CRUDE directory
	keep if regexm(file, "CUP") 
	drop if ihme_var == ""
	
// propogate to codebooks 
	populate_codebooks , ///
	mirror_root(/snfs3/WORK/05_risk/temp/explore/second_hand_smoke/MACRO_DHS) //			This is where we want to save all our new definitions we just made. It should be the mirror directory
	
***********************************************************************************
** EXTRACT
***********************************************************************************

// run extraction
	svy_extract_assign, /// 
	svy_dir($prefix/DATA/MACRO_DHS) ///																	Here we specify where we want to get the variables from. Usually a spot on J:/DATA 
	primary_extract(smoke_female smoke_male under_5) ///												This is where we specify what our indicator variables are
	secondary_extract(amount_female amount_male cluster pweight_w pweight_m psu strata age_m age_f) /// This is where we specify what our demographic and survey design variables are
	job_name(shs_extract) ///																		This is what our final file will be called
	output_dir(/snfs3/WORK/05_risk/temp/explore/second_hand_smoke) ///				This is where our final file will be saved
	mirror_location(/snfs3/WORK/05_risk/temp/explore/second_hand_smoke) ///	This is where the code should look for your codebooks. It should be 1 directory below the "survey_dir" eg (survey_dir = ".../WHO_WHS/ARE" the mirror_location = ".../WHO_WHS")
	recur //																							This tells the program to look in all sub-directories

	
	
***********************************************************************************
** CLEAN DATA
***********************************************************************************

// open extration file for example purposes
	use "/snfs3/WORK/05_risk/temp/explore/second_hand_smoke/shs_extract.dta", clear

// Clean up variables after extraction process 
	drop amount_female__s amount_male__s age_m__s strata__s labels
	
// A loop to clean out nulls created during extraction. Any variable that is null in a survey is recoded to -9999 during extraction
	foreach var of varlist * {
		cap replace `var' = . if `var' == -9999
	}
	
// drop rows where we don't have the data we need
	// drop if smoke_female == . 
	// drop if smoke_male == . 
	
save "/snfs1/WORK/05_risk/02_models/smoking_shs/01_exp/01_tabulate/data/raw/shs_dhs_extract.dta", replace

*/
