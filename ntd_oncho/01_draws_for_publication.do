// Purpose: GBD 2015 Onchocerciasis Estimates
// Description:	Extract draws from files provided by expert group for GBD 2010 and organize according to GBD 2015 infrastructure.
//                      The data used here are the original draws of numbers of cases generated for GBD 2010 (1990, 2005, and 2010),
//                      plus exponentially interpolated/extrapolated figure for 1995, 2000, and 2013 plus extrapolated values for 2015.

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
	// base directory on clustertmp
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
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step'_`step_name'/03_outputs/01_draws"
	// directory for standard code files
	adopath + $prefix/WORK/10_gbd/00_library/functions
	adopath + $prefix/WORK/10_gbd/00_library/functions/utils
	quietly do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"

	di "`out_dir'/02_temp/02_logs/`step'.smcl"
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

// Create dummy file with zeroes for Late Neonatal and Post Neonatal

  clear all
  set obs 2
  generate double age_group_id = 3 //LN
  replace age_group_id = 4 if _n == 2 //PN
  forvalues i = 0/999 {
    generate draw_`i' = 0
  }
  tempfile age0_1_zero_draws
  save `age0_1_zero_draws', replace
  
  // Create draw file with zeroes for countries without data (i.e. assuming no burden in those countries)
  clear
  quietly set obs 20
  quietly generate double age = .
  quietly format age %16.0g
  quietly replace age = _n * 5
  quietly replace age = 0 if age == 85
  quietly replace age = 0.01 if age == 90
  quietly replace age = 0.1 if age == 95
  quietly replace age = 1 if age == 100
  sort age

  generate double age_group_id = .
  format %16.0g age_group_id
  replace age_group_id = _n + 1

  forvalues i = 0/999 {
    quietly generate draw_`i' = 0
  }

  quietly format draw* %16.0g

  tempfile zeroes
  save `zeroes', replace  
  // Load and save geographical names
   //DisMod and Epi Data 2015
   clear
   get_location_metadata, location_set_id(9)

  // Prep country codes file
  duplicates drop location_id, force
  tempfile country_codes
  save `country_codes', replace

    keep ihme_loc_id location_id location_name
	tempfile codes
	save `codes', replace

// Prepare envelope and population data
// Get connection string
create_connection_string, server(modeling-mortality-db) database(mortality) 
local conn_string = r(conn_string)

  //gbd2015 version:
 odbc load, exec("SELECT a.age_group_id, a.age_group_name_short AS age, a.age_group_name, o.sex_id AS sex, o.year_id AS year, o.location_id, o.mean_env_hivdeleted AS envelope, o.pop_scaled AS pop FROM output o JOIN output_version USING (output_version_id) JOIN shared.age_group a USING (age_group_id) WHERE is_best=1") `conn_string' clear
 
  tempfile demo
  save `demo', replace
  
  use "`country_codes'", clear
  merge 1:m location_id using "`demo'", nogen
  keep age age_group_id sex year ihme_loc_id parent location_name location_id location_type region_name envelope pop
  keep if inlist(location_type, "admin0","admin1","admin2","nonsovereign", "subnational", "urbanicity")

   replace age = "0" if age=="EN"
   replace age = "0.01" if age=="LN"
   replace age = "0.1" if age=="PN"
   drop if age=="All" | age == "<5"
   keep if age_group_id <= 22
   destring age, replace
   
  keep if year >= 1980 & age < 80.1 & sex != 3
  drop if inlist(age, 0.01, 0.1)
  sort ihme_loc_id year sex age
  tempfile pop_env
  save `pop_env', replace
  
	keep ihme_loc_id location_id year age age_group_id sex pop
	tempfile popfile
	save `popfile', replace
	
	
// Pull in the OCP file: "ocp_draws_gbd2015.dta" from folder `in_dir'.
	use "`in_dir'/ocp_draws_gbd2015.dta", clear
	drop panel

	tempfile ocp_2013
	save `ocp_2013', replace

// Within each draw, multiply the number of cases with visual impairment by a random value,
// which is defined as the exponent of a normally distributed variable with mean zero and sd 0.1.
// Use the function rnormal (with mean 0 and sd 0.1) to create the random value and exponentiate it.
// Within a draw, apply the same randomly drawn value to all country-year-sex-age. This step adds
// some uncertainty to these estimates (relative sd +/-20%). Do the same for blindness; don't do this
// for the other sequelae, as these already have uncertainty quantified.

	gen rando=.
	forvalues x = 0/999 {
	quietly local rando = rnormal(0,0.1)
	quietly replace rando = `rando' if draw == `x'
	}

	replace vicases = vicases * exp(rando)
	replace blindcases = blindcases * exp(rando)

	drop rando

	tempfile ocp
	save `ocp', replace


// Pull in the APOC file: "apoc_draws_gbd2015.dta.csv" from folder `in_dir'
// Do the same as for the OCP file, but skip the first step (no need to add variation to the
// vision loss sequelae here).
	use "`in_dir'/apoc_draws_gbd2015.dta", clear
	drop panel

	tempfile apoc
	save `apoc', replace

	// Append the draws from the OCP
	append using `ocp'


// Next, split the cases of visual impairment into moderate and severe cases. The fraction moderate
// cases should be .8365775  (standard error .0030551). Generate random values
// using the rnormal function. Within each draw, apply the same randomly drawn fraction to all country-year-sex-age.
	gen vis_rando = .
	forvalues x = 0/999 {
	quietly local vis_rando = rnormal(.8365775, .0030551)
	quietly replace vis_rando = `vis_rando' if draw == `x'
	}

	gen vis_mod = vis_rando * vicases
	gen vis_sev = (1-vis_rando) * vicases

	drop vis_rando

// Calculate the prevalence of sequela by dividing by the population envelope (mean_pop)
// temporarily save results.
	joinby ihme_loc_id year age sex using "`popfile'", unmatched(none)
	
	replace wormcases = wormcases/pop
	replace mfcases = mfcases/pop
	replace blindcases = blindcases/pop
	replace vicases = vicases/pop
	replace osdcases1acute = osdcases1acute/pop
	replace osdcases1chron  = osdcases1chron/pop
	generate osdcases2 = (osdcases2acute + osdcases2chron)/pop
	replace osdcases3acute = osdcases3acute/pop
	replace osdcases3chron = osdcases3chron/pop
	replace vis_mod = vis_mod/pop
	replace vis_sev = vis_sev/pop

// reshape to wide format
	drop osdcases2acute osdcases2chron
	reshape wide wormcases mfcases blindcases vicases osdcases1acute osdcases1chron osdcases2 osdcases3acute osdcases3chron vis_mod vis_sev, i(ihme_loc_id age sex year) j(draw)

	save "`tmp_dir'/draws.dta", replace
	use "`tmp_dir'/draws.dta", clear
	
// Rename the variables to be what we want for upload
  forvalues x = 0/999 {
    rename mfcases`x' _parent`x'
    rename osdcases1acute`x' disfigure_pain_1`x'
    rename osdcases1chron`x' disfigure_1`x'
    rename osdcases2`x' disfigure_pain_2`x'
    rename osdcases3acute`x' disfigure_pain_3`x'
    rename osdcases3chron`x' disfigure_3`x'
    rename vis_mod`x' vision_mod`x'
    rename vis_sev`x' vision_sev`x'
    rename blindcases`x' vision_blind`x'
  } 
	
  tempfile draws
  save `draws', replace
  
  	save "`tmp_dir'/draws_renamed.dta", replace

  use "`pop_env'", clear
  levelsof location_id, local(isos)

  foreach i of local isos {
  	use "`tmp_dir'/draws_renamed.dta", clear
    quietly keep if location_id == `i'
    di "`i'"
    
  foreach year in 1990 1995 2000 2005 2010 2015 {
  forvalues s = 1/2 {
  foreach var in "_parent" "disfigure_pain_1" "disfigure_1" "disfigure_pain_2" "disfigure_pain_3" "disfigure_3" "vision_mod" "vision_sev" "vision_blind" {
  
    preserve
    quietly keep `var'* age_group_id sex year location_id
    quietly keep if sex == `s' & year == `year'
    quietly keep age_group_id `var'*

    if ("`var'" == "_parent" | "`var'" == "disfigure_pain_1" | "`var'" == "disfigure_1" | "`var'" == "disfigure_pain_2" | "`var'" == "disfigure_pain_3" | "`var'" == "disfigure_3") {
      local grouping = "cases" 
    }
    if ("`var'" == "vision_mod" | "`var'" == "vision_sev") {
      local grouping = "_vision_low" 
    }

    if "`var'" == "vision_blind" {
      local grouping = "_vision_blind"
    }
    rename `var'* draw_*
	
		quietly count
		if r(N) > 0 {
			quietly keep age_group_id draw*
			// Add two data rows for age 0.01 and 0.1 with all zeroes for draws			
			append using `age0_1_zero_draws'
          }
          else {
			//save empty draws for countries that should be set to 0
            use `zeroes', clear
          }

    cap mkdir "`tmp_dir'/`grouping'/"
    cap mkdir "`tmp_dir'/`grouping'/`var'/"
    quietly outsheet using "`tmp_dir'/`grouping'/`var'/5_`i'_`year'_`s'.csv", comma replace
    restore	

  }
  }
  }
  }


