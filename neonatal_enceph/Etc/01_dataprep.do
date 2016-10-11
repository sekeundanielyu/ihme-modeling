
/* **************************************************************************
MODELING PROCESS: For neonatal encephalopathy, neonatal sepsis, and each gestational age of preterm conditions (<28wks = Group 1, 
28-32wks=Group 2, 32-36wks=Group 3), we have data for the following:

1. Birth prevalence (bprev) of the condition (with-condition births / all births)
2. Case fatality ratio (cfr) of the condition (deaths due to condition / with-condition births)
3. Mild impairment proportion (mild_imp)
 (number with condition who survive and go on to have mild impairment / number with condition who survive)
4. Moderate to severe impairment proportion (modsev_imp)
 (number with condition who survive and go on to have moderate/severe impairment / number with condition who survive)

In 01_dataprep, we only work with cfr, mild_imp, and modsev_imp. Starting with GBD 2015, there is sufficient raw bprev data,  
so we input it into the first Dismod step without further modification. 

What we want, ultimately, are estimates of mild and mod-severe impairment due to 
these conditions for every country-age-sex-year. In 01_dataprep.do, the process is the following for each cause/gestational age:

1. Run independent regressions for each of three modeled parameters (cfr, mild_imp and mosev_imp) to generate a 
	full set of estimates.
	NOTE: In two cases, we have too little data for a regression (when we try to run one, the coefficient is 
	in the opposite direction from what we expect).  In these sitations, we run a meta-analysis instead.  This occurs
	for:
	--long_modsev of sepsis
	--long_mild of sepsis

	A. In addition we run a single severity regression for all gestational ages of preterm mild_imp 
	and modsev_imp, and another for encephalopathy mild_imp and modsev_imp. Ln_NMR is included as a predictor, and dummies are placed on 
	each severity-gestational age category.

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
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
	// base directory on /ihme
	local root_tmp_dir `2'
	// timestamp of current run (i.e. 2014_01_17)
	local date `3'
	// step number of this step (i.e. 01a)
	local step_num `4'
	// name of current step (i.e. first_step_name)
	local step_name `5'
	// step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
	local hold_steps `6'
	// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
	local last_steps `7'
    // directory where the code lives
    local code_dir `8'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on /ihme
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	
	// write log if running in parallel and log is not already open
	cap log using "`out_dir'/02_temp/02_logs/`step_num'.smcl", replace
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

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE


/* ***************************************************************************
PART I: Data prep

Here, for each of the four causes of interest (encephalopathy and the three 
preterms) we import the data, do some cleaning/checks, import covariates,
and otherwise get the dataset ready for analysis.
*****************************************************************************/
clear all
set more off
set maxvar 32000
version 13

/*  //////////////////////////////////////////////
		WORKING DIRECTORY
////////////////////////////////////////////// */
	

//root dir
if c(os) == "Unix" {
	local j "/home/j"
	local working_dir = "/homes/User/neo_model" 
} 
else if c(os) == "Windows" {
	local j "J:"
	local working_dir = "H:/neo_model" 
	// Load the PDF appending application
	quietly do "`j'/Usable/Tools/ADO/pdfmaker_acrobat11.do"
}

// Create timestamp for logs
    local c_date = c(current_date)
    local c_time = c(current_time)
    local c_time_date = "`c_date'"+"_" +"`c_time'"
    display "`c_time_date'"
    local time_string = subinstr("`c_time_date'", ":", "_", .)
    local timestamp = subinstr("`time_string'", " ", "_", .)
    display "`timestamp'"

// set directories
	local parent_log_dir = "/ihme/scratch/users/User/neonatal/logs"
	local data_dir = "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data" 
	local parent_source_dir = "`j'/WORK/04_epi/01_database/02_data"
	local cov_dir = "`data_dir'/00_covariates/"

// run functions
run "`j'/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
run "`j'/WORK/10_gbd/00_library/functions/get_data.ado"

