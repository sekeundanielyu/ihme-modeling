// Date: May 11, 2015
// Purpose: Secondhand-smoke extraction from Global Youth Tobacco Survey 

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
	local run_extract 0 

	
// Bring in country codes 
	
	// Prepare countrycodes database 
	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & inlist(level, 3, 4)

	keep ihme_loc_id location_id location_ascii_name location_name super_region_name super_region_id region_name region_id
	
	rename ihme_loc_id iso3 
	tostring location_id, replace
	//rename location_ascii_name location_name
	
	tempfile countrycodes
	save `countrycodes', replace


// if `rerun_search' == 1 {
/*
***********************************************************************************
** RUN SEARCH
***********************************************************************************


// run search for variables (currently case sensative - be aware of this) 
	svy_search_assign , /// 
	job_name(shs_gyts_search_vars) /// 															This is what your final file will be named
	output_dir(/share/epi/risk/temp/smoking_shs/) /// 							This is where your final file will be saved
	svy_dir($prefix/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY) ///										This is the directory of the data you want to search through
	lookat("finalwgt" "strat" "psu" "inr84" "cr32" "CR32" /// 
	"home" "sex" "gender" "are you a boy" "Do you parents smoke cigerttes?" "Do your parents smoke" "Do your parents or custodian smoke" /// 
	"Which or your parents" "Does any of your close family members smoke?" "parent smok" "guard" "parents (or guardians)" /// 
	"parents smok" "Do your parents" "PARENTAL SMOKING" "Where do you usually smoke" "In what place do you usually smoke" /// 
	"where do you smoke" "In what kind of place do you live" "past 30 days" "how many days have people smoked" "past 7 days" "How often do you see" "smoking in your home" "smoked in your home") /// 				These are the variable names you want to search for
	recur ///																					This tells the program to look in all sub directories
	variables /// 
	descriptions /// 
	val_labels
		


***********************************************************************************
** CREATE MIRROR DIRECTORY
***********************************************************************************
	
// make a mirror directory of J:/DATA/MACRO_DHS

	make_mirror, ///
	data_root($prefix/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY) ///							This is the directory that you want to make a copy of
	mirror_location(/share/epi/risk/temp/smoking_shs) //			This is where you want to save the copy


***********************************************************************************
** POPULATE CODEBOOKS
***********************************************************************************
	
// open search file for example purposes
	use "/share/epi/risk/temp/smoking_shs/shs_gyts_search_vars.dta", clear  
		
// this section renames things so that they match the names required to produce an "ihme standard codebook"
	drop file
	rename filename file
	rename variable svy_var
	rename path directory

// this section creates the "map" between the variable name in the survey, and what we want it to be called
	// Stata can only handle uniquely named variables for a given dataset and therefore since the smoking questions are asked in different ways across surveys, have to create series of different smoking vars that will be combied later
	gen ihme_var = ""  //		

// Standard variables	
	replace ihme_var = "sex" if regexm(description, "sex") | regexm(description, "are you a boy") | regexm(description, "gender") | svy_var == "czr57" 
	replace ihme_var = "sex" if svy_var == "CR83" & regexm(file, "HRV_GYTS_2011") 
	replace ihme_var = "sex" if svy_var == "CR53" & regexm(file, "STP_GYTS_2010") 
	replace ihme_var = "" if svy_var == "CR85" & regexm(file, "HRV_GYTS_2011") 
	replace ihme_var = "age" if regexm(description, "how old are you?") 
	replace ihme_var = "weight" if regexm(svy_var, "finalwgt") | regexm(svy_var, "FinalWgt") 
	replace ihme_var = "strata" if regexm(svy_var, "Strat") | regexm(svy_var, "strat") 
	replace ihme_var = "psu" if regexm(svy_var, "psu") 
	replace ihme_var = "urban" if regexm(svy_var, "inr84") | regexm(description, "in what kind of place do you live?")
	
// Smoking variables
	replace ihme_var = "smoke1" if svy_var == "kwr58"
	replace ihme_var = "smoke2" if svy_var == "syr58" 
	replace ihme_var = "smoke3" if svy_var == "syr75" 
	replace ihme_var = "smoke4" if svy_var == "syr60" 
	replace ihme_var = "smoke5" if regexm(description, "do you smoke now?")
	replace ihme_var = "smoke6" if regexm(description, "did you smoke cigarettes?")
	replace ihme_var = "smoke7" if regexm(description, "how many days did you smoke cig")
	replace ihme_var = "smoke8" if regexm(description, "how many days you smoked")
	replace ihme_var = "smoke9" if regexm(description, "where do you usually smoke?")
	replace ihme_var = "smoke10" if regexm(description, "Where do you smoke?")
	replace ihme_var = "smoke11" if regexm(description, "how many days you have smoked?")
	replace ihme_var = "smoke12" if regexm(description, "where do you usually smoke shisha?")
	replace ihme_var = "smoke13" if regexm(description, "how many days did you smoke shisha")
	replace ihme_var = "smoke14" if regexm(description, "where do you usually smoke bidis")
	replace ihme_var = "smoke15" if regexm(description, "on how many days did you smoke cigars, cigarillos") 


// Parental smoking variables
	replace ihme_var = "parent" if regexm(description, "do your parents smoke?") 
	replace ihme_var = "parent" if svy_var == "NZR10" 
	replace ihme_var = "parent" if regexm(description, "your parents") & regexm(description, "smoke") 
	replace ihme_var = "parent" if regexm(description, "you parents") & regexm(description, "smoke") 
	replace ihme_var = "parent" if regexm(description, "do your parents/grandparents/guardians smoke?")
	replace ihme_var = "parent_hun_f" if svy_var == "HUR23" 
	replace ihme_var = "parent_hun_m" if svy_var == "HUR24"
	replace ihme_var = "parent_shisha" if regexm(description, "do your parents smoke shisha?")
	replace ihme_var = "parent_bidi" if regexm(description, "do your parents smoke bidi?") 
	replace ihme_var = "past_7_days" if regexm(description, "how many days have people smoked in your home")
	
// Other family members variable
	replace ihme_var = "other_shisha" if regexm(description, "does anyone in your house other than your parents smoke shisha")
	replace ihme_var = "other_cig" if regexm(description, "does anyone in your house other than your parents smoke cigarettes") | ///
	regexm(description, "any other person living with you") | regexm(description, "does anyone in your immediate family members, other than") | ///
	regexm(description, "does your guardian or any other person living with you smoke?") | /// 
	regexm(description, "do any other adults")

// Irrelevant variables
	replace ihme_var = "" if regexm(description, "know that you smoke cigarettes?") | regexm(description, "know you smoke cigarettes") | /// 
	regexm(description, "know that you smoke") | regexm(description, "allow you to smoke") | regexm(description, "are your parents okay with letting") | /// 
	regexm(description, "know that you are a smoker") | regexm(description, "know you smoke") | regexm(description, "know the you smoke cigarettes") | ///
	regexm(description, "now that you smoke cigarettes") | regexm(description, "argilla") | regexm(description, "know that smoke cigarettes") | regexm(description, "narguileh") | ///
	regexm(description, "chicha") | regexm(description, "told you not to smoke") | regexm(description, "sexy and attractive") | regexm(description, "how often do you see your") | /// 
	regexm(description, "water pipe") | regexm(description, "narguile") | regexm(description, "when you go to sports events") 
	
	// What about the question: "do your parents chew or apply tobacco" 
	// "Does anyone in your house other than your parents smoke cigarettes?" 
	// Should shisha be included? 

// Frequency in which family members smoke in home 
	replace ihme_var = "past_7_days" if regexm(description, "how many days have people smoked in your home") | regexm(description, "anyone at home smoke in your presence")
	replace ihme_var = "past_7_days" if regexm(description, "home|presence|past 7 days|presenc") & svy_var == "cr32" & regexm(file, "BRA")
	replace ihme_var = "past_7_days" if regexm(description, "during the past 7 days, on how many days") & (svy_var == "cr30" | svy_var == "CR30")

	//replace ihme_var = "past_7_days" if regexm(description, "smoked in your presenc") 
	
// set primary key
	gen unique_id = "id" // 													

// drop crude
	keep if regexm(file, "LABELED") // 									
	drop if ihme_var == ""
	
// Codebooks are wrong in some places so make adjustments

drop if (svy_var == "CR13" | svy_var == "CR16") & directory == "/home/j/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/ZAF/2011"
drop if svy_var == "CR35" & directory == "/home/j/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/ZAF/2011"
drop if svy_var == "CR55" & regexm(file, "CZE_GYTS_2011") 
drop if svy_var == "KRR67" & regexm(file, "KOR_GYTS_2008") 
drop if svy_var == "CR52" & regexm(file, "LKA_GYTS_2011") 
drop if svy_var == "mor33" & regexm(file, "MAC_GYTS_2001")
drop if svy_var == "GRPpsu" & regexm(file, "PAK_QUETTA_GYTS_2004") 
drop if svy_var == "GRPstrat" & regexm(file, "PAK_QUETTA_GYTS_2004")
drop if svy_var == "pbr68" & regexm(file, "PSE_GAZA_STRIP_GYTS_2000") 
drop if svy_var == "pbr68" & regexm(file, "PSE_WEST_BANK_GYTS_2000") 
drop if svy_var == "CR30" & regexm(file, "ZAF_GYTS_2011") 
drop if svy_var == "cr33" & ihme_var == "past_7_days" & regexm(file, "BRA")

// Make sure we identify duplicates 

 // First drop duplicates of svy_var (not sure why the search function is generating duplicates)
	egen group = group(file)
	levelsof group, local(groups)

	sort group svy_var
	by group svy_var: gen dup = cond(_N==1,0,_n)
	drop if dup > 1
	drop dup
// Then evaluate duplicates of my variable (ihme_var)
	sort group ihme_var
	by group ihme_var: gen dup = cond(_N==1,0, _n)
	drop if dup > 1 
	drop dup


// propogate to codebooks 
	populate_codebooks , ///
	mirror_root(/share/epi/risk/temp/smoking_shs/GLOBAL_YOUTH_TOBACCO_SURVEY) //	



}

***********************************************************************************
** EXTRACT
***********************************************************************************

// run extraction

	svy_extract_assign, /// 
	svy_dir($prefix/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY) ///																	Here we specify where we want to get the variables from. Usually a spot on J:/DATA 
	primary_extract(smoke1 smoke2 smoke3 smoke4 smoke5 smoke6 smoke7 smoke8 smoke9 smoke10 smoke11 smoke12 smoke13 smoke14 smoke15 parent parent2 parent_hun_f parent_hun_m parent_shisha parent_bidi past_7_days other_shisha other_cig) ///												This is where we specify what our indicator variables are
	secondary_extract(sex age weight strata psu urban) /// This is where we specify what our demographic and survey design variables are
	job_name(shs_gyts_extract) ///																		This is what our final file will be called
	output_dir(/share/epi/risk/temp/smoking_shs) ///				This is where our final file will be saved
	mirror_location(/share/epi/risk/temp/smoking_shs) ///	This is where the code should look for your codebooks. It should be 1 directory below the "survey_dir" eg (survey_dir = ".../WHO_WHS/ARE" the mirror_location = ".../WHO_WHS")
	recur //																							This tells the program to look in all sub-directorie





***********************************************************************************
** CLEAN DATA
***********************************************************************************
// open extration file for example purposes
	use "/share/epi/risk/temp/smoking_shs/shs_gyts_extract.dta" , clear  
	
// drop bad data. we scan the dataset and find these ones lack weight variables
	drop if weight == . 
	
// run encode loop
	svy_encode_apply *__s // 												This command recodes and combines variables that were split during extraction
	
// A loop to clean out nulls created during extraction. Any variable that is null in a survey is recoded to -9999 during extraction
	foreach var of varlist * {
		cap replace `var' = . if `var' == -9999
	}
	
	save "/snfs1/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/shs_gyts_extract_new.dta", replace
	


*/

