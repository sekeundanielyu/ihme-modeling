** ***********************************************************
** Date Created: 19 April 2011 
** Description: fits the age and sex models and saves model coefficients and 
**			  random effects. Note that this code also outputs plots to 
**			  'Results/age_sex_model_plots' that show random effect 
**			  estimates for each model. 
** ***********************************************************

	clear all 
	capture cleartmp
	set more off
	pause off
	cap restore, not
	
	capture log close
	
	global archive = 0 

** set globals 
	if (c(os)=="Unix") {
		set odbcmgr unixodbc
		global root "" 
		local input_data "input_data.dta"
		local child_data ""
		global R_path ""
		local code_dir `1'
		local use_ctemp `2'
		if ("`use_ctemp'" == "1") global root ""
		di "`code_dir'"
		qui do "get_locations.ado"
	}
	else {
		global root ""
		local input_data "input_data.dta"
		local child_data ""
		global R_path ""
		qui do "get_locations.ado"
		local code_dir ""
	}
	 
	cd ""
	
	if ($archive==1) { 
		local date = subinstr("`c(current_date)'", " ", "_", 2)	
		mkdir "data/fit_models/archive/`date'"
	}
	
	
** get locations
	get_locations, level(estimate)
	keep if level_all == 1
	keep ihme_loc_id region_name
	rename region_name gbdregion
	levelsof ihme_loc_id, local(all_iso3s)
	local num_countries: word count `all_iso3s'
	tempfile countrycodes
	save `countrycodes', replace

	
** ***************************	
** Fit sex-model 
** ***************************
noisily di in red "fit sex model" 

** Format data which will be used to build the model 
	use "`input_data'", clear
	keep if exclude == 0 
	keep region_name ihme_loc_id year source sex q_u5
	reshape wide q_u5, i(ihme_loc_id year source) j(sex, string)
	rename q_u5both q5_both 
	gen q5_sex_ratio = q_u5male / q_u5female 
	rename region_name gbdregion
	keep gbdregion ihme_loc_id year q5_both q5_sex_ratio 
	gen type = "data" 
	
** Create 5q0 bins 
	sort q5_both
	local total = _N 
	gen bin = . 
	forvalues m=1/20 { 	
		replace bin = `m' if _n >= (`total'*(`m'-1)/20) & _n <= (`total'*(`m')/20)
	} 	
	
	gen log_q5_sex_ratio = ln(q5_sex_ratio)
	
** Fit model: 
	xtmixed log_q5_sex_ratio || _all: R.bin || gbdregion: || ihme_loc_id: 
	
** Extract random effects 
	predict re_bin, reffects level(_all)
    predict re_bin_se, reses level(_all)
	predict regbd, reffects level(gbdregion)
	predict regbd_se, reses level(gbdregion) 
	predict reiso, reffects level(ihme_loc_id)
	predict reiso_se, reses level(ihme_loc_id)
	
	
