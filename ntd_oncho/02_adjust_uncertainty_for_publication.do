// Purpose: GBD 2015 Onchocerciasis Estimates
// Description:	Adjust uncertainty scale of draws to better take account of uncertainty of conversion of nodule prevalence to mf
//                      mf prevalence, and uncertainty in effects of mass treatment. Nod/mf conversion uncertainty was adjusted based on
//                      a published Bayesian analysis of nod/mf conversion (Zoure et.al., 2014 (“The geographic distribution of onchocerciasis in the 20 participating countries of the African Programme for Onchocerciasis Control: (2) pre-control endemicity levels and estimated number infected”)). Uncertainty of treatment effects were based on analysis of
//                      longitudinal limited-use data from West-Africa (see "oncho_limited_use.xlsx" for graphical illustration; the data
//                      itself is not available to IHME). (Coffeng et.al., 2014 (“Elimination of African onchocerciasis: modeling the impact of increasing the frequency of ivermectin mass treatment”)

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

// ************************************************************************
// Set standard errors of additional errors that we want to include in the draws
  local nodmf_sd = 0.261236  // for predictions at higher geographical level (10-20 villages)
  local trend_sd = 0.0262011 // sd of time trend in mf prevalence during MDA at higher geographical level (10-20 villages)
  
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


// For each endemic country, correct uncertainty
  use "`pop_env'", clear
  levelsof location_id, local(isos)
  
  foreach iso of local isos { 
    display in red `iso'
  forvalues s = 1/2 {
  foreach var in "_parent" "disfigure_pain_1" "disfigure_1" "disfigure_pain_2" "disfigure_pain_3" "disfigure_3" "vision_mod" "vision_sev" "vision_blind" {
  foreach year in 1990 1995 2000 2005 2010 2015 {
  
    if ("`var'" == "_parent" | "`var'" == "disfigure_pain_1" | "`var'" == "disfigure_1" | "`var'" == "disfigure_pain_2" | "`var'" == "disfigure_pain_3" | "`var'" == "disfigure_3") {
    local grouping = "cases" 
    }
    if ("`var'" == "vision_mod" | "`var'" == "vision_sev") {
    local grouping = "_vision_low" 
    }
    
    if "`var'" == "vision_blind" {
    local grouping = "_vision_blind"
    }
	
    quietly insheet using "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_oncho/04_models/gbd2015/03_steps/2016_05_13/01_draws/03_outputs/01_draws/`grouping'/`var'/5_`iso'_`year'_`s'.csv", comma double clear
    
    format age_group_id draw_* %16.0g
    
  ** // If country is endemic, adjust uncertainty in draws
     //if inlist("`iso'","MWI","TCD","TZA","CMR","CAF","GNQ","LBR","NGA") | inlist("`iso'","UGA","COG","ETH","COD","AGO","BDI","SSD","BEN","BFA") | inlist("`iso'","CIV","GHA","GIN","GNB","MLI","NER","SEN","SLE","TGO") {
	 
	 //for GBD 2015, use corresponding location_ids:
    if inlist(`iso',182,204,189,202,169,172,210,214) | inlist(`iso',190,170,179,171,168,175,435,200,201) | inlist(`iso',205,207,208,209,211,213,216,217,218) {
    
      display in red "`iso' `s' `var' `year'"
    
      ** // Transform prevalences to logit plane
        forvalues i = 0/999 {
          quietly replace draw_`i' = logit(draw_`i')
        }
      
      ** // Add uncertainty due to nod-mf conversion for OCP countries
        //if inlist("`iso'","BEN","BFA","CIV","GHA","GIN","GNB","MLI","NER","SEN") | inlist("`iso'","SLE","TGO") {
		
		//for GBD 2015, use corresponding lcoation_ids:
        if inlist(`iso',200,201,205,207,208,209,211,213,216) | inlist(`iso',217,218) {		
          forvalues i = 0/999 {
            local z = rnormal()
            quietly replace draw_`i' = draw_`i' + `z' * `nodmf_sd'
          }
        }
      
      ** // Calculate mean and sd of draws, and if draws are mf prev, save sd for using with other vars
        quietly egen double mean_draw = rowmean(draw_*)
        quietly egen double sd_draw = rowsd(draw_*)
        if "`var'" == "_parent" {
          preserve
            rename sd_draw sd_draw_mf
            quietly keep age sd_draw
            tempfile sd_mf_`iso'_`year'_`s'
            quietly save `sd_mf_`iso'_`year'_`s'', replace
          restore
        }
        
      ** // Normalize draws
        forvalues i = 0/999 {
          quietly replace draw_`i' = (draw_`i' - mean_draw)/sd_draw
        }
        
      ** // Add nod-mf conversion uncertainty (reset sd of draws if var is mf-prev; adjust sd if other var)
        quietly merge 1:1 age using `sd_mf_`iso'_`year'_`s'', keepusing(sd_draw_mf) nogen
        quietly replace sd_draw = sqrt(sd_draw^2 - sd_draw_mf^2 + `nodmf_sd'^2)
        quietly replace sd_draw = `nodmf_sd' if sd_draw < `nodmf_sd'
       
      ** // Set year when MDA with ivermectin started
        local start_control 1990		
        //"MWI"
		if `iso' == 182 {
          local start_control = 1997
        }
		//"TCD","NER","TZA"
        if inlist(`iso',204,213,189) {
          local start_control = 1998
        }
		//"CMR","CAF","GNQ","LBR","NGA","UGA"
        if inlist(`iso',202,169,172,210,214,190) {
          local start_control = 1999
        }
		//"COG","ETH","COD"
        if inlist(`iso',170,179,171) {
          local start_control = 2001
        }
		//"AGO","BDI","SSD"
        if inlist(`iso',168,175,435) {
          local start_control = 2005
        }    
      
      ** // Add time trend uncertainty
        quietly replace sd_draw = sqrt(sd_draw^2 + ((`year'-`start_control') * `trend_sd')^2)
      
      ** // Re-expand normalized draws to location and adjusted scale.
        forvalues i = 0/999 {
          quietly replace draw_`i' = (draw_`i' * sd_draw) + mean_draw
          quietly replace draw_`i' = 1 / (1 + exp(-draw_`i'))
          quietly replace draw_`i' = 0 if missing(draw_`i')
        }
      
        drop mean_draw sd_draw
        cap drop sd_draw_mf
      }
    
    cap mkdir "`tmp_dir'/`grouping'/"
    cap mkdir "`tmp_dir'/`grouping'/`var'/"
    quietly outsheet using "`tmp_dir'/`grouping'/`var'/5_`iso'_`year'_`s'.csv", comma replace
    
  }
  }
  }
  }