if `run_extract' == 1 { 

***********************************************************************************
** DEFINE INDICATOR VARIABLES FOR SECONDHAND SMOKE
***********************************************************************************

use "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/shs_gyts_extract_new.dta", clear

// ************************ MAIN SHS INDICATOR ****************************************/ 
// Question: During the past 7 days, on how many days have people smoked in your home, in your presence? 
	
	// 1 = 0 days 
	// 2 = 1-2 days 
	// 3 = 3-4 days
	// 4 = 5-6 days 
	// 5 = 7 days 

	recode past_7_days (1 = 0) (2 = 1) (3 = 1) (4 = 1) (5 = 1) (6 = 1) 



// ************************ PARENTAL SMOKING****************************************/


// (which assesses whether a parent/guardian or someone in the house smokes) 

	// 1 = neither parent smokes --> recode as 0 
	// 2 = both; 3 = father only; 4 = mother only --> recode all as 1 
	// 5 don't know 
    // 6, 7 and 8 have different meanings in different surveys but either mean they're ex-smokers, or don't know 
	
	replace parent = 0 if parent == 1
	replace parent = 1 if inlist(parent, 2, 3, 4) 


// In some cases, parent/guardian/relative smoking variable is defined differently, so recdoe based on these exceptions to the rule 
	// Brazil Macapa 2007 (5 is i have no parents and 6 is I don't know)
	replace parent = 0 if parent == 5 & (regexm(path, "MACAPA_GYTS_2007") | regexm(path, "JOAO_PESSOA") | regexm(path, "SALVADOR_GYTS_2005") | /// 
	regexm(path, "FORTALEZA_GYTS_2006") | regexm(path, "CPV_GYTS_2007") | regexm(path, "CURITIBA_GYTS_2006") | regexm(path, "BELEM_GYTS_2006") | /// 
	regexm(path, "PALMAS_GYTS_2006") | regexm(path, "PALMITOS_GYTS_2007") | regexm(path, "NATAL_GYTS_2006") | regexm(path, "RIO_DE_JANEIRO_GYTS_2005") | /// 
	regexm(path, "CATAGUASES_GYTS_2006") | regexm(path, "BRA_SAO_LUIS_GYTS_2006"))
	
	replace parent = 1 if parent == 6 & (regexm(path, "MACAPA_GYTS_2007") | regexm(path, "JOAO_PESSOA") | regexm(path, "SALVADOR_GYTS_2005") | /// 
	regexm(path, "FORTALEZA_GYTS_2006") | regexm(path, "CPV_GYTS_2007") | regexm(path, "CURITIBA_GYTS_2006") | regexm(path, "BELEM_GYTS_2006") | /// 
	regexm(path, "PALMAS_GYTS_2006") | regexm(path, "PALMITOS_GYTS_2007") | regexm(path, "NATAL_GYTS_2006") | regexm(path, "RIO_DE_JANEIRO_GYTS_2005") | /// 
	regexm(path, "CATAGUASES_GYTS_2006") | regexm(path, "BRA_SAO_LUIS_GYTS_2006"))
	
	// Egypt 2005
	
	replace parent = 0 if inlist(parent, 5, 6, 7, 8) & regexm(path, "EGY_GYTS_2005") 
	replace parent = . if inlist(parent, 8) & regexm(path, "EGY_GYTS_2005") 
	
	// Egypt 2001
	
	replace parent = . if parent == 5 & regexm(path, "EGY_GYTS_2001") 
	replace parent = 1 if parent == 6 & regexm(path, "EGY_GYTS_2001") 
	
	// Saint Lucia 2000
	
	replace parent = . if parent == 5 & regexm(path, "LCA_GYTS_2000") 
	replace parent = 1 if parent == 6 & regexm(path, "LCA_GYTS_2000") 
	
	// Saint Lucia 2011
	
	replace parent = . if parent == 5 & regexm(path, "LCA_GYTS_2011") 
	replace parent = 1 if parent == 6 & regexm(path, "LCA_GYTS_2011") 

	// Kenya 2007 
	
	replace parent = 1 if parent == 5 & regexm(path, "KEN_GYTS_2007") 
	replace parent = . if parent == 6 & regexm(path, "KEN_GYTS_2007") 
	
	// Lesotho 2008 
	
	replace parent = 1 if parent == 5 & regexm(path, "LSO_GYTS_2008")
	replace parent = . if parent == 6 & regexm(path, "LSO_GYTS_2008") 
	
	// India (all GYTS surveys across states seem to be consistent in terms of the parental question) 
		// Should further investigate the applicability of this question to second-hand smoke since the question asks whether parents "smoke, chew or apply tobacco?" 
		// 5 = Grandfather only, 6 = Grandmother only, 7 = any other members
		
	replace parent = 1 if inlist(parent, 5, 6, 7) & regexm(path, "IND") 
	
	// Swaziland 2001
	replace parent = 1 if inlist(parent, 5, 6, 7) & regexm(path, "SWZ_GYTS_2001")
	replace parent = . if inlist(parent, 8) & regexm(path, "SWZ_GYTS_2001") 
	
	// Kosovo 2004 ( 5 is Grandfather and 6 is Grandmother so recode these as 1)
	
	replace parent = 1 if inlist(parent, 5, 6) & regexm(path, "KOSOVO_GYTS_2004") 
	
	// Myanmar 2001 
	
	replace parent = . if parent == 5 & regexm(path, "MMR_GYTS_2001") 
	replace parent = 1 if parent == 6 & regexm(path, "MMR_GYTS_2001") 
	
	// West Bank 2000
	
	replace parent = 1 if parent == 5 & (regexm(path, "PSE_WEST_BANK_GYTS_2000") | regexm(path, "PSE_GAZA_STRIP_GYTS_2000"))
	replace parent = 0 if parent == 6 & (regexm(path, "PSE_WEST_BANK_GYTS_2000") | regexm(path, "PSE_GAZA_STRIP_GYTS_2000"))
	replace parent = . if parent == 7 & (regexm(path, "PSE_WEST_BANK_GYTS_2000") | regexm(path, "PSE_GAZA_STRIP_GYTS_2000"))
	
	// Hungary 2008 GYTS asked about parental smoking in a slightly different fashion so replace the main parent variable with 1 if 
	
	replace parent = 0 if inlist(parent_hun_m, 1, 3) & regexm(path, "HUN_GYTS_2008") 
	replace parent = 1 if parent_hun_m == 2 & regexm(path, "HUN_GYTS_2008") 
	replace parent = 0 if inlist(parent_hun_f, 1, 3) & regexm(path, "HUN_GYTS_2008") 
	replace parent = 1 if parent_hun_f == 2 & regexm(path, "HUN_GYTS_2008") 

	// Solomon Islands 2008 
	recode parent (1=0) (0=1) if regexm(path, "SLB_GYTS_2008") 

// 5 indicates I don't know in the majority of surveys 

	replace parent = . if inlist(parent, 5)


// ************************ OTHERS WHO SMOKE IN THE HOUSE ****************************************// 

	// Make an indicator for others in the house who smoke that we capture other potential sources of SHS besides just parents 
	
	
	gen other = . 
	
	replace other = 1 if other_cig == 1 
	replace other = 0 if other_cig == 2 
	
	// KEN 2001
	
	replace other = 0 if other_cig == 1 & regexm(path, "KEN_GYTS_2001") 
	replace other = 1 if other_cig == 2 & regexm(path, "KEN_GYTS_2001") 
	
	// TTO 2000
	
	replace other = 0 if inlist(other_cig, 1, 2) & regexm(path, "TTO_GYTS_2000") 
	replace other = 1 if inlist(other_cig, 3, 4) & regexm(path, "TTO_GYTS_2000") 
	
	// replace parent = 1 if other == 1
	
	replace parent = 1 if other == 1 & parent == 0 
	
// ************************ SMOKING INDICATOR ****************************************// 


	// We need to exclude from our exposed population those people who are smokers because we don't consider them vulnerable to second-hand smoke 
		gen smoker = . 
	
	// Replace smoker variable patching together all of our smoking questions across surveys 
	
		// Do you smoke now question
		
		replace smoker = 0 if smoke1 == 1 
		replace smoker = 1 if inlist(smoke1, 2, 3, 4, 5) 
		
		replace smoker = 0 if inlist(smoke2, 1, 2, 3, 4) 
		replace smoker = 1 if inlist(smoke2, 5, 6, 7, 8) 
		
		replace smoker = 0 if inlist(smoke3, 1, 2, 4) 
		replace smoker = 1 if smoke3 == 3
		
		replace smoker = 0 if inlist(smoke5, 1) 
		replace smoker = 1 if inlist(smoke5, 2, 3, 4, 5) 
		replace smoker = . if smoke5 != . & (regexm(path, "NZL_GYTS_2010") | regexm(path, "SLB_GYTS_2008")) 
		
		// During the past 30 days, how many days did you smoke cigarettes? (since all questionnaires don't have the "do you smoke?" question, use these to fill in the gaps) 
	
		replace smoker = 0 if smoker == . & smoke6 == 1 
		replace smoker = 1 if smoker == . & inlist(smoke6, 2, 3, 4, 5, 6, 7) 
		
		replace smoker = 0 if smoker == . & smoke7 == 1 
		replace smoker = 1 if smoker == . & inlist(smoke7, 2, 3, 4, 5, 6, 7)
		
		replace smoker = 0 if smoker == . & smoke8 == 1 
		replace smoker = 1 if smoker == . & inlist(smoke8, 2, 3, 4, 5, 6, 7) 
		
		replace smoker = 0 if smoker == . & smoke9 == 1
		replace smoker = 1 if smoker == . & inlist(smoke9, 2, 3, 4, 5) 
		
		replace smoker = 0 if smoker == . & smoke11 == 1 
		replace smoker = 1 if smoker == . & inlist(smoke11, 2, 3, 4, 5, 6, 7) 
		
	// Keep only known non-smokers 
		
		keep if smoker == 0 
		
		tempfile all 
		save `all', replace
		
		// smoke9 is where do you usually smoke, smoke13 is about smoking shisha, smoke14 is about bidi, smoke15 about cigars 
	
	//save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/crosswalk_experiment", replace
	
	// Clean things up 
		 
	keep path psu strata weight urban sex parent smoker past_7_days
	
	
	
