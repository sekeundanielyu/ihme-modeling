

* BOILERPLATE *
  set more off
  clear all
  
  if c(os) == "Unix" {
    local j "/home/j"
    set odbcmgr unixodbc
    }
  else if c(os) == "Windows" {
    local j "J:"
    }
	

  tempfile hepA covariates pop locations

  
  
/******************************************************************************\	  
                         BRING IN CASE FATALITY 
\******************************************************************************/  
  
  use  `j'/WORK/04_epi/02_models/01_code/06_custom/hepatitis/inputs/hepA_caseFatality.dta, clear

  metaprop deaths cases,  nograph random
  
  local mu = `r(ES)'
  local sigma = `r(seES)'
  local cfAlpha = `mu' * (`mu' - `mu'^2 - `sigma'^2) / `sigma'^2 
  local cfBeta = `cfAlpha' * (1 - `mu') / `mu' 
  
 
  
/******************************************************************************\	  
                         BRING IN SEROPREVALENCE DATA 
\******************************************************************************/

* FIND AND IMPORT MOST RECENT DATA FILE *	
  cd `j'/WORK/04_epi/01_database/02_data/hepatitis_a/1647/03_review/01_download
  local files: dir . files "me_1647_ts_*.xlsx"
  local files: list sort files
  
  import excel using `=word(`"`files'"', wordcount(`"`files'"'))', firstrow clear
  
  
* CLEAN UP DATA *
 
  expand 2 if nid==141754, gen(newTemp)
  foreach var of varlist sample_size effective_sample_size cases {
   replace `var' = `var'/2 if nid==141754
   }
  foreach var of varlist lower upper standard_error {
   replace `var' = . if nid==141754
   }
  replace location_id = 43887 if nid==141754 & newTemp==0
  replace location_id = 43923 if nid==141754 & newTemp==1
  drop newTemp
  
  replace location_id = 98 if nid==236431
  replace location_name = ""  if nid==141754 | nid==236431
  
  assert measure=="prevalence"
  
* CREATE AGE MID-POINT FOR MODELLING *  
  replace age_end = age_end + age_demographer if !missing(age_demographer)
  egen ageMid = rowmean(age_start age_end)
  
* CREATE YEAR MID-POINT FOR MODELLING * 
  gen year_id = floor((year_start + year_end) / 2)
  
* CREATE SEX_ID *
  generate sex_id = (sex=="Male")*1 + (sex=="Female")*2 + (sex=="Both")*3  
  

* ENSURE THAT WE HAVE SAMPLE SIZE AND CASE NUMBERS FOR ALL ROWS *    
  replace cases = mean * effective_sample_size if missing(cases) & missing(sample_size)
  
  generate meanTestSS = abs(mean - cases/sample_size)
  generate meanTestESS = abs(mean - cases/effective_sample_size)

  generate alpha = mean * (mean - mean^2 - standard_error^2) / standard_error^2
  generate beta  = alpha * (1 - mean) / mean
  
  generate exp = effective_sample_size if missing(sample_size) | sample_size==effective_sample_size | (meanTestESS < meanTestSS & !missing(meanTestSS))
  replace  exp = sample_size if missing(exp) & (meanTestESS > meanTestSS & !missing(meanTestESS))
  replace  exp = alpha + beta if missing(exp)
  replace  exp = min(sample_size, effective_sample_size) if missing(exp)
  
  generate index=_n
  levelsof index if exp<=0, local(indicies) clean
  foreach index of local indicies {
    local stop 0
    local count 1
    while `stop'==0 {
      quietly cii `count' `=`count' * `=mean[`index']'', wilson
	  if (`r(lb)' >= `=lower[`index']' & `=mean[`index']' >= 0.5) | (`r(ub)' <= `=upper[`index']' & `=mean[`index']' < 0.5) {
	    local ++stop
		replace cases = `count' * `=mean[`index']' in `index'
		replace exp = `count' in `index'
		}		
	  local ++count
	  }
    }

  generate out = cases
  replace  out = exp * mean if missing(out)

  generate expRound = round(exp)
  generate outRound = round(out)
  
  keep location_id ageMid year_id sex_id mean lower upper standard_error effective_sample_size cases sample_size cv_* exp out expRound outRound is_outlier
  
  local nDataRows = _N
  di _N
  
  save `hepA'
 	
  gen before1980 = "(location_id==" + string(location_id) + " & year_id==" + string(year_id) + ")"
  levelsof before1980 if year_id<1980, clean sep( | ) local(keepBefore80)
  levelsof location_id if year<1980, clean sep ( | location_id==) local(toModelPre80)	
  
/******************************************************************************\	
                           PULL IN COVARIATE DATA
\******************************************************************************/

local covIds   2210, 1151, 1205 
local name2210 ldi 
local name1151 sanitation 
local name1205 water
	
odbc load, exec("SELECT model_version_id, year_id, location_id, mean_value AS cov_ FROM model WHERE model_version_id IN (`covIds') AND age_group_id = 22 AND sex_id = 3") dsn(covariates) clear

