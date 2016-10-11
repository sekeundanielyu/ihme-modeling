
* BOILERPLATE *
  clear all
  set maxvar 10000
  set more off
  
  if c(os)=="Unix" {
	local j = "/home/j"
	set odbcmgr unixodbc
	}
  else {
	local j = "J:"
	}

  adopath + `j'/WORK/10_gbd/00_library/functions
	
	
* ESTABLISH LOCALS AND DIRECTORIES *	

  tempfile dengue covariates pop deaths income


* BRING IN DENGUE NOTIFICATION DATA *
  get_data, modelable_entity_id(1505) clear
  keep if strmatch(lower(source_type), "case notifications*")==1 
  
  
* CLEAN UP AGE-SPECIFIC DATA POINTS (MODEL IS BASED ON ALL-AGE, BOTH-SEX DATA) *  
  * Where we have an all-age, both-sex data point for a location/year, drop all age/sex specific points *
  bysort location_id year_start: egen anyComplete = max(age_start==0 & age_end>=99 & sex=="Both")
  drop if anyComplete==1 & (age_start!=0 | age_end<99 | sex!="Both")
  
  * Where we have all-age, sex-sepcific data points for a location/year, combine them to be both sex and drop all other points *
  bysort location_id year_start: egen anyCompleteMales = max(age_start==0 & age_end>=99 & sex=="Male")
  bysort location_id year_start: egen anyCompleteFemales = max(age_start==0 & age_end>=99 & sex=="Female")
  gen anyCompleteBySex = anyCompleteMales==1 & anyCompleteFemales==1
  bysort location_id year_start age_start age_end: egen totalCases = total(cases)
  bysort location_id year_start age_start age_end: egen totalSS = total(sample_size)
  replace cases = totalCases if anyCompleteBySex == 1
  replace sample_size = totalSS if anyCompleteBySex == 1
  drop if anyCompleteBySex==1 & (age_start!=0 | age_end<99 | sex=="Female")
  replace sex = "Both" if anyCompleteBySex==1
  replace mean = cases / sample_size if anyCompleteBySex==1
  foreach var of varlist lower upper standard_error effective_sample_size {
    replace `var' = .  if anyCompleteBySex==1
	}
	
  drop anyComplete* totalCases totalSS
	
  * Where we have both sex, age-sepcific data points for a location/year, combine them to be all age and drop all other points *
  bysort location_id year_start sex (age_start): gen ageGap = age_start - age_end[_n-1]
  replace ageGap = 0 if age_start<=1
  bysort location_id year_start: egen maxGap = max(ageGap>1)
  drop if maxGap == 1
  
  bysort location_id year_start: egen totalCases = total(cases)
  bysort location_id year_start: egen totalSS = total(sample_size)
  replace cases = totalCases if age_start>0 | age_end<99
  replace sample_size = totalSS if  age_start>0 | age_end<99
  replace sex = "Both" if age_start>0 | age_end<99
  replace mean = cases / sample_size if age_start>0 | age_end<99
  foreach var of varlist lower upper standard_error effective_sample_size {
    replace `var' = .  if age_start>0 | age_end<99
	}
  

  * Drop duplicates *
  bysort location_id year_start (mean): gen keep = _N==_n
  keep if keep==1
  
  * Clean up *
  rename year_start year_id
  keep location_id year_id mean lower upper cases *sample_size
  save `dengue'
 
 
 
 
 

* BRING IN AND MERGE COVARIATE DATA *
  foreach covar in dengue_prob dengueAnomalies {
    get_covariate_estimates, covariate_name_short("`covar'") clear
    rename mean_value `covar' 
	keep `covar' location_id year_id 
	if "`covar'"!="dengue_prob" merge 1:1 location_id year_id using `covariates', nogenerate
	save `covariates', replace
	}


	
	
	
	
	
* BRING IN MORTALITY & POPULATION ESTIMATES *
  tempfile pop

  
  odbc load, exec("SELECT output_version_id FROM output_version WHERE is_best = 1") dsn(mort2015) clear
  odbc load, exec("SELECT age_group_id, year_id, location_id, sex_id, mean_pop FROM output WHERE year_id>=1980 AND age_group_id = 22 AND sex_id = 3 AND output_version_id = `=output_version_id[1]'") dsn(mort2015) clear
  save `pop'

  levelsof year_id, local(years) clean
  get_outputs, topic(cause) location_id(all) year_id(`years') metric_id(1)  cause_id(357) clear
  keep location_id location_name year_id val 
  rename val deaths

  merge 1:1 year_id location_id using `pop', assert(1 3) keep(3) nogenerate
  
  replace deaths = 0 if missing(deaths)
  generate deathRate = deaths / mean_pop
  
  save `deaths'

  
  
  
* BRING IN INCOME DATA *  
  odbc load, exec("SELECT location_id AS country_id, location_metadata_type_id, location_metadata_value FROM location_metadata WHERE location_metadata_type_id IN (12, 13)") dsn(shared) clear
  reshape wide location_metadata_value, i(country_id) j( location_metadata_type_id)
  rename location_metadata_value12 income
  rename location_metadata_value13 income_short
  save `income'

  
* GET LOCATION METADATA *  
  get_location_metadata, location_set_id(8) clear
  rename ihme_loc_id iso3
  split path_to_top_parent, parse(,) gen(pathTemp) destring
  rename pathTemp4 country_id
  keep iso3 location_id location_name location_type country_id *region* is_estimate
  
  
* COMBINE DATASETS *
  merge 1:m location_id using `deaths'
  drop if is_estimate==0 & _merge==1
  drop _merge
  
  merge 1:1 year_id location_id using `covariates', keep(3) nogenerate
  merge 1:1 year_id location_id using `dengue', assert(1 3) nogenerate
  
  merge m:1 country_id using `income', keep(1 3) nogenerate
  replace income = "Upper middle income" if location_name=="Taiwan"     
  replace income_short = "UMC" if location_name=="Taiwan" 
  generate highIncome = strmatch(income, "High*")
  
  merge 1:1 iso3 year_id using `j'/WORK/04_epi/02_models/01_code/06_custom/dengue/data/empiricalExpansionFactors.dta, assert(1 3) nogenerate

  merge 1:1 location_id year_id using `j'/WORK/04_epi/02_models/01_code/06_custom/dengue/data/dengueTrendRR.dta, assert(2 3) keep(3) nogenerate
  
  merge m:1 year_id using `j'/WORK/04_epi/02_models/01_code/06_custom/dengue/data/efInflatorDraws.dta, assert(3) nogenerate	
	
	
* PREP DATA FOR MODELLING *

  
  rename dengue_prob denguePr
  replace denguePr = 0 if missing(denguePr) & region_id==73
    
  gen sqrtMR = sqrt(deathRate)
  bysort iso3: egen meanMR = mean(deathRate)
  bysort iso3: egen meanSqrtMR = mean(sqrtMR)
  quietly sum meanSqrtMR if meanSqrtMR >0
  gen normSqrtMR = (meanSqrtMR) / r(max)  
  gen lnNormSqrtMR = ln(normSqrtMR)

  
  pca denguePr normSqrtMR if denguePr>0
  predict score 

  gen yearC = year-1996.5
  generate yearWindow = round(year_id, 5)
  
  generate sampleM = sample_size
  replace  sampleM = 1 if missing(sample_size)
  
  generate casesM = cases
  replace  casesM = 0.0001 if cases==0 & denguePr>0
  replace  casesM = 0 if denguePr==0
  
  generate meanM = casesM / sampleM
  
    
  gen lnrrMean = ln(rrMean)
  



save `j'/WORK/04_epi/02_models/01_code/06_custom/dengue/data/modelingData.dta, replace	







* PREP AGE DISTRIBUTION DATASET *

  odbc load, exec("SELECT output_version_id FROM output_version WHERE is_best = 1") dsn(mort2015) clear
  odbc load, exec("SELECT age_group_id, year_id, location_id, sex_id, mean_pop FROM output WHERE year_id IN (1980, 1985, 1990, 1995, 2000, 2005, 2010, 2015) AND age_group_id < 22 AND age_group_id>1 AND sex_id < 3 AND output_version_id = `=output_version_id[1]'") dsn(mort2015) clear

  
  local j = "J:"
  joinby age_group_id sex_id using `j'/WORK/04_epi/02_models/01_code/06_custom/dengue/data/ageDistribution.dta
  save `j'/WORK/04_epi/02_models/01_code/06_custom/dengue/data/ageSpecific.dta, replace



