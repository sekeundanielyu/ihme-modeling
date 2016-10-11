// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	apply probability of long-term outcomes to short-term incidence to get incidence of long-term outcomes by ecode-ncode-platform
//                       then run dismod engine to get non-shock prevalence and custom ODE solver to get shock prevalence

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM MASTER CODE (NO NEED TO EDIT THIS SECTION)

	// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	set type double, perm
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
		local 4 "05b"
		local 5 long_term_inc_to_raw_prev

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

// Filepaths
	local func_dir "$prefix/WORK/04_epi/01_database/01_code/00_library" // Filepath to where pyHME function library is located
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local pops_dir "`tmp_dir'/01_inputs"
	local rundir "`root_tmp_dir'/03_steps/`date'"
	local checkfile_dir "`tmp_dir'/02_temp/01_code/checks"
	local ode_checkfile_dir "`tmp_dir'/02_temp/01_code/custom_ode_checks"
	local prev_results_dir "/share/injuries/dm/prev_results_tree"
	
// Import functions
	adopath + "`code_dir'/ado"
	adopath + "`func_dir'"
	adopath + "$prefix/WORK/10_gbd/00_library/functions"

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// use these to turn on the different blocks of code
	global update_pops 0
	// temporarily save the long-term incidence numbers in this file structure
	global prep_ltinc 0
	// Run Ian's shock ODE solver
	global shock 0
	// create rate_in value_in plain_in data_in effect_in
	global prep_dm_input 0
	// run Ian/Amelia's nonshock dismod code to create estimates of long term preavlence for the nonshock e-codes
	global nonshock 0
	// Append results to the country-year-sex level
	global append_results 1
	
	// are you just testing this code and don't wait to erase/zip any previous files at the end?
	local debug 1
	
// Settings
	** two ways of sending excess mortality data to dismod "SMR" or "chi"; try both ways
	global SMR_or_chi "chi"
	** how much memore does the prep_ltinc step need
	local prep_ltinc_mem 2
	** how much memory does the prep_ltinc step need for shocks
	local prep_ltinc_mem_shocks 4
	** how much memory does the data_in/rate_in generation script need
	local data_rate_mem 4
	** how much memory does creating the value_in files need
	local value_in_mem 2
	** how much memory does appending the results take
	local append_results_mem 2
	
// Load parameters
	load_params
	get_demographics, gbd_team("epi") 
	local platforms inp otp
			
// Write file to signify whether we are using SMR or excess mort (chi in dismod terms)
	capture erase "`tmp_dir'/02_temp/01_code/SMR.txt"
	capture erase "`tmp_dir'/02_temp/01_code/chi.txt"
	
	if "$SMR_or_chi"== "SMR" {
		file open check using "`tmp_dir'/02_temp/01_code/SMR.txt", replace write
	}
		
	if "$SMR_or_chi"== "chi" {
		file open check using "`tmp_dir'/02_temp/01_code/chi.txt", replace write
		local has_mort =1
	}

// set type for pulling different years (cod/epi); this is used for what parellel jobs to submit based on cod/epi estimation demographics, not necessarily what inputs/outputs you use
	local type "epi"
// set subnational=no (drops subnationals) or subnational=yes (drops national CHN/IND/MEX/GBR)
	local subnational "yes"
	
// Step 1: Save all major inputs that don't need to be parallelized: single-year populations, GBD age group populations
	** get single-year and group-year age pops for Ian's code to pull.
	clear
	get_populations, year_id($year_ids) location_id($location_ids) sex_id($sex_ids) age_group_id($age_group_ids)
	save "`pops_dir'/pops.dta", replace
	
	** get the filepath to the excess mortality draws and incidence draws
	import excel using "`code_dir'/_inj_steps.xlsx", firstrow clear
	** non-shock incidence
	preserve
	keep if name == "SMR_to_excessmort"
	local this_step=step in 1
	local SMR_dir = "`root_tmp_dir'/03_steps/`date'/`this_step'_SMR_to_excessmort"
	restore