reshape wide cov_, i(location_id year_id) j(model_version_id) 

foreach var of varlist cov_* {
  label variable `var' ""
  rename `var' `name`=subinstr("`var'", "cov_", "", .)''
  }	
  
  
* EXTRAOLPATE WATER AND SANIATAION VARIABLES OUT PRE-1980 TO MATCH PRE-1980 DATA POINTS *  
  foreach cov in water sanitation {

    bysort location_id (year_id): gen pctChange_`cov' = (`cov'[_n] - `cov'[_n-1]) / `cov'[_n-1]
    bysort location_id: egen `cov'Mean = mean(`cov')

    mixed pctChange_`cov' ldi `cov'Mean if location_id==`toModelPre80' || location_id: ldi `cov'Mean
    predict prChange_`cov'

    gsort location_id -year_id
    by location_id: replace `cov' =  `cov'[_n-1] - `cov'[_n-1] * prChange_`cov'[_n] if year<1980 & (location_id==`toModelPre80')
    }

* CREATE MODELLING COVARIATE USING PCA *
  gen lnLdi = ln(ldi)
  gen lnNoWater = ln(1 - water)
  pca lnNoWater lnLdi
  predict lnWL	
	
* CLEAN UP *	
  drop *Change* *Mean	
  keep if year>=1980 | `keepBefore80'
  
  save `covariates'  
  
  
  
  
/******************************************************************************\	
 CREATE A SKELETON DATASET CONTAINING EVERY COMBINATION OF ISO, AGE, SEX & YEAR
\******************************************************************************/ 
tempfile pop
* PULL AGE GROUP METADATA *
  odbc load, exec("SELECT age_group_id, age_group_years_start AS age_start, age_group_years_end AS age_end FROM age_group WHERE age_group_id >1 AND age_group_id < 22") dsn(shared) clear
  save `pop'

  
* PULL POPULATION DATA *
  odbc load, exec("SELECT output_version_id FROM output_version WHERE is_best=1") dsn(mort2015) clear
  local ovi = output_version_id in 1

  odbc load, exec("SELECT year_id, age_group_id, sex_id, location_id, mean_pop FROM output WHERE output_version_id = `ovi' AND year_id > 1979 AND age_group_id >1 AND age_group_id < 22 AND sex_id < 3") dsn(mort2015) clear

  merge m:1 age_group_id using `pop', assert(3) nogenerate
  save `pop', replace

  
* PULL LOCATION METADATA *  
  get_location_metadata, location_set_id(8) clear
  
  split path_to_top_parent, gen(path) parse(,) destring
  rename path4 country_id
  rename ihme_loc_id iso3
  
  keep location_id location_name parent_id location_type iso3 *region* country_id iso3

  merge 1:m location_id using `pop', nogenerate

  
* PULL LIST OF LOCATION_IDs TO MODEL *  
  get_demographics, gbd_team(cod) 
  generate toModel = 0
  foreach l in $location_ids {
    quietly replace toModel = 1 if location_id==`l'
    }

  keep if toModel==1 | location_type=="admin0"
  
  
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
  order location* iso3 country_id countryIso parent_id *region* year sex age_group_id age_start age_end ageMid mean_pop income toModel
  save `pop', replace
  
  keep location* iso3 country_id countryIso parent_id *region* income
  duplicates drop

  save `locations'
  
  
  
/******************************************************************************\	
         COMBINE HEP A, LOCATION, SKELETON, AND COVARIATE DATASETS
\******************************************************************************/
  
  use `hepA', clear
  
  merge m:1 location_id using `locations', //assert(2 3) keep(3) nogenerate

  append using `pop'
  
  merge m:1 location_id year_id using `covariates', keep(3) nogenerate
  
    macro dir
	
  count if !missing(out, exp)
  *assert `r(N)'==`nDataRows'
  
  generate cfAlpha = `cfAlpha'
  generate cfBeta  = `cfBeta'
  
  save `j'/WORK/04_epi/02_models/01_code/06_custom/hepatitis/inputs/hepA_modellingData.dta, replace
  
  
  
  
  