/*  //////////////////////////////////////////////
		COVARIATES
		
		The covariates used are the following: 
		--ln_NMR: each country-year's NMR, in log space
		--year
		--developed: binary, =1 if country is developed, =0 if country is developing
		--year_dev_int: interaction term, equal to year * developed
		
		Only the birth prevalence regressions for preterm conditions use all 4 of these
		covariates.  All other regressions use only ln_NMR. 
		
		RANDOM EFFECTS 
		Birth prevalence regressions for preterm have three levels of random effects: 
		superregion, region, and iso3.  Every other regression has only superregion, except
		long_mild_ga2, which has only global.  
////////////////////////////////////////////// */
	
//NMR from mortality team
use "`j'/WORK/02_mortality/03_models/3_age_sex/results/stable_output/estimated_enn-lnn-pnn-ch-u5_noshocks.dta", clear
keep region_name location_name ihme_loc_id sex year q_nn_med
gen NMR = q_nn_med * 1000
gen ln_NMR = log(NMR)
rename sex gender
gen sex = 1 if gender == "male"
replace sex = 2 if gender == "female" 
replace sex = 3 if gender == "both"
//The mortality data explicitly estimates year at midyear; we rename this to 
// simply 'year', keeping in mind that the value is a mid-year estimate
replace year = year - 0.5
drop gender q_nn_med
tempfile neo
save `neo', replace

// Country codes (also used for developed/developing)
get_location_metadata, location_set_id(9) clear
keep if level > 2 // this is keeping all the locations we estimate for, plus the national level of locations where we estimate subnationals
destring developed, replace
replace developed = 0 if developed == . 
tempfile country_code_data
save `country_code_data', replace

// create a dataset that has developed/developing country information
preserve
keep location_id developed
duplicates drop 
tempfile developing 
save `developing', replace
restore 

//create an empty dataset that we will fill with our predictions
keep location_id location_name location_type super_region_id super_region_name region_id region_name ihme_loc_id
expand 66 // we need each current record to be expanded to 66 records, one for every year 1950-2015
bysort location_id: gen year = 1949 + _n
tempfile template
save `template', replace

//_m==2 denotes locations modeled for mortality that we don't model for epi - national-level for countries where we have subnats (e.g., Japan, Saudi, US, UK), India state-level (w/o urban/rural)
merge 1:m ihme_loc_id year using `neo' // `neo' is split by sex: males, females and both
drop if _merge == 2 
drop _merge

merge m:1 location_id using `developing'
drop _merge

gen year_dev_int = year*developed

tempfile covariate_template
save `covariate_template', replace
	
/*  //////////////////////////////////////////////
		DATA PREP
////////////////////////////////////////////// */	

//To start: we have created our own rendition of the 'dimensions' spreadsheet, 
// that has information on the names of each sequela, what modeling method to use 
// with it, and any relevant covariates/random effects.  We bring this in, and 
// loop through it. 

import delimited "`data_dir'/dimensions_mini_2015.csv", clear 

