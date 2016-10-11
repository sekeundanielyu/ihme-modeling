// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description: 	submit to the cluster files that will take the Dismod output for all of the e-code models and split the results into inpatient/not-inpatient

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
	// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	
// Global can't be passed from master when called in parallel
	if missing("$check") global check 0

	local pull_covs = 1

	if "`1'" == "" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "02a"
		local 5 raw_nonshock_short_term_ecode_inc_by_platform

		local 8 "/share/code/injuries/ngraetz/inj/gbd2015"
	}
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
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	
	// write log if running in parallel and log is not already open
	cap log using "`out_dir'/02_temp/02_logs/`step_num'.smcl", replace name(log_`step_num')
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

** *********************************************
// WRITE CODE HERE
** *********************************************

// Settings
	local debug 0

// Filepaths
	local gbd_ado "$prefix/WORK/10_gbd/00_library/functions"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	
// Import GBD functions
	adopath + "`gbd_ado'"
	adopath + `code_dir'/ado
	
// Load injury parameters
	load_params
	
// set memory (gb) for each job
	local mem 2
// set type for pulling different years (cod/epi); this is used for what parellel jobs to submit based on cod/epi estimation demographics, not necessarily what inputs/outputs you use
	local type "epi"
// set subnational=no (drops subnationals) or subnational=yes (drops national CHN/IND/MEX/GBR)
	local subnational "yes"
	local metric incidence
// set code file from 01_code to run in parallel (change from template; just "name.do" no file path since it should be in same directory)
	local code "`step_name'/`step_name'_parallel.do" 

** Pull the list of e-codes that are modeled by DisMod that we are going to transform
	insheet using "`code_dir'/master_injury_me_ids.csv", comma names clear
		keep if injury_metric == "Adjusted data"
		drop if aggregate == 1
		levelsof modelable_entity_id, l(me_ids)
		keep modelable_entity_id e_code
		tempfile mes 
		save `mes', replace

// SAVE ANY COMMON INPUTS NEEDED BY PARALLELIZED JOBS
		// best epi models
		if `pull_covs' == 1 {
			adopath + "$prefix/WORK/10_gbd/00_library/functions"
			insheet using "`code_dir'/master_injury_me_ids.csv", comma names clear
				keep if injury_metric == "Adjusted data"
				levelsof modelable_entity_id, l(me_ids)
				keep modelable_entity_id e_code
				tempfile mes 
				save `mes', replace
			get_best_model_versions, gbd_team(epi) id_list(`me_ids') clear
				tostring model_version_id, replace
				tostring modelable_entity_id, replace
			clear mata
			putmata acause model_version_id modelable_entity_id 
			count
			local mata_tot=`r(N)'	
			forvalues i=1/`mata_tot' {
				mata: st_local("acause", acause[`i'])
				mata: st_local("model_version_id", model_version_id[`i'])
				mata: st_local("modelable_entity_id",modelable_entity_id[`i'])
				di "`acause' `model_version_id' `modelable_entity_id'"
					cap !gunzip /share/epi/panda_cascade/prod/`model_version_id'/full/locations/1/outputs/both/2000/post_ode.csv.gz
					import delimited "/share/epi/panda_cascade/prod/`model_version_id'/full/locations/1/outputs/both/2000/post_ode.csv", delim(",") varn(1) clear
					keep beta_incidence_x_s_*
					foreach var of varlist * {
						local shortcov = subinstr("`var'","beta_incidence_x_s_","",.)
						rename `var' `shortcov'
						replace `shortcov'=exp(`shortcov')
					}
					count
					local end_row = `r(N)'
					local start_row = `r(N)'-999
					keep in `start_row'/`end_row'
					gen inpatient=1
					// Figure out which one is the highest 
					preserve
						collapse (mean) *
						rename * cov*
						rename covinpatient inpatient
						cap mkdir "$prefix/WORK/04_epi/01_database/02_data/_inj/05_diagnostics/gbd2015/covs_june14"
						save "$prefix/WORK/04_epi/01_database/02_data/_inj/05_diagnostics/gbd2015/covs_june14/`acause'_covariates.dta", replace
						reshape long cov, i(inpatient) j(index, string)
						sum cov
						keep if cov == r(max)
						local max_cov = index
					restore
					keep inpatient `max_cov'
					rename `max_cov' medcare_		
					gen acause="`acause'"
					gen draw = _n - 1
					reshape wide medcare*, i(inpatient acause) j(draw)
					save "`out_dir'/01_inputs/`acause'_covariates.dta", replace
			}		
		}			
		** end loop saving covariates
		
		// parallelize by location/year/sex
		get_demographics , gbd_team(epi)
		foreach location_id of global location_ids {
			foreach year_id of global year_ids {
				foreach sex_id of global sex_ids {
					!qsub -e /share/temp/sgeoutput/ngraetz/errors -o /share/temp/sgeoutput/ngraetz/output -P proj_injuries -N _`step_num'_`location_id'_`year_id'_`sex_id' -pe multi_slot 4 -l mem_free=8 -p -2 "`code_dir'/stata_shell.sh" "`code_dir'/`step_name'/raw_nonshock_short_term_ecode_inc_by_platform_parallel.do" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `location_id' `year_id' `sex_id'"
				}
			}
		}

** ***********************************************************
// Write check files
** ***********************************************************

	// write check file to indicate step has finished
		file open finished using "`out_dir'/finished.txt", replace write
		file close finished
		
	// close log if open
		log close log_`step_num'
		
