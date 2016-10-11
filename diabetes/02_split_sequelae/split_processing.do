// Set up environment with necessary settings and locals

// Boilerplate
	clear all
	set maxvar 10000
	set more off
  
	adopath + "strPath/functions"
	adopath + "strPath/functions/utils"		
  
// Pull in parameters from bash command
	local location "`1'"
	capture log close
	log using strPath/logs/log_`location', replace
	
// Set up output directories
	capture mkdirs, dirs(/strPath)
	capture mkdirs, dirs(/strPath)
	capture mkdirs, dirs(/strPath)
	capture mkdirs, dirs(/strPath)
	capture mkdirs, dirs(/strPath)
	capture mkdirs, dirs(/strPath)
	capture mkdirs, dirs(/strPath)
	
	local out_dir strPath/diabetes

// Make globals for use as necessary
	get_demographics, gbd_team(epi)
	local years = r(year_ids)
	local sexes = r(sex_ids)
  
// Load parent results
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(2005) measure_ids(5 6) location_ids(`location') age_group_ids($age_group_ids) status(best) source(dismod) clear
		// Save incidence from overall model to upload into uncomplicated (2006)
			preserve
			keep if measure_id==6
			foreach sex of local sexes {
				foreach year of local years {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "strPath/6_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore
	
	//Continue processing prevalence
	keep if measure_id==5
	forvalues j = 0(1)999 {
			rename draw_`j' parent_`j'
	}	
	compress
	tempfile parent_draws
	save `parent_draws', replace
	
// Load child models *investigate mata?*
	// Diabetic foot
		get_draws, gbd_id_field(modelable_entity_id) gbd_id(2007) measure_ids(18) location_ids(`location') age_group_ids($age_group_ids) status(best) source(dismod) clear
		forvalues j = 0(1)999 {
			rename draw_`j' foot_`j'
		}
		compress
		tempfile foot_draws
		save `foot_draws', replace
	
	// Diabetic neuropathy
		get_draws, gbd_id_field(modelable_entity_id) gbd_id(2008) measure_ids(18) location_ids(`location') age_group_ids($age_group_ids) status(best) source(dismod) clear
		forvalues j = 0(1)999 {
			rename draw_`j' neuro_`j'
		}
		compress
		tempfile neuro_draws
		save `neuro_draws', replace
		
	// Amputation
		get_draws, gbd_id_field(modelable_entity_id) gbd_id(2010) measure_ids(5) location_ids(`location') age_group_ids($age_group_ids) status(best) source(dismod) clear
		forvalues j = 0(1)999 {
			rename draw_`j' amp_`j'
		}
		compress
		tempfile amp_draws
		save `amp_draws', replace
	
	// Vision loss
		// _vision_low
		get_draws, gbd_id_field(modelable_entity_id) gbd_id(2790) measure_ids(5) location_ids(`location') age_group_ids($age_group_ids) status(latest) source(dismod) clear
		forvalues j = 0(1)999 {
			rename draw_`j' lowvision_`j'
		}
		compress
		tempfile visionlow_draws
		save `visionlow_draws', replace
		
		// blindness
		get_draws, gbd_id_field(modelable_entity_id) gbd_id(2016) measure_ids(5) location_ids(`location') age_group_ids($age_group_ids) status(latest) source(dismod) clear
		forvalues j = 0(1)999 {
			rename draw_`j' blind_`j'
		}
		compress
		tempfile blind_draws
		save `blind_draws', replace
		
	
// Merge the parent prevalence onto child proportions
	use `parent_draws', clear
	merge 1:1 age_group_id year_id sex_id using `foot_draws', keep(3) nogen
	merge 1:1 age_group_id year_id sex_id using `neuro_draws', keep(3) nogen
	merge 1:1 age_group_id year_id sex_id using `amp_draws', keep(3) nogen
	merge 1:1 age_group_id year_id sex_id using `visionlow_draws', keep(3) nogen
	merge 1:1 age_group_id year_id sex_id using `blind_draws', keep(3) nogen
		
// Multiply child proportions by parent prevalence
	forvalues j = 0(1)999 {
		quietly replace foot_`j' = foot_`j' * parent_`j'
		quietly replace neuro_`j' = neuro_`j' * parent_`j'
		quietly replace amp_`j' = amp_`j' * parent_`j'
	}
		
// Add low vision and blindness
	forvalues j = 0(1)999 { 	
		quietly gen visiondraw_`j' = lowvision_`j' + blind_`j'
	}
		drop lowvision_* blind_*	

	fastrowmean foot_*, mean_var_name(mean_foot_orig)
	fastrowmean neuro_*, mean_var_name(mean_neuro_orig)
	fastrowmean amp_*, mean_var_name(mean_amp_orig)
	
		
// Rescale results to ensure that (neuropathy + vision loss) < 0.9
	local changes 0
	forvalues i=0/999 {
		if (neuro_`i'+ visiondraw_`i') > (0.9*parent_`i') {
			local changes = `changes' + 1
		}
		qui replace neuro_`i' = neuro_`i'/(visiondraw_`i'+ neuro_`i')*(0.9*parent_`i') if (neuro_`i'+ visiondraw_`i') > (0.9*parent_`i')
		qui replace neuro_`i' = 0 if neuro_`i'==. | neuro_`i'<0
	}

	
