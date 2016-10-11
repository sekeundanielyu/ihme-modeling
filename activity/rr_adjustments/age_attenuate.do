/// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 			21 November 2014
// Project:		RISK
// Purpose:		Age attenuate relative risks for physical inactivity outcomes. Note: we only do this for cardiovascular outcomes, the other outcomes use the same relative risk for all ages. This code also saves 1,000 draws of the relative risk for each outcome for access by central PAF calculation.
** **************************************************************************
** RUNTIME CONFIGURATION
** **************************************************************************

// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		set mem 12g
		set maxvar 32000
	// Set to run all selected code without pausing
		set more off
	// Set graph output color scheme
		set scheme s1color
	// Remove previous restores
		cap restore, not
	// Reset timer (?)
		timer clear	
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}
	// Close previous logs
		cap log close	
	
// Set version number (increase by 1 for every change)
	local version 8
	global outcomes "ihd ischemic_stroke"
	
// Calculate age midpoints for each cardiovascular outcome
	foreach cause of global outcomes {
		di in red "`cause'"
		
		** First prep extraction sheet containing mean/median age at baseline and average years of follow up for merge with Bradmod RR estimations
		insheet using "$prefix/DATA/Incoming Data/WORK/05_risk/0_ongoing/physical_inactivity/new data/new articles/studies_included_excluded/`cause'_prepped_updated_with_study_names.csv", comma clear
		rename *, lower
		
		** Restrict dataset to points that were actually used in meta-analysis
		capture drop if exclude_study == 1
		drop if exclude == 1
		
		** Estimate age midpoint based on studies that were actually used in meta-analysis
		gen age_midpoint = baseline_mean_age
		replace age_midpoint = baseline_median_age if age_midpoint == . 
		replace age_midpoint = age_midpoint + (mean_yrs_follow_up/2) if mean_yrs_follow_up != .
		
		** Sometimes we don't have age_midpoint so we will "impute"
		gen age_avg = (age_start + age_end) / 2
		replace age_avg = (age_start + age_end) / 2 + (mean_yrs_follow_up/2) if mean_yrs_follow_up != . 
		gen x= age_midpoint / age_avg
		egen beta = mean(x)
		gen age_calc = age_avg * beta
		replace age_midpoint = age_calc if age_midpoint == .
		
		** Use confidence interval around relative risk to make a weight for inverse variance weighting the mean
		gen sd = (rr_upper - rr_lower)/ (2*1.96)
		gen weight = 1/sd
		
		** Fill in acause field with proper sequela name
		gen acause = ""
		replace acause = "cvd_ihd" if "`cause'" == "ihd"
		replace acause = "cvd_stroke_isch" if "`cause'" == "ischemic_stroke"
		
		** Calculate one weighted mean age for each outcome
		collapse (mean) age_midpoint [aweight = weight], by(acause) fast
		
		tempfile `cause'
		save ``cause'', replace
	}
	
// Append all outcomes
	clear
	foreach cause of global outcomes {
		append using ``cause''
	}
	
	tempfile agemidpoints
	save `agemidpoints', replace
	
// Pull relative risks calculated by Bradmod for each outcome
	local cause_ids "CC BC DB IS IHD"
	foreach id of local cause_ids {
		insheet using "$prefix/temp/dismod_ode/PA_`id'_Feb_2015/model_draw3.csv", comma clear
		keep in 4001/5000
		
		** Category 4 is the theoretical minimum risk so must divide by it so that cat4 relative risk is 1
		forvalues x = 1/4 {
			replace cat`x' = cat`x'/cat4
		}
		
		** Fill in acause field with proper sequela name
		gen acause = ""
		replace acause = "neo_colorectal" if "`id'" == "CC" 
		replace acause = "neo_breast" if "`id'" == "BC"
		replace acause = "cvd_ihd" if "`id'" == "IHD"
		replace acause = "cvd_stroke_isch" if "`id'" == "IS"
		replace acause = "diabetes" if "`id'" == "DB"
		
		tempfile `id'
		save ``id'', replace
	}
	
// Append all outcomes
	clear
	foreach id of local cause_ids {
		append using ``id''
	}
	
// Merge with age midpoints
	merge m:1 acause using `agemidpoints', nogen
	
// Log scale
	forvalues x = 1/4 {
		** Calculate beta multiplier
		gen beta_`x' = ln(cat`x') / (age_midpoint - 110)
		
		** Predict age-specific relative risk
		forvalues age = 25(5)85 {
			gen rr_cat`x'`age' =  cat`x' * exp(beta_`x' * ((`age'-110) - (age_midpoint-110))) //  + c_`x'
		}
	}
	
// Format dataset 
	keep acause	rr_cat* cat*
	bysort acause: gen draw = _n
	reshape long rr_cat1 rr_cat2 rr_cat3 rr_cat4, i(acause draw cat*) j(age)
	
	** Fill in relative risks for non-cardiovascular outcomes where RR is not age attenuated 
	forvalues x = 1/4 {
		replace rr_cat`x' = cat`x' if inlist(acause, "diabetes", "neo_colorectal", "neo_breast")
		drop cat`x'
	}
	reshape long rr_, i(acause age draw) j(parameter, string)
	reshape wide rr_, i(acause age parameter) j(draw)
	
	gen risk = "activity"
	rename age gbd_age_start
	gen gbd_age_end = gbd_age_start 
	gen sex = 3 
	gen mortality = 1 
	gen morbidity = 1
	gen year = 0
	
// Save draws on clustertmp for access by central PAF prep machinery
	local variables "risk acause gbd_age_start gbd_age_end sex mortality morbidity parameter year"
	keep `variables' rr_*
	order `variables'
	cap mkdir "/clustertmp/WORK/05_risk/02_models/02_results/activity/rr/`version'"
	outsheet using "/clustertmp/WORK/05_risk/02_models/02_results/activity/rr/`version'/rr_G.csv", comma replace
	
// Save mean RR and 95% CI on J drive
	egen rr_mean = rowmean(rr_*)
	egen rr_lower = rowpctile(rr_*), p(2.5)
	egen rr_upper = rowpctile(rr_*), p(97.5)
	keep `variables' rr_mean rr_lower rr_upper
	cap mkdir "$prefix/WORK/05_risk/02_models/02_results/activity/rr/`version'"
	outsheet using "$prefix/WORK/05_risk/02_models/02_results/activity/rr/`version'/rr_G.csv", comma replace
	
