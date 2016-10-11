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
	
	if "`1'" == "" {
	global prefix /home/j
	local 1 otp
	local 2 "/clustertmp/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/04a_prob_long_term"
	local 3 "`2'/02_temp/03_data"
	local 4 "N30 N31 N32 N47"
	local 5 "N1	N2 N4 N5 N7 N3 N6"
	local 6 "`2'/02_temp/03_data"
	local 7 "/snfs2/HOME/ngraetz/local/inj/gbd2015"
	local 8 "`3'/lt_t_dws_by_ncode.csv"
	local 9 "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	local 10
	local 11
	local 12
	}
// Import macros
	local inp `1'
	local step_dir `2'
	local data_dir `3'
	local no_lt `4'
	local all_lt `5'
	local savedir `6'
	local code_dir `7'
	local dw_file `8'
	// Directory of general GBD ado functions
	local gbd_ado `9'
	// Step diagnostics directory
	local diag_dir `10'
	// Name for this job
	local name `11'
	// Number of slots used
	local slots `12'
	
// Log
	local log_file "`step_dir'/02_temp/02_logs/run_regression_`inp'_WITH_AGE.smcl"
	log using "`log_file'", name(run_regression) replace
	
// Import functions
	// adopath + `gbd_ado'
	adopath + `code_dir'/ado
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	
// Settings
	local debug 99
	set type double, perm
	
// Load injury parameters
	load_params
	
// Make square dataset for predictions
	insheet using "`code_dir'/convert_to_new_age_ids.csv", comma names clear
		tempfile new_ages
		save `new_ages', replace
	get_demographics, gbd_team(epi) make_template clear
	merge m:1 age_group_id using `new_ages', keep(3) nogen
		keep if location_name == "China" | location_name == "United States" | location_name == "Netherlands"
		gen iso3 = "CHN" if location_name == "China"
		replace iso3 = "USA" if location_name == "United States"
		replace iso3 = "NLD" if location_name == "Netherlands"
	keep if year == 2000 // just some random year, only need one because we aren't predicting by year
	keep iso3 sex age_start
	rename sex_id sex
	rename age_start age
	drop if age < 1 & age != 0
	expand 48
	bysort iso3 sex age: gen n_code_num = _n
	rename age age_gr
	gen n_code = n_code_num
	tostring n_code, replace
	replace n_code = "N"+n_code
			gen dummy_N21 = 1 if n_code_num == 21
			replace dummy_N21 = 0 if dummy_N21 == .
		gen dummy_N28 = 1 if n_code_num == 28
			replace dummy_N28 = 0 if dummy_N28 == .
		gen dummy_N41 = 1 if n_code_num == 41
			replace dummy_N41 = 0 if dummy_N41 == .
	gen nvrinj = 0
	tempfile square
	save `square', replace
	
// import dataset
	use "`data_dir'/appended.dta", clear
	
// keep relevant platforms
** NOTE 19 Feb 2014 (IB): Decided for patients with one inpatient and one outpatient injury 
** (i.e. inpatient == 2), we will include these patients in the inpatient analysis, since this is
** more severe. Eventually, we hope to keep track of which n-code is inpatient so that we
** can keep those N-codes automatically and drop the outpatient codes.
	if `inp'==1 keep if inlist(inpatient,1,2) | inpatient == .
	else if `inp'==0 keep if inpatient == 0 | inpatient == .
	tempfile current_ds
	
