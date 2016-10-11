// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	Run ODE on all incidence combinations: location/year/sex/platform/E-code/N-code

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM STEP CODE (NO NEED TO EDIT THIS SECTION)

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
	if "`1'"=="" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "05b"
		local 5 long_term_inc_to_raw_prev
		local 6 "/share/code/injuries/strUser/inj/gbd2015"
		local 7 72
		local 8 2010
		local 9 2
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
    // directory where the code lives
    local code_dir `6'
    // iso3
	local location_id `7'
	// year
	local year `8'
	// sex
	local sex `9'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for standard code files
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	
// SETTINGS
	** how many slots is this script being run on?
	local slots 1
	
// Filepaths
	local gbd_ado "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local dm_input_dir "/share/injuries/dm"
	local datain_dir "`dm_input_dir'/data_in_tree"
	local ratein_dir "`dm_input_dir'/rate_in_tree"
	local valuein_dir "`dm_input_dir'/value_in_storage"
	
	cap mkdir "`dm_input_dir'"
	cap mkdir "`datain_dir'"
	cap mkdir "`ratein_dir'"
	cap mkdir "`valuein_dir'"

// Import functions
	adopath + "`code_dir'/ado"
	adopath + `gbd_ado'
	
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Settings
	** use age mesh from E-code dm model, or arbitrary age mesh
	local use_ecode_age_mesh 1
	** turn on and off blocks for making the data_in files and the rate_in files
	local data_in 1
	local rate_in 1
	
// Load parameters
	load_params
	// if `check' local platforms inp
	local platforms inp otp
	
	get_demographics, gbd_team("epi") 
	get_populations, year_id(`year') location_id(`location_id') sex_id(`sex') age_group_id($age_group_ids) clear
		tempfile pops 
		save `pops', replace

// we need to check which version we specfied in the master step file:
// are we doing this analysis with SMR (mtstandard) in the data_in.csv file, or with chi (excess mortality) in the rate_in.csv file?
	capture confirm file  "`tmp_dir'/02_temp/01_code/SMR.txt"
	if !_rc {
		global SMR_or_chi SMR
	}
	else {
		capture confirm file  "`tmp_dir'/02_temp/01_code/chi.txt"
		if _rc {
			di "SMR_or_chi file incorrectly specified for this run"
		}
		else {
			global SMR_or_chi chi
		}
	
	}
	global SMR_or_chi chi
	di "$SMR_or_chi"

	
// get the directory with the dismod model numbers we pulled the original short-term incidence results from 
	import excel using "`code_dir'/_inj_steps.xlsx", sheet("steps") firstrow clear
	preserve
	keep if name == "SMR_to_excessmort"
	local pull_step = step in 1
	local SMR_dir = "`root_tmp_dir'/03_steps/`date'/`pull_step'_SMR_to_excessmort"	
	restore
	keep if name=="raw_nonshock_short_term_ecode_inc_by_platform"
	local pull_step = step in 1
	local model_num_dir = "`root_j_dir'/03_steps/`date'/`pull_step'_raw_nonshock_short_term_ecode_inc_by_platform"
	
// store in memory the list of n-codes with their own SMRs or excess mortality
// we will use regexm() later to decide if a given n-code is in this list
// we need to tack on "_true" to the end of the ncodes because:
// regexm("N33", "N3")=1 but regexm("N33_true","N3_true")=0
	import delimited using "`in_dir'/data/02_formatted/lt_SMR/lt_SMR_by_ncode.csv", delim(",") varnames(1) asdouble clear
	generate ncodes_true = ncode+"_true"
	levelsof ncodes_true, local(smr_ncodes) clean
	drop ncodes_true
	tempfile smrs
	save `smrs', replace

			
	adopath + "`code_dir'/ado"
	load_params
	
	
