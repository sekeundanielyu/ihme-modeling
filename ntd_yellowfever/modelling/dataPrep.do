
local version 8
* PREP STATA *
  clear all 
  set more off, perm
  set maxvar 10000


* ESTABLISH TEMPFILES AND APPROPRIATE DRIVE DESIGNATION FOR THE OS * 

  if c(os) == "Unix" {
    local j "/home/j"
    set odbcmgr unixodbc
    }
  else if c(os) == "Windows" {
    local j "J:"
    }
	 
  tempfile appendTemp mergingTemp skeleton pop
  
  adopath + `j'/WORK/10_gbd/00_library/functions

   
* CREATE A LOCAL CONTAINING THE ISO3 CODES OF COUNTRIES WITH YELLOW FEVER *
  local yfCountries AGO ARG BEN BOL BRA BFA BDI CMR CAF TCD COL COG CIV COD ECU GNQ ETH GAB GHA GIN GMB GNB ///
     GUY KEN LBR MLI MRT NER NGA PAN PRY PER RWA SEN SLE SDN SSD SUR TGO TTO UGA VEN ERI SOM STP TZA ZMB
	 

* STORE FILE PATHS IN LOCALS *	 
  local epiDir    `j'/WORK/04_epi/01_database/02_data/ntd_yellowfever/1509/03_review/01_download
  local inputDir  `j'/WORK/04_epi/02_models/01_code/06_custom/ntd_yellowfever/inputs

	 
/******************************************************************************\	
         IMPORT DATA AND LIMIT TO COUNTRIES WITH ENDEMIC YELLOW FEVER
\******************************************************************************/ 

* CREATE LIST OF ENDEMIC LOCATION_IDS *
  get_location_metadata, location_set_id(8) clear
  keep location_id ihme_loc_id
  
  generate endemic = 0
  foreach i of local yfCountries {
	quietly replace endemic = 1 if strmatch(ihme_loc_id, "`i'*")==1
	}
	
  levelsof location_id if endemic==1, local(endemicLids) sep( | location_id==)
	 
* IMPORT THE MOST RECENT DATASHEET (DOES NOT CONTAIN UPDATED DATA) *	  
  cd `epiDir'
  local files: dir . files "me_1509_ts_*.xlsx"
  local files: list sort files
  import excel using `=word(`"`files'"', wordcount(`"`files'"'))', sheet("extraction") firstrow clear


  * DROP NON-ENDEMIC COUNTRIES*
  keep if location_id == `endemicLids'
  duplicates drop nid location_id year_start year_end sex age_start age_end mean, force

  
* SAVE A COPY OF ALL-AGES DATA POINTS *  
  egen ageCat = concat(age_start age_end), punc(-)
  preserve
  keep if ageCat=="0-100"
  save `appendTemp', replace

* DROP ALL-AGES DATA POINTS *
  restore
  keep if ageCat!="0-100"


/* IDENTIFY AND KEEP COMPLETE DATA SOURCES:
  To offer complete data sources that report age-specific data must cover
  ages 0 through 100 with no gaps (1 year gap okay due to demographic notation) */
  
  bysort year_start nid age_start sex location_id: gen count = _N
  egen group = group(nid location_id year_start year_end sex)
  keep if count==1
  bysort group (age_start): gen ageGap = age_start[_n] - age_end[_n-1]
  bysort group: egen maxAge = max(age_end)
  bysort group: egen minAge = min(age_start)
  bysort group: egen maxGap = max(abs(ageGap))

  keep if minAge==0 & maxAge==100 & maxGap<=1
  