***********************************************************************************
** TABULATE MEAN EXPOSURE FOR EACH DEMOGRAPHIC GROUP
***********************************************************************************

// Set survey weights
	svyset psu [pweight=weight], strata(strata)	
	
	tempfile before_calc
	save `before_calc', replace

// Create empty matrix for storing calculation results
	mata 
		path = J(1,1,"path")
		sex = J(1,1,999)
		mean_parent_smoke = J(1,1,999)
		se_parent_smoke = J(1,1,999)
		ss_parent_smoke = J(1,1,999)
		mean_7_days = J(1,1,999)
		se_7_days = J(1,1,999)
		ss_7_days = J(1,1,999)
	end	
	
// ************* CALCULATE MEAN EXPOSURE TO SHS FOR ALL COUNTRIES (EXCEPT INDIA) *********

// Loop through countries, sexes and ages and calculate secondhand smoke prevalence among nonsmokers using survey weights 
		levelsof path, local(paths)
		levelsof sex, local(sexes) 
		
		foreach path of local paths {
			foreach sex of local sexes { 
			
				use `before_calc', clear
				keep if path == "`path'"
				
				count if path == "`path'" & sex == `sex' & parent != . & past_7_days != . 
				local sample_size = r(N)
						
				if `sample_size' > 0 {

					di in red  "File `path' sex `sex'" 

					** Extract parental smoking

					svy linearized, subpop(if path == "`path'" & sex == `sex' & parent != .): mean parent
						
						matrix mean_matrix = e(b)
						local mean_scalar = mean_matrix[1,1]
						mata: mean_parent_smoke = mean_parent_smoke \ `mean_scalar'
						
						matrix variance_matrix = e(V)
						local se_scalar = sqrt(variance_matrix[1,1])
						mata: se_parent_smoke = se_parent_smoke \ `se_scalar'

						mata: ss_parent_smoke = ss_parent_smoke \ `e(N_sub)'


				//count if path == "`path'" & sex == `sex' & past_7_days != . 

				//local sample_size = r(N)


					** Extract exposure in the last 7 days in the home 

					svy linearized, subpop(if path == "`path'" & sex == `sex' & past_7_days != .): mean past_7_days

						matrix mean_matrix = e(b)
						local mean_scalar = mean_matrix[1,1]
						mata: mean_7_days = mean_7_days \ `mean_scalar'
						
						matrix variance_matrix = e(V)
						local se_scalar = sqrt(variance_matrix[1,1])
						mata: se_7_days = se_7_days \ `se_scalar'
						
						mata: ss_7_days = ss_7_days \ `e(N_sub)'
					

						mata: path = path \ "`path'" 
						mata: sex = sex \ `sex'
					}
				}
			}
		
			
	// Get stored prevalence calculations from matrix
		clear

		getmata path sex mean_parent_smoke se_parent_smoke ss_parent_smoke mean_7_days se_7_days ss_7_days

		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
		
		recode se_parent_smoke (0=.) // Standard error should not be 0 so we will use sample size to estimate error instead
		recode se_7_days (0=.)

		tempfile mata_calculations
		save `mata_calculations'
		
	// Get iso3 and year from file path
		split path, p("/")
		drop path1 path2 path3 path4 path5 
		rename path6 iso3 
		
		gen year = regexs(0) if(regexm(path7, "[0-9]*$"))
		destring year, replace
		
		gen gyts_names = substr(path7, 1, length(path7) - 4)
		replace gyts_names = subinstr(gyts_names, "_", " ", .) 
		drop path7 path8 
		
		drop if path == "/home/j/DATA/GLOBAL_YOUTH_TOBACCO_SURVEY/IND/ODISHA_2002/IND_ODISHA_GYTS_2002_LABELED.DTA"
		
	// Drop Indian subnationals because  we have to calculate urban/rural 

		drop if iso3 == "IND" & gyts_names != ""
		
		tempfile all 
		save `all', replace
	
// ************* CALCULATE MEAN EXPOSURE TO SHS FOR INDIA URBAN/RURAL *********

	// Do mata calculations for India urban/rural 
		
		use `before_calc', clear
		
		split path, p("/")
		drop path1 path2 path3 path4 path5 
		rename path6 iso3 
		
		gen year = regexs(0) if(regexm(path7, "[0-9]*$"))
		destring year, replace
		
		gen gyts_names = substr(path7, 1, length(path7) - 4)
		replace gyts_names = subinstr(gyts_names, "_", " ", .) 
		drop path7 path8 
		
		keep if iso3 == "IND" & gyts_names ! = "" 
		
		// Create empty matrix for storing calculation results
	mata 
		path = J(1,1,"path")
		sex = J(1,1,999)
		mean_parent_smoke = J(1,1,999)
		se_parent_smoke = J(1,1,999)
		ss_parent_smoke = J(1,1,999)
		mean_7_days = J(1,1,999)
		se_7_days = J(1,1,999)
		ss_7_days = J(1,1,999)
	end	
	
// Loop through countries, sexes and ages and calculate secondhand smoke prevalence among nonsmokers using survey weights
		
		svyset psu [pweight=weight], strata(strata)	
		
		tempfile india
		save `india', replace 
		
		levelsof path, local(paths)
		levelsof sex, local(sexes) 
		levelsof urban, local(urbanicities)
		
		foreach path of local paths {
			foreach urban of local urbanicities {
				foreach sex of local sexes { 
			
				use `india', clear
				keep if path == "`path'"
				
				count if path == "`path'" & sex == `sex' & urban == `urban' & smoker != 1 & parent != . & past_7_days != . 

				local sample_size = r(N)
						
				if `sample_size' > 0 {

					di in red  "File `path' sex `sex' urban `urban'"
					
					svy linearized, subpop(if path == "`path'" & sex == `sex' & urban == `urban' & smoker != 1 & parent != .): mean parent
					** Extract exposure at home
					
						matrix mean_matrix = e(b)
						local mean_scalar = mean_matrix[1,1]
						mata: mean_parent_smoke = mean_parent_smoke \ `mean_scalar'
						
						matrix variance_matrix = e(V)
						local se_scalar = sqrt(variance_matrix[1,1])
						mata: se_parent_smoke = se_parent_smoke \ `se_scalar'

						mata: ss_parent_smoke = ss_parent_smoke \ `e(N_sub)'

					svy linearized, subpop(if path == "`path'" & sex == `sex' & urban == `urban' & smoker != 1 & past_7_days != .): mean past_7_days

						matrix mean_matrix = e(b)
						local mean_scalar = mean_matrix[1,1]
						mata: mean_7_days = mean_7_days \ `mean_scalar'
						
						matrix variance_matrix = e(V)
						local se_scalar = sqrt(variance_matrix[1,1])
						mata: se_7_days = se_7_days \ `se_scalar'
						
						mata: ss_7_days = ss_7_days \ `e(N_sub)'
					

						mata: path = path \ "`path'" 
						mata: sex = sex \ `sex'
						mata: urban = urban \ `urban' 
				}
			}
		}
	}
	