** *****************************************************************
**		CREATE DATA_IN CSVS
** *****************************************************************	
			
	// Pull and format all-cause mortality
		// New envelope 2015
		insheet using "`code_dir'/convert_to_new_age_ids.csv", comma names clear
			tempfile convert_ages
			save `convert_ages', replace
		quiet run "$prefix/WORK/10_gbd/00_library/functions/create_connection_string.ado"
			create_connection_string, strConnection
			local conn_string = r(conn_string)
		odbc load, exec("SELECT ihme_loc_id, location_name, location_id, location_type, super_region_name, most_detailed FROM shared.location_hierarchy_history WHERE location_set_version_id = (SELECT location_set_version_id FROM shared.location_set_version WHERE location_set_id = 9 and end_date IS NULL)") `conn_string' clear
			keep if most_detailed == 1
			keep if location_id == `location_id'
			local iso3 = [ihme_loc_id]

		capture mkdir "`datain_dir'/`iso3'"
		capture mkdir "`datain_dir'/`iso3'/`year'"
		capture mkdir "`datain_dir'/`iso3'/`year'/`sex'"
		capture mkdir "`ratein_dir'/`iso3'"	
		capture mkdir "`ratein_dir'/`iso3'/`year'"	
		capture mkdir "`ratein_dir'/`iso3'/`year'/`sex'"

		cap mkdir "/share/injuries/dm/prev_results_tree"
		cap mkdir "/share/injuries/dm/prev_results_tree/`iso3'"
		cap mkdir "/share/injuries/dm/prev_results_tree/`iso3'/`year'"
		cap mkdir "/share/injuries/dm/prev_results_tree/`iso3'/`year'/`sex'"

		// Make directory tree for temporary outputs from Bradmod
		cap mkdir "/share/injuries/dm/temp`location_id'/"
		cap mkdir "/share/injuries/dm/temp`location_id'/`year'"
		cap mkdir "/share/injuries/dm/temp`location_id'/`year'/`sex'"

		// Make a prev_results, data_in, and rate_in dir for each E-code
		foreach ecode of global nonshock_e_codes {
			cap mkdir "/share/injuries/dm/prev_results_tree/`iso3'/`year'/`sex'/`ecode'"
			cap mkdir "`datain_dir'/`iso3'/`year'/`sex'/`ecode'"
			cap mkdir "`ratein_dir'/`iso3'/`year'/`sex'/`ecode'"
		}