drop if grouping == "retino" | grouping == "kernicterus"
tempfile small_dimensions
save `small_dimensions', replace

// Keep enceph, preterm and sepsis
local acause_list " "neonatal_enceph" "neonatal_preterm" "neonatal_sepsis" "

//here begins the acause looping
foreach acause of local acause_list { 

	// first, delete pre-existing files 
	// so we will be able to check at the
	// end that this step finished
	di "Removing old files"
	cd "`data_dir'/02_analysis/`acause'/draws"
	local files: dir . files "`acause'*"
	foreach file of local files {
		erase `file'
	}

	di in red "`acause'"
	
	local log_dir "`parent_log_dir'/`acause'"
	local out_dir "`data_dir'/01_prep/`acause'"
	local archive_dir "`out_dir'/#ARCHIVE"
	
	capture mkdir "`log_dir'"
	capture mkdir "`out_dir'"
	capture mkdir "`archive_dir'"
	
	capture log close 
	log using "`log_dir'/`acause'_`timestamp'.smcl", replace
	
	use `small_dimensions', clear
	
	keep if acause=="`acause'"
	levelsof(gest_age), local(gest_age_list)
	
	tempfile local_dimensions
	save `local_dimensions', replace
	
	// enceph and sepsis don't have gestational age splits, but we want to loop 
	// through every gestational age (for the sake of preterm), so we temporarily generate 
	// a gestational age 
	if "`acause'"=="neonatal_enceph" | "`acause'" == "neonatal_sepsis" {
		local gest_age_list "none"
	}
	
	levelsof modelable_entity_id, local(modelable_entity_list) // will loop over this to bring in the most recent download sheet for each me_id, for each cause 

	local source_dir "`parent_source_dir'/`acause'" 
	
	//here begins the gestational age loop
	foreach gest_age of local gest_age_list{
	
		use `local_dimensions', clear
		di in red "gest age is `gest_age' for acause `acause'"
		
		//reverting gest_age back to nothing for encephalopathy
		if "`gest_age'"=="none"{
			local gest_age ""
		}
		
		tostring gest_age, replace
		replace gest_age="" if gest_age=="."
		
		//bring in data points we will use in our regression. This
		// next chunk of code loops over all the me_ids for an 
		// acause, goes into their respective 02_data folders, and 
		// only retrieves the newest download sheet.
		di in red "importing data"

		local x = 0
		foreach modelable_entity of local modelable_entity_list {

			di "setting directory"
			cd "`source_dir'/`modelable_entity'/03_review/01_download"
			di "creating files local"
			local files: dir . files "me_`modelable_entity'_ts_*.xlsx"
			di "sorting files"
			local files: list sort files
			di "importing files"
			import excel using `=word(`"`files'"',wordcount(`"`files'"'))', firstrow clear
			di "Counting observations"
			count
			if `r(N)' == 0 {
				di "Obs = 0. No data for me_id `modelable_entity'"
			}
			else if `x' == 0 {
				di "saving original file"
				tempfile `acause'_`gest_age'_data
				save ``acause'_`gest_age'_data', replace
			}
			else if `x' == 1 {
				di "appending subsequent files"
				append using ``acause'_`gest_age'_data', force 
				di "saving subsequent files"
				save ``acause'_`gest_age'_data', replace
			}
		local x = 1
		}


		/* format so that 2015 database template
		// will be compatible with 
		// what this script requires */

			// create 'grouping' variable 
			gen grouping = ""

			// neonatal_preterm
			replace grouping = "ga1" if modelable_entity_id == 1557
			replace grouping = "ga2" if modelable_entity_id == 1558
			replace grouping = "ga3" if modelable_entity_id == 1559
			drop if grouping == "ga1" | grouping == "ga2" | grouping == "ga3" & measure == "mtexcess"
			replace grouping = "long_mild_ga1" if modelable_entity_id == 1560
			replace grouping = "long_mild_ga2" if modelable_entity_id == 1561
			replace grouping = "long_mild_ga3" if modelable_entity_id == 1562
			replace grouping = "long_modsev_ga1" if modelable_entity_id == 1565
			replace grouping = "long_modsev_ga2" if modelable_entity_id == 1566
			replace grouping = "long_modsev_ga3" if modelable_entity_id == 1567
			replace grouping = "cfr1" if modelable_entity_id == 2571
			replace grouping = "cfr2" if modelable_entity_id == 2572
			replace grouping = "cfr3" if modelable_entity_id == 2573

			// neonatal_enceph
			replace grouping = "cases" if modelable_entity_id == 2525
			drop if grouping == "cases" & measure == "mtexcess" // this is the EMR data that must be included for Dismod Step 1
			replace grouping = "cfr" if modelable_entity_id == 2524
			replace grouping = "long_mild" if modelable_entity_id == 1581
			replace grouping = "long_modsev" if modelable_entity_id == 1584

			// neonatal_sepsis
			replace grouping = "cases" if modelable_entity_id == 1594
			drop if grouping == "cases" & measure == "mtexcess" // this is the EMR data that must be included for Dismod Step 1
			replace grouping = "cfr" if modelable_entity_id == 3964
			replace grouping = "long_mild" if modelable_entity_id == 3965
			replace grouping = "long_modsev" if modelable_entity_id == 3966

			// change sex var to numeric
			replace sex = "1" if sex == "Male"
			replace sex = "2" if sex == "Female"
			replace sex = "3" if sex == "Both"
			destring sex, replace

		drop if location_name == "England"

		// naming conventions have changed, fix grouping names
		replace grouping="cases" if grouping == "bprev"
		keep if regexm(grouping, "`gest_age'") == 1
		
		// make sure there are no doubled files
		drop row_num
		duplicates drop
		
		// fixes that one datapoint in neonatal_enceph where cases>denominator 
		drop if cases > sample_size

		// make sure you have some kind of value for numerator and denominator
		// (used in age-sex splitting)
		replace sample_size = (mean*(1-mean))/(standard_error)^2 if sample_size == .
		replace cases = mean * sample_size if cases == .

		count if mean==.
		di in red "acause `acause' at gestational age `gest_age' has `r(N)' missing mean values!"
		drop if mean== .
		
		// get proper iso3 names
		merge m:1 location_id using `developing', keep(1 3) nogen
		drop if location_id == .
		
		//merge the dimensions sheet back on so we have the name/covariate information again
		di in red "merging dimensions onto data"
		merge m:1 grouping using `local_dimensions', keep(3) nogen
		levelsof standard_grouping, local(standard_grouping_list)
		
		keep acause *grouping location_* sex year* mean sample_size cases covariates random_effect_levels
		
		/* ************************
		SEX SPLITTING
		For most of the four groupings, we are satisfied with sex="Both". 
		For birth prevalence, however, we want to predict separately for 
		different sexes.  As such, we need to split the values where sex is 'both'.
		We do this through multiplication by a scalar that takes into account both
		the sex ratio at birth and the sex ratio of the incidence of the condition.
		See the do-file for the sex split for more details. 
		*************************/
		preserve 
			di "sex splitting for `acause'"
			keep if standard_grouping == "birth_prev"
			count if sex == 3
			di in red "splitting `r(N)' birth prev values by sex"
			global sexsplit_dir "`data_dir'/01_prep/sex_split"
			global param "birth_prev"
			global acause "`acause'"
			global gest_age "`gest_age'"
			save "$sexsplit_dir/pre_sex_split/${acause}${gest_age}_${param}_for_sex_split.dta", replace
			do "`working_dir'/sex_split.do" 
		restore 
		
		//append new data on, drop old, non sex-split values
		append using "$sexsplit_dir/post_sex_split/`acause'`gest_age'_birth_prev_sex_split_complete.dta"  
		drop old*
		
		drop if standard_grouping == "birth_prev" & sex == 3
		
		count if mean > 1
		if `r(N)' > 0{
			di in red "too-large parameter estimate!"  
			BREAK
		}

		// Place year at midyear
		gen year = floor((year_start+year_end)/2)
		drop year_*
		
		// sometimes, different values fall on the same year.  If this occurs,
		// use numerator and denominator to come up with a new prevalence estimate.
		// Also, for all params except birth prevalence, make sure all causes are NOT sex-specific
		replace sex = 3 if standard_grouping != "birth_prev"
		collapse(sum) cases sample_size, by(acause *grouping location_* sex year covariates random_effect_levels)
		gen mean = cases/sample_size
		
		tempfile dataset
		save `dataset'
		
		/*  //////////////////////////////////////////////
		Parameter-specific analysis
		now we have a prepped dataset.  All that
		remains is to merge this dataset with a template
		(such that we can make predictions even for years 
		where we have missing data), merge on covariates,
		and call the code for the next step.
		////////////////////////////////////////////// */
		
		// here begins the parameter-specific loop
		// local standard_grouping cfr // EDIT: setting for testing 
		 foreach standard_grouping of local standard_grouping_list {
			di in red "saving template for `standard_grouping' of `acause'"
			use `dataset', clear
			
			keep if standard_grouping == "`standard_grouping'" 
			
			local grouping = grouping
			local covariates = covariates
			local random_effects = random_effect_levels
			
			local cov_count: word count `covariates'
			local re_count: word count `random_effects'
			
			if `cov_count' > 1{
				local covs_to_pass: word 1 of `covariates'
				forvalues i = 2 / `cov_count'{
					local to_append: word `i' of `covariates'
					local covs_to_pass "`covs_to_pass'__`to_append'"
				}
				di in red "`covs_to_pass'"
				local covariates = "`covs_to_pass'"
			}
			
			if `re_count'>1{
				local random_effects_to_pass: word 1 of `random_effects'
				forvalues i = 2 / `re_count'{
					local to_append: word `i' of `random_effects'
					local random_effects_to_pass "`random_effects_to_pass'__`to_append'"
				}
				di in red "`random_effects_to_pass'"
				local random_effects = "`random_effects_to_pass'"
			}
			//necessary for long_modsev_ga2 regression
			if "`random_effects'" == "global_level"{
				gen global_level = 1
			}
			drop covariates random_effect_levels *grouping acause 
			
			di in red "official grouping name is `grouping'"
			merge 1:1 location_id year sex using `covariate_template'
			
			if "`standard_grouping'" == "birth_prev"{
				drop if sex == 3
			}
			else{
				drop if sex != 3
			}
			
			// rename gbd_analytical_* *
			// drop deprecated_iso3 gbdregion

			
			// save so the next script can find it
			local fname "`acause'_`grouping'_prepped"
			local prepped_dta_dir "`out_dir'/`fname'.dta"
			save "`prepped_dta_dir'", replace
			export delimited using "`out_dir'/`fname'.csv", replace
			
			// archive
			save "`archive_dir'/`fname'_`timestamp'.dta", replace
			export delimited using "`archive_dir'/`fname'_`timestamp'.csv",  replace
			
			// if the covariates list is empty, that means we should run a meta-analysis. 
			// if the covariates list is nonempty, that means we should run a hierarchichal
			// mixed-effects model.
			if "`covariates'" == "meta"{
				!qsub -e /share/temp/sgeoutput/strUser/errors -o /share/temp/sgeoutput/strUser/output -pe multi_slot 8 -N "meta_`acause'_`grouping'" -P "proj_custom_models" "`working_dir'/stata_shell.sh" "`working_dir'/enceph_preterm_sepsis/model_custom/02a_meta_analysis.do" "`acause' `grouping' `data_dir' `prepped_dta_dir' `timestamp'" 
			}
			
			else if "`covariates'" == "ln_NMR"{
				!qsub -e /share/temp/sgeoutput/strUser/errors -o /share/temp/sgeoutput/strUser/output -pe multi_slot 8 -N "regress_`acause'_`grouping'" -P "proj_custom_models" "`working_dir'/stata_shell.sh" "`working_dir'/enceph_preterm_sepsis/model_custom/02b_regress.do" "`acause' `grouping' `covariates' `random_effects' `data_dir' `prepped_dta_dir' `timestamp'"
			}

			else if "`covariates'" == "severity_regression" {
				!qsub -e /share/temp/sgeoutput/strUser/errors -o /share/temp/sgeoutput/strUser/output -pe multi_slot 8 -N "severity_`acause'_`grouping'" -P "proj_custom_models" "`working_dir'/stata_shell.sh" "`working_dir'/enceph_preterm_sepsis/model_custom/02c_severity.do" "`acause'"
			}
			
			di in red "analysis submitted for `grouping' of `acause'!"
		
		}
		
	
	}
	

}