// save dataset to use in regression
	save `current_ds', replace
	
//	while "`no_lt'" != "" {
		use `current_ds', clear
		
	// add recent additions to the 100% LT groups to a local (used to append on these DWs after regression model is done)
		local no_lt_tot `no_lt_tot' `no_lt'
		
	// drop variables that previously resulted in negative DWs (or are a priori no-LT)
		foreach n of local no_lt {
			replace n_code_num = 0 if n_code == "`n'"
			replace n_code = "" if n_code == "`n'"
		}
	
	// save adjusted dataset
		save `current_ds', replace
		
	// run regression
		** need to rename the never_injured variable because we are getting variable names that are too long
		rename never_injured nvrinj
		// MAKE DUMMIES
		gen dummy_N21 = 1 if n_code_num == 21
			replace dummy_N21 = 0 if dummy_N21 == .
		gen dummy_N28 = 1 if n_code_num == 28
			replace dummy_N28 = 0 if dummy_N28 == .
		gen dummy_N41 = 1 if n_code_num == 41
			replace dummy_N41 = 0 if dummy_N41 == .
		// mixed logit_dw b0.n_code_num age_gr##sex##nvrinj || iso3: || id:
		// NO AGE:
			// mixed logit_dw b0.n_code_num b0.nvrinj b0.nvrinj#c.age_gr c.age_gr#dummy_N21 c.age_gr#dummy_N28 c.age_gr#dummy_N41 || iso3: || id:
		// WITH AGE:
			//save "/share/injuries/03_steps/2016_02_08/review_week/`inp'_input.dta"
			mixed logit_dw b0.n_code_num c.age_gr b0.nvrinj b0.nvrinj#c.age_gr c.age_gr#dummy_N21 c.age_gr#dummy_N28 c.age_gr#dummy_N41 || iso3: || id:
	
	if 1==2 {
	// Don't need people without an injury anymore
		drop if n_code_num == 0
		
	// get draws of prediction of observed logit(DW)
		linear_fixed_predict_draws obs, n($drawnum)
		
		** drop anyone who may have been missing
		drop if obs_1 == .
		
		** obtain residuals
		foreach var of varlist obs_* {
			replace `var' = logit_dw - `var'
			local newvar = subinstr("`var'","obs_","resid_",1)
			rename `var' `newvar'
		}
		
	// predict counterfactual if no injury
		replace n_code_num = 0
		linear_fixed_predict_draws cf, n($drawnum)
		
		** add on residual from predicted outcome
		foreach var of varlist cf_* {
			local resid_var = subinstr("`var'","cf_","resid_",1)
			replace `var' = `var' + `resid_var'
		}
		
				** calculate DW attributable to injury
		foreach var of varlist cf_* {
			local drawvar = subinstr("`var'","cf_","draw_",1)
			gen `drawvar' = 1 - ((1-invlogit(logit_dw))/(1-invlogit(`var')))
			drop `var'
		}
		
		// EDIT 8/18/14 NG - TRY USING 2010 TOTAL DW AS COUNTERFACTUAL INSTEAD OF MEPS DATA
			tempfile predictions
			save `predictions', replace
			// outsheet using "/snfs3/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2013/03_steps/2014_05_30/04a_prob_long_term/02_temp/02_logs/new_regress_predictions`inp'.csv", comma names replace
			
			tostring age, replace force format(%12.3f)
			destring age, replace force
			merge m:1 iso3 age_gr sex using `totaldw'
			keep if _merge == 3
			drop _merge
			forvalues i = 0/999 {
				gen draw_`i' = 1 - ((1-invlogit(logit_dw))/(1-invlogit(total_dw)))
			}
			// outsheet using "/snfs3/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2013/03_steps/2014_05_30/04a_prob_long_term/02_temp/02_logs/probs`inp'.csv", comma names replace
			}
			
		// NEW PREDICTION METHOD - by square iso3/age/sex, ignore residual weirdness above
		use `square', clear
		predict obs_1
		//save "/share/injuries/03_steps/2016_02_08/review_week/`inp'_results.dta", replace
		replace n_code_num = 0
		replace dummy_N21 = 0
		replace dummy_N28 = 0
		replace dummy_N41 = 0
		predict cf_1
		gen draw_ = 1 - ((1-invlogit(obs_1))/(1-invlogit(cf_1)))
		
		** collapse to find mean values for each draw for each N-code
		** TODO: Is there a better way to do this than crude mean? This is bad f there are differing age/sex
		** patterns in different N-codes. Maybe generate a dataset with one observation per age-sex and use 
		** global age-standardization weighting. Shouldn't make a huge difference though, given that we are just
		** looking at the marginal effect of the n-code
		gen n_ = 1
		collapse (mean) draw_* (sum) n_, by(age n_code)
		drop if n_code == ""
		
		** check for no-LT N-codes
		egen high_prob = rowmax(draw_*)
		levelsof n_code if high_prob <= 0, l(no_lt) c
		drop high_prob
				
	// }
		
// Continue if no "no-LT" n-codes found during this iteration

// constrain all draws to be 0<=x<=1
	foreach var of varlist draw_* {
		replace `var' = 0 if `var' < 0
		replace `var' = 1 if `var' > 1
	}
	
	
// add in the no-LT and all-LT n-codes
	foreach a in no_lt_tot all_lt {
		if "`a'" == "no_lt_tot" local value = 0
		else if "`a'" == "all_lt" local value = 1
		gen `a' = 0
		foreach n of local `a' {
			drop if n_code == "`n'"
			local new_obs = _N + 1
			set obs `new_obs'
			replace n_code = "`n'" in `new_obs'
			replace `a' = 1 in `new_obs'
			foreach var of varlist draw_* {
				replace `var' = `value' in `new_obs'
			}
		}
	}

// save draws
	// cap mkdir "`savedir'/00_dw_draws"
	// save "`savedir'/00_dw_draws/platform_`inp'.dta", replace
	
// merge on GBD dws
	tempfile main
	save `main', replace
	import delimited using "`dw_file'", delim(",") clear varnames(1)
	rename draw* gbd_draw_*
	merge 1:m n_code using `main'
	** need to keep not only those that merge, but those that shouldn't merge
	keep if _m == 3 | all_lt == 1 | no_lt_tot == 1

// Edit 8/14/14 ng - output a pooled followup DW vs GBD DW for diagnostics
	preserve
		egen gbd_mean = rowmean(gbd_draw_*)
		egen followup_mean = rowmean(draw_*)
		drop draw_* gbd_draw_*
		// outsheet using "`data_dir'/NO_DUTCH_gbd_followup_comparison_platform`inp'.csv", comma names replace
	restore

	// NEW TO ACCOUNT FOR REGRESSION METHOD BY AGE
	forvalues i = 0/999 {
	replace gbd_draw_`i' = draw_/gbd_draw_`i'
	replace gbd_draw_`i' = 1 if gbd_draw_`i'>1 & gbd_draw_`i' !=.
	rename gbd_draw_`i' draw_`i'
	}
	** replace values that are > 1 
	foreach var of varlist draw_* {
		replace `var' = 1 if `var' > 1 & `var' != .
	}
	
	** Confirm that we should not have any duplicate n-codes
	// isid n_code
	
	** save
	cap mkdir "`savedir'/01_prob_draws"
	save "`savedir'/01_prob_draws/`inp'_squeeze_WITH_AGE.dta", replace
	//save "/share/injuries/03_steps/2016_02_08/review_week/`inp'_results.dta", replace

	** create check files
	local check_file_dir "`data_dir'/check_files"
	file open done_summary using "`check_file_dir'/regression_`inp'.txt", replace write
	file close done_summary
	
	log close run_regression


	