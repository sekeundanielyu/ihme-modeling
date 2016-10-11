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
	
	local rerun_search 0
	
***********************************************************************************
** RUN SEARCH
***********************************************************************************

if `rerun_search' == 0 {

// run search for variables (currently case sensative must fix this!!!!!)
	svy_search_assign , /// 
	job_name(shs_dhs_search_vars) /// 																					This is what your final file will be named
	output_dir(/snfs3/WORK/05_risk/temp/explore/second_hand_smoke) /// 							This is where your final file will be saved
	svy_dir($prefix/DATA/MACRO_DHS) ///																				This is the directory of the data you want to search through
	lookat("v463 v464 mv463 mv464 v137 v001 v005 mv005 v012 mv012 v021 mv021 v022 mv022 psu primary sampling pweight strata stratum v151 mv151") /// 	These are the variable names you want to search for
	recur ///																										This tells the program to look in all sub directories
	variables /// 
	descriptions ///																										This tells the program to at variable names
	

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
	
save "/snfs1/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/shs_dhs_extract.dta", replace

*/

************************************
** GENERATE INDICATOR VARIABLE
************************************

use "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/shs_dhs_extract.dta", clear


// Definition of SHS from DHS: "Non-smokers who live with a spouse or parent that smokes"
	
	// (1) First create female dataset 
	preserve
	drop age_m amount_male amount_female pweight_m 
	
		// Female non-smokers whose husband smokes 
			gen shs = 1 if smoke_female == 1 & smoke_male == 0
			replace shs = 0 if smoke_female == 1 & smoke_male == 1 // if neither are smokers
			drop if smoke_female == . | smoke_male == . 
			drop if smoke_female == 0 // only want to include non-smokers
		
		// Clean up dataset 
			drop smoke_female__s smoke_male__s smoke_female smoke_male under_5
			rename pweight_w pweight 
			rename age_f age 
			gen sex = 2 
			
			tempfile shs_women 
			save `shs_women', replace 
	
	// (2) Male dataset 
	restore 
	preserve 
	drop age_f amount_female amount_male pweight_w 
	
		// Male non-smokers whose wife smokes 
			gen shs = 1 if smoke_female == 0 & smoke_male == 1 
			replace shs = 0 if smoke_male == 1 & smoke_female == 1 // if neither are smokers 
			drop if smoke_female == . | smoke_male == . 
			drop if smoke_male == 0 // only want to include non-smokers
			
		// Clean up dataset 
			drop smoke_female__s smoke_male__s smoke_female smoke_male under_5
			rename pweight_m pweight 
			rename age_m age 
			gen sex = 1 
			
			tempfile shs_men 
			save `shs_men', replace
	
	// (3) Child dataset - want to calculate the prevalence of second-hand smoke exposure for children < 5
	restore
		
		// Drop if households have no children under age 5 and expand observations so that we have one row for each child
			drop if under_5 == 0 
			expand under_5, gen(child)
			drop if smoke_male == . & smoke_female == . 
			drop if smoke_male == 9 | smoke_female == 9 
			
		// Generate SHS indicator variable  
			gen shs = 1 if smoke_female == 0 & smoke_male == 1 // mom smokes, dad doesn't
			replace shs = 1 if smoke_male == 0 & smoke_female == 1 // dad smokes, mom doesn't
			replace shs = 1 if smoke_male == 0 & smoke_female == 0 // both smoke 
			replace shs = 1 if smoke_male == 0 & smoke_female == . // dad smokes, mom unknown 
			replace shs = 1 if smoke_female == 0 & smoke_male == . // mom smokes, dad unknown 
			replace shs = 0 if smoke_female == 1 & smoke_male == 1 // neither smoke 
			replace shs = 0 if smoke_male == 1 & smoke_female == . // dad doesn't smoke, mom unknown 
			replace shs = 0 if smoke_female == 1 & smoke_male == . // mom doesn't smoke, dad unknown
			
		// Clean up dataset (use same pweight as mothers, as the DHS says) 
			drop smoke_female__s smoke_male__s smoke_female smoke_male under_5 pweight_m age_f age_m amount_male amount_female child
			rename pweight_w pweight 
			gen sex = 3
			gen age = . // Will define GBD age group later for under 5 group 
			
			tempfile shs_children 
			save `shs_children', replace 
			
	append using `shs_women' 
	append using `shs_men' 
	tempfile all 
	save `all', replace

************************************
** STRATIFY AGES 
************************************

	egen age_start = cut(age), at(15(5)65)
	replace age_start = 97 if age_start == . // gbd age 97 represents the under 5 age group 
	levelsof age_start, local(ages)
	drop age
	
	** First, generate country/year/age/sex variables
	split path, parse("/") gen(path)
	rename path4 iso3
	rename path5 year
	split year, parse("_")
	rename year1 year_start 
	rename year2 year_end
	drop path1 path2 year 
	rename path6 file	

	** Must divide 8 digit weight by 1,000,000 to get the actual weight
	replace pweight = pweight / 1000000

************************************
** TABULATE
************************************	
	
// initialize storage file. always run this section. It creates a temporary file to store things in.
	preserve
		clear
		tempfile tabs
		save `tabs', replace emptyok
	restore

