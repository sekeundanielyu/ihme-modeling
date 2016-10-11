// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	This code submits jobs that will apply the EN matrices to the Ecode-platform incidence data to get Ecode-Ncode-platform-level incidence data
//					- Set locals for submitting nonshock/shock jobs, and whether to only submit jobs for files that are missing from the final draws folder or submit all jobs and overwrite.
//					- Saves some common inputs used for all jobs, i.e. populations.

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// PREP STATA (DON'T EDIT)
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
	if "`1'" == "" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "04b"
		local 5 scaled_short_term_en_inc_by_platform

		local 8 "/share/code/injuries/strUser/inj/gbd2015"
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
	
// SETTINGS
	** how many slots is this script being run on?
	local slots 1
// Filepaths
	local gbd_ado "$prefix/WORK/10_gbd/00_library/functions"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local stepfile "`code_dir'/_inj_steps.xlsx"
	
// Import functions
	adopath + "`code_dir'/ado"
	adopath + `gbd_ado'

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE
		// SET LOCALS
		// set type for pulling different years (cod/epi); this is used for what parellel jobs to submit based on cod/epi estimation demographics, not necessarily what inputs/outputs you use
		local type "epi"
		// set subnational=no (drops subnationals) or subnational=yes (drops national CHN/IND/MEX/GBR)
		local subnational "yes"
		// Set this local to 0 if you want to zip up all old files and/or clean the 02_temp folder when you are done running this step
		local debug 99
		// Which scripts to run, with an option to not overwrite existing files (only submits a job if that output file is missing)
		local do_nonshock 0
			local overwrite_nonshock 0
		local do_shock 1
			local overwrite_shock 1
		
		** save the countries high/low income status in the inputs for easy access in the parallel steps
		clear
			odbc load, exec("SELECT ihme_loc_id, location_name, location_id, location_type, super_region_name, most_detailed FROM shared.location_hierarchy_history WHERE location_set_version_id = (SELECT location_set_version_id FROM shared.location_set_version WHERE location_set_id = 9 and end_date IS NULL)") dsn(strDSN)
			keep if most_detailed == 1
			keep location_id super_region super_region_name
			gen high_income=0
			replace high_income=1 if super_region_name=="High-income"
			keep location_id high_income 
		save "`out_dir'/01_inputs/income_map.dta", replace
				
		** save the parent/child relationships for pulling when scaling incidence post-EN matrix for easy access during jobs
		import excel using "`in_dir'/parameters/injury DisMod parent-children.xlsx", firstrow clear
		rename acause child_model
		gen parent_model=subinstr(DisModmodels, "Child of ", "", .) if regexm(DisModmodels, "Child of")
		replace DisModmodels="Single model" if child_model=="inj_disaster" | child_model=="inj_war"
		replace parent_model=child_model if DisModmodels=="Single model"
		keep if parent_model!=""
		keep child_model parent_model DisModmodels
		save "`out_dir'/01_inputs/relationships.dta", replace
		
		