** // Export results to epi viz
  quietly do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
  save_results, modelable_entity_id(1494) description("oncho mf prevalence uncertainty fix") in_dir("`tmp_dir'/cases/_parent") metrics(prevalence) mark_best(yes)
  
  save_results, modelable_entity_id(1495) description("oncho disfigure pain 1 uncertainty fix") in_dir("`tmp_dir'/cases/disfigure_pain_1") metrics(prevalence) mark_best(yes)

  save_results, modelable_entity_id(2620) description("oncho disfigure 1 uncertainty fix") in_dir("`tmp_dir'/cases/disfigure_1") metrics(prevalence) mark_best(yes)

  save_results, modelable_entity_id(2515) description("oncho disfigure pain 3 uncertainty fix") in_dir("`tmp_dir'/cases/disfigure_pain_3") metrics(prevalence) mark_best(yes)

  save_results, modelable_entity_id(2621) description("oncho disfigure 3 uncertainty fix") in_dir("`tmp_dir'/cases/disfigure_3") metrics(prevalence) mark_best(yes)

  save_results, modelable_entity_id(1496) description("oncho disfigure pain 2 uncertainty fix") in_dir("`tmp_dir'/cases/disfigure_pain_2") metrics(prevalence) mark_best(yes)

  save_results, modelable_entity_id(1497) description("oncho vision mod uncertainty fix") in_dir("`tmp_dir'/_vision_low/vision_mod") metrics(prevalence) mark_best(yes)

  save_results, modelable_entity_id(1498) description("oncho vision sev uncertainty fix") in_dir("`tmp_dir'/_vision_low/vision_sev") metrics(prevalence) mark_best(yes)
  
  save_results, modelable_entity_id(1499) description("oncho vision blind uncertainty fix") in_dir("`tmp_dir'/_vision_blind/vision_blind") metrics(prevalence) mark_best(yes)
  
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