** Deal with bin RE's 
	** Smooth bins RE in R
		preserve
		keep q5_both bin re_bin re_bin_se
		gen model = "sex_model" 
		gen varname = "q5_both"
		saveold "data/fit_models/bin_res_for_smoothing.dta", replace	
		saveold "data/fit_models/sex_model_parameters_bins_before_smoothing.dta", replace	
		if ($archive==1) saveold "data/fit_models/archive/`date'/sex_model_parameters_bins_before_smoothing.dta", replace			
		! "$R_path" < "`code_dir'/smooth_bin_re.r" --no-save		
	
	** Simulate for bins RE
		use "data/fit_models/bin_res_smoothed.dta", clear
		expand 1000 
		bysort q5_both: gen simulation = _n -1
		set seed 826
		gen rebin = rnormal(re_bin_pred, re_bin_pred_se)
		drop re_bin_*
		rename q5_both merge_q5_both
		tostring merge_q5_both, replace force format(%9.3f)
		saveold "data/fit_models/sex_model_simulated_parameters_bins.dta", replace
		if ($archive==1) saveold "data/fit_models/archive/`date'/sex_model_simulated_parameters_bins.dta", replace
		use "data/fit_models/bin_res_smoothed.dta", clear 
		rename re_bin_pred rebin
		drop re_bin_pred_se
		rename q5_both merge_q5_both
		tostring merge_q5_both, replace force format(%9.3f)
		saveold "data/fit_models/sex_model_parameters_bins.dta", replace	
		if ($archive==1) saveold "data/fit_models/archive/`date'/sex_model_parameters_bins.dta", replace
		restore
		
		** create region-level error term SD
		preserve
		tostring q5_both, gen(merge_q5_both) format(%9.3f) force
		merge m:1 merge_q5_both using "data/fit_models/sex_model_parameters_bins.dta"
		drop if _m == 2
		drop if q5_both == .
		drop _m
		matrix b = e(b) 
		gen intercept = _b[log_q5_sex_ratio:_cons]
		gen pred = intercept + regbd + reiso + rebin
		gen er = pred-log_q5_sex_ratio
		bysort gbdregion: egen error_sd = sd(er)
		keep gbdregion error_sd
		duplicates drop
		tempfile region_errors
		save `region_errors', replace
		restore
		
		drop re_bin* q5* bin year
		
	rm "data/fit_models/bin_res_for_smoothing.dta"
	rm "data/fit_models/bin_res_smoothed.dta"

		append using `countrycodes'
		replace type = "hold" if type == "" 

		estat recovariance, level(ihme_loc_id)
			matrix temp = r(cov)
			gen reiso_var = temp[1,1]
		estat recovariance, level(gbdregion)
			matrix temp = r(cov)
			gen regbd_var = temp[1,1]			
		
		preserve 
		keep if type == "data" & reiso != .  
		keep reiso* ihme_loc_id 
		duplicates drop 
		tempfile reiso
		save `reiso', replace 
		restore, preserve
		keep if type == "data" & regbd != . 
		keep regbd* gbdregion
		duplicates drop
		tempfile regbd
		save `regbd', replace
		restore
		merge m:1 ihme_loc_id using `reiso', update
		drop _m 
		merge m:1 gbdregion using `regbd', update
		drop _m 

		foreach level in iso gbd { 
			replace re`level' = 0 if re`level' == . 
			replace re`level'_se = sqrt(re`level'_var) if re`level'_se == . 
			drop re`level'_var
		} 
		keep if type == "hold"
		merge m:1 gbdregion using `region_errors'
		assert _m == 3
		drop _m
		drop type gbdregion
		
	** Sampling for ihme_loc_id RE and error term 
		set seed 826
		expand 1000 
		bysort ihme_loc_id: gen simulation = _n - 1
		gen reiso_ = rnormal(reiso, reiso_se)
		gen regbd_ = rnormal(regbd, regbd_se)
		gen error = rnormal(0,error_sd)
		rename reiso reiso_nosim
		rename regbd regbd_nosim
		drop reiso_se regbd_se error_sd
		rename reiso_ reiso	
		rename regbd_ regbd 

** Deal with fixed effects 		
	** Extract fixed effects estimates and variance-covariance matrices 
		matrix b = e(b) 
		gen intercept = _b[log_q5_sex_ratio:_cons]
		matrix v = e(V)
		gen intercept_se = sqrt(v[1,1])
		
	** Sampling for fixed effects 
		gen intercept_ = rnormal(intercept, intercept_se)
		rename intercept intercept_nosim
		drop intercept_se
		rename intercept_ intercept
	
** Save model parameters 
	preserve
	keep ihme_loc_id *_nosim
	foreach var in regbd reiso intercept { 
		rename `var' `var'
	} 
	duplicates drop
	saveold "data/fit_models/sex_model_parameters_other.dta", replace
	if ($archive==1) saveold "data/fit_models/archive/`date'/sex_model_parameters_other.dta", replace
	restore
	
	drop *nosim
	saveold "data/fit_models/sex_model_simulated_parameters_other.dta", replace 	
	if ($archive==1) saveold "data/fit_models/archive/`date'/sex_model_simulated_parameters_other.dta", replace 
	
** ***************************	
** Fit age-model 
** ***************************
noisily di in red "fit age model" 

** Format data which will be used to build the model 
	use "`input_data'", clear
	gen i_nonvr = 0 if inlist(broadsource,"DSP","VR","SRS")
	replace i_nonvr = 1 if i_nonvr == .
	keep if exclude == 0 
	gen log_q_u5_ = log(q_u5)
	keep region_name ihme_loc_id year sex log_q_u5 prob* source age_type out* i_nonvr s_comp
	rename region_name gbdregion 
	foreach var of varlist prob* { 
		replace `var' = log(`var')
		rename `var' log_`var'_
	} 
	gen yearmerge = round(year)
	tempfile data
	save `data', replace
	
	** Load in covariates
	insheet using "`child_data'/data/prediction_input_data.txt", clear
	keep ihme_loc_id year hiv maternal_educ
	rename maternal_educ m_educ
	gen yearmerge = round(year)
	duplicates drop
	merge 1:m ihme_loc_id yearmerge using `data'
	keep if _merge == 3
	drop _merge yearmerge
	
	reshape wide log_prob_enn log_prob_lnn log_prob_pnn log_prob_inf log_prob_ch log_q_u5, i(ihme_loc_id year source age_type) j(sex, string)
	preserve
	keep ihme_loc_id year source age_type log*
	saveold "data_modelspace.dta", replace
	restore
	
	gen type = "data" 
	save `data', replace

** Loop through sex and age to fit each model 
	tempfile saveall_bins
	tempfile saveall_bins2
	tempfile saveall_other
	tempfile saveall_other2
	tempfile residuals
	
	local count = 0 
	foreach sex in male female { 
	foreach age in enn lnn pnn inf ch { 
		noisily di in red "   `sex' - `age'" 
		local count = `count' + 1 
		use `data', clear 			
		
	** Create bins
		if ("`age'" == "enn") keep if age_type == "enn/lnn/pnn/ch" & out_enn == 0
		if ("`age'" == "lnn") keep if age_type == "enn/lnn/pnn/ch" & out_lnn == 0
		if ("`age'" == "pnn") keep if out_pnn == 0 & age_type == "enn/lnn/pnn/ch" | age_type == "nn/pnn/ch" 
		if ("`age'" == "inf") keep if out_inf == 0
		drop age_type source out*
		sort log_q_u5_`sex'
		local total = _N 
		gen bin = . 
		forvalues m=1/20 { 	
			replace bin = `m' if _n >= (`total'*(`m'-1)/20) & _n <= (`total'*(`m')/20)
		} 			
		
		
	** Fit model 
	** some options for regression "hiv m_educ i_nonvr s_comp"
		local betas = "hiv m_educ s_comp"
		local betacoeffs = "hivcoeff m_educcoeff s_compcoeff"
		xtmixed log_prob_`age'_`sex' `betas' || _all: R.bin || gbdregion: || ihme_loc_id: 
	
	** Extract random effects 
		predict re_bin, reffects level(_all)
		predict re_bin_se, reses level(_all)
		predict regbd, reffects level(gbdregion)
		predict regbd_se, reses level(gbdregion) 
		predict reiso, reffects level(ihme_loc_id)
		predict reiso_se, reses level(ihme_loc_id)
		
		preserve
		predict res, r
		drop re_* reg* rei* bin
		rename res res_`age'_`sex'
		if (`count' > 1) merge 1:1 ihme_loc_id year log_q_u5_both using `residuals'
		if (`count' > 1) keep if _merge == 3
		if (`count' > 1) drop _merge
		save `residuals', replace
		restore

		
	** Deal with bin RE's 
		** Smooth bins RE in R
			preserve
			keep log_q_u5_`sex' bin re_bin re_bin_se
			gen varname = "log_q_u5_`sex'"
			gen model = "age_model_`age'_`sex'" 
			saveold "data/fit_models/bin_res_for_smoothing.dta", replace	
			saveold "data/fit_models/age_model_`age'_`sex'_parameters_bins_before_smoothing.dta", replace	
			if ($archive==1) saveold "data/fit_models/archive/`date'/age_model_`age'_`sex'_parameters_bins_before_smoothing.dta", replace
			!"$R_path" < "`code_dir'/smooth_bin_re.r" --no-save
		
		** Simulate for bins RE
			use "data/fit_models/bin_res_smoothed.dta", clear
			expand 1000 
			rename log_q_u5_`sex' log_q_u5
			bysort log_q_u5: gen simulation = _n -1
			set seed 826
			gen rebin = rnormal(re_bin_pred, re_bin_pred_se)
			drop re_bin_*
			rename log_q_u5 merge_log_q_u5
			tostring merge_log_q_u5, replace force format(%9.2f)
			
		** Store simulations
			rename rebin rebin_`age'_`sex'
			if (`count' > 1) merge 1:1 merge_log_q_u5 simulation using `saveall_bins'
			capture drop _m 
			save `saveall_bins', replace 
			
		** Store parameters without simulations
			use "data/fit_models/bin_res_smoothed.dta", clear
			rename log_q_u5_`sex' merge_log_q_u5
			tostring merge_log_q_u5, replace force format(%9.2f)
			rename re_bin_pred rebin_`age'_`sex'
			drop re_bin_pred_se
			if (`count' > 1) merge 1:1 merge_log_q_u5 using `saveall_bins2'
			capture drop _m 
			save `saveall_bins2', replace 		
			
			restore
			drop re_bin* log* bin year
			
			rm "data/fit_models/bin_res_for_smoothing.dta"
			rm "data/fit_models/bin_res_smoothed.dta"

	** Deal with ihme_loc_id and gbd RE & error term 
		** Fill in missing countries for ihme_loc_id and gbd RE 
			append using `countrycodes'
			replace type = "hold" if type == "" 

			estat recovariance, level(ihme_loc_id)
				matrix temp = r(cov)
				gen reiso_var = temp[1,1]
			estat recovariance, level(gbdregion)
				matrix temp = r(cov)
				gen regbd_var = temp[1,1]			
			
			preserve 
			keep if type == "data" & reiso != .  
			keep reiso* ihme_loc_id 
			duplicates drop 
			tempfile reiso
			save `reiso', replace 
			restore, preserve
			keep if type == "data" & regbd != . 
			keep regbd* gbdregion
			duplicates drop
			tempfile regbd
			save `regbd', replace
			restore
			merge m:1 ihme_loc_id using `reiso', update
			drop _m 
			merge m:1 gbdregion using `regbd', update
			drop _m 

			foreach level in iso gbd { 
				replace re`level' = 0 if re`level' == . 
				replace re`level'_se = sqrt(re`level'_var) if re`level'_se == . 
				drop re`level'_var
			} 
			keep if type == "hold"
			drop type gbdregion

		** Extract sd of error term 
			matrix b = e(b) 
			local error = _b[lnsig_e:_cons]
			gen error_sd = exp(`error')
			
		** Sampling for ihme_loc_id RE and error term 
			set seed 826
			expand 1000 
			bysort ihme_loc_id: gen simulation = _n - 1
			gen reiso_ = rnormal(reiso, reiso_se)
			gen regbd_ = rnormal(regbd, regbd_se)
			gen error = rnormal(0,error_sd)
			rename reiso reiso_nosim
			rename regbd regbd_nosim
			drop reiso_se regbd_se error_sd
			rename reiso_ reiso	
			rename regbd_ regbd 

	** Deal with fixed effects 		
		** Extract fixed effects estimates and variance-covariance matrices 
			gen intercept_nosim = _b[_cons]
			gen intercept_se = _se[_cons]
		** Extract fixed effect beta and se
			foreach var of varlist `betas' {
				gen `var'coeff_nosim = _b[`var']
				gen `var'coeff_se = _se[`var']
			}
			
		** get matrix of means and var/covar matrix to draw from for sims	
			matrix m = e(b)' // The apostrophe stores the beta matrix as columns instead of rows
			matrix list m
			matrix m = m[1..(rowsof(m)-4), 1]
			matrix C = e(V)
			matrix C = C[1..(rowsof(C)-4), 1..(colsof(C)-4)] 
			
			preserve
			drawnorm `betacoeffs' intercept, means(m) cov(C) n(1000) clear
			gen simulation = _n - 1
			tempfile draws
			save `draws', replace
			restore
			merge m:1 simulation using `draws', assert(3) nogen
			drop `betas'
			
	** Store simulations 
		foreach var in reiso regbd error intercept `betacoeffs' *nosim { 
			rename `var' `var'_`age'_`sex'
		}
		if (`count' > 1) merge 1:1 ihme_loc_id simulation using `saveall_other'
		capture drop _m 
		save `saveall_other', replace 
		keep ihme_loc_id *nosim*
		foreach var in regbd reiso intercept `betacoeffs' { 
			rename `var'_nosim* `var'*
		} 
		duplicates drop		
		if (`count' > 1) merge 1:1 ihme_loc_id using `saveall_other2'
		capture drop _m 
		save `saveall_other2', replace 
		
	} 
	} 
	
** Save model parameters 
	use `residuals', clear
	saveold "data/fit_models/age_model_residuals.dta", replace

	use `saveall_other', clear
	saveold "data/fit_models/age_model_simulated_parameters_other.dta", replace 	
	if ($archive==1) saveold "data/fit_models/archive/`date'/age_model_simulated_parameters_other.dta", replace
	use `saveall_other2', clear
	saveold "data/fit_models/age_model_parameters_other.dta", replace 	
	if ($archive==1) saveold "data/fit_models/archive/`date'/age_model_parameters_other.dta", replace 
	
	use `saveall_bins', clear
    saveold "data/fit_models/age_model_simulated_parameters_bins.dta", replace 	
	if ($archive==1) saveold "data/fit_models/archive/`date'/age_model_simulated_parameters_bins.dta", replace
	use `saveall_bins2', clear
	saveold "data/fit_models/age_model_parameters_bins.dta", replace 
	if ($archive==1) saveold "data/fit_models/archive/`date'/age_model_parameters_bins.dta", replace

	exit, clear
	
	log close