// Get stored prevalence calculations from matrix
		clear

		getmata path urban sex mean_parent_smoke se_parent_smoke ss_parent_smoke mean_7_days se_7_days ss_7_days

		drop if sex == . 
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
		
			recode se_parent_smoke (0=.) // Standard error should not be 0 so we will use sample size to estimate error instead
			recode se_7_days (0=.)

		tempfile mata_calculations_ind
		save `mata_calculations_ind'
		
		split path, p("/")
		drop path1 path2 path3 path4 path5 
		rename path6 iso3 
		
		gen year = regexs(0) if(regexm(path7, "[0-9]*$"))
		destring year, replace
		
		gen gyts_names = substr(path7, 1, length(path7) - 4)
		replace gyts_names = subinstr(gyts_names, "_", " ", .) 
		drop path7 path8 
		
		
		append using `all' 
		
		egen group = group(path) if regexm(path, "IND")

	sort group urban
	by group: gen count = _n 
	
	drop if regexm(path, "IND") & (count == 5 | count == 6) & urban == . 
	drop group count
		
	// 1 = live in village; 2 =  live in a town or city 
	
	replace gyts_names = gyts_names + (", RURAL") if urban == 1
	replace gyts_names = gyts_names + (", URBAN") if urban == 2
	replace gyts_names = "" if gyts_names != "" & iso3 == "IND" & urban == . 
	
	// No longer using rural/urban iso3 codes 
	replace iso3 = "IND" if iso3 == "XIR" 
	replace iso3 = "IND" if iso3 == "XIU"
	// Virgin islands has a new iso3 code for 2013
	replace iso3 = "VIR" if iso3 == "VGB"
	// Macao has a new iso3 code for 2013
	replace iso3 = "CHN" if iso3 == "MAC"
	
	preserve 
	drop if (regexm(iso3, "IND") & gyts_name != "") | regexm(iso3, "BRA") | regexm(iso3, "CHN") | /// 
	regexm(iso3, "MEX") | regexm(iso3, "SAU") 
	
	tempfile gyts 
	save `gyts', replace
	
	restore
	gen gyts_names_subnationals = "" 
	replace gyts_names_subnationals = gyts_names 
	
	replace gyts_names_subnationals = strproper(gyts_names)
	replace gyts_names_subnationals = "Macao Special Administrative Region of China" if iso3 == "CHN" & regexm(path, "MAC")
	
	keep if gyts_names_subnationals != ""  & (regexm(iso3, "IND") | regexm(iso3, "BRA") | regexm(iso3, "CHN") | regexm(iso3, "MEX") | regexm(iso3, "SAU"))
	drop gyts_names
	rename gyts_names_subnationals gyts_names
	replace gyts_names = strrtrim(gyts_names)
	tempfile subnationals
	save `subnationals', replace 
	
