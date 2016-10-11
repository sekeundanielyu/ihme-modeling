** Description: Calculating EMR based on the raw incidence data from literature/hospital data and custom CODEm deaths
** Steps: (1) Create custom age groups for Echino deaths at the 1000 draw level; 
        **(2) Calculate CSMR as CSMR=deaths/population at the 1000 draw level --> calculate mean CSMR, UI and standard error; 
	    **(3) Calculate EMR as EMR=CSMR/prevalence; standard error of EMR will then be calculated taking into consideration the standard errors of both prevalence and CSMR

// LOAD SETTINGS FROM MASTER CODE

	// prep stata
	clear all
	set more off
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

	// base directory on J 
	local root_j_dir `1'
	// base directory on ihme/gbd (formerly clustertmp)
	local root_tmp_dir `2'
	// timestamp of current run (i.e. 2015_11_23)
	local date `3'
	// step number of this step (i.e. 01a)
	local step `4'
	// name of current step (i.e. first_step_name)
	local step_name `5'
	// step numbers of immediately anterior parent step (i.e. first_step_name)
	local hold_steps `6'
	// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
	local last_steps `7'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step'_`step_name'"
	// directory for output on ihme/gbd (formerly clustertmp)
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step'_`step_name'/03_outputs/01_draws"
	// directory for standard code files
	adopath + $prefix/WORK/10_gbd/00_library/functions
	adopath + $prefix/WORK/10_gbd/00_library/functions/utils

	di "`out_dir'/02_temp/02_logs/`step'.smcl""
	cap log using "`out_dir'/02_temp/02_logs/`step'.smcl", replace
	if !_rc local close_log 1
	else local close_log 0
	
	// check for finished.txt produced by previous step
	if "`hold_steps'" != "" {
		foreach step of local hold_steps {
			local dir: dir "`root_j_dir'/03_steps/`date'" dirs "`step'_*", respectcase
			// remove extra quotation marks
			local dir = subinstr(`"`dir'"',`"""',"",.)
			capture confirm file "`root_j_dir'/03_steps/`date'/`dir'/finished.txt"
			if _rc {
				di "`dir' failed"
				BREAK
			}
		}
	}	
//mkdir to save custom draws
 cap mkdir "`tmp_dir'/emr"

  // Load and save geographical names
   //DisMod and Epi Data 2015
   clear
   get_location_metadata, location_set_id(9)
 
  // Prep country codes file
  duplicates drop location_id, force
  tempfile country_codes
  save `country_codes', replace
 
// Prepare envelope and population data
// Get connection string
create_connection_string, server(modeling-mortality-db) database(mortality) 
local conn_string = r(conn_string)

 odbc load, exec("SELECT a.age_group_id, a.age_group_name_short AS age, a.age_group_name, o.sex_id, o.year_id, o.location_id, o.mean_env_hivdeleted AS mean_env, o.lower_env_hivdeleted AS lower_env, o.upper_env_hivdeleted AS upper_env, o.pop_scaled AS mean_pop FROM output o JOIN output_version USING (output_version_id) JOIN shared.age_group a USING (age_group_id) WHERE is_best=1")  `conn_string' clear
  
  tempfile demo
  save `demo', replace

  use "`country_codes'", clear
  merge 1:m location_id using "`demo'", nogen
  keep age age_group_id age_group_name sex_id year_id ihme_loc_id parent location_name location_id location_type region_name mean_env lower_env upper_env mean_pop
  keep if inlist(location_type, "admin0","admin1","admin2","nonsovereign", "subnational", "urbanicity")

   replace age = "0" if age=="EN"
   replace age = "0.01" if age=="LN"
   replace age = "0.1" if age=="PN"
   drop if age == "<5"
   keep if age_group_id <= 22
   destring age, replace
   
  keep if year_id >= 1980 & sex_id != 3
  sort ihme_loc_id year_id sex_id age
  tempfile pop_env
  save `pop_env', replace
 
************* Explore incidence data ************
** Explore incidence data to identify age groups, years and locations for which we'll need to create custom age groups for CE deaths
// Get the raw incidence data to list different age groups
import excel using "$prefix/WORK/04_epi/01_database/02_data/ntd_echino/1484/03_review/03_upload/deleted_central_emr_ntd_echino_1484_Y2016M06D03.xlsx", sheet("extraction") firstrow clear

//round age groups to the closest multiple of 5 
gen age_s = round(age_start,5)
gen age_e = round(age_end,5)
//convert from numeric to string
tostring age_s, replace
tostring age_e, replace

//creat age categories
gen age_cat = age_s+"-"+age_e

//explore age categories
sort age_start age_end
levelsof age_cat // From the list of age groups that appear (44), select those that are not GBD age groups (27): "0-0" "0-10" "0-15" "0-20" "0-5" "0-70" "0-90" "10-20" "15-100" "15-15" "20-100" "20-30" "30-40" "30-45" "40-50" "45-65" "5-15" "5-20" "5-65" "5-70" "5-85" "50-60" "60-100" "60-70" "65-100" "70-80" "70-90" 

//explore years
gen year_mean = (year_start+year_end)/2
gen year = round(year_mean, 1)
levelsof year  // Incidence data are available for 36 years: 1979 1980 1981 1982 1983 1984 1985 1986 1987 1988 1989 1990 1991 1992 1993 1994 1995 1996 1997 1998 1999 2000 2001 2002 2003 2004 2005 2006 2007 2008 2009 2010 2011 2012 2013 2014 

//explore locations
levelsof location_id	//137 locations

//Step 1: Create custom age groups for CE deaths
******************************************* 
// Get CODEm CE deaths
get_best_model_versions, gbd_team(cod) id_list(353) clear
preserve
keep if sex_id==1
local mvid1 = model_version_id
restore
keep if sex_id==2
local mvid2 = model_version_id

//males
get_models, type("cod") model_version_ids("`mvid1'")
 tempfile ce_deaths_male
 save `ce_deaths_male', replace

//females
get_models, type("cod") model_version_ids("`mvid2'")
 tempfile ce_deaths_female
 save `ce_deaths_female', replace
 
//append male deaths 
 append using `ce_deaths_male'
 