// wait until meta-analysis and regression files are finished 
foreach acause of local acause_list {

	use `small_dimensions', clear
	keep if acause == "`acause'" 
	drop if regex(grouping, "^ga")
	drop if covariates == ""
	levelsof grouping, local(grouping_list)

	foreach grouping of local grouping_list {
		capture noisily confirm file "`data_dir'/02_analysis/`acause'/draws/`acause'_`grouping'_draws.csv"
		while _rc!=0 {
			di "File `acause'_`grouping'_draws.csv not found :["
			sleep 60000
			capture noisily confirm file "`data_dir'/02_analysis/`acause'/draws/`acause'_`grouping'_draws.csv"
		}
		if _rc == 0 {
			di "File `acause'_`grouping'_draws.csv found!"
		}
		
	}

}



// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
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
					local dir: dir "`root_j_dir'/03_steps/`date'" dirs "`i'_*", respectcase
					local dir = subinstr(`"`dir'"',`"""',"",.)
					cap confirm file "`root_j_dir'/03_steps/`date'/`dir'/finished.txt"
					if _rc local write_file 0
				}
			}
			
			// write file if all steps finished
			if `write_file' {
				file open all_finished using "`root_j_dir'/03_steps/`date'/finished.txt", replace write
				file close all_finished
			}
		}
		
	// close log if open
		if `close_log' log close
	
