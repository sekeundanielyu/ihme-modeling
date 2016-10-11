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
  local tmp_dir `1'
  local var `2'
  local iso `3'
  local sex `4'
  local year `5'


//With parallelization of get_draws()
        
        display in red "`var' `iso'"
        
		get_draws, gbd_id_field(modelable_entity_id) gbd_id(`var') measure_ids(5) location_ids(`iso') year_ids(`year') sex_ids(`sex') source(epi) status(best) clear		
        quietly drop if age_group_id > 21
		quietly keep age_group_id draw*
      
	  quietly outsheet using "`tmp_dir'/`var'_prev/5_`iso'_`year'_`sex'.csv", comma replace
