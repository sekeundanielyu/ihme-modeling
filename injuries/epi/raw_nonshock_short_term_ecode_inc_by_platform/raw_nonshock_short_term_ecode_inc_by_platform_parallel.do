** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************

** Description:	This code is submitted by the raw_short_term_ecode_inc_by_platform.do file to grab dismod short-term incidence results for e-codes, as well as the study-level covariate for transforming into outpatient results

** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** LOAD SETTINGS FROM STEP CODE (NO NEED TO EDIT THIS SECTION)

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

	if "`1'" == "" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "02a"
		local 5 raw_nonshock_short_term_ecode_inc_by_platform

		local 6 "/share/code/injuries/ngraetz/inj/gbd2015"
		local 7 89
		local 8 2000
		local 9 1
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
    // location id
    local location_id `7'
    // year id
    local year_id `8'
    // sex id 
    local sex_id `9'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"

** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** SETTINGS
	// Set covariate we are using to adjust final estimates (inpatient) to inpatient+outpatient
	local covariate "beta_incidence_x_s_medcare"

	set type double, perm
** how many slots were used to run this script
	local slots 1
	** are we using higashi's hsa scalers to bump up the all medcare estimates? As of 3/24/14 - No. This is being performed on the data pre-dismod.
	local use_hsa_adjust = 0
	local metric incidence
	** as of 3/10/2014 there are two possible models for the HSA covariate that higashi hasn't decided which to use to calculate the "inflation factor" so we leave this as an option
	local hsa_mod 208
	
** Filepaths
	local gbd_ado "$prefix/WORK/10_gbd/00_library/functions"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local summ_dir "`tmp_dir'/03_outputs/02_summary"
	local draw_dir "`tmp_dir'/03_outputs/01_draws"
	
** Import GBD functions
	adopath + "`gbd_ado'"
	adopath + "`code_dir'/ado"
	
** Load injury parameters
	load_params
	get_demographics , gbd_team(epi)

