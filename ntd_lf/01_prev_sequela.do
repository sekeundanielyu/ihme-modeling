// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global
// Description:	Correct dismod output for pre-control prevalence of infection and morbidity for the effect of mass treatment, and scale
// 				to the national level (dismod model is at level of population at risk).
// include "/home/j/WORK/04_epi/01_database/02_data/ntd_lf/1491/04_models/gbd2015/01_code/dev/01_prev_sequela.do"

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM MASTER CODE (NO NEED TO EDIT THIS SECTION)

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
	if "`1'" != "" {
		// base directory on J 
		local root_j_dir `1'
		// base directory on clustertmp
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
	}
	else if "`1'" == "" {
		// base directory on J 
		local root_j_dir "$prefix/WORK/04_epi/01_database/02_data/ntd_lf/1491/04_models/gbd2015"
		// base directory on clustertmp
		local root_tmp_dir "/ihme/gbd/WORK/04_epi/01_database/02_data/ntd_lf/1491/04_models/gbd2015"
		// timestamp of current run (i.e. 2014_01_17)
		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
		local date = subinstr("`date'"," ","_",.)
		// step number of this step (i.e. 01a)
		local step_num "01"
		// name of current step (i.e. first_step_name)
		local step_name "prev_sequela"
		// step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
		local hold_steps ""
		// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
		local last_steps ""
		// directory where the code lives
		local code_dir "$prefix/WORK/04_epi/01_database/02_data/ntd_lf/1491/04_models/gbd2015/01_code/dev"
	}
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
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
// Create directories for storing draw files
  foreach meid in 1492 1493 {
	local root_tmp_dir_`meid' = subinstr("`root_tmp_dir'","1491","`meid'",.)
	capture mkdir "`root_tmp_dir_`meid''/03_steps/"
	capture mkdir "`root_tmp_dir_`meid''/03_steps/`date'"
	capture mkdir "`root_tmp_dir_`meid''/03_steps/`date'/`step_num'_`step_name'"
	capture mkdir "`root_tmp_dir_`meid''/03_steps/`date'/`step_num'_`step_name'/03_outputs"
	capture mkdir "`root_tmp_dir_`meid''/03_steps/`date'/`step_num'_`step_name'/03_outputs/01_draws"
  }
  local out_dir_infection "`tmp_dir'/03_outputs/01_draws/cases"
  local out_dir_lymphedema = subinstr("`out_dir_infection'","1491","1492",.)
  local out_dir_hydrocele = subinstr("`out_dir_infection'","1491","1493",.)
  capture mkdir "`out_dir_infection'"
  capture mkdir "`out_dir_lymphedema'"
  capture mkdir "`out_dir_hydrocele'"

// Create directory for storing inputs
  local tmp_in_dir "`tmp_dir'/02_inputs"
  capture mkdir "`tmp_in_dir'"
  
 // Import functions
	run "$prefix/WORK/10_gbd/00_library/functions/get_demographics.ado"
	run "$prefix/WORK/10_gbd/00_library/functions/get_populations.ado"
	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
    run "$prefix/WORK/10_gbd/00_library/functions/get_covariate_estimates.ado"
	do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
    run "$prefix/WORK/10_gbd/00_library/functions/get_best_model_versions.ado"

// Prep country population sizes into temp files for quickly looping through them later
  get_demographics , gbd_team(epi) clear
  get_location_metadata, location_set_id(35) clear
  save "`tmp_in_dir'/loc_met.dta", replace
  levelsof location_id if is_estimate == 1, local(location_ids)
  global location_ids `location_ids'
  get_populations , year_id(1990 1995 2000 2005 2010 2015) location_id($location_ids) sex_id($sex_ids) age_group_id($age_group_ids) clear
  keep location_id year_id age_group_id sex_id pop_scaled
  save "`tmp_in_dir'/pops.dta", replace
  