// Step 2 prep long-term incidence files in the right format
	if $prep_ltinc {
		local prep_ltinc_mem 2
		if $nonshock {
			local code "`step_name'/apply_lt_probs.do"
			foreach location_id of global location_ids {
				foreach year_id of global year_ids {
					foreach sex_id of global sex_ids {
						! qsub -P proj_injuries -N _`step_num'_`location_id'_`year_id'_`sex_id' -pe multi_slot 4 -l mem_free=8 -p -2 "`code_dir'/stata_shell.sh" "`code_dir'/`code'" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `location_id' `year_id' `sex_id'"
						}
					}
				}
			}

		if $shock {
			local shock_code "`step_name'/apply_lt_probs_to_shocks.do"
			// NEED TO DO SHOCK E-CODES SEPERATELY BECUASE THEY HAVE DATA FOR YEARS OTHER THAN 1990-2013
			import excel using "`code_dir'/_inj_steps.xlsx", firstrow clear
			foreach location_id of global location_ids {
				foreach platform of local platforms {
					foreach sex_id of global sex_ids {
						! qsub -P proj_injuries -N _`step_num'_`location_id'_`platform'_`sex_id' -pe multi_slot 4 -l mem_free=8 -p -2 "`code_dir'/stata_shell.sh" "`code_dir'/`shock_code'" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `location_id' `sex_id' `platform'"
						}
					}
				}		
			di "all shocks submitted with slots: `slots', mem: `mem'."
		}
		
	}

// Step 3: submit shock e-codes to Ian's custom ODE solver
if $shock {
	// directory of GBD age group characteristics (created earlier)
		local ages_dir "`in_dir'/parameters/automated"
	// filepath to csv that contains cleaned single-year-age-group populations
		local pop_s_path "`pops_dir'/sy_pop.csv"
		if $update_pops {
			insheet using "`out_dir'/01_inputs/sy_pop.csv", comma names clear
			outsheet using "`pop_s_path'", comma names replace
		}
	// filepath to csv that contains cleaned GBD-age-group populations	
		local pop_grp_path "`pops_dir'/grp_pop.csv"
		if $update_pops {	
			insheet using "`out_dir'/01_inputs/grp_pop.csv", comma names clear
			outsheet using "`pop_grp_path'", comma names replace	
		}

	// Keep count of how many shock jobs have been submitted
		local shock_jobs 0
	
	// Loop over platforms
		foreach platform of local platforms {
			
		// Set excess mortality directory, if exists for this ncode-platform
			if "`platform'"=="inp" local mort_dir "`SMR_dir'/03_outputs/01_draws"
			else local mort_dir ""
		// directory of long-term shock incidence estimates
			local shockinc_dir = "`tmp_dir'/02_temp/03_data/lt_inc/shocks/`platform'"
			
		// Loop over sex
			foreach sex_string in male female {
			
			// Loop over countries
				//foreach iso3 of global iso3s {
				foreach location_id of global location_ids {
					capture mkdir "`ode_checkfile_dir'"
					
				// Set path for timer-file to be created
					local time_path "`diag_dir'/shocks_`platform'_`iso3'_`sex_string'.csv"
				
					// Increment count of how many jobs have been submitted (to check for checkfiles)
					local ++shock_jobs
					
					// Path of check file for this platform-iso3-sex group
					local checkfile_path "`ode_checkfile_dir'/shocks_`platform'_`iso3'_`sex_id'.txt"
					
					quiet run "$prefix/WORK/10_gbd/00_library/functions/create_connection_string.ado"
					create_connection_string, strConnection
					local conn_string = r(conn_string)
					odbc load, exec("SELECT ihme_loc_id, location_id FROM shared.location_hierarchy_history WHERE location_set_version_id = (SELECT location_set_version_id FROM shared.location_set_version WHERE location_set_id = 9 and end_date IS NULL)") `conn_string' clear
					keep if location_id == `location_id'
					local iso3 = ihme_loc_id

				// Set output directory
					cap mkdir "`prev_results_dir'"
					cap mkdir "`prev_results_dir'/shocks"
					cap mkdir "`prev_results_dir'/shocks/`iso3'"
					cap mkdir "`prev_results_dir'/shocks/`iso3'/`sex_string'"
					cap mkdir "`prev_results_dir'/shocks/`iso3'/`sex_string'/`platform'"
					local output_dir "`prev_results_dir'/shocks/`iso3'/`sex_string'/`platform'"

				// Submit ODE solver
					local slots 4
					local mem 8
					di "`checkfile_path'"
					confirm file "`code_dir'/python_shell.sh"
					confirm file "`code_dir'/`step_name'/run_shock_inc_to_prev.py"
					!qsub -e /share/temp/sgeoutput/ngraetz/errors -o /share/temp/sgeoutput/ngraetz/output -P proj_injuries -N shock_ode_`platform'_`iso3'_`sex_string' -pe multi_slot `slots' -l mem_free=`mem' -p -2 "`code_dir'/python_shell.sh" "`code_dir'/`step_name'/run_shock_inc_to_prev.py" `iso3' `sex_string' `ages_dir' `func_dir' `code_dir' `pop_s_path' `pop_grp_path' `shockinc_dir' `output_dir' `time_path' `checkfile_path' `mort_dir'

				}
			}
		}
	}
	** end block running shock ODE solver
	
// Step 4: prep input files for dismod runs wait for all the long-term incidence jobs to finish before continuing (occurs in the parallelize function)
	if $prep_dm_input {
	
		** need a file path for the file with the model version ids pulled from dismod 
		import excel using "`code_dir'/_inj_steps.xlsx", firstrow clear
		// where are the short term incidence results by EN combination saved
		keep if name == "raw_nonshock_short_term_ecode_inc_by_platform"
		local pull_step = step in 1
		local modnum_dir = "`root_j_dir'/`date'/`pull_step'_raw_nonshock_short_term_ecode_inc_by_platform"	
		
		local dminput_dir "`tmp_dir'/02_temp/03_data/dm"
		capture mkdir "`dminput_dir'"
		
		** make effect_in.csv; same for all models
		import delimited "`in_dir'/parameters/draw_in.csv", delim(",") asdouble varnames(1) clear
		gen x_ones=1 
		export delimited using "`dminput_dir'/draw_in.csv", delim(",") replace
		
		** make draw_in.csv; same for all models
		import excel using "`in_dir'/parameters/effect_in_example.xlsx", sheet("Sheet1") firstrow clear
		if ("$SMR_or_chi"=="chi") drop if integrand=="mtstandard"
		expand 2 if integrand == "incidence", gen(mtexcess)
		replace integrand = "mtexcess" if mtexcess == 1
		export delimited using "`dminput_dir'/effect_in.csv", delim(",") replace
		
		** make the folder where the plain_in_`ecode'.csv files will be made
		local plainin_dir "`dminput_dir'/plain_in"			
		capture mkdir "`plainin_dir'"			
		** make the folder where the `ncode'/rate_in_`ecode'.csv files will be made
		local  ratein_dir "`dminput_dir'/rate_in"			
		capture mkdir "`ratein_dir'"
		
		local datain_dir "`dminput_dir'/data_in"
		capture mkdir "`datain_dir'"
		local ecode_count=0
		
		// PARALLELIZE data_in and rate_in BY ISO3/YEAR/SEX				
		local code "/`step_name'/create_data_rate_in_then_dismod_TREES_v2.do"
		get_demographics, gbd_team("epi")
		foreach location_id of global location_ids {
			foreach year_id of global year_ids {
				foreach sex_id of global sex_ids {
					! qsub -e /share/temp/sgeoutput/ngraetz/errors -o /share/temp/sgeoutput/ngraetz/output -P proj_injuries -N ode_`location_id'_`year_id'_`sex_id' -l hosttype=intel -pe multi_slot 4 -l mem_free=8 "`code_dir'/stata_shell.sh" "`code_dir'/`code'" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `location_id' `year_id' `sex_id'"
				}
			}
		}
		BREAK		
	}
	** end prep dm_input block

// Step 6: Append non-shock and shock E-codes to one file
	** make sure shock step has finished
	if $shock {
		local i = 0
		while `i' == 0 {
			local checks : dir "`ode_checkfile_dir'" files "shocks_*.txt", respectcase
			local count : word count `checks'
			di "checking `c(current_time)': `count' of `shock_jobs' jobs finished"
			if (`count' == `shock_jobs') continue, break
			else sleep 60000
		}
	}
	
	** run parallelized code to append results
	if ${append_results} {
		local code "`step_name'/smrs_append_results.do"	
		get_demographics, gbd_team("epi")	
		foreach location_id of global location_ids {
			foreach year_id of global year_ids {
				foreach sex_id of global sex_ids {
					! qsub -e /share/temp/sgeoutput/ngraetz/errors -o /share/temp/sgeoutput/ngraetz/output -P proj_injuries -N append_`location_id'_`year_id'_`sex_id' -pe multi_slot 4 -l mem_free=8 "`code_dir'/stata_shell.sh" "`code_dir'/`code'" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `location_id' `year_id' `sex_id'"
				}
			}
		}
	}
	
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

