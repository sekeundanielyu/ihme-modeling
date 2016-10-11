  get_demographics, gbd_team(cod)
  local years = subinstr(itrim(ltrim("$year_ids")), " ", ",", .)
  local locations = subinstr(itrim(ltrim("$location_ids")), " ", ",", .)


* PULL POPULATION DATA *
  odbc load, exec("SELECT output_version_id FROM output_version WHERE is_best=1") dsn(mortality) clear
  local ovi = output_version_id in 1
  odbc load, exec("SELECT year_id, age_group_id, sex_id, location_id, mean_pop FROM output WHERE output_version_id = `ovi' AND year_id IN (`years') AND location_id IN (`locations') AND age_group_id < 22 AND sex_id < 3") dsn(mortality) clear
  tempfile pop
  save `pop'

  
  
* PULL LOCATION METADATA *  
  get_location_metadata, location_set_id(8) clear
  keep location_id is_estimate path_to_top_parent *region* //location_name location_type ihme_loc_id
  
  split path_to_top_parent, gen(path) parse(,) destring
  rename path4 country_id
  drop path*
 
  merge 1:m location_id using `pop', assert(1 3) keep(3) nogenerate
  save `pop', replace

* BRING IN INCOME DATA *  
  odbc load, exec("SELECT location_id AS country_id, location_metadata_value FROM location_metadata WHERE location_metadata_type_id = 12") dsn(shared) clear
  rename location_metadata_value income


  merge 1:m country_id using `pop', keep(2 3) nogenerate
  replace income = "Upper middle income" if location_id==8     
  
  generate incomeCat = 1 if strmatch(income, "High*")==1
  replace  incomeCat = 2 if strmatch(income, "Upper *")==1
  replace  incomeCat = 3 if strmatch(income, "Low*")==1
  
  keep if age==2 & year==2010 & sex_id==1
  keep location_id incomeCat *region*

  
  save "J:\WORK\04_epi\02_models\01_code\06_custom\intest\inputs\submit_split_data.dta", replace
  