* WITH COMPLETE DATA ISOLATED, WE NOW COLLAPSE AGE-SPECIFIC TO ALL-AGE *  
  preserve
  bysort group: generate groupIndex = _n
  keep if groupIndex==1
  drop cases effective_sample_size upper lower nid ihme_loc_id year_start year_end mean standard_error age_start age_end
  save `mergingTemp', replace

  restore
  replace cases = mean*effective_sample_size if missing(cases)
  replace effective_sample_size = sample_size if missing(effective_sample_size)
  collapse (sum) cases effective_sample_size, by(group nid location_id year_start year_end)

  merge m:1 group using `mergingTemp', nogenerate
  save `mergingTemp', replace

* COMBINE THESE NEWLY COLLAPSED ALL-AGE OBSERVATIONS WITH THE ORIGINAL ALL-AGE DATA *  
  use `appendTemp', clear
  append using `mergingTemp'
  
* COLLAPSE SEX-SPECIFIC DATA TO BOTH SEXES *
  generate sex_id = (sex=="Male") + (2*(sex=="Female")) + (3*(sex=="Both"))
  
  forvalues i = 1/2 {
    bysort nid location_id year_start year_end: egen maxSex = max(sex_id)
    bysort nid location_id year_start year_end: egen minSex = min(sex_id)
  
    if `i'==1 {
	  drop if maxSex==3 & sex_id<3
	  drop maxSex minSex
	  }
	}
	
  assert minSex==maxSex | minSex==1 & maxSex==2
  
  preserve
  
  keep if maxSex<3
  bysort nid location_id year_start year_end (sex): replace cases = sum(cases)
  bysort nid location_id year_start year_end (sex): replace effective_sample_size = sum(effective_sample_size)
  
  foreach var of varlist mean lower upper sample_size standard_error {
    replace `var' = .
	}
	
  keep if sex_id==2
  replace sex_id = 3
  replace sex = "Both"
  save `appendTemp', replace
  
  restore 
  drop if maxSex<3
  append using `appendTemp'
  


   
   
/******************************************************************************\	
         CLEAN UP VARIABLES, & CALCULATE UNCERTAINTY WHERE MISSING
\******************************************************************************/  
 

  keep nid location_name location_id sex sex_id year_start year_end mean lower upper standard_error effective_sample_size cases sample_size
  generate age_group_id = 22
  
  replace mean = cases / effective_sample_size if missing(mean)
  replace cases = mean * effective_sample_size if missing(cases)


* ESTIMATE STANDARD ERRORS & CIs *   
   replace standard_error = ((5 - cases) * (1/effective_sample_size) + cases * (sqrt( (5/effective_sample_size) / effective_sample_size ))) / 5  if cases<=5 & missing(standard_error)

   replace standard_error = sqrt(mean / effective_sample_size)  if cases>5 & missing(standard_error)
   

   replace upper = mean + (invnormal(0.975) * standard_error) if missing(upper)
   replace lower = mean + (invnormal(0.025) * standard_error) if missing(lower)
   replace lower = 0 if lower < 0

   
   
/******************************************************************************\	
                                RESOLVE DUPLICATES
\******************************************************************************/ 

  drop if year_start!=year_end
  bysort location_id year_start year_end sex (mean): gen count = _N
  bysort location_id year_start year_end sex (mean): gen index = _n

  keep if count==index 
  save `appendTemp', replace   
   

   
/******************************************************************************\	
 CREATE A SKELETON DATASET CONTAINING EVERY COMBINATION OF ISO, AGE, SEX & YEAR
\******************************************************************************/ 


* PULL POPULATION DATA *
  odbc load, exec("SELECT output_version_id FROM output_version WHERE is_best=1") dsn(mort2015) clear
  local ovi = output_version_id in 1
  odbc load, exec("SELECT year_id, age_group_id, sex_id, location_id, mean_pop FROM output WHERE output_version_id = `ovi' AND year_id > 1979") dsn(mort2015) clear
  save `pop'

  get_location_metadata, location_set_id(8) clear
  keep location_id location_name parent_id location_type ihme_loc_id *region*
  merge 1:m location_id using `pop', nogenerate
  
  get_demographics, gbd_team(cod) 
  generate toModel = 0
  foreach l in $location_ids {
    quietly replace toModel = 1 if location_id==`l'
	}
  
  keep if toModel==1 | location_type=="admin0"
  generate countryIso = substr(ihme_loc_id, 1, 3)
  
  save `inputDir'/skeleton.dta, replace

* WITH THE FULL SKELETON DATASET SAVED, LIMIT NOW TO BE YEAR-ISO SPECIFIC *
  keep if sex_id==3 & age_group_id==22
  rename year_id year_start
 
* CREATE YELLOW FEVER ENDEMICITY VARIABLE...AGAIN *
  generate yfCountry = location_id==`endemicLids'
 

 
/******************************************************************************\	
      MERGE THE YEAR-ISO SPECIFIC SKELETON TO THE YELLOW FEVER DATASET
	  
  This ensures that we now have an observation for every year and country, not
  just an observation for years and countries with data.
\******************************************************************************/ 
  
  merge 1:m location_id year_start using `appendTemp',  nogenerate

  keep if yfCountry == 1
 
* CLEAN UP A FEW VARIABLES * 
  replace cases = . if cases == 0
  replace cases = mean * effective_sample_size if missing(cases)

  gen yearC = year_start - ((2015 - 1990)/2)
  
  order location* ihme_loc_id *region* year* age* sex* mean lower upper standard_error effective_sample_size cases mean_pop nid
  
  drop count index

  save `inputDir'/dataToModel.dta, replace
