

* BOILERPLATE *
  set more off
  clear all
  
  if c(os) == "Unix" {
    local j "FILEPATH"
    set odbcmgr unixodbc
    }
  else if c(os) == "Windows" {
    local j "FILEPATH"
    }
	

  tempfile trachoma covariates pop locations

  
  run "FILEPATH/fastcollapse.ado"
  run "FILEPATH/get_covariate_estimates.ado"
  run "FILEPATH/get_location_metadata.ado"
  
/******************************************************************************\	  
                         BRING IN PROPORTION DATA 
\******************************************************************************/

* FIND AND IMPORT MOST RECENT DATA FILE *	
  cd FILEPATH
  local files: dir . files "me_1500_ts_*.xlsx"
  local files: list sort files
  
  import excel using `=word(`"`files'"', wordcount(`"`files'"'))', firstrow clear
  save `trachoma'
  
  
  cd FILEPATH
  local files: dir . files "me_1503_ts_*.xlsx"
  local files: list sort files
  
  import excel using `=word(`"`files'"', wordcount(`"`files'"'))', firstrow clear
  append using `trachoma'
  save `trachoma', replace
  
  
  
* CLEAN UP DATA *
  drop if is_outlier
  assert measure=="proportion"
  foreach var of varlist *issue age_demographer{
    capture destring `var', replace force
	if "`var'" != "age_demographer" assert `var'==0
	}
  
  generate outcome = proper(reverse(word(reverse(subinstr(lower(trim(modelable_entity_name)), " due to trachoma unsqueezed", "", .)), 1)))
  
  replace age_end = age_end - age_demographer
  rename note_modeler note
  rename sample_size sample
  
 
  fastcollapse cases sample, by(outcome nid location_* ihme_loc_id sex *_start *_end note cv_*) type(sum)
  
  compress
  
  reshape wide cases sample note cv*, i(nid location_* ihme_loc_id sex *_start *_end) j(outcome) string
  
  foreach stub in cv_blood_donor cv_ref note{
    rename `stub'Blindness `stub'
	replace `stub' = `stub'Impairment if missing(`stub')
	drop `stub'Impairment
	}
	

  
* CREATE AGE MID-POINT FOR MODELLING *  
  egen ageMid = rowmean(age_start age_end)
  
* CREATE YEAR MID-POINT FOR MODELLING * 
  gen year_id = floor((year_start + year_end) / 2)
  replace year_id = 1980 if year_id<1979
  
* CREATE SEX_ID *
  generate sex_id = (sex=="Male")*1 + (sex=="Female")*2 + (sex=="Both")*3  
  
  order nid location_name location_id ihme_loc_id sex_id sex year_id year_start year_end age_start age_end ageMid casesBlindness sampleBlindness casesImpairment sampleImpairment cv_blood_donor cv_ref note
  
  save `trachoma', replace
 	

  
/******************************************************************************\	
                           PULL IN COVARIATE DATA
\******************************************************************************/

local covIds   57 142 160 207 
local name57 ldi 
local name142 sanitation 
local name160 water
local name207 trachomaPar

	
tempfile covarTemp
local count 1

foreach covId of local covIds {
	get_covariate_estimates, covariate_id(`covId') clear
	assert inlist(age_group_id, 22, 27) & sex_id==3
	keep if inrange(year_id, 1980, 2016)
	keep location_id year_id mean_value
	rename mean_value `name`covId''

	if `count'>1 merge 1:1 location_id year_id using `covarTemp', nogenerate
	save `covarTemp', replace
	local ++count
	}	
  
  
merge 1:1 location_id year_id using FILEPATH\prAtRiskTrachomaModelled.dta, keep(3) nogenerate
 
save `covariates' 

get_location_metadata, location_set_id(8) clear
keep location_id location_name location_type ihme_loc_id parent_id *region* is_estimate

merge 1:m location_id using `covariates', nogenerate
keep if is_estimate==1 | location_type=="admin0"

	
order year_id location_id location_name ihme_loc_id iso3 parent_id is_estimate location_type super_region_id super_region_name region_id region_name sanitation water ldi prAtRiskTrachoma trachomaPar
  
save `covariates'  , replace	
  
  
  
  
/******************************************************************************\	
 CREATE A SKELETON DATASET CONTAINING EVERY COMBINATION OF ISO, AGE, SEX & YEAR
\******************************************************************************/ 
tempfile pop

  get_demographics, gbd_team(epi) clear
  local ages `r(age_group_ids)'
  local years `r(year_ids)'
 
  
* PULL AGE GROUP METADATA *
  odbc load, exec("SELECT age_group_id, age_group_years_start AS age_start, age_group_years_end AS age_end FROM age_group WHERE age_group_id IN (`=subinstr("`ages'", " ", ",", .)')") dsn(shared) clear
  save `pop'
 
  
* PULL LOCATION METADATA *  
  get_location_metadata, location_set_id(8) clear
  keep if is_estimate==1 | location_type=="admin0"
  
  split path_to_top_parent, gen(path) parse(,) destring
  rename path4 country_id
  generate iso3 = ihme_loc_id
  
  keep location_id location_name parent_id location_type iso3 *region* country_id iso3 is_estimate
  save `locations'
  
  levelsof location_id, local(location_ids) clean
  
  
* PULL POPULATION DATA *
  numlist "1980/2016"
  get_population, age_group_id(`ages') location_id(`location_ids') sex_id(1 2) year_id(`r(numlist)') clear
  merge m:1 age_group_id using `pop', assert(3) nogenerate
  merge m:1 location_id  using `locations', assert(3) nogenerate
  
  save `pop', replace
  
  

  
  
* GENERATE A COUPLE OF VARIABLES NEEDED FOR MERGING * 
  egen ageMid = rowmean(age_start age_end)
  generate countryIso = substr(iso3, 1, 3)
  save `pop', replace
  
  
* BRING IN INCOME DATA *    
  odbc load, exec("SELECT location_id AS country_id, location_metadata_value FROM location_metadata WHERE location_metadata_type_id = 12") dsn(shared) clear
  rename location_metadata_value income

  merge 1:m country_id using `pop', keep(2 3) nogenerate
  replace income = "Upper middle income" if location_id==8    


* CLEAN UP *  
  order location* iso3 country_id countryIso parent_id *region* year sex age_group_id age_start age_end ageMid population income 
  save `pop', replace
  
  keep location* iso3 country_id countryIso parent_id *region* income
  duplicates drop

  save `locations', replace
  
  
  
/******************************************************************************\	
         COMBINE TRACHOMA, LOCATION, SKELETON, AND COVARIATE DATASETS
\******************************************************************************/
  
  use `trachoma', clear
  
  merge m:1 location_id using `locations', keep(3) nogenerate

  append using `pop'
  
  drop ihme_loc_id
  
  merge m:1 location_id year_id using `covariates', gen(covarMerge) //assert(3) 
  
  save FILEPATH/modellingData.dta, replace
  