// Keep only the locations, years, and age groups for which we have
// Keep cause fraction (cf) only (because uncertainty intervals are available only for cf at this time)
keep if number_space == "cf"
//rename mean as cf
rename mean cf
// calculate se for cf
gen cf_se=(upper-lower)/(2*1.96)
drop lower upper

// merge pop_env
merge 1:1 location_id year_id age_group_id sex_id using `pop_env', keep(3) nogen

// calculate standard error for the envelope 
gen env_se = (upper_env-lower_env)/(2*1.96)

// calculate deaths
gen deaths = cf*mean_env

// calculate the standard error for deaths taking into consideration the standard errors of both cause fraction and envelope
gen deaths_se = deaths*sqrt((cf_se/cf)^2+(env_se/mean_env)^2)
keep location_id ihme_loc_id year_id sex_id age_group_id age_group_name deaths deaths_se mean_pop

// replace age group names with numerical values
 replace age_group_name="80 to 100" if age_group_name=="80 plus"
 replace age_group_name="0 to 0" if age_group_name=="Post Neonatal"
 replace age_group_name="0 to 100" if age_group_name=="All Ages"
 
// round GBD age groups to the closest multiple of 5 (e.g. 1-4 to 1-5; 5-9 to 5-10)
 split age_group_name, p( to )
 destring age_group_name1, replace
 destring age_group_name2, replace
 gen age_s = round(age_group_name1,5)
 gen age_e = round(age_group_name2,5) 
 gen age = age_s		
 tostring age_s, replace
 tostring age_e, replace
 gen age_cat = age_s+"-"+age_e		 
 replace age_cat = "1-5" if age_cat == "0-5"
 drop age_group_name1 age_group_name2 age_s age_e

 tempfile ce_deaths_both
 save `ce_deaths_both', replace
 
// rename variables 
rename year_id year
rename sex_id sex
rename ihme_loc_id iso3

// keep only the locations where we have incidence data (137 loc_ids)
keep if inlist(location_id, 36, 37, 39, 40, 41, 45, 46, 47, 51, 52, 53, 54, 55, 59, 60, 62, 72, 75, 76, 77, 78, 79, 82, 85, 86, 87, 90, 92, 93, 94, 95, 97, 98, 99, 101, 102, 122, 123, 141, 142, 144, 145, 155, 179, 189, 196, 212, 434, 482, 483, 484, 486, 487, 488, 489, 490, 501, 510, 525, 526, 527, 528, 532, 538, 543, 545, 551, 553, 555, 556, 570, 572, 4618, 4619, 4620, 4621, 4622, 4623, 4624, 4625, 4626, 4643, 4644, 4645, 4646, 4647, 4648, 4649, 4650, 4651, 4652, 4653, 4654, 4655, 4656, 4657, 4658, 4659, 4660, 4661, 4662, 4663, 4664, 4665, 4666, 4667, 4668, 4669, 4670, 4671, 4672, 4673, 4674, 4750, 4751, 4752, 4753, 4754, 4755, 4756, 4757, 4758, 4759, 4762, 4763, 4764, 4765, 4766, 4767, 4768, 4769, 4770, 4772, 4773, 4775, 4776, 35659)

