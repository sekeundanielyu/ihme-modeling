// Incorporate Chagas results; scale 7 groups, split into 17 groups

// Prep Stata
	clear all
	set more off
	set maxvar 32767 
	
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	
	else if c(os) == "Windows" {
		global prefix "J:"
	}
// Add adopaths
	adopath + "strPath/functions"
	
// Locals for file paths
	local code_dir "strPath"
	local tmp_dir "strPath"
	local out_dir "strPath"
	local source_dir "strPath"

// Get inputs from bash commmand
	local location "`1'"
	
// write log if running in parallel and log is not already open
	cap log close
	log using "`out_dir'/logs/log_hfsplits_`location'.smcl", replace

// Get locations and demographic information; make macros
	get_location_metadata, location_set_id(9)
	get_demographics, gbd_team(epi)
	local year_ids 1990 1995 2000 2005 2010 2015
	local sex_ids 1 2 

// Get splits 
	insheet using "`source_dir'/heart_failure_target_props_subnat.csv", comma names clear
	drop std_err_adj
	preserve
		keep if age_group_id==28
		expand 2, gen(flag)
		replace age_group_id=3 if age_group_id==28 & flag==1
		drop flag
		expand 2 if age_group_id==28, gen(flag)
		replace age_group_id=2 if age_group_id==28 & flag==0
		replace age_group_id=4 if age_group_id==28 & flag==1
		drop flag
		tempfile babies
		save `babies', replace
	restore
	append using `babies'
	drop if age_group_id==28
	reshape wide hf_target_prop , i(location_id age_group_id sex_id) j(cause_id)
	tempfile weights
	save `weights', replace

// Get overall HF draws, 7 subcauses and generate proportions
// Overall
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(2412) source(dismod) measure_ids(5) location_ids(`location') status(best) clear
	drop measure_id model_version_id modelable_entity_id
	forvalues j = 0/999 {
		rename draw_`j' overall_`j'
	}
	tempfile overall
	save `overall', replace
	
// 7 subcauses

	// Import best Chagas envelope (prevalence); ensures that HF due to Chagas doesn't go above overall Chagas prevalence (concern from GBD2010)
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(2413) source(dismod) measure_ids(5) location_ids(`location') status(best) clear
	drop measure_id model_version_id modelable_entity_id
	forvalues j = 0/999 {
		rename draw_`j' chagas_`j'
	}
	tempfile chagas
	save `chagas', replace

	// Proportions
	// Ischemic heart disease
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(2414) source(dismod) measure_ids(18) location_ids(`location') status(best) clear
	drop measure_id model_version_id modelable_entity_id
	forvalues j = 0/999{
		rename draw_`j' ihd_`j'
	}
	reshape long ihd_, i(age_group_id sex_id year_id)
	tempfile ihd
	save `ihd', replace
	
	// Hypertensive heart disease
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(2415) source(dismod) measure_ids(18) location_ids(`location') status(best) clear
	drop measure_id model_version_id modelable_entity_id
	forvalues j = 0/999{
		rename draw_`j' htn_`j'
	}
	reshape long htn_, i(age_group_id sex_id year_id)
	tempfile htn
	save `htn', replace
	
	// Cardiopulmonary
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(2416) source(dismod) measure_ids(18) location_ids(`location') status(best) clear
	drop measure_id model_version_id modelable_entity_id
	forvalues j = 0/999{
		rename draw_`j' cpm_`j'
	}
	reshape long cpm_, i(age_group_id sex_id year_id)
	tempfile cpm
	save `cpm', replace
	
	// Valvular
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(2417) source(dismod) measure_ids(18) location_ids(`location') status(best) clear
	drop measure_id model_version_id modelable_entity_id
	forvalues j = 0/999{
		rename draw_`j' valvular_`j'
	}
	reshape long valvular_, i(age_group_id sex_id year_id)
	tempfile valvular
	save `valvular', replace
	
	// Cardiomyopathy
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(2418) source(dismod) measure_ids(18) location_ids(`location') status(best) clear
	drop measure_id model_version_id modelable_entity_id
	forvalues j = 0/999{
		rename draw_`j' cmp_`j'
	}
	reshape long cmp_, i(age_group_id sex_id year_id)
	tempfile cmp
	save `cmp', replace
	
	// Other
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(2419) source(dismod) measure_ids(18) location_ids(`location') status(best) clear
	drop measure_id model_version_id modelable_entity_id
	forvalues j = 0/999{
		rename draw_`j' other_`j'
	}
	reshape long other_, i(age_group_id sex_id year_id)
	tempfile other
	save `other', replace
	
	//Merge and rescale
	use `ihd', clear
	merge 1:1 age_group_id sex_id year_id _j using `htn', keep(3) nogen
	tempfile results
	save `results', replace
	merge 1:1 age_group_id sex_id year_id _j using `cpm', keep(3) nogen
	save `results', replace
	merge 1:1 age_group_id sex_id year_id _j using `valvular', keep(3) nogen
	save `results', replace
	merge 1:1 age_group_id sex_id year_id _j using `cmp', keep(3) nogen
	save `results', replace
	merge 1:1 age_group_id sex_id year_id _j using `other', keep(3) nogen
	save `results', replace
	
	use `results', clear 
	egen scale_factor = rowtotal(ihd_ htn_ cpm_ valvular_ cmp_ other_) 
	tempfile results_scaled
	save `results_scaled', replace

	use `results', clear
	merge 1:1 age_group_id year_id sex_id _j using `results_scaled', keepusing(scale_factor) keep(3) nogen
	
	local subtype "ihd htn cpm valvular cmp other"
	foreach type of local subtype {
		replace `type'_  = `type'_ / scale_factor // Adjusting for fractions above or below 1, making sure all adds up to 1
	}
	tempfile scaled
	save `scaled', replace
	
// Get envelope & subtract Chagas prevalence from overall envelope
	use `overall', clear
	merge 1:1 age_group_id sex_id year_id using `chagas', keep(3) nogen
	forvalues j=0/999 {
		generate nochagas_`j' = overall_`j' - chagas_`j'
		quietly replace nochagas_`j' = 0 if nochagas_`j'<0 | nochagas_`j'==.
	}
	drop overall_* chagas_*
	
	reshape long nochagas_, i(age_group_id sex_id year_id)

// Merge with scaled proportions	
	merge 1:1 age_group_id sex_id year_id _j using `scaled', keep(3) nogen
	tempfile results_merged
	save `results_merged', replace
	
// Split out 7 main groups
	//IHD
		use `results_merged', clear
		generate draw_ = nochagas_ * ihd_
		drop nochagas_* ihd_* htn_* cpm_* valvular_* cmp_* other_* scale_factor
		reshape wide draw_, i(age_group_id sex_id year_id) j(_j)
	
		foreach year of local year_ids {
			foreach sex of local sex_ids {
				outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/ihd/5_`location'_`year'_`sex'.csv", comma replace
			}
		}

	// Hypertensive heart disease
		use `results_merged', clear
		generate draw_ = nochagas_ * htn_
		drop nochagas_* ihd_* htn_* cpm_* valvular_* cmp_* other_* scale_factor
		reshape wide draw_, i(age_group_id sex_id year_id) j(_j)
		
		foreach year of local year_ids {
			foreach sex of local sex_ids {
				outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/htn/5_`location'_`year'_`sex'.csv", comma replace
			}
		}
	
	// Cardiopulmonary
		use `results_merged', clear
		generate draw_ = nochagas_ * cpm_ //Draws now 
		drop nochagas_* ihd_* htn_* cpm_* valvular_* cmp_* other_* scale_factor
		reshape wide draw_, i(age_group_id sex_id year_id) j(_j)
		merge m:1 age_group_id sex_id location_id using `weights', keep(3) nogen
		
		// COPD
			preserve
			forvalues j=0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop509/hf_target_prop520)  // proportion of cardiopulmonary due to copd
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids { 
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/copd/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore
		
		// Interstitial
			preserve
			forvalues j=0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop516/hf_target_prop520)
				quietly replace draw_`j' = 0 if draw_`j'==. | draw_`j'<0
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/interstitial/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore
		
		//Pneumoconiosis - silicosis
			preserve
			forvalues j=0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop511/hf_target_prop520)
				quietly replace draw_`j' = 0 if draw_`j'==. | draw_`j'<0
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/pneum_other/silicosis/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore
		
		//Pneumoconiosis - asbestosis
			preserve
			forvalues j=0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop512/hf_target_prop520)
				quietly replace draw_`j' = 0 if draw_`j'==. | draw_`j'<0
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/pneum_other/asbestosis/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore
		
		//Pneumoconiosis - coal workers
			preserve
			forvalues j=0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop513/hf_target_prop520)
				quietly replace draw_`j' = 0 if draw_`j'==. | draw_`j'<0
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/pneum_other/coalworker/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore
		
		//Pneumoconiosis - other
			preserve
			forvalues j=0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop514/hf_target_prop520)
				quietly replace draw_`j' = 0 if draw_`j'<0 | draw_`j'==.
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/pneum_other/other/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore
				
	// Valvular heart disease - all going to RHD
		use `results_merged', clear
		generate draw_ = nochagas_ * valvular_ //Draws now 
		drop nochagas_* ihd_* htn_* cpm_* valvular_* cmp_* other_* scale_factor
		reshape wide draw_, i(age_group_id sex_id year_id) j(_j)
		
		foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/rhd/5_`location'_`year'_`sex'.csv", comma replace
				}
			}		
				
	
	//Other #REPLACE 507 with new aggregate & subcause (new aggregate code is 385)
	use `results_merged', clear
	generate draw_ = nochagas_ * other_
	drop nochagas_* ihd_* htn_* cpm_* valvular_* cmp_* other_* scale_factor
	reshape wide draw_, i(age_group_id sex_id year_id) j(_j)
	merge m:1 age_group_id sex_id location_id using `weights', keep(3) nogen
	
		//Endocarditis
			preserve
			forvalues j = 0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop503/hf_target_prop385)
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/endo/5_`location_`year'_`sex'.csv", comma replace
				}
			}
			restore
		
		//Thalassemia
			preserve
			forvalues j = 0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop614/hf_target_prop385)
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/thalass/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore
		
		// Iron deficiency anemia
			preserve
			forvalues j = 0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop390/hf_target_prop385)
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/anemia/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore
			
		// Iodine deficiency
			preserve
			forvalues j = 0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop388/hf_target_prop385)
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/iodine/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore
		
		//G6PD deficiency
			preserve
			forvalues j = 0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop616/hf_target_prop385)
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/g6pd/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore

		// Oher endocrine, nutritional, blood, and immune disorders
			preserve
			forvalues j = 0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop619/hf_target_prop385)
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/other_combo/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore
		
		// Other anemias
			preserve
			forvalues j = 0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop618/hf_target_prop385)
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/other_anemia/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore
		
		// Congenital
			preserve
			forvalues j = 0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop643/hf_target_prop385)
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/congenital/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore
			
		// Other circulartory and cardiovascular
			preserve
			forvalues j = 0/999 {
				quietly replace draw_`j' = draw_`j' * (hf_target_prop507/hf_target_prop385)
			}
			foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/valvu/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
			restore
			
	
	// Cardiomyopathy
		use `results_merged', clear
		generate draw_ = nochagas_ * cmp_
		drop nochagas_* ihd_* htn_* cpm_* valvular_* cmp_* other_* scale_factor
		reshape wide draw_, i(age_group_id sex_id year_id) j(_j)

		preserve
		foreach year of local year_ids {
				foreach sex of local sex_ids {
					outsheet age_group_id draw_* if sex_id==`sex' & year_id==`year' using "`tmp_dir'/draws/cmp/5_`location'_`year'_`sex'.csv", comma replace
				}
			}
		restore

log close