// Model for prevalence of morbidity, given mf prevalence, based on data from the Global LF Atlas (thiswormyworld.org)
  quietly insheet using "`in_dir'/Global_lf_atlas_data_extracted_2014_04_30.csv", double comma clear
  
  // Keep data for all ages
    keep if age_start == 0 & age_end == 99 & sex == "M/F" 
  // Keep data points with relevant data
    drop if (pop_mf == 0 | missing(pop_mf) | missing(np_mf)) | ((pop_lymph == 0 | missing(pop_lymph) | missing(np_lymph)) & (pop_hydrocele == 0 | missing(pop_hydrocele) | missing(np_hydrocele)))
  // Recalculate prevalences
    drop prev_mf
    generate double prev_mf = np_mf / pop_mf
    generate double prev_lymph = np_lymph / pop_lymph
    generate double prev_hydrocele = np_hydrocele / pop_hydrocele
  // Scatter data
    ** scatter prev_hydrocele prev_mf
    ** scatter prev_lymph prev_mf
  // Outsheet selection of data so that it can be regressed in with Stan in R (Stata has no facilities to take account of 
  // error in independent variables (mf prevalence).
    keep adm* year_survey lf_species sex age_start age_end *mf *hydrocele *lymph source_data1
    preserve  
      keep if !missing(prev_hydrocele)
      drop if pop_hydrocele == pop_mf
      drop *lymph
      outsheet using "`in_dir'/morbidity_regression/lf_atlas_hydrocele_compiled_`date'.csv", comma replace
    restore
    preserve
      keep if !missing(prev_lymph)
      drop *hydrocele
      outsheet using "`in_dir'/morbidity_regression/lf_atlas_lymphedema_compiled_`date'.csv", comma replace
    restore

  // ========================================== //
  // Perform non-linear error-in-variables regression with Stan in R //
  // ========================================== //
    
  // Load thousand draws of parameter values for predicting morbidity from mf prevalence
  // Functional association hydrocele prevalence (y, scale 0-1) vs mf prevalence (x, scale 0-1): (a+bx^c)/(1+bx^c)
    insheet using "`in_dir'/morbidity_regression/lf_hydrocele_gnlm_logistic_stan_posterior.csv", double clear
    format %16.0g *
    generate int index = _n
	save "`tmp_in_dir'/hyd_regression.dta", replace
    
  // Functional association lymphedema prevalence (y, scale 0-1) vs mf prevalence (x, scale 0-1): (a+bx^c)/(1+bx^c)
    insheet using "`in_dir'/morbidity_regression/lf_lymphedema_gnlm_logistic_stan_posterior.csv", double clear
    format %16.0g *
    generate int index = _n
	save "`tmp_in_dir'/oed_regression.dta", replace
    
    
// Model for reduction in mf prevalence as function of average number of treatments per person
  quietly insheet using "$prefix/Project/GBD/Causes/Parasitic and Vector Borne Diseases/LF/expert_group_data/lf_efficacy_data.csv", double comma clear
  
  rename datathief percent_reduction
  rename v2 tpp
  
  drop if percent_reduction < 0.5
  generate reduction = percent_reduction/100
  replace reduction = 1 if reduction > 1 & reduction != .
  
  // Fit non-linear regression (OLS), using a general logistic function and limiting parameters
  // to have positive values by means of exponentiation
    nl (reduction = 1 / (1 + 1/(exp({b0=1}) * tpp^(exp({b1=3}))))), vce(hc3)
    local n_data = _N
    local n_new = `n_data' + 1001
    set obs `n_new'
    replace tpp = 7 * (_n - `n_data') / 1000 if missing(tpp)
    predict mu
    twoway (scatter reduction tpp)(line mu tpp, sort), aspect(1)
    matrix mu = e(b)'
    matrix sigma = e(V)
    local covars: rownames mu
    local num_covars: word count `covars'
    local betas
    forvalues j = 1/`num_covars' {
      local p = `j' - 1
      local betas `betas' b`p'
    }

  clear
  set obs 1000
  generate index = _n
  drawnorm `betas', means(mu) cov(sigma) double
  tempfile effect_inf
  quietly save `effect_inf', replace
  
  
