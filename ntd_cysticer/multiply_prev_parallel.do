// Prep stata
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
	adopath + $prefix/WORK/10_gbd/00_library/functions

// Set locals from arguments passed on to job
  local in_dir `1'
  local out_dir `2'
  local iso `3'
  local sex `4'
  local year `5'
	


// Multiply NCC prevalence among all epileptics with epilepsy envelope, correcting for population not at risk
//with parallelization
  
    display in red "`iso' `year' `sex'"
    
    // Load and temporarily store the NCC prevalence among epileptics at risk
	  get_draws, gbd_id_field(modelable_entity_id) gbd_id(1479) location_ids(`iso') year_ids(`year') sex_ids(`sex') source(epi) status(best) clear
      
      //quietly drop if age > 80
	  quietly drop if age_group_id > 21
      
      format draw* %16.0g
      
      forvalues i = 0/999 {
        quietly rename draw_`i' ncc_prev_`i'
      }
      
      tempfile ncc_prev_`iso'_`sex'_`year'
      quietly save `ncc_prev_`iso'_`sex'_`year'', replace
    
    // Load epilepsy envelope
	  get_draws, gbd_id_field(modelable_entity_id) gbd_id(2403) measure_ids(5) location_ids(`iso') year_ids(`year') sex_ids(`sex') source(epi) status(best) clear
      
	  quietly drop if age_group_id > 21

      format draw* %16.0g
      
    // Merge in predicted NCC prevalence among epileptics at risk
      quietly merge m:1 age using `ncc_prev_`iso'_`sex'_`year'', keepusing(ncc_prev*) nogen
	  rename sex_id sex
	  rename year_id year      
      
    // Merge in proportion of population not at risk for NCC (proportion Muslim or with access to sanitation)
      quietly merge m:1 location_id year using "`in_dir'/not_at_risk.dta", keepusing(not_at_risk) keep(master match) nogen
      
      
    // Calculate prevalence of epilepsy due to NCC as: P * (NM-N) / (NM-1), where
    // P = prevalence of all-cause epilepsy in total population.
    // N = proportion of NCC among epileptics at risk (non-muslims without access to sanitation).
    // M = proportion of population not at risk of contracting NCC (i.e. muslims and people with access to sanitation).
    // Assumption: prevalence of epilepsy due to causes other than NCC is the same for population at risk and not at risk for NCC.
    // Assumption: muslims and non-muslims have equal access to sanitation.
      forvalues i = 0/999 {
        quietly replace draw_`i' = draw_`i' * (ncc_prev_`i' * not_at_risk - ncc_prev_`i') / (ncc_prev_`i' * not_at_risk - 1)
      }
	  
//replace missing draws with zeros for Greenland (349) and Guam (351)
	forvalues i = 0/999 {
        quietly replace draw_`i' = 0 if missing(draw_`i') & missing(not_at_risk)
      }
//replace negative draws with zeros for location_id 43880 year 2010
	forvalues i = 0/999 {
        quietly replace draw_`i' = 0 if draw_`i' < 0
      }
	  
    quietly keep draw_* age_group_id
    
    quietly outsheet using "`out_dir'/5_`iso'_`year'_`sex'.csv", comma replace
 
