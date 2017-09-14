/******************************************************************************\

Purpose: 
  This script creates a dataset to be used to build custom CoD models

  
Details: 
  1) Create master skeleton dataset: the script first builds a master skeleton 
     dataset containing one row for every combination of location, year, age, 
	 and sex. 
	 
  2) Create model results datase: the script then cycles through the specified
     get_model_results options. It cycles through each  get_model_results
	 command, loads the model results, preps that data for merging. For each
	 get_model_results command, the data are loaded, prepped and merged into  
	 the master skeleton.  
	 
  3) Create covariate dataset: the script then cycles through the specified
     list of covariate_ids.  It first pulls the meta-data for each covariate
	 (i.e. covariate name, age/sex specificity). It then cycles through each
	 covariate_id, loads the covariate data, preps that data for merging 
	 (note, we pulled age/sex specificity to determine how to appropriately
	 prep the file for the merge and determine the correct merge command). 
	 For each covariate, the data are loaded, prepped and merged into the 
	 master skeleton.  
	 
  4) Bring in mortality envelope and population estimates.
  
  5) Create all-age versions of all age-specific model results and 
     covariates.
  
  6) Bring in CoD data: the script then loads the cause-specific data from 
     the CoD database and merges these data into the master
	 
  7) Clean up: finally, the script cleans things up by ordering and sorting 
     data, and saving the dataset.
	 
	 

Syntax:
  build_cod_dataset <i>cause_id</i> [, covariate_ids(<i>covariate_ids</i> saveto(<i>filepath</i>)]
  
Examples: 
1) Create a dataset for cause_id 360 with no covariates, and without saving a copy:
   build_cod_dataset 360
  
2) Create a dataset for cause_id 360 including covariates 142, 208, 118, & 109:
   build_cod_dataset 360, covariate_ids(142 208 118 109)
  
3) Create the same dataset as for example 2, but also save the file:
   build_cod_dataset 360, covariate_ids(142 208 118 109) ///
   saveto("FILEPATH/cod360.dta")
   
4) Same as for 3, but with prevalence estimates added as well:
   build_cod_dataset 360, covariate_ids(142 208 118 109) ///
   get_model_results(gbd_team(epi) model_version_id(95825)) ///
   saveto("FILEPATH/cod360.dta")
   
   
\******************************************************************************/ 


capture program drop build_cod_dataset
program define build_cod_dataset
syntax  anything(name=cause_id id=cause_id), [covariate_ids(string) get_model_results(string) saveto(string) outliers clear]