// each file must be in memory individually for the svyset command to function properly so we loop through them all

	levelsof path, local(files)	//											we find all files in our dataset and store them in a local called files
	foreach path of local files { //											we start to loop through them
	
		preserve // 															preserve the dataset in memory so that we can restore it later
		
			keep if path == "`path'" // 										only keep the current file we are working on in our loop
			
		// here we declare the surveyset using a convenience wrapper function
			svy_svyset , ///  												
			pweight(pweight) ///												the variable that means weight
			strata(strata) ///												the variable that means stratification
			psu(psu) //														the varialbe that means primary sampling unit
			
		// then we call the tabulation function where the "bylist" is a unique stratification
			bysort path age_start sex year_start : ///						this is where we decare what stratifications we want to tabulate our data into
			svy_subpop ///													function call
			shs, ///															this is the variable we want to tabulate
			tab_type(prop) ///												this is where we tell the function what type of tabulation we want to do. options are (mean and prop (proportion))
			replace	// 														lastly we tell it to replace whatever is in memory with our new tabulations
			
		// append it all together
			append using `tabs' //											we append to our temporary storage file created earlier
			save `tabs', replace //											then resave it
			
		restore //															and finally restore the pre tabulated dataset
	}
	

************************************
** EXPORT FINAL DATASET
************************************		
	use `tabs', clear // 													now we open up our tabulations that we saved in a temporary file
	
	** First, generate country/year/age/sex variables
	split path, parse("/") gen(path)
	rename path4 iso3
	rename path5 year
	split year, parse("_")
	
	drop year1 path1 path2 year
	rename year2 year_end 
	rename path3 survey
	rename path6 file
	drop shs_0 // only care about the exposed population
	
	rename shs_1 mean 
	rename shs_se se 
	
	// Format child data to make it consistent with how it was done in 2013 and how it is inputed into the compile code 
	gen mean_ch = . 
	replace mean_ch = mean if sex == 3 & age_start == 97
	gen se_ch = . 
	replace se_ch = se if sex == 3 & age_start == 97 
	replace mean = . if mean_ch != . 
	replace se = . if se_ch != . 
	
	rename file name 
	rename path file 
	rename age_start gbd_age
	replace gbd_age = . if gbd_age == 97 
	drop year_end
	rename shs_sample sample_size
	
	order file name iso3 year_start gbd_age sex mean se mean_ch se_ch sample_size 
	sort file sex gbd_age 
	
	drop if sample_size < 10 // These means are too unstable
	
	// drop if iso3 == "IND" // Wnat to extract both national and subnational India DHS
	
	save "J:/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped/dhs_revised.dta", replace 
	
	