// Model for reduction in hydrocele prevalence as function of number of rounds of treatment
  quietly insheet using "`in_dir'/MDA_effect_on_hydrocele.csv", double comma clear

  // Fit non-linear regression (OLS), using a logistic function and limiting parameters
  // to have positive values by means of exponentiation
    nl (reduction = 1 / (1 + 1/(exp({b0=-4}) * rounds^(exp({b1=0.1}))))), vce(hc3)
    local n_data = _N
    local n_new = `n_data' + 1001
    set obs `n_new'
    replace rounds = 12.5 * (_n - `n_data') / 1000 if missing(rounds)
    predict mu
      replace mu = 0 if mu < 0 
    twoway (scatter reduction rounds)(line mu rounds, sort), aspect(1)
    matrix mu = e(b)'
    matrix sigma = e(V)
    local covars: rownames mu
    local num_covars: word count `covars'
    local betas
    forvalues j = 1/`num_covars' {
      local p = `j' - 1
      local betas `betas' b`p'
    }

  clear
  set obs 1000
  generate index = _n
  drawnorm `betas', means(mu) cov(sigma) double
  tempfile effect_hyd
  quietly save `effect_hyd', replace
  
  
// Prepare data on population at risk (fraction of total population that is at risk for LF)
  get_covariate_estimates, covariate_id(253) clear
  rename mean_value prop_at_risk
  keep if inlist(year_id,1990,1995,2000,2005,2010,2015)
  
  // Correct implausible proportions at risk (carry proportions backward or forward where appropriate)
    // Carry forward
      bysort location_id (year_id): replace prop_at_risk = prop_at_risk[_n-1] if year_id > 2005 & inlist(location_name,"Malaysia","Sierra Leone","Mali","Kiribati","Timor-Leste")
    
    // Carry backward
      gsort location_id -year_id
      bysort location_id: replace prop_at_risk = prop_at_risk[_n-1] if year_id < 2010 & inlist(location_name,"Burkina Faso","Haiti","Laos")
      bysort location_id: replace prop_at_risk = prop_at_risk[_n-1] if year_id < 2005 & inlist(location_name,"Bangladesh","Comoros","Sri Lanka","Thailand","Tanzania")
      bysort location_id: replace prop_at_risk = prop_at_risk[_n-1] if inlist(year_id,2010,2005) & location_name == "Samoa"
      bysort location_id: replace prop_at_risk = prop_at_risk[_n-1] if year_id < 2015 & location_name == "Nepal"
    
  // Correct proportion at risk in China, based on De-jian et al (Inf Dis Poverty 2013): total of 330 million people at risk in China in 1980.
  // Assume that between 1985 and 1994, the proportion of counties/cities that reached elimination increased linearly from 0.764 to 1.000
    preserve
	  get_populations , year_id(1980) location_id(491,493,494,496,497,498,499,502,503,504,506,507,513,514,516,521) sex_id(3) age_group_id(22) clear
	  
      collapse (sum) pop_scaled
      
      local prop_at_risk_CHN_precontrol = 300*10^6 / pop_scaled * (1 - 0.764) * 5 / 9
    restore
    
    // Assume that proportion at risk is same in all endemic provinces (for lack of better data)
      replace prop_at_risk = `prop_at_risk_CHN_precontrol' if year_id == 1990 & inlist(location_id,491,493,494,496,497,498,499,502,503,504,506,507,513,514,516,521)
  keep location_id year_id prop_at_risk
  sort location_id year_id
  save "`tmp_in_dir'/prop_at_risk.dta", replace
  
  