quietly {

/******************************************************************************\
                            SETUP THE ENVIRONMENT                             
\******************************************************************************/

*** CHECK IF CLEAR WOULD ERASE DATA ***
    describe
    if "`clear'" == "" & (`r(N)' > 0 | `r(width)' > 0) {
      noisily di as error "If data is in memory you must specify the option clear"
      exit
	  }
		
    clear
	
*** BOILERPLATE ***
	if c(os) == "Unix" {
	  local j FILEPATH
	  }
	else {
	  local j FILEPATH
	  }

	adopath + FILEPATH/current  
	adopath + FILEPATH/stata
	
	run FILEPATH/get_cod_data.ado
	run FILEPATH/get_population.ado
	run FILEPATH/get_envelope.ado
	run FILEPATH/resolver.ado
	
*** CREATE TEMPORARY VARIABLES ***
	tempfile cod allAgeCod codLocations estimates locations age master resolverMaster year covars env allAgeMaster
	tempfile age_groupListTemp locationListTemp yearListTemp sexListTemp
	  
	  
*** CREATE CONNECTION STRING TO SHARED DATABASE ***
	noisily di "{hline}" _n _n "Connecting to the database"
	
	run FILEPATH/create_connection_string.ado
	
	create_connection_string, database(shared)
	local shared = r(conn_string)
	
	sleep 5000
	
	create_connection_string, server(modeling-epi-db) database(epi)
	local epi = r(conn_string)
	

	
	
/******************************************************************************\
                               BRING IN COD DATA                               
\******************************************************************************/ 	  
	
	noisily di _n "Getting the CoD data (this will take a few minutes)"

	get_cod_data, cause_id(`cause_id') location_set_id(45) clear
	
	if "`outliers'"=="outliers" {
		drop data_id
		save `cod'
		get_cod_data, cause_id(`cause_id') is_outlier(1) location_set_id(45) clear
		append using `cod'
		}

	rename year year_id
	rename sex  sex_id
	drop acause cause_id cause_name upload_date age_name data_id
	egen data_group = group(cod_source_label description nid data_type location_id year_id sex_id site urbanicity_type representative), missing
	
	
	preserve
	keep if !inlist(age_group_id, 22, 27)
	save `cod', replace
	
	
	   
	keep location_id
	duplicates drop
	save `codLocations'
	
	restore
	keep if age_group_id==22
	
	local sumList study_deaths sample_size cf rate pop deaths env sex is_outlier
	keep `sumList' data_group

	fastcollapse `sumList', by(data_group) type(sum)
	
	foreach var of varlist `sumList' {
		rename `var' `var'_22
		}
		
	merge 1:m data_group using `cod', nogenerate
	
	bysort data_group: gen aaIndex = _n==1
	
	save `cod', replace
	

	
/******************************************************************************\
                         CREATE MASTER SKELETON DATASET                         
\******************************************************************************/ 

	noisily di _n "Creating a master skeleton dataset"
	
*** BRING IN LIST OF COD ESTIMATION AGE GROUPS ***	
	noisily di " . Loading age groups"
	odbc load, exec("SELECT age_group_id FROM age_group_set_list WHERE age_group_set_id = 12") `shared' clear
	save `age'

*** BRING IN AGE GROUP DETAILS ***	
	odbc load, exec("SELECT age_group_id, age_group_name, age_group_years_start, age_group_years_end FROM age_group") `shared' clear
	egen age_mid = rowmean( age_group_years_start age_group_years_end)
	merge 1:1 age_group_id using `age', keep(3) nogenerate
	save `master'

*** BRING IN AGE WEIGHTS ***	
	odbc load, exec("SELECT age_group_id, age_group_weight_value FROM age_group_weight WHERE gbd_round_id = 4") `shared' clear
	merge 1:m age_group_id using `master', assert(1 3) keep(3) nogenerate
	save `master', replace

*** BRING IN LIST OF COD ESTIMATION LOCATIONS ***
	noisily di " . Loading locations"
	odbc load, exec("SELECT location_id, parent_id, path_to_top_parent, level, is_estimate, most_detailed, location_name, location_type_id, location_type, super_region_id, super_region_name, region_id, region_name, ihme_loc_id FROM location_hierarchy_history WHERE location_set_id = 8 AND location_set_version_id = 158") `shared' clear
	
	/* Now we merge in the locations file from above and keep all countries, 
	estimation units, & locations with CoD data */
	merge 1:1 location_id using `codLocations'
	keep if is_estimate == 1 | level == 3 | _merge == 3
	drop _merge
	
	* Most regions have sufficient data to model at the region level
	generate mod_region_id = region_id 
	generate mod_region_name = region_name
	* Oceania; if <25% of locations in Oceania have data, then add it to SE Asia
	replace  mod_region_id = 9 if region_id==21 
	replace  mod_region_name = "SE Asia and Oceania" if mod_region_id==9
	* Central, Eastern, & Western Sub-Saharan Africa together
	replace  mod_region_id = super_region_id if inlist(region_id, 167, 174, 199)
	replace  mod_region_name = "Central, Eastern, & Western Sub-Saharan Africa" if inlist(region_id, 167, 174, 199)
	
	* Create country id variable
	gen country_id = word(subinstr(path_to_top_parent, ",", " ", .), 4)
	destring country_id, replace
	


*** CREATE DATASET WITH EVERY COMBINATION OF AGE AND LOCATION (MASTER) ***	
	cross using `master'
	save  `master', replace


***	CREATE DATASET WITH EVERY COD ESTIMATION YEAR ***
	noisily di " . Loading years"
	clear
	set obs `=2016 - 1979'
	generate year_id = _n + 1979
	save `year'
	
	
*** CREATE DATASET WITH EVERY COMBINATION OF AGE, LOCATION, & YEAR (MASTER, UPDATED) ***	
	cross using `master'
	save  `master', replace

	
***	CREATE DATASET WITH EVERY COD ESTIMATION SEX ***	
	noisily di " . Loading sexes"
	clear
	set obs 2
	generate sex_id = _n 


*** CREATE DATASET WITH EVERY COMBINATION OF AGE, LOCATION, YEAR, & SEX (MASTER, UPDATE 2) ***
	cross using `master'
	save  `master', replace
	
	keep location_id year_id age_group_id sex_id parent_id
	save `resolverMaster'
	
*** CREATE TEMPORARY DATASETS WITH EVERY VALUE OF AGE, LOCATION & YEAR (TO BE USED TO DEAL WITH MISSING VALUES OF COVARIATES) ***
	noisily di " . Storing vectors"
	foreach x in age_group location year sex {
		preserve
		keep `x'_id
		duplicates drop
		
		save ``x'ListTemp'
		levelsof `x'_id, local(`x'FullVector) clean
		
		restore
		}
	

	