// keep only the  years where we have incidence data (35 loc_ids > = 1980)
keep if inlist(year, 1980, 1981, 1982, 1983, 1984, 1985, 1986, 1987, 1988, 1989, 1990, 1991, 1992, 1993, 1994, 1995, 1996, 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014)


// generate 1000 death draws based on the mean and standard error

di in red "get 1,000 death draws"
	forvalues k = 1/1000 {
		gen deaths_`k' = rnormal(deaths, deaths_se)
	}
	drop deaths deaths_se
 
 // save a temporary file that inlcudes the "0-100" category only
preserve 
keep if age_cat=="0-100"
tempfile age_0to100
save `age_0to100', replace
restore

// save a temporary file for all other age groups, excluding the "0-100" category
drop if age_cat=="0-100"
tempfile all
save `all', replace

// calculate deaths for custom age groups: "0-0" "0-10" "0-15" "0-20" "0-5" "0-70" "0-90" "10-20" "15-100" "15-15" "20-100" "20-30" "30-40" "30-45" "40-50" "45-65" "5-15" "5-20" "5-65" "5-70" "5-85" "50-60" "60-100" "60-70" "65-100" "70-80" "70-90"

// create custom age groups for  "0-10"  "10-20"  "20-30" "30-40" "40-50" "50-60" "60-70" "70-80"
***********************************************************************************
	//REm: "0-0" "0-15" "0-20" "0-5" "0-70" "0-90" "15-100" "15-15" "20-100" "30-45" "45-65" "5-15" "5-20" "5-65" "5-70" "5-85" "60-100" "65-100" "70-90"

	use `all', clear
	forvalues i=0(10)70 {
		preserve
		local k = `i'+5
		keep if age>=`i' & age<=`k'
		collapse (sum) deaths_* mean_pop, by(location_id iso3 year sex)
		gen age = `i'
		gen age_s = age
		gen age_e = `i'+10
		tostring age_s, replace
		tostring age_e, replace
		gen age_cat = age_s+"-"+age_e
		tempfile tmp_`i'
		save `tmp_`i'', replace 
		restore
	}
	
	use "`tmp_0'", clear
	forvalues i=10(10)70 {
		qui append using "`tmp_`i''"
	}

tempfile custom_age_1
save `custom_age_1', replace

// create custom age groups for `"0-15"' `"15-30"' `"30-45"' `"45-60"' `"60-75"' 
*******************************************************************
	//Rem: "0-0" "0-20" "0-5" "0-70" "0-90" "15-100" "15-15" "20-100" "45-65" "5-15" "5-20" "5-65" "5-70" "5-85" "60-100" "65-100" "70-90"

	use `all', clear
	forvalues i=0(15)60 {
		preserve
		local k=`i'+10
		keep if age>=`i' & age<=`k'
		collapse (sum) deaths_* mean_pop, by(location_id iso3 year sex)
		gen age=`i'
		gen age_s=age
		gen age_e=`i'+15
		tostring age_s, replace
		tostring age_e, replace
		gen age_cat=age_s+"-"+age_e		
		tempfile tmp_`i'
		save `tmp_`i'', replace 
		restore
	}
	
	use "`tmp_0'", clear
	forvalues i=15(15)60 {
		qui append using "`tmp_`i''"
	}
	
tempfile custom_age_3
save `custom_age_3', replace


// create custom age groups for "10-100", "15-100", "20-100", ... , "75-100"
*****************************************************************
	//Rem: "0-0" "0-20" "0-5" "0-70" "0-90" "15-15" "45-65" "5-15" "5-20" "5-65" "5-70" "5-85" "70-90"
	use `all', clear
	forvalues i=10(5)75 {
		preserve
		keep if age>=`i' & age<100
		collapse (sum) deaths_* mean_pop, by(location_id iso3 year sex)
		gen age=`i'
		gen age_s=age
		gen age_e=100
		tostring age_s, replace
		tostring age_e, replace
		gen age_cat=age_s+"-"+age_e		
		tempfile tmp_`i'
		save `tmp_`i'', replace 
		restore
	}
	
	use "`tmp_10'", clear
	forvalues i=15(5)75 {
		qui append using "`tmp_`i''"
	}

tempfile custom_age_4
save `custom_age_4', replace

// create other custom age groups "0-0" "0-20" "0-5" "0-70" "0-90" "5-15"  "5-20"  "5-65" "5-70" "5-85" 15-15"  "45-65" "70-90"

// ages 0-0, 0-5 
use `all', clear
keep if age_cat=="0-0" | age_cat=="1-5"
collapse (sum) deaths_* mean_pop, by (location_id iso3 year sex) fast
gen age_cat="0-5"
tempfile gp_1
save `gp_1', replace

// ages "0-20"
use `all', clear
keep if age>=0 & age<=15
collapse (sum) deaths_* mean_pop, by (location_id iso3 year sex) fast
gen age_cat="0-20"
tempfile gp_2
save `gp_2', replace

// ages "0-70"
use `all', clear
keep if age>=0 & age<=65
collapse (sum) deaths_* mean_pop, by (location_id iso3 year sex) fast
gen age_cat="0-70"
tempfile gp_3
save `gp_3', replace

// ages "0-90" //this should be similar to 0-100
use `all', clear
keep if age>=0 & age<=85
collapse (sum) deaths_* mean_pop, by (location_id iso3 year sex) fast
gen age_cat="0-90"
tempfile gp_4
save `gp_4', replace

// ages "5-15"
use `all', clear
keep if age>=5 & age<=10
collapse (sum) deaths_* mean_pop, by (location_id iso3 year sex) fast
gen age_cat="5-15"
tempfile gp_5
save `gp_5', replace

// ages "5-20"
use `all', clear
keep if age>=5 & age<=15
collapse (sum) deaths_* mean_pop, by (location_id iso3 year sex) fast
gen age_cat="5-20"
tempfile gp_6
save `gp_6', replace

// ages "5-65"
use `all', clear
keep if age>=5 & age<=60
collapse (sum) deaths_* mean_pop, by (location_id iso3 year sex) fast
gen age_cat="5-65"
tempfile gp_7
save `gp_7', replace

// ages "5-70"
use `all', clear
keep if age>=5 & age<=65
collapse (sum) deaths_* mean_pop, by (location_id iso3 year sex) fast
gen age_cat="5-70"
tempfile gp_8
save `gp_8', replace

// ages "5-85"  //this should be similar to 5-100
use `all', clear
keep if age>=5 & age<=80
collapse (sum) deaths_* mean_pop, by (location_id iso3 year sex) fast
gen age_cat="5-85"
tempfile gp_9
save `gp_9', replace

// ages "15-15" //assume age 15-20 (original incidence data is 15-17)
use `all', clear
keep if age>=15 & age<=15
collapse (sum) deaths_* mean_pop, by (location_id iso3 year sex) fast
gen age_cat="15-15"
tempfile gp_10
save `gp_10', replace

// ages "45-65"
use `all', clear
keep if age>=45 & age<=60
collapse (sum) deaths_* mean_pop, by (location_id iso3 year sex) fast
gen age_cat="45-65"
tempfile gp_11
save `gp_11', replace

// ages "70-90"  //this should be similar to 70-100
use `all', clear
keep if age>=70 & age<=85
collapse (sum) deaths_* mean_pop, by (location_id iso3 year sex) fast
gen age_cat="70-90"
tempfile gp_12
save `gp_12', replace

// append the files
use `all', clear
quietly append using `custom_age_1'
//append using `custom_age_2'	//not in CE inc data
quietly append using `custom_age_3'
quietly append using `custom_age_4'

//append using `custom_age_5'	//not in CE inc data
quietly append using `gp_1'
quietly append using `gp_2'
quietly append using `gp_3'
quietly append using `gp_4'
quietly append using `gp_5'
quietly append using `gp_6'
quietly append using `gp_7'
quietly append using `gp_8'
quietly append using `gp_9'
quietly append using `gp_10'
quietly append using `gp_11'
quietly append using `gp_12'

//append the "0-100" age category
append using `age_0to100'

tempfile deaths_male_female
save `deaths_male_female', replace

// calculate deaths for both sexes
use `deaths_male_female', clear
collapse (sum) deaths_* mean_pop, by (location_id iso3 year age_cat) fast
//gen sex="Both"
gen sex = 3
tempfile deaths_both
save `deaths_both', replace

// append the files so that male, female and both sexes will be in the same file

use `deaths_male_female', clear
append using `deaths_both', force
tempfile deaths_ready
save `deaths_ready', replace

save "`tmp_dir'/emr/CE_death_draws_custom_age_groups.dta", replace

use "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_echino/1484/04_models/gbd2015/03_steps/2016_06_03/03_emr_calculation/03_outputs/01_draws/emr/CE_death_draws_custom_age_groups.dta"

//Step 2: Calculate CSMR as CSMR=deaths/population
********************************************
    // calculate csmr at the 1000 draw level
	forvalues x = 1/1000 {
		** Convert deaths to death rates (csmr)
		gen csmr_`x' = deaths_`x'/mean_pop
				}
	drop deaths*
		
	// calculate mean CSMR and UIs 
	egen mean_csmr=rowmean(csmr_*)
	egen upper_csmr=rowpctile(csmr_*), p(97.5)
	egen lower_csmr=rowpctile(csmr_*), p(2.5)
	drop csmr_*
	
	// calculate standard error of CSMR
	gen se_csmr = (upper_csmr - lower_csmr)/(2*1.96)
	save "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_echino/1484/04_models/gbd2015/03_steps/2016_06_03/03_emr_calculation/03_outputs/01_draws/emr/CE_csmr.dta", replace

	tostring sex, replace
	replace sex = "Male" if sex=="1"
	replace sex = "Female" if sex == "2"
	replace sex = "Both" if sex == "3"	
	tempfile csmr
	save `csmr', replace	

// Step 3: Calculate EMR as EMR=CSMR/(incidence * average duration). For CE assume remission of 0.15 to 0.25 i.e 2-6.7years(average = 0.2 i.e 5years)
*********************************************************************************************************************************
// get the raw incidence data
import excel using "/home/j/WORK/04_epi/01_database/02_data/ntd_echino/1484/03_review/03_upload/deleted_central_emr_ntd_echino_1484_Y2016M06D03.xlsx", sheet("extraction") firstrow clear

// fill in the missing standard errors
replace standard_error = (upper-lower)/(2*1.96) if standard_error==.
replace standard_error = sqrt(mean*(1-mean)/sample_size) if standard_error==.
//round age groups to the closest multiple of 5 
gen age_s = round(age_start,5)
gen age_e = round(age_end,5)
//convert from numeric to string
tostring age_s, replace
tostring age_e, replace
//creat age categories
gen age_cat = age_s+"-"+age_e		
//calculated mean year
gen year_mean = (year_start+year_end)/2
// round year to the nearest integer
gen year = round(year_mean, 1)

// merge on CSMR
merge m:1 location_id year age_cat sex using `csmr', keep(3)nogen

// calculate EMR as EMR=CSMR/(incidence * average duration).
gen emr = mean_csmr/(mean*5)
// calculate standard error of EMR 
gen se_emr = emr*sqrt((se_csmr/mean_csmr)^2+(standard_error/(mean*5))^2)

save "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_echino/1484/04_models/gbd2015/03_steps/`date'/03_emr_calculation/03_outputs/01_draws/emr/CE_inc_csmr_emr.dta", replace

export excel using "/home/j/WORK/04_epi/01_database/02_data/ntd_echino/1484/03_review/03_upload/inc_csmr_emr_ntd_echino_1484_`date'.xlsx", firstrow(variables)  sheet("extraction") replace

// **********************************************************************
// CHECK FILES

	// write check file to indicate step has finished
		file open finished using "`out_dir'/finished.txt", replace write
		file close finished
		
	// if step is last step, write finished.txt file
		local i_last_step 0
		foreach i of local last_steps {
			if "`i'" == "`this_step'" local i_last_step 1
		}
		
		// only write this file if this is one of the last steps
		if `i_last_step' {
		
			// account for the fact that last steps may be parallel and don't want to write file before all steps are done
			local num_last_steps = wordcount("`last_steps'")
			
			// if only one last step
			local write_file 1
			
			// if parallel last steps
			if `num_last_steps' > 1 {
				foreach i of local last_steps {
					local dir: dir "root_j_dir/03_steps/`date'" dirs "`i'_*", respectcase
					local dir = subinstr(`"`dir'"',`"""',"",.)
					cap confirm file "root_j_dir/03_steps/`date'/`dir'/finished.txt"
					if _rc local write_file 0
				}
			}
			
			// write file if all steps finished
			if `write_file' {
				file open all_finished using "root_j_dir/03_steps/`date'/finished.txt", replace write
				file close all_finished
			}
		}
		
	// close log if open
		if `close_log' log close