// Merge with codebook that maps GBD hierarchy location_names to GYTS survey names 

	import excel using "$j\WORK\05_risk\risks\smoking_shs\data\exp\01_tabulate\raw\GYTS_codebook_revised.xlsx", firstrow clear
	
	merge 1:m iso3 gyts_names using `subnationals' 
	// replace subnationals = "National" if subnationals == ""
	//rename subnationals location_name
	drop _merge
	//rename location_name location_ascii_name
	save `subnationals', replace
	
// Append using country codes 
	use `countrycodes', clear 
	duplicates tag location_name, gen(dup)
	drop if dup == 1 & iso3 != "MEX_4651" 

	// Fix weird symbols that import as question marks 
	replace location_name = subinstr(location_name, "?", "o", .) if regexm(iso3, "JPN")
	replace location_name = subinstr(location_name, "?", "a", .) if regexm(iso3, "IND")
	replace location_name = "Chhattisgarh" if location_name == "Chhattasgarh"
	replace location_name = "Chhattisgarh, Rural" if location_name == "Chhattasgarh, Rural" 
	replace location_name = "Chhattisgarh, Urban" if location_name == "Chhattasgarh, Urban" 
	replace location_name = "Jammu and Kashmir" if location_name == "Jammu and Kashmar" 
	replace location_name = "Jammu and Kashmir, Rural" if location_name == "Jammu and Kashmar, Rural"
	replace location_name = "Jammu and Kashmir, Urban" if location_name == "Jammu and Kashmar, Urban" 	

	merge 1:m location_name using `subnationals', keep(2 3 4 5)
	drop if _m == 1
	drop dup _merge 