/******************************************************************************\
                           BRING IN MODEL RESULTS                               
\******************************************************************************/ 
	
if "`get_model_results'" != "" {	
  tokenize `get_model_results', parse(|)	

  while "`1'" != "" {
  
  * PULL IN MODEL RESULTS & CLEAN UP A COUPLE VARIABLES ***
	noisily di _n "Getting model results: `1'"
	
	* Get the modelable entity name to label the variable produced by the resolver *
	local mvid = word(subinstr(substr("`1'", strpos("`1'", "model_version_id") + length("model_version_id") + 1, .), ")", " ", 1), 1)
	odbc load, exec("SELECT modelable_entity_name FROM epi.model_version JOIN epi.modelable_entity USING (modelable_entity_id) WHERE model_version_id = `mvid'") `epi' clear
	levelsof modelable_entity_name, local(me_name) clean
	
	* Run the resolver *
	use `resolverMaster', clear
	noisily resolver `1', estimate_type(results) by(age_group_id sex_id) covariate_name("`me_name'") age_groupFullVector(`age_groupFullVector') locationFullVector(`locationFullVector') yearFullVector(`yearFullVector') 
	
  * MERGE IT ALL TOGETHER *		
	merge 1:1 location_id year_id age_group_id sex_id using `master', assert(1 3) keep(3) nogenerate
	save `master', replace
	macro shift 2
	}
  }




/******************************************************************************\
                           CREATE COVARIATE DATASET                             
\******************************************************************************/	

if "`covariate_ids'" != "" {
	noisily di _n "Loading covariate metadata" _continue
	
  * LOAD IN COVARIATE META-DATA TO DETERMINE NAME & AGE/SEX SPECIFICITY *
	odbc load, exec("SELECT covariate_id, covariate_name_short, covariate_name, by_age, by_sex, dichotomous FROM covariate WHERE covariate_id IN (`=subinstr(trim(itrim("`covariate_ids'")), " ", ",", .)')") `shared' clear

	generate sex = "sex_id" if by_sex==1
	generate age = "age_group_id" if by_age==1
	
	levelsof covariate_name_short, local(covarList) clean

	forvalues i = 1/`=_N' {
		foreach var of varlist covariate_name* dichotomous age sex by_age {
			local `var'_`=covariate_id[`i']'  `=`var'[`i']'
			}
		}

  * LOAD IN COVARIATE DATA, PROCESS TO ACCOUNT FOR AGE/SEX SPECIFICITY & MERGE INTO MASTER ***  
	foreach covariate_id of local covariate_ids {
		noisily di _n "Getting covariate `covariate_id' (`covariate_name_`covariate_id'')"
	  	  
		use `resolverMaster', clear
		noisily resolver `covariate_id', estimate_type(covariates) by(`age_`covariate_id'' `sex_`covariate_id'') covariate_name(`covariate_name_`covariate_id'') covariate_name_short(`covariate_name_short_`covariate_id'') age_groupFullVector(`age_groupFullVector') locationFullVector(`locationFullVector') yearFullVector(`yearFullVector') 
		
		merge 1:1 location_id year_id age_group_id sex_id using `master', keep(2 3) nogenerate
		save `master', replace
		}
	}
	

  