// Save rate in files by ecode in temp directory for this job
	// Get me ids
		insheet using "`code_dir'/master_injury_me_ids.csv", comma names clear
		keep if injury_metric == "Adjusted data"
		keep modelable_entity_id e_code
		tempfile mes 
		save `mes', replace
		foreach ecode of global nonshock_e_codes {
			quietly {
				use `mes' if e_code == "`ecode'", clear
				local me_id = modelable_entity_id
				get_best_model_versions, gbd_team(epi) id_list(`me_id') clear
				local model_id = model_version_id
				import delimited "/share/epi/panda_cascade/prod/`model_id'/full/rate.csv", delim(",") varnames(1) clear asdouble		
				tempfile `ecode'_rate_in
				save ``ecode'_rate_in', replace 
			}
		}

// Save rho and chi for this job 
	quietly {
		insheet using "`out_dir'/01_inputs/rho.csv", comma names clear
		tostring lower, replace
		tostring upper, replace
		tempfile def_rho
		save `def_rho', replace
	}
	
	// Bring in 0 excess file
	quietly {
		insheet using "`out_dir'/01_inputs/chi.csv", comma names clear
		tostring lower, replace
		tostring upper, replace
		tempfile def_chi
		save `def_chi', replace
	}

	// Save age bounds in temp folder 
	use "`out_dir'/01_inputs/age_bounds.dta", clear
	tempfile age_bounds
	save `age_bounds', replace 

	local dm_input = "/share/injuries/dm"

		import delimited using  "/ihme/gbd/WORK/02_mortality/03_models/5_lifetables/results/env_loc/with_shock/env_`location_id'.csv", delim(",") varnames(1) clear
		keep if sex_id == `sex' & year_id == `year'
		gen ihme_loc_id = "`ihme_loc_id'"
		gen location_id = `location_id'
		drop if age_group_id > 21 | age_group_id == 1 
		keep ihme_loc_id location_id sex_id age_group_id year_id draw_*
		merge 1:1 age_group_id using `pops', assert(match) nogen
		rename draw* env*
		merge 1:1 age_group_id using `convert_ages', keep(3) nogen

		//rename age age_start
		merge 1:1 age_start using `age_bounds', keep(3) nogen
		rename age_start age
		forvalues i = 0/999 {
			replace env_`i' = env_`i' / pop
		}
		egen mean = rowmean(env_*)
		egen upper = rowpctile(env_*), p(97.5)
		egen lower = rowpctile(env_*), p(2.5)
		egen std = rowsd(env_*)
		keep age_lower age_upper mean std upper lower
		// BOUND AT ZERO - this was causing entire C/Y/S's to not make it through Dismod
		replace lower = 0 if lower < 0
		// Make sure mean not greater that upper (ERI is messed up because of shocks)
		replace mean = lower + ((upper-lower)/2) if mean > upper 
		gen age = (age_upper + age_lower) / 2 
		gen type = "omega"
		sum std
		gen mean_std = r(mean)
		tostring mean_std, force replace
		tostring std, force replace
		tostring upper, force replace
		tostring lower, force replace
		expand 2 if age_lower == 0, gen(dup)
			replace age = 0 if dup == 1
			replace std = "inf" if dup == 1
			replace lower = "0" if dup == 1
			replace upper = "inf" if dup == 1
			drop dup
		expand 2 if age == 90, gen(dup)
			replace age = 100 if dup == 1
			sum std
			replace std = mean_std if dup == 1
			replace lower = "0" if dup == 1
			replace upper = "inf" if dup == 1
			drop dup
		expand 2, gen(dup)
			replace type = "domega" if dup == 1
			drop if age == 100 & dup == 1
			replace lower = "_inf" if dup == 1
			replace upper = "inf" if dup == 1
			replace mean = 0 if dup == 1
			replace std = "inf" if dup == 1
			drop dup
			drop age_lower age_upper mean_std
		tempfile mtall
		save `mtall', replace
		
	// Pull and format incidence
		use "`tmp_dir'/02_temp/03_data/lt_inc/nonshocks/summary/incidence_`location_id'_`year'_`sex'.dta", clear
			rename age age_start
		merge m:1 age_start using `age_bounds', keep(3) nogen
			rename age_start age
		// edit 8/10/14 ng - replace age_upper = 1 to accomodate only using a single 0-1 age group now
		replace age_upper = 1 if age == 0
		// drop if age==80
		rename mean meas_value
		capture rename meas_std meas_stdev
		keep meas_value meas_stdev age_lower age_upper e_code n_code inpatient
		gen integrand = "incidence"	
		gen subreg="none"
		gen region="none"
		gen super="none"
		
	
	** EDIT 7/10/14 ng - There was an issue with incidence inputs with extremely high SDs (especially with means near 0) resulting in dismod failing to fit an incidence curve and spitting out really high, random prevs.  Artficial SD cap for now via Theo - no more than 50% of mean 
		
		replace meas_stdev = (meas_value/2) if meas_stdev > (meas_value/2) 
		** replace SD = lowest SD of any non-zero means if mean = 0 & SD != 0
		sum meas_value if meas_value > 0
		sum meas_stdev if meas_value == r(min) 
		replace meas_stdev = r(min) if meas_value == 0 
		
	** save incidence inputs
		tempfile inc
		save `inc', replace

		
	// Format SMRs for data_in file
		if "$SMR_or_chi" == "SMR" {
			use `smrs', clear
			rename smr meas_value
			rename age age_start
			merge m:1 age_start using `age_bounds', keep(3) nogen
			rename age_lower gbd_age_lower
			rename age_upper gbd_age_upper
			egen age_lower = min(gbd_age_lower), by(ncode meas_value)
			egen age_upper = max(gbd_age_upper), by(ncode meas_value)
			gen meas_stdev = (ul - ll) / 3.92
			rename ncode n_code
			keep meas_value meas_stdev age_upper age_lower n_code
			generate integrand="mtstandard"
			duplicates drop
			gen subreg="none"
			gen region="none"
			gen super="none"
			tempfile newsmrs
			save `newsmrs', replace
		}
		** end loop confirming if "SMR_or_chi"=="SMR"

// ******************************************************************************
// ******************************************************************************
//			LOOP OVER PYTHON ODE SOLVER
//				by platform, E-code, N-code
// ******************************************************************************
// ******************************************************************************		
	// Set platforms
		local platforms inp otp

	// Write data_in and hold onto data values for use when creating value_in file (need to make eta = to 1% of median of non-zero values in data_in
		tempfile pf_inc pf_n_inc SMR_n valin
		foreach platform of local platforms {
		
		// Get numerical indicator of inpatient status for use in pulling from incidence data
			if "`platform'"=="inp" {
				local inpatient_num = 1
			}				
			if "`platform'"=="otp" {
				local inpatient_num = 0
			}			
			
		// Get list of N-codes experienced in this country-year-sex-platform and save portion of dataset to draw from later
			quietly {
				use `inc' if inpatient == `inpatient_num', clear
				save `pf_inc', replace
				levelsof n_code, local(`pf'_ncodes)
			}

		// Loop over N-codes within a platform
			foreach ncode of local `pf'_ncodes {

				// Pull in relavent incidence
				use `pf_inc' if n_code == "`ncode'", clear
				save `pf_n_inc', replace				
			
			if n_code == "N9" | n_code == "N19" | n_code == "N28" | n_code == "N33" | n_code == "N19" | n_code == "N34" | n_code == "N48" {
			if "$SMR_or_chi" == "chi" {
				
				if `sex' == 1 {
					local sex_string male
					}
				if `sex' == 2 {
					local sex_string female
					}
				
				
				if n_code == "N48" {
					// Import N-code with highest excess mort to use with N48 because we have no data - "multiple significant injuries"
					qui import delimited using "`SMR_dir'/03_outputs/01_draws/N9/f_`iso3'_`year'_`sex_string'.csv", delim(",") asdouble clear
					}
				else {
					qui import delimited using "`SMR_dir'/03_outputs/01_draws/`ncode'/f_`iso3'_`year'_`sex_string'.csv", delim(",") asdouble clear
					}
				quietly {
				fastrowmean draw*, mean_var_name("meas_value")
				egen meas_stdev = rowsd(draw_*)
				drop draw_*
				rename age age_start
				merge 1:1 age_start using `age_bounds', keep(3) nogen
				drop if age_start > 0 & age_start < 1
				drop age_group_id age_start

				// edit 8/10/14 ng - change to 0-1 category to incorporate collapsed group instead of all those weird groups between 0 and 1
				replace age_upper = 1 if age_lower == 0
				gen integrand = "mtexcess"
				gen subreg = "none"
				gen region = "none"
				gen super = "none"
				//rename age age_lower
				sum meas_value
				local mtexcess_value = r(min)*0.01
				tempfile mtexcess
				save `mtexcess', replace
				}
			}
			}
			// Pull in relavent incidence
				use `pf_inc' if n_code == "`ncode'", clear
				save `pf_n_inc', replace				
			// Get list of E-codes that distribute to this particular N-code
				levelsof e_code, local(`ncode'_`pf'_ecodes)
				
			// Loop over E-codes within an Ncode-platform group
				foreach ecode of local `ncode'_`pf'_ecodes {
					
				// REFRESH e-code rate tempfiles
				quietly {
					use ``ecode'_rate_in', clear
					save ``ecode'_rate_in', replace
					// REFRESH tempfiles
					use `pf_inc', clear
					save `pf_inc', replace
					use `mtall', clear
					save `mtall', replace
				}
				
				// RESET out_dir local, as it gets changed in each loop at the Dismod part
				local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
				
				// Load incidence by E-code, N-code, platform
				qui use `pf_n_inc' if e_code=="`ecode'", clear

				// Append SMR if applicable
					if "$SMR_or_chi"=="SMR" append using `SMR_n'
					
				// Append all-cause mortality
					// append using `mtall' - NOT ANYMORE, THIS IS GOING IN RATE_IN
				
				// edit 7/23/14 ng - Append excess mortality
					if n_code == "N9" | n_code == "N19" | n_code == "N28" | n_code == "N33" | n_code == "N19" | n_code == "N34" | n_code == "N48" {
						qui append using `mtexcess'
					}
				// Append column used to define heterogenaeity of data
					qui generate x_ones=1
					
				// Save data_in file
					preserve
					quietly {
						drop n_code inpatient e_code
						order integrand meas_value meas_stdev age_lower age_upper subreg region super
						sort integrand age_lower
					}
						di "	"
						di "Saving data_in..."
						tempfile tmp_data_in
						save `tmp_data_in', replace
						qui outsheet using "`datain_dir'/`iso3'/`year'/`sex'/`ecode'/data_in_`ncode'_`platform'.csv", comma names replace
					restore

	
** *****************************************************************
**		CREATE RATE_IN CSVS
** *****************************************************************
	
	
	// Bring in 0 remission file
	quietly {
	use `def_rho', clear
	save `def_rho', replace
	}
	
	// Bring in 0 excess file
	quietly {
	use `def_chi', clear
	save `def_chi', replace
	}
	
	// Create list of midpoints for GBD age groups
		if "${SMR_or_chi}"=="chi" | !`use_ecode_age_mesh' {
			quietly {
				use `age_bounds', clear
				egen mid_age = rowmean(age_lower age_upper)
				drop age_*
				tempfile mesh
				save `mesh', replace
			}
		}		

	// Now create rate_in_iso3_year_sex over n/e codes
		qui tempfile chi_only chi
			
					if "`ncode'" == "N9" | "`ncode'" == "N19" | "`ncode'" == "N28" | "`ncode'" == "N33" | "`ncode'" == "N19" | "`ncode'" == "N34" | "`ncode'" == "N48" {
						local excess_mort_code = 1
						}
					else {
						local excess_mort_code = 0
						}

	// Get iota and omega age mesh from e-code dismod file if we are taking that approach
					if `use_ecode_age_mesh' {
						quietly {
							di "``ecode'_rate_in'"
							use ``ecode'_rate_in', clear
							save ``ecode'_rate_in', replace
							keep if regexm(type,"iota") | regexm(type,"omega")
							replace lower = "0" if type == "iota"
							replace lower = "_inf" if type == "diota"
							replace upper = "inf" if type == "diota"
							replace mean = 0 if type == "diota"
							// edit 7/23/14 ng - duplicate iota and diota paramters for chi, dchi
							if `excess_mort_code' == 1 {
								expand 2 if type == "iota", gen(dup)
								replace type = "chi" if dup == 1
								drop dup
								expand 2 if type == "diota", gen(dup)
								replace type = "dchi" if dup == 1
								drop dup
							}
							else {
								append using `def_chi'
							}
							tempfile iota_omegas
							save `iota_omegas', replace
						}
					}
					
					** append all of the pieces (iota, omega, rho, chi) together
					quietly {
						use `iota_omegas', clear
						append using `def_rho'
						
						** edit 7/24/14 ng - APPEND mtall to rate_in instead of data_in
						drop if type == "omega" | type == "domega"
						append using `mtall'
					}
				// Save rate_in file
					qui sort type age
					di "Saving rate_in..."
					qui outsheet using "`ratein_dir'/`iso3'/`year'/`sex'/`ecode'/rate_in_`ncode'_`platform'.csv", comma names replace						
						
			
// NEW - RUN DISMOD THEN DELETE ALL C/Y/S INPUTS RIGHT AWAY
	
	// Filepaths
	local gbd_ado "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Settings
	local use_clustertmp 1
	local code_lib "$prefix/WORK/04_epi/01_database/01_code/00_library"
	local python_code "`code_lib'/pyHME/epi/run_dismod_ode_nick.py"

// Define parent loaction for dismod input
	local dm_input = "`dm_input_dir'"
	
// Run dismod for each E-N-platform combo
	foreach f in effect_in draw_in {
		local `f' "`f'.csv"
	}
	
	local output_dir "`out_dir'/03_outputs"
	local draw_dir "/share/injuries/dm/prev_results_tree"
	
			di "Running ODE: `ncode' `ecode' `platform'"
			di "......."
			di "......."

				** need to do a couple of checks before submitting the files for dismod:
				** check that value_in.csv got made for this e-code
				
					** check that there is a data_in file for this e/n/pf

						** check that there is nonzero incidence in the data_in.csv
						use `tmp_data_in', clear
						qui count if integrand=="incidence" & meas_stdev!=0
						if r(N)==0 {
							di "`ecode' `ncode' `platform' has all meas_stdev = 0. Check if this is unexpected"
						}
						else {
							
							local value_in "value_in/`ecode'/value_in_`ncode'.csv"
								if "`ecode'" == "inj_non_disaster" {
									local value_in "value_in/inj_trans_road_pedest/value_in_`ncode'.csv"
								}
							local rate_in "rate_in_tree/`iso3'/`year'/`sex'/`ecode'/rate_in_`ncode'_`platform'.csv"
							local data_in "data_in_tree/`iso3'/`year'/`sex'/`ecode'/data_in_`ncode'_`platform'.csv"
							local plain_in "plain_in/plain_in_`ecode'.csv"
							local temp_dir "temp`location_id'/`year'/`sex'"
							local temp_suffix "`iso3'_`year'_`sex'_`platform'_`ncode'_`ecode'"
							local draw_out "`draw_dir'/`iso3'/`year'/`sex'/`ecode'/prevalence_`ncode'_`platform'.csv"					
							
							// Run ODE
							quietly !/usr/local/epd-current/bin/python `python_code' `dm_input' `draw_in' `data_in' `value_in' `plain_in' `rate_in' `effect_in' `temp_dir' `temp_suffix' `draw_out' `code_lib'
							
						// Confirm that python worked or indicate that code broke
							di "Final file confirmed - deleting temp inputs/outputs"
								quietly {
									cap erase "`dm_input'/`temp_dir'/sample_out_`iso3'_`year'_`sex'_`platform'_`ncode'_`ecode'.csv"
									cap erase "`dm_input'/`data_in'"
									cap erase "`dm_input'/`rate_in'"
								}
							
						}
						** end confirming that meas_stdev>0 for this e-code/platform
					
					** end confirming there is a data_in.csv file for this e-code/platform
				
				** end confirming there is a value_in_`ncode'.csv file
			}
		}
	}
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// CHECK FILES (NO NEED TO EDIT THIS SECTION)

	// write check file to indicate sub-step has finished
		file open finished using "/snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/05b_long_term_inc_to_raw_prev/02_temp/04_diagnostics/`location_id'_`year'_`sex'_nonshock.txt", replace write



	