// Rescale results to ensure that (amputation + foot ulcer) < 0.9*neuropathy
	local changes 0
	forvalues i=0/999 {
		if (amp_`i'+ foot_`i') > 0.9*neuro_`i' {
			local changes = `changes' + 1
		}
		qui replace amp_`i' = amp_`i'/(amp_`i' + foot_`i')*(0.9*neuro_`i') if (amp_`i' + foot_`i') > 0.9*neuro_`i'
		qui replace foot_`i' = foot_`i'/(amp_`i' + foot_`i')*(0.9*neuro_`i') if (amp_`i' + foot_`i') > 0.9*neuro_`i'
		qui replace amp_`i' = 0 if amp_`i'==. | amp_`i'<0
		qui replace foot_`i' = 0 if foot_`i'==. | foot_`i'<0
	}

	fastrowmean foot_*, mean_var_name(mean_foot_scaled)
	fastrowmean neuro_*, mean_var_name(mean_neuro_scaled)
	fastrowmean amp_*, mean_var_name(mean_amp_scaled)
	
	preserve
	keep age_group_id sex_id location_id year_id mean_neuro_orig mean_amp_orig mean_foot_orig mean_neuro_scaled mean_amp_scaled mean_foot_scaled
	gen pct_change_neuro = (mean_neuro_scaled - mean_neuro_orig)/mean_neuro_orig
	gen pct_change_amp = (mean_amp_scaled - mean_amp_orig)/mean_amp_orig
	gen pct_change_foot = (mean_foot_scaled - mean_foot_orig)/mean_foot_orig
	tempfile diagnostic
	save `diagnostic', replace
	outsheet using "`out_dir'/diagnostics/diabetes_split_squeeze_`location'.csv", comma replace
	restore
	
	drop mean_neuro* mean_amp* mean_foot*

// Calculate uncomplicated diabetes
	qui forvalues j = 0(1)999 {
		** generate the maximum possible complicated prevalence
		gen max_`j' = neuro_`j' + visiondraw_`j' //maximum possible complicated prevalence
		gen uncomplicated_`j' = parent_`j' - max_`j' //uncomplicated 
		replace uncomplicated_`j' = 0 if (uncomplicated_`j'<0 | uncomplicated_`j'==.)
	}

local me_ids "2006 3048 3049 3050"
local me_names "uncomplicated foot neuro amp" 
local n: word count `me_ids'

forvalues i =1/`n' {
	local a : word `i' of `me_ids'
	local b : word `i' of `me_names'
		preserve
		keep sex_id year_id age_group_id location_id `b'_*
		//gen modelable_entity_id = `a'
		//keep age_group_id `b'_*
		capture gen measure_id = 5
		forvalues j = 0(1)999 {
			rename `b'_`j' draw_`j'
		}
		foreach sex of local sexes {
			foreach year of local years {
				//keep if sex_id==`sex' & year_id==`year'
				outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`out_dir'/draws/me_`a'/5_`location'_`year'_`sex'.csv", comma replace
			}
		}
	restore
}

log close	