/******************************************************************************\
                     BRING IN POPULATION & ENVELOPE ESTIMATES                              
\******************************************************************************/ 	

*** GET THE ENVELOPE ***
	noisily di _n "Getting the mortality envelope"
	get_envelope, location_id("`locationFullVector'") sex_id("1 2") age_group_id("`age_groupFullVector'") year_id("`yearFullVector'") clear		 
	rename mean envelope
	keep age_group_id location_id year_id sex_id envelope
	save `env'

*** GET THE POPULATIONS ***	
	noisily di "Getting population estimates"
	get_population, location_id("`locationFullVector'") sex_id("1 2") age_group_id("`age_groupFullVector'") year_id("`yearFullVector'") clear	 
	keep age_group_id location_id year_id sex_id population


*** MERGE IT ALL TOGETHER & CLEAN UP ***	
	noisily di "Merging envelope & population estimates"
	merge 1:1 age_group_id location_id year_id sex_id using `env', assert(3) nogenerate
	
	noisily di "Merging envelope + population estimates to the master"
	merge 1:1 age_group_id location_id year_id sex_id using `master', assert(3) nogenerate
	
	save `master', replace
	  


/******************************************************************************\
           CREATE ALL-AGE VERSIONS OF MODEL RESULTS & COVARIATES                               
\******************************************************************************/
  
  if "`get_model_results'" != "" | "`covariate_ids'" != "" {
  
	noisily di "Creating age-standardized versions of age-specific covariates and model results"
  
  	drop age_group_id age_group_name age_group_years_start age_group_years_end age_mid sex_id envelope level is_estimate most_detailed location_name location_type* *region* ihme_loc_id country_id *parent*
	
	ds location_* year_id age_group_weight population, not
	local covars_to_collapse `r(varlist)'
	
	foreach var of varlist `covars_to_collapse' {
		generate `=substr("`var'", 1, 29)'_27 = `var' * age_group_weight / 2
		generate `=substr("`var'", 1, 29)'_22 = `var' * population
		}

	fastcollapse *_22 *_27 population, by(location_id year_id) type(sum)

	foreach var of varlist *_22 {
		replace `var' = `var' / population
		}
		
	drop population	
	
	merge 1:m location_id year_id using `master', assert(3) nogenerate
	}
	


	  
/******************************************************************************\
                MERGE IN COD DATA, CLEAN UP & SAVE DATASET                               
\******************************************************************************/

*** MERGE IN COD DATA ***
	noisily di "Merging CoD data to master"  
	merge 1:m location_id year_id age_group_id sex_id using `cod', nogenerate
	

	
/******************************************************************************\
               MERGE IN COD DATA, CLEAN UP & SAVE ALL-AGE DATASET                               
\******************************************************************************/	

*** CLEAN UP ***
	order year_id location_id location_name ihme_loc_id  ///
	      super_region_id super_region_name region_id region_name mod_region_id country_id parent_id path_to_top_parent ///
	      location_type_id location_type level is_estimate most_detailed  ///
		  age_group_id age_group_name age_group_years_start age_group_years_end age_mid sex_id ///
	      `covarList' *_2? cf rate sample_size study_deaths pop deaths env data_type representative ///
		  urbanicity_type is_outlier cod_source_label description nid citation 
		  
	sort  location_id year_id age_group_id sex_id data_type cod_source_label
		  
	
*** SAVE FILE ***
	noisily di "Saving the dataset"
	if "`saveto'"!="" {
		save `saveto'
		}
	else {
		save FILEPATH/cause`cause_id'_`=subinstr(subinstr(itrim(trim("`c(current_date)'_`c(current_time)'")), " ", "_", .), ":", "_", .)'.dta, replace
		}
}	
end