** Pull the list of e-codes that are modeled by DisMod that we are going to transform
	insheet using "`code_dir'/master_injury_me_ids.csv", comma names clear
		keep if injury_metric == "Adjusted data"
		drop if e_code == "inj_war" | e_code == "inj_disaster"
		// drop if modelable_entity_id == 2586 | modelable_entity_id == 2595
		levelsof modelable_entity_id, l(me_ids)
		keep modelable_entity_id e_code
		tempfile mes 
		save `mes', replace
		
	if `use_hsa_adjust'==1 {
		** pull the relationships between the available e-code scaling-up factors and which dismod models they should be used to scale-up
		insheet using "`in_dir'/parameters/adjustment_factor_relationships.csv", comma names clear
		levelsof dismod_model
		di "`e_codes'"
		tempfile adjustment
		save `adjustment', replace
	}
	
	tempfile appended
	tempfile ecode
	foreach me_id of local me_ids {
		// Pull acause associated with this ME id
		use `mes', clear
			keep if modelable_entity_id == `me_id'
			local e_code = e_code 
		
		if `use_hsa_adjust'==1 {
			
			** get the corresponding e-code from which to get Higashi's scaling-up factor
			use if dismod_model=="`e_code'" using `adjustment', clear
			local use_adjust = use_adjustment in 1
		
			use if iso3=="`iso3'" & year==`year_id' using "`in_dir'/parameters/medcare_carenocare_inflate/factor_warrantcare_draw_`use_adjust'_`hsa_mod'.dta", clear
			rename draw_* hsa_draw_*
			tempfile scalers
			save `scalers', replace
			
		}


		// Get measure_id for incidence 
		get_ids, table(measure) clear
			preserve 
				keep if measure_name == "Incidence"
				local inc_id = measure_id 
			restore
			preserve
				keep if measure_name == "Remission"
				local remission_id = measure_id
			restore
			preserve
				keep if measure_name == "Excess mortality rate"
				local emr_id = measure_id
			restore			

		di "Pulling draws... me_id:`me_id', year_id:`year_id', sex_id:`sex_id', location_id:`location_id'"
		// For two models that keep failing in Dismod, use pedestrian road injuries results as placeholders
		get_draws, gbd_id_field(modelable_entity_id) gbd_id(`me_id') location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') age_group_ids($age_group_ids) status(latest) source(dismod) clear
		keep if measure_id == `inc_id' | measure_id == `remission_id' | measure_id == `emr_id'
		tostring measure_id, replace
		replace measure_id = "inc" if measure_id == "`inc_id'"
		replace measure_id = "remission" if measure_id == "`remission_id'"
		replace measure_id = "emr" if measure_id == "`emr_id'"
		reshape wide draw_*, i(location_id year_id age_group_id sex_id modelable_entity_id model_version_id) j(measure_id, string)
		gen inpatient = 1

		** EDIT 8/11/14 ng - There is a systematic issue with pulling hazards from Dismod and treating them like population incidence rate in ages below 1.  Need to scale these down to account for the tiny population sizes in these 0.01, 0.1, 0 age groups resulting in huge "incidences".
		forvalues i = 0/999 {
			replace draw_`i'inc = (exp(draw_`i'inc * (1/52)) - 1) * 52 if age == 0
			replace draw_`i'inc = (exp(draw_`i'inc * (3/52)) - 1) * (52/3) if age == .01
			replace draw_`i'inc = (exp(draw_`i'inc * (48/52)) - 1) * (52/48) if age == .1
		}
		
		** EDIT 5/25/16 ng - Need to correct incidence results for mortality. We only don't want all incidence of injuries to estimate nonfatal burden, we just want incidence of nonfatal injuries. Subtract incidence that results in mortality. nonfatal_inc = inc * exp(-EMR/remission)
		forvalues i = 0/999 {
			gen draw_`i' = draw_`i'inc * exp( -( draw_`i'emr / draw_`i'remission ) )
		}
		// Save diagnostics ratios 
		preserve 
			forvalues i = 0/999 {
				gen inc_ratio_`i' = draw_`i' / draw_`i'inc 
			}
			egen mean_inc_ratio = rowmean(inc_ratio_*)
			keep location_id year_id age_group_id sex_id modelable_entity_id mean_inc_ratio
			cap mkdir "/share/injuries/03_steps/2016_02_08/02a_raw_nonshock_short_term_ecode_inc_by_platform/03_outputs/03_other/diagnostics/`me_id'"
			save "/share/injuries/03_steps/2016_02_08/02a_raw_nonshock_short_term_ecode_inc_by_platform/03_outputs/03_other/diagnostics/`me_id'/ratios_`location_id'_`year_id'_`sex_id'.dta", replace
		restore
		drop draw_*inc draw_*emr draw_*remission

		** save these as inpatient draws
		gen ecode = "`e_code'"
		save `ecode', replace
		
	** merge on and create outpatient draws
		rename draw* inp_draw*
		merge m:1 inpatient using "`out_dir'/01_inputs/`e_code'_covariates.dta", nogen

		** multiply inpatient incidence by the exponentiated medcare covariate to get all medical care incidence
		forvalues j=0/999 {
			generate otp_draw_`j'=inp_draw_`j' * medcare_`j'
			drop medcare_`j' inp_draw_`j'
		}
		
		** multiply the all medical care by Higashi's scaling-up factor to get all "warranting" medical care numbers
		capture drop iso3 year
		generate year = `year_id'
		generate iso3 = "`iso3'"
		
		if `use_hsa_adjust'==1 {
			merge m:1 year iso3 using `scalers', keep(3) nogen
			** multiply all medcare by the scalers from Higashi to get "all warranting care"
			forvalues j=0(1)999 {
				replace otp_draw_`j' = otp_draw_`j' * hsa_draw_`j'
				drop hsa_draw_`j'
			}
		}
		
		** now subtract off inpatient incidence to get just outpatient numbers
		merge 1:1 age inpatient using `ecode'
		forvalues j=0(1)999 {
			replace otp_draw_`j' = otp_draw_`j' - draw_`j'	
			drop draw_`j'
		}
		rename otp_draw* draw*
		replace inpatient=0
		
		append using `ecode'
		keep ecode inpatient age draw*
		
	** Append to other e-codes
		cap confirm file `appended'
		if !_rc append using `appended'
		save `appended', replace
	}
		
** Save draws
	format draw* %16.0g
	
	order ecode inpatient age draw*
	sort ecode inpatient age
	export delimited using "`draw_dir'/`metric'_`location_id'_`year_id'_`sex_id'.csv", replace
		
** Save summary files
	fastrowmean draw*, mean_var_name("mean")
	fastpctile draw*, pct(2.5 97.5) names(ll ul)
	drop draw*
	format mean ul ll %16.0g
	export delimited "`summ_dir'/`metric'_`location_id'_`year_id'_`sex_id'.csv", replace

** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************

