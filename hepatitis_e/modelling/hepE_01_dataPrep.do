* BOILERPLATE *
  clear all
  set maxvar 10000
  set more off
  
  if c(os) == "Unix" {
    local j "/home/j"
    set odbcmgr unixodbc
    }
  else if c(os) == "Windows" {
    local j "J:"
    }
	
  
  adopath + `j'/WORK/10_gbd/00_library/functions
  
  tempfile pop
  
  
  
/******************************************************************************\	
 CREATE A SKELETON DATASET CONTAINING EVERY COMBINATION OF ISO, AGE, SEX & YEAR
\******************************************************************************/ 

* PULL AGE GROUP METADATA *
  odbc load, exec("SELECT age_group_id, age_group_years_start + (age_group_years_end - age_group_years_start)/2 AS ageMid FROM age_group WHERE age_group_id >1 AND age_group_id < 22") dsn(shared) clear
  save `pop'

  
* PULL POPULATION DATA *
  odbc load, exec("SELECT output_version_id FROM output_version WHERE is_best=1") dsn(mort2015) clear
  local ovi = output_version_id in 1

  odbc load, exec("SELECT year_id, age_group_id, sex_id, location_id, mean_pop FROM output WHERE output_version_id = `ovi' AND year_id > 1979 AND age_group_id < 22 AND sex_id < 3") dsn(mort2015) clear

  merge m:1 age_group_id using `pop', assert(3) nogenerate
  save `pop', replace
  
  get_location_metadata, location_set_id(8) clear
  keep location_id *region* location_type is_estimate
  
  merge 1:m location_id using `pop', keep(3) nogenerate
  save `pop', replace


  
   
/******************************************************************************\	
                          ESTIMATE CASE FATALITY
						  
        For males use CFR of non-pregnant people, for females calculate 
  country/age/year-specific CFRs as weighted averages of the pregant and non-
                              pregnant CFRs 
\******************************************************************************/  


import delimited using "`j'/WORK/04_epi/02_models/01_code/06_custom/hepatitis/inputs/reinhev.csv", clear


keep if pregnant < 3 & !missing(deaths) & jaundiced > 0  & deaths < jaundiced & year >= 1980

glm deaths pregnant, family(binomial jaundiced) robust eform

lincom _cons + pregnant * 1
  local nopregCf = r(estimate) 
  local nopregSe = r(se)

lincom _cons + pregnant * 2
  local pregCf = r(estimate) 
  local pregSe = r(se)




use "`j'/WORK/04_epi/02_models/01_code/06_custom/hepatitis/inputs/prPreg.dta", clear
keep location_id year_id age_group_id prPreg
expand 2, gen(sex_id)
replace sex_id = sex_id + 1

replace prPreg = 0 if age_group_id<7 | age_group_id>15 | sex==1 
replace prPreg = prPreg * 40 / 52


merge 1:1 location_id year_id age_group_id sex_id using `pop', keep(3) nogenerate

keep if is_estimate==1
drop is_estimate
	

	
*ESTIMATE BETA DISTRIUBTION PARAMETERS FOR PROPORTION SYMPTOMATIC *
  local mu    = 0.198
  local sigma = (0.229 - 0.167)/(2 * invnormal(0.975))
  local alpha = `mu' * (`mu' - `mu'^2 - `sigma'^2) / `sigma'^2 
  local beta  = `alpha' * (1 - `mu') / `mu' 	
	
	
* CREATE CASE FATALITY DRAWS *  
  forvalues i = 0/999 {
	local pregCfTemp = exp(rnormal(`pregCf', `pregSe'))
	local nopregCfTemp = exp(rnormal(`nopregCf', `nopregSe'))
	local symptomatic = rbeta(`alpha', `beta')
	
	quietly generate cfr_`i' = ((prPreg * `pregCfTemp') + ((1 - prPreg) * `nopregCfTemp')) * `symptomatic' 
	quietly replace  cfr_`i' = 0 if age_group_id < 3 | (!strmatch(region_name, "*Asia")==1 & !strmatch(region_name, "*Africa*")==1 & region_name!="Oceania")
	}

save "`j'/WORK/04_epi/02_models/01_code/06_custom/hepatitis/inputs/hepE_cfDraws.dta", replace