// Prepare data on history of mass treatment (coverage of mass treatment against LF in populations at risk)
  get_covariate_estimates, covariate_id(254) clear
  rename mean_value coverage
  
  // Calculate cumulative number of treatments per person at risk over the year
    quietly bysort location_id (year_id): generate tpp_cum = coverage if _n == 1
    quietly bysort location_id (year_id): replace tpp_cum = tpp_cum[_n-1] + coverage if _n > 1
  
  // Calculate the five-year moving average coverage (to be used to estimate proportion of population
  // that experiences zero incidence of lymphedema)
    quietly generate cov_avg5 = (coverage[_n-4] + coverage[_n-3] + coverage[_n-2] + coverage[_n-1] + coverage) / 5
  
  // Predict effect on prevalence of infection, based on non-linear regression of reduction vs. treatments per person
    generate index = _n
    merge 1:1 index using `effect_inf', nogen
    
    forvalues i = 0/999 {
      quietly generate double effect_inf_`i' = 1 - 1 / (1 + 1/(exp(b0[`i'+1]) * tpp_cum^(exp(b1[`i'+1]))))
      quietly replace effect_inf_`i' = 1 if tpp_cum == 0
    }
    drop index b*
    
  // Predict effect on prevalence of hydrocele
    generate index = _n
    merge 1:1 index using `effect_hyd', nogen
    
    forvalues i = 0/999 {
      quietly generate double effect_hyd_`i' = 1 - 1 / (1 + 1/(exp(b0[`i'+1]) * tpp_cum^(exp(b1[`i'+1]))))
      quietly replace effect_hyd_`i' = 1 if tpp_cum == 0
    }
    drop index b*
    
    keep if inlist(year_id,1990,1995,2000,2005,2010,2015)
    keep location_id year_id coverage cov_avg5 tpp_cum effect_*
    save "`tmp_in_dir'/coverage.dta", replace

// ****************************************************************************************************  
// ****************************************************************************************************
// Submit jobs by location to scale scale for population at risk and effect of MDA
    foreach location_id of global location_ids {
		!qsub -N "LF_custom_model_lid_`location_id'" -P proj_codprep -pe multi_slot 4 -l mem_free=8g "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh" "`code_dir'/`step_num'_`step_name'_parallel.do" "`location_id' `tmp_in_dir' `out_dir' `out_dir_infection' `out_dir_lymphedema' `out_dir_hydrocele'"
    }
// Wait for results (check for the last file saved)
    foreach location_id of global location_ids {
		use "`tmp_in_dir'/loc_met.dta" if location_id == `location_id', clear
		quietly levelsof ihme_loc_id, local(iso3) c
		capture confirm file "`out_dir_lymphedema'/5_`location_id'_2015_2.csv"
		if _rc == 601 noisily display "Searching for `location_id' (`iso3') -- `c(current_time)'"
		while _rc == 601 {
			capture confirm file "`out_dir_lymphedema'/5_`location_id'_2015_2.csv"
			sleep 1000
		}
		if _rc == 0 {
			noisily display "`iso3' FOUND!"
		}
    }
   
  // Set the model number and saving parameters
	  ** Microfilaria
	  get_best_model_versions, gbd_team(epi) id_list(1491) clear
	  local mod_num_inf = model_version_id
	  ** Lymphedema
	  get_best_model_versions, gbd_team(epi) id_list(1492) clear
	  local mod_num_oed = model_version_id
	  ** Hydrocele
	  get_best_model_versions, gbd_team(epi) id_list(1493) clear
	  local mod_num_hyd = model_version_id
	  
// Upload to central database
  save_results, modelable_entity_id(1491) metrics(prevalence) in_dir(`out_dir_infection') move(yes) ///
				description(LF infection prev from dismod model `mod_num_inf' corrected for effect of MDA - `date')
  save_results, modelable_entity_id(1492) metrics(prevalence) in_dir(`out_dir_lymphedema') move(yes) ///
				description(LF lymphedema prev from dismod model `mod_num_oed' corrected for effect of MDA - `date')
  save_results, modelable_entity_id(1493) metrics(prevalence) in_dir(`out_dir_hydrocele') move(yes) ///
				description(LF hydrocele prev from dismod model `mod_num_hyd' corrected for effect of MDA - `date')
  
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// CHECK FILES (NO NEED TO EDIT THIS SECTION)

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
	
