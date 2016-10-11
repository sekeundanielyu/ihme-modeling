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

// Set locals from arguments passed on to job
  local in_dir `1'
  local out_dir `2'
  local cause `3'
  local sequela `4'
  local i `5'
  local sex `6'
	
 
// Interpolate draws between 1990 and 2005 exponentially, and save for 1995 and 2000
  tempfile pre_format mergingTemp  
  
  
  // Load draw data for years between which will be interpolated for prevalence (measure id = 5)
    foreach year in 1990 2005 {
      quietly insheet using "`in_dir'/`cause'_`sequela'/5_`i'_`year'_`sex'.csv", clear double
      
      quietly reshape long draw_, i(age) j(num_draw)
      
      sort age_group_id draw_
      rename draw_ dr`year'
      generate mu`year' = .
      
      levelsof age_group_id, local(ages)
      
      foreach age in `ages' {
        capture quietly summarize dr`year' if age_group_id == `age'
        capture replace mu`year' = `r(mean)' if age_group_id == `age'
      }
      
      bysort age_group_id: replace num_draw = _n-1
	  
      capture merge 1:1 age_group_id num_draw using `mergingTemp', nogen
      save `mergingTemp', replace
    }
    
    summarize num_draw
    local draw_max = `r(max)'
    
    
  // Interpolate exponentially for years 1995 and 2000
    generate double rate_ann = (mu2005/mu1990)^(1/15)
    generate double dr1995 = dr1990 * rate_ann^5
    generate double dr2000 = dr1990 * rate_ann^10
      replace dr1995 = 0 if missing(dr1995)
      replace dr2000 = 0 if missing(dr2000)
    drop m* rate_ann
    quietly reshape wide dr*, i(age_group_id) j(num_draw)
    
    save `pre_format', replace
    
    
  // Export each year as a separate csv file.
    foreach year in 1995 2000 {
      use `pre_format', clear
    
      keep dr`year'* age_group_id
      rename dr`year'* draw_*
      
      format %16.0g age_group_id draw_*
      
      quietly outsheet using "`out_dir'/`cause'_`sequela'/5_`i'_`year'_`sex'.csv", replace comma
    }



	
	
	
	
	  