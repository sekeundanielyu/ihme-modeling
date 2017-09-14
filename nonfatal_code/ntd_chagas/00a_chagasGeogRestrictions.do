
* BOILERPLATE *
  clear all
  set maxvar 12000
  set more off
   
  if c(os) == "Unix" {
    local j "FILEPATH"
    set odbcmgr unixodbc
    }
  else if c(os) == "Windows" {
    local j "FILEPATH"
    }
	
  
  adopath + FILEPATH
  run FILEPATH/get_location_metadata.ado	
  run FILEPATH/get_demographics.ado
  
  tempfile years
  

* GET YEAR LIST *
  get_demographics, gbd_team(cod) clear
  local maxYear = max(`=subinstr("`r(year_ids)'", " ", ",", .)')
  
  clear 
  set obs `=`maxYear'-1979'
  generate year_id = _n + 1979

  save `years'

  
* BUILD LIST OF ENDEMIC LOCATIONS * 
  get_location_metadata, location_set_id(8) clear
  
  generate endemic =(strmatch(lower(region_name), "*latin america*") | inlist(ihme_loc_id, "BLZ", "GUY", "SUR"))
  keep if is_estimate==1 & endemic==0
  keep location_id 

  cross using `years'
  generate cause_id = 346
  
  order cause_id location_id year_id
  sort location_id year_id 
  
  export delimited using FILEPATH/chagasGeographicRestrictions.csv, replace
