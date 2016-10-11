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
  
  
* DEFINE LOCALS *  
  local incModel  80171
  local typhModel 80901
  local paraModel 80903

  local ages 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21
  local team epi

  local measure 6

  tempfile locationTemp popTemp appendTemp mergeTemp


  
  
/******************************************************************************\		
    BRING IN CHINA DATA TO ESTIMATE TYPHOID:PARATYPHOID CASE FATALITY RATIO  
\******************************************************************************/  

  foreach i in typhoid paratyphoid {
  
    import excel `j'/LIMITED_USE/PROJECT_FOLDERS/CHN/GBD_COLLABORATORS/NOTIFIABLE_INFECTIOUS_DISEASES/CHN_NOTIFIABLE_INFECTIOUS_DISEASES_2004_2012_TYPE_I_II_INC_MOR_BY_PROV_Y2013M11D22.XLSX, sheet("`i' fever") firstrow clear

    bysort year: egen cases  = total(reportincidence)
    bysort year: egen deaths = total(reportdeaths)
    bysort year: gen touse = _n ==_N
 
    generate typhoid = "`i'" == "typhoid"
   
    order year cases deaths typhoid

    keep if touse==1
    keep year cases deaths typhoid
  
    if "`i'" == "paratyphoid" append using `appendTemp'
  
    save `appendTemp', replace
	
    }


/******************************************************************************\		
              ESTIMATE TYPHOID:PARATYPHOID CASE FATALITY RATIO
\******************************************************************************/  
  
  glm deaths typhoid, family(binomial cases) eform
  
  local cfRatioB  = _b[typhoid]
  local cfRatioSe = _se[typhoid]
  
  
  
  
/******************************************************************************\		
                    BRING IN INCIDENCE & SPLIT ESTIMATES
\******************************************************************************/


* PULL POPULATION NUMBERS *
  get_demographics, gbd_team(epi) get_population make_template clear
  save `popTemp', replace
  
  
* PULL MODEL ESTIMATES *  
  local count 1

  foreach x in inc typh para {
	get_estimates, gbd_team(`team') model_version_id(``x'Model') age_group_ids(`ages') clear

	keep location_id year_id age_group_id sex_id mean
	keep if sex_id<3
	rename mean mean_`x'
	
	if `count'>1 merge 1:1 location_id year_id age_group_id sex_id using `mergeTemp', assert(3) nogenerate
	save `mergeTemp', replace
	
	local ++count
	}

* MERGE IN POPULATION *	
  merge m:1 location_id year_id age_group_id sex_id using `popTemp', keep(3) nogenerate


* CONVERT TOTAL INCIDENCE TO CAUSE-SPECIFIC NUMBERS *
  gen nTyph = mean_inc * pop_scaled * mean_typh / (mean_typh + mean_para)
  gen nPara = mean_inc * pop_scaled * mean_para / (mean_typh + mean_para)


* BRING IN INCOME CATEGORY DATA *
  merge m:1 location_id using "`j'/WORK/04_epi/02_models/01_code/06_custom/intest/inputs/submit_split_data.dta", nogenerate


* TOTAL UP CASE-SPECIFIC NUMBERS BY AGE AND INCOME *  
  fastcollapse nTyph nPara pop_scaled, by(incomeCat age_group_id) type(sum)
  generate pTyph = nTyph / (nTyph + nPara)

  

  
/******************************************************************************\		
                     BRING IN CASE FATALITY MODEL RESULTS
\******************************************************************************/


merge 1:1 age_group_id incomeCat using `j'/WORK/04_epi/02_models/01_code/06_custom/intest/inputs/cfDraws.dta, assert(3) nogenerate
  
forvalues i = 0/999 {
  local ratio = exp(rnormal(`cfRatioB', `cfRatioSe'))
  quietly generate cf_para_`i'   = cf_`i'  / (`ratio' * pTyph + 1 - pTyph)
  quietly generate cf_typh_`i'   = cf_para_`i' * `ratio'
  di "." _continue
  }
  
drop cf_0-cf_999 pop_scaled nTyph nPara pTyph
sort incomeCat age_group_id


save `j'/WORK/04_epi/02_models/01_code/06_custom/intest/inputs/cfDrawsByIncomeAndAge.dta, replace

forvalues i = 1/3 {
  preserve
  keep if incomeCat==`i'
  drop incomeCat
  save `j'/WORK/04_epi/02_models/01_code/06_custom/intest/inputs/cfDraws_`i'.dta, replace
  restore
  }
  