// Append to larger GYTS file 

	append using `gyts' 

	// Assign Kosovo survey to Serbia
	replace iso3 = "SRB" if iso3 == "KOSOVO" 
	replace iso3 = "JOR" if iso3 == "JOR_UNRWA" 
	replace iso3 = "LBN" if iso3 == "LBN_UNRWA" 
	replace iso3 = "SYR" if iso3 == "SYR_UNRWA"

	
	rename location_id location_id_old 
	merge m:1 iso3 using `countrycodes', keep(3)
	drop location_id_old
	
	gen national = "Subnational" if location_name != ""
	drop gyts_names 
	

	// Fix paths 
	replace path = subinstr(path, "/home/j", "J:", .)
	gen file = path 
	
	gen example = regexs(0) if regexm(path,"[\/]([A-z.0-9]*)$")
	replace path = subinstr(path, example, "", .) 
	
	// Set variables that are always tracked

		gen id = _n
		reshape long mean_ se_ ss_, i(id) j(src) string
		
		gen cv_anybody_smoking = 0 if src == "7_days" 
		gen cv_act_of_smoking = 0 if src == "7_days"
		replace cv_anybody_smoking = 1 if src == "parent_smoke"
		replace cv_act_of_smoking = 1 if src == "parent_smoke"

		rename mean_ mean 
		rename se_ standard_error
		rename ss_ sample_size 

		gen survey = "GYTS"
		gen national_type_id = 10 if location_name != "" & (regexm(iso3, "BRA") | regexm(iso3, "MEX") | regexm(iso3, "SAU"))  // Representative of urban areas only
		replace national_type_id = 8 if location_name != "" & regexm(iso3, "IND") 
		replace national_type_id = 1 if national_type_id == .
		gen age_start = 0
		gen age_end = 15
		gen year_start = year
		gen year_end = year_start
		gen orig_unit_type = "Rate per capita"
		gen orig_uncertainty_type = "SE" 
		replace orig_uncertainty_type = "ESS" if standard_error == .
	
	// Organize
	order path file iso3 location_name year_start year_end sex age_start age_end sample_size mean standard_error, first
	sort path file iso3 location_name sex age_start age_end
	drop example id location_ascii_name location_name super_region_id super_region_name region_name subnationals urban _merge
	// Save to prepped data file 

	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped/gyts_subnationals_revised.dta", replace