*** ********************* STEP 1: APPLY EN Matrix to nonshock E-codes for the normal GBD country/years/sexes ********************************
		local code "`step_name'/apply_EN_matrix.do" 

	// set mem/slots and create job checks directory
	// Test on Dev, hard-code values from test environment (a single node totally filled with these jobs). Maybe create master codebook later.
		// Maximum memory used by job via qstat -j job_id, under maxvmem.
		local ideal_mem = ceil(5.25)
		// Calculate ideal slots based on monitoring %CPU usage test.
		local cpu_usage_ideal = 80
		local cpu_usage_total = 140
		local slots_node_total = 64
		local slots_allocated = 4
		local ideal_jobs = (`cpu_usage_ideal'/`cpu_usage_total') * (`slots_node_total'/`slots_allocated')
		local ideal_slots = round(`slots_node_total'/`ideal_jobs')
		// Use whichever is higher - ideal allocation based on memory of %CPU usage.
		if `ideal_mem'/2 > `ideal_slots' local ideal_slots = `ideal_mem'/2
		
	// submit jobs
		local n 0
		// Pull demographics to loop over
		get_demographics, gbd_team("epi") 
		clear
		get_populations, year_id($year_ids) location_id($location_ids) sex_id($sex_ids) age_group_id($age_group_ids)
		// Save populations file for use by jobs
		save "`out_dir'/01_inputs/pops.dta", replace
		
		if `do_nonshock' == 1 {
		foreach location_id of global location_ids {
			foreach year_id of global year_ids {
				foreach sex_id of global sex_ids {
					if `overwrite_nonshock' == 0 {
						quietly capture confirm file "/snfs3/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/04b_scaled_short_term_en_inc_by_platform/03_outputs/01_draws/nonshocks/collapsed/incidence_`location_id'_`year_id'_`sex_id'.csv"
						if _rc != 0 {
							! qsub -P proj_injuries -N _`step_num'_`location_id'_`year_id'_`sex_id' -pe multi_slot `ideal_slots' -l mem_free=`ideal_mem' -p -2 "`code_dir'/stata_shell.sh" "`code_dir'/`code'" "`repo'/`gbd'/`code'" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `location_id' `year_id' `sex_id'"
							local n = `n' + 1
						}
					}
					if `overwrite_nonshock' == 1 {
						! qsub -P proj_injuries -N _`step_num'_`location_id'_`year_id'_`sex_id' -pe multi_slot `ideal_slots' -l mem_free=`ideal_mem' -p -2 "`code_dir'/stata_shell.sh" "`code_dir'/`code'" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `location_id' `year_id' `sex_id'"
						local n = `n' + 1
					}
				}
			}
		}		
	}
		
		*** ********************* STEP 2: APPLY EN Matrix to Shock E-codes for the all country/year/sexes that have ********************************
		
		// need to write our own qsub function for the shock e-codes because those have results from years other than the GBD years
		** get the step name of the shock incidence step
		// import excel using "`code_dir'/`functional'_steps.xlsx", firstrow clear
		// keep if name == "impute_short_term_shock_inc"
		// local this_step=step in 1
		// local shock_inc_dir = "/clustertmp/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/03_steps/`date'/`this_step'_impute_short_term_shock_inc/03_outputs/01_draws/"
		local ideal_slots 8
		local platforms = "inp otp"
		local shock_code "`step_name'/shock_EN.do"
		if `do_shock' == 1 {
		foreach location_id of global location_ids {
			foreach platform of local platforms {
				foreach sex_id of global sex_ids {
					foreach year_id of global year_ids {
						if `overwrite_shock' == 0 {
							quietly capture confirm file "/snfs3/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/04b_scaled_short_term_en_inc_by_platform/03_outputs/01_draws/shocks/incidence_`location_id'_`platform'_`sex_id'.csv"
							if _rc != 0 {
								! qsub -e /share/temp/sgeoutput/ngraetz/errors -o /share/temp/sgeoutput/ngraetz/output -P proj_injuries -N shock_`functional'_`step_num'_`location_id'_`platform'_`sex_id' -pe multi_slot `ideal_slots' -l mem_free=`ideal_mem' -p -2 "`repo'/`gbd'/stata_shell.sh" "`repo'/`gbd'/`shock_code'" "`functional' `gbd' `date' `step_num' `step_name' `repo' `type' `location_id' `sex_id' `platform' `slots'"
								local n = `n' + 1
							}
						}
						if `overwrite_shock' == 1 {
							di "PLATFORM: `platform'"
							! qsub -e /share/temp/sgeoutput/ngraetz/errors -o /share/temp/sgeoutput/ngraetz/output -P proj_injuries -N _`step_num'_`location_id'_`platform'_`sex_id' -pe multi_slot `ideal_slots' -l mem_free=`ideal_mem' -p -2 "`code_dir'/stata_shell.sh" "`code_dir'/`shock_code'" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `location_id' `year_id' `sex_id' `platform'"
							local n = `n' + 1
						}
					}
				}
			}
		}			
	}


** ***********************************************************
// Write check files
** ***********************************************************

	// close log if open
	log close master
		