** // Export results to epi viz
  quietly do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
  save_results, modelable_entity_id(1494) description("oncho mf prevalence") in_dir("`tmp_dir'/cases/_parent") metrics(prevalence) mark_best(yes)

  save_results, modelable_entity_id(1495) description("oncho disfigure pain 1") in_dir("`tmp_dir'/cases/disfigure_pain_1") metrics(prevalence) mark_best(yes)

  save_results, modelable_entity_id(2620) description("oncho disfigure 1") in_dir("`tmp_dir'/cases/disfigure_1") metrics(prevalence) mark_best(yes)

  save_results, modelable_entity_id(2515) description("oncho disfigure pain 3") in_dir("`tmp_dir'/cases/disfigure_pain_3") metrics(prevalence) mark_best(yes)

  save_results, modelable_entity_id(2621) description("oncho disfigure 3") in_dir("`tmp_dir'/cases/disfigure_3") metrics(prevalence) mark_best(yes)

  save_results, modelable_entity_id(1496) description("oncho disfigure pain 2") in_dir("`tmp_dir'/cases/disfigure_pain_2") metrics(prevalence) mark_best(yes)

  save_results, modelable_entity_id(1497) description("oncho vision mod") in_dir("`tmp_dir'/_vision_low/vision_mod") metrics(prevalence) mark_best(yes)

  save_results, modelable_entity_id(1498) description("oncho vision sev") in_dir("`tmp_dir'/_vision_low/vision_sev") metrics(prevalence) mark_best(yes)
  
  save_results, modelable_entity_id(1499) description("oncho vision blind") in_dir("`tmp_dir'/_vision_blind/vision_blind") metrics(prevalence) mark_best(yes)

  
******************************************************************************************************************************************************************
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