// Purpose: GBD 2015 Human African Trypanosomiasis (HAT) Estimates
// Description:	To produce death, incidence and prevalence estimates of HAT and the two sequelae (Severe motor and cognitive impairment due to sleeping disorder and disfiguring skin disease)

// LOAD SETTINGS FROM MASTER CODE

	// prep stata
	clear all
	set more off
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

	// base directory on J 
	local root_j_dir `1'
	// base directory on ihme/gbd (formerly clustertmp)
	local root_tmp_dir `2'
	// timestamp of current run (i.e. 2015_11_23)
	local date `3'
	// step number of this step (i.e. 01a)
	local step `4'
	// name of current step (i.e. first_step_name)
	local step_name `5'
	// step numbers of immediately anterior parent step (i.e. first_step_name)
	local hold_steps `6'
	// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
	local last_steps `7'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step'_`step_name'"
	// directory for output on ihme/gbd (formerly clustertmp)
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step'_`step_name'"
	// directory for standard code files
	adopath + $prefix/WORK/10_gbd/00_library/functions
	adopath + $prefix/WORK/10_gbd/00_library/functions/utils
	quietly do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
	
	di "`out_dir'/02_temp/02_logs/`step'.smcl"
	cap log using "`out_dir'/02_temp/02_logs/`step'.smcl", replace
	if !_rc local close_log 1
	else local close_log 0
	
	// check for finished.txt produced by previous step
	if "`hold_steps'" != "" {
		foreach step of local hold_steps {
			local dir: dir "`root_j_dir'/03_steps/`date'" dirs "`step'_*", respectcase
			// remove extra quotation marks
			local dir = subinstr(`"`dir'"',`"""',"",.)
			capture confirm file "`root_j_dir'/03_steps/`date'/`dir'/finished.txt"
			if _rc {
				di "`dir' failed"
				BREAK
			}
		}
	}	

  // Prep population at risk (estimates from ArcGIS analysis for GBD 2010)
  use "$prefix/Project/GBD/Causes/Parasitic and Vector Borne Diseases/HAT/HAT_pop_at_risk_with_green.dta", clear
  replace iso3 = "SSD" if iso3 == "SDN" // this was done because all cases occur in South Sudan (see Simaro et.al., 2010 Fig. 3) and at the time this data was prepared, Sudan and South Sudan had not split.
  rename iso3 ihme_loc_id
  tempfile pop_risk
  save `pop_risk', replace
  
  local reported_data2010 "$prefix/Project/GBD/Causes/Parasitic and Vector Borne Diseases/HAT/parameters HAT.csv"
  
  use "$prefix/WORK/04_epi/01_database/01_code/02_central/07_conversions/WHO_website/HAT/HAT_cases2015.dta", clear
  rename iso3 ihme_loc_id
  tempfile reported_data2015
  save `reported_data2015', replace 
  local history_data "$prefix/Project/GBD/Causes/Parasitic and Vector Borne Diseases/HAT/HAT history numbers.csv"

  //CoD and Outputs 2015
  clear
  get_location_metadata, location_set_id(35)
 
// Prep country codes file
  duplicates drop location_id, force
  tempfile country_codes
  save `country_codes', replace

// Create dummy file with zeroes for Early Neonatal (EN), Late Neonatal (LN) and Post Neonatal (PN)
  clear all
  set obs 3
  generate double age_group_id = .
  format %16.0g age_group_id
  replace age_group_id = 4 //PN
  replace age_group_id = 3 if _n == 2 //LN
  replace age_group_id = 2 if _n == 3 //EN
  forvalues i = 0/999 {
    generate draw_`i' = 0
  }
  tempfile age0_1_zero_draws
  save `age0_1_zero_draws', replace	
  
// Create draw file with zeroes for countries without data (i.e. assuming no burden in those countries)
  clear
  quietly set obs 20
  quietly generate double age = .
  quietly format age %16.0g
  quietly replace age = _n * 5
  quietly replace age = 0 if age == 85
  quietly replace age = 0.01 if age == 90
  quietly replace age = 0.1 if age == 95
  quietly replace age = 1 if age == 100
  sort age

  generate double age_group_id = .
  format %16.0g age_group_id
  replace age_group_id = _n + 1

  forvalues i = 0/999 {
    quietly generate draw_`i' = 0
  }

  quietly format draw* %16.0g

  tempfile zeroes
  save `zeroes', replace


// Prepare envelope and population data
	// Get connection string
create_connection_string, server(modeling-mortality-db) database(mortality) 
local conn_string = r(conn_string)

  //gbd2015 version:
 odbc load, exec("SELECT a.age_group_id, a.age_group_name_short AS age, a.age_group_name, o.sex_id AS sex, o.year_id AS year, o.location_id, o.mean_env_hivdeleted AS envelope, o.pop_scaled AS pop FROM output o JOIN output_version USING (output_version_id) JOIN shared.age_group a USING (age_group_id) WHERE is_best=1") `conn_string' clear
  
  tempfile demo
  save `demo', replace
  
  use "`country_codes'", clear
  merge 1:m location_id using "`demo'", nogen
  keep age age_group_id sex year ihme_loc_id parent location_name location_id location_type region_name envelope pop
  keep if inlist(location_type, "admin0","admin1","admin2","nonsovereign", "subnational", "urbanicity")

   replace age = "0" if age=="EN"
   replace age = "0.01" if age=="LN"
   replace age = "0.1" if age=="PN"
   drop if age=="All" | age == "<5"
   keep if age_group_id <= 22
   destring age, replace
   
  keep if year >= 1980 & age > 0.9 & age < 80.1 & sex != 3 
  sort ihme_loc_id year sex age
  tempfile pop_env
  save `pop_env', replace
	
//edit country_codes data to remove duplicate location_name: 
	use "`country_codes'", clear
	duplicates drop location_name, force
	tempfile country_codes_rev
	save `country_codes_rev', replace
	
// Bring in reported data and clean it. These data include number of people screened per country-year, where available.
  insheet using "`reported_data2010'", clear
  drop v7-v19
  rename countryname location_name
  replace location_name = "South Sudan" if location_name == "Sudan" //this was done because all cases occur in South Sudan (see Simaro et.al., 2010 Fig. 3) and at the time this data was prepared, Sudan and South Sudan had not split.
  drop reported_*
 
// Merge with countrycodes file
  merge m:1 location_name using "`country_codes_rev'", keepusing(ihme_loc_id location_name location_id parent_id region_id region_name) keep(master match) nogen
  replace ihme_loc_id = "COD" if location_name == "Democratic Republic of Congo"
  replace ihme_loc_id = "GMB" if location_name == "Gambia"
  replace ihme_loc_id = "GNB" if location_name == "Guinea Bissau"
  replace location_name = "Democratic Republic of the Congo" if location_name =="Democratic Republic of Congo"
  replace location_name = "The Gambia" if location_name =="Gambia" 
  replace location_name = "Guinea-Bissau" if location_name =="Guinea Bissau" 
  tempfile reported_data2010_rev
  save `reported_data2010_rev', replace
	
 use "`reported_data2015'", clear
 merge m:1 ihme_loc_id using "`country_codes'", keepusing(ihme_loc_id location_name location_id parent_id region_id region_name) keep(master match) nogen
 merge 1:1 ihme_loc_id year using "`reported_data2010_rev'", nogen
 
  rename reported_tgr reported_tbr
  rename reported_tgb reported_tbg
  drop location_name parent
  merge m:1 location_id using "`country_codes'", keepusing(location_id ihme_loc_id location_name parent_id region_id region_name) keep(matched) nogen

// Clean
  destring ppl_risk, replace force
  rename ppl_risk WHO_estimate_risk  // for comparison only //e.g. in AGO 1998, ppl_risk here = 3M, in the `pop_risk' file it is = 1871355.8

// Generate new variable for total cases
  generate total_reported = reported_tbg + reported_tbr
  replace total_reported = reported_tbg if total_reported == .
  replace total_reported = reported_tbr if total_reported == .

// Reshape data
  reshape wide ppl_screened reported* total_reported WHO_estimate_risk, i(ihme_loc_id parent) j(year)
  
  foreach var in ppl_screened reported_tbg reported_tbr total_reported WHO_estimate_risk {
  forvalues y = 1990/2014 {
    rename `var'`y' YR_`y'_`var'
  }
  }
    
  reshape long YR_1990_ YR_1991_ YR_1992_ YR_1993_ YR_1994_ YR_1995_ YR_1996_ YR_1997_ YR_1998_ YR_1999_ YR_2000_ YR_2001_ YR_2002_ YR_2003_ YR_2004_ YR_2005_ YR_2006_ YR_2007_ YR_2008_ YR_2009_ YR_2010_ YR_2011_ YR_2012_ YR_2013_ YR_2014_, i(ihme_loc_id parent) j(type) string
  
  rename YR*_ YR*

  tempfile report_data
  save `report_data', replace

// Bring in historical dataset on total number of HAT cases reported (T. brucei gambiense + T. brucei rhodesiense)
  insheet using "`history_data'", comma names clear
  replace countryname_ihme = "South Sudan" if countryname_ihme == "Sudan" //this was done because all cases occur in South Sudan (see Simaro et.al., 2010 Fig. 3) and at the time this data was prepared, Sudan and South Sudan had not split.
  forvalues y = 1922/1998 {
    rename yr_`y' YR_`y'
    destring YR_`y', ignore(,) replace
  }
  rename countryname_ihme location_name
  replace location_name = "Democratic Republic of the Congo" if location_name =="Congo, the Democratic Republic of the"
  replace location_name = "Cote d'Ivoire" if location_name =="Côte d'Ivoire"
  replace location_name = "The Gambia" if location_name =="Gambia" 
  replace location_name = "Tanzania" if location_name =="Tanzania, United Republic of"
  
  merge m:1 location_name using "`country_codes_rev'", nogen

  tempfile historical_numbers
  save `historical_numbers', replace
  
// Merge reported and historical data
  use `report_data', clear
  merge m:1 location_name type using `historical_numbers', keep(master matched) nogen
  
  keep location_name ihme_loc_id YR* type
  order location_name ihme_loc_id type YR_1922-YR_1989 YR_1990-YR_2014
  reshape long YR_, i(ihme_loc_id location_name type) j(year) string
  reshape wide YR_, i(ihme_loc_id location_name year) j(type) string
  renpfix YR_ 
  destring year, replace

  tempfile hat
  save `hat', replace

// Merge on population at risk, as estimated with ArcGIS for GBD 2010
  use "`pop_risk'", clear
  collapse (sum) ppl_risk, by(ihme_loc_id year)
  merge 1:m ihme_loc_id year using "`hat'", nogen
  order ihme_loc_id location_name year ppl_risk total_reported
 
  
  //quick way of adding rows of data for locations without year 2015
  local new = _N + 4
  set obs `new'
  replace year = 2015 if missing(year)
  replace ihme_loc_id = "BWA" if _n == 3378
  replace ihme_loc_id = "ETH" if _n == 3379
  replace ihme_loc_id = "GNB" if _n == 3380
  replace ihme_loc_id = "RWA" if _n == 3381

  
  tempfile hat_risk
  save `hat_risk', replace
  
   //Export Kenya data and split by subnational based on the article by Rutto & Karuga: "Temporal and spatial epidemiology of sleeping sickness and use of geographical information system (GIS) in Kenya"
   //Note: Assumed that the population at risk is the same for all 5 subnational locations with data (e.g. for 1990, ppl_risk per county = national ppl_risk/5)
   /*
   keep if ihme_loc_id =="KEN"
   drop reported_*
   sort year
   save "`in_dir'/kenya_deaths_national.dta", replace
   outsheet using "`in_dir'/kenya_deaths_national.csv", comma replace
   */
 // Import updated Kenya subnationals and append with hat data
	insheet using "`in_dir'/kenya_deaths_subnational.csv", comma names clear
	drop if ihme_loc_id=="KEN"
	append using `hat_risk'
	order ihme_loc_id year
	
  drop if year < 1980 | year > 2015	

 //Revise exclusions according to GBD 2015 decisions (include BWA, ETH, GNB, RWA, SLE)
	drop if inlist(ihme_loc_id,"COM","CPV","DJI","ERI") & total_reported == . | inlist(ihme_loc_id,"GMB","LSO","MDG","MRT","NAM") & total_reported == . | inlist(ihme_loc_id,"SOM","STP","SWZ","ZAF") & total_reported == .

    drop if inlist(ihme_loc_id, "BDI", "LBR", "SEN", "NER") & total_reported == .

  tempfile HAT_data 
  save `HAT_data', replace

// Generate values to regress
  gen incidence_risk = total_reported/ ppl_risk
  gen ln_inc_risk = log(incidence_risk)
  gen coverage = ppl_screened/ ppl_risk
  gen ln_coverage = log(coverage)

  merge m:1 ihme_loc_id using "`country_codes'", keepusing(location_id  parent_id region_id region_name) keep(master match) nogen

// Graph for report: log-incidence vs log-screening coverage
  if `make_graphs' == 1 {
    scatter ln_inc_risk ln_coverage, title(Log Incidence in Pop at Risk vs. Log Coverage)
    graph export "`out_dir'/scatter_incidence_coverage.png", replace
  }

  tempfile pre_regress
  save `pre_regress', replace	


// Regress observed incidence versus screening coverage, given estimated population at risk, and cross-walk
// incidence towards perfect screening coverage.
  use `pre_regress', replace

  mixed ln_inc_risk ln_coverage || ihme_loc_id:	

  // Fill gaps in total number of reported cases
	// For Mozambique, assume zero cases if missing (very low numbers in general)
    replace total_reported = 0 if ihme_loc_id == "MOZ" & missing(total_reported)
	
	//For countries excluded in GBD 2013 but included in GBD 2015, assume zero cases if missing:
	replace total_reported = 0 if inlist(ihme_loc_id, "BWA", "ETH", "GNB", "RWA", "SLE") & missing(total_reported)
  
  // Carry forward incidence rate from 2014 to 2015
	bysort ihme_loc_id (year): replace incidence_risk = incidence_risk[_n-1] if year == 2015 & missing(incidence_risk)
	
  // Exponential interpolation of missing incidence rates between first and last year for which cases are reported (roc = rate of change)
    generate has_data = !missing(incidence_risk)
    bysort ihme_loc_id has_data (year): generate double roc = (incidence_risk[_n+1]/incidence_risk)^(1/(year[_n+1]-year))
    bysort ihme_loc_id (year): replace roc = roc[_n-1] if missing(roc)
    bysort ihme_loc_id (year): replace incidence_risk = incidence_risk[_n-1] * roc[_n-1] if missing(incidence_risk)
  // carry backward rate for years with missing data before first reports of cases
    gsort ihme_loc_id -year
    bysort ihme_loc_id: replace incidence_risk = incidence_risk[_n-1] if missing(incidence_risk)
    sort ihme_loc_id year

    replace total_reported = incidence_risk * ppl_risk if missing(total_reported)

  // Fill gaps in population screening coverage (needed to predict case detection rate)
  // Carry forward and backward over years within countries.
    bysort ihme_loc_id (year): replace ln_coverage = ln_coverage[_n-1] if missing(ln_coverage)
    gsort ihme_loc_id -year
    bysort ihme_loc_id: replace ln_coverage = ln_coverage[_n-1] if missing(ln_coverage)
    sort ihme_loc_id year
  // For countries without any coverage data, assume the average of the region (on log scale)
    bysort region_name year (ihme_loc_id): egen mean_ln_cov = mean(ln_coverage)
    sort region_name ihme_loc_id year
  // Regions without any coverage data at this point, assume the average over all other regions (on log scale)
    bysort year (ihme_loc_id): egen mean_mean_ln_cov = mean(mean_ln_cov)
    sort ihme_loc_id year
  // Fold in all estimates
    replace mean_ln_cov = mean_mean_ln_cov if missing(mean_ln_cov)
    replace ln_coverage = mean_ln_cov if missing(ln_coverage)
  
// Generate 1000 draws of mortality among treated cases, assuming that 0.7% - 6.0% of all treated (reported) cases
// die (95%-CI; source: GBD 2010, which refers to Balasegaram 2006, Odiit et al. 1997, and Priotto et al. 2009)
  local sd_mort_treat = (log(0.06) - log(0.007)) / (invnormal(0.975) * 2)
  local mu_mort_treat = (log(0.06) + log(0.007)) / 2
  capture set obs 1000
  generate mort_treated = exp(`mu_mort_treat' + rnormal() * `sd_mort_treat')
  
// Generate 1000 draws of case detection rate and counterfactual cases, given (expected) screening coverage
  matrix m = e(b)'
  //matrix list m
  matrix m = m[1..2,1]
  local covars: rownames m
  local num_covars: word count `covars'
  local betas
  forvalues j = 1/`num_covars' {
    local this_covar: word `j' of `covars'
    local betas `betas' b_`this_covar'
  }
  matrix C = e(V)
  matrix C = C[1..2,1..2]
  drawnorm `betas', means(m) cov(C)

  // Start with predicting the counterfactual incidence, and simplify by shuffling terms.
  // Assuming everything is the same (random effects, residuals, etc.), the counterfactual log-incidence is:
  //    ln_inc_counterfact = ln_inc_risk - ln_coverage * b_ln_coverage[`j'], 
  //    cdr = exp(ln_inc_risk)/exp(ln_inc_counterfact)
  //    cdr = exp(ln_inc_risk - ln_inc_counterfact)
  //    cdr = exp(ln_inc_risk - (ln_inc_risk - ln_coverage * b_ln_coverage[`j']))
  //    cdr = exp(ln_inc_risk - ln_inc_risk + ln_coverage * b_ln_coverage[`j'])
  // This boils down to:
    local counter = 0
    forvalues j = 1/1000 {
      
      quietly generate cdr_`counter' = exp(ln_coverage * b_ln_coverage[`j'])

    // Generate "true" number of incident cases and deaths, but save reported and undetected cases separately,
    // so that we can apply different duration of symptoms for prevalence calculation.
      quietly generate undetected_`counter' = total_reported / cdr_`counter' - total_reported
      quietly generate deaths_`counter' = undetected_`counter' + total_reported * mort_treated[`j']

      local counter = `counter' + 1
    }

// Drop excess empty rows that were generated to hold draws of detection rates and
// excess rows related to the generation of draws
  drop if missing(ihme_loc_id)
  
  keep ihme_loc_id location_name location_id parent_id region_name year total_reported undetected_* deaths_*
  order ihme_loc_id year total_reported undetected_* deaths_*

  tempfile inc_deaths_country_year
  save `inc_deaths_country_year', replace

// Crudely estimate age-pattern age using raw data
 import excel using "$prefix/WORK/04_epi/01_database/02_data/ntd_afrtryp/1462/03_review/01_download/me_1462_ts_2015_10_15__164408.xlsx", sheet("extraction") firstrow clear

  drop if age_start == 0 & inlist(age_end, 99, 100) //only DRC (2004-2004) and Uganda(1995-2005) has age specific info (for both sexes)

  keep age_* mean effective_sample_size
  
  generate age0_20 = 0
  replace age0_20 = 1 if age_start < 20 & age_end <= 20 //only 6 rows of data, GBD 2015 revision to include row with age 16-20
  
  generate product = mean * effective_sample_size
  bysort age0_20: egen age_product = total(product)
  egen tot_product = total(product)
  generate mean_agg = age_product/tot_product
  
  keep mean_agg age0_20
  duplicates drop mean_agg age0_20, force
  
  summarize mean_agg if age0_20 == 0
  local adults = `r(mean)'
  
  summarize mean_agg if age0_20 == 1
  local kids = `r(mean)'

  // Calculate incidence and deaths by country-year-age-sex, assuming the same age-distribution for
  // reported, undetected and mortality cases.
  use "`pop_env'", clear
  bysort ihme_loc_id year: egen check = total(pop)
  keep ihme_loc_id location_id year sex age age_group_id pop envelope
  //to make merging faster, keep only locations we are modeling (ow just merge and keep matched):
  keep if inlist(ihme_loc_id, "AGO", "BEN", "BFA", "CAF", "CIV", "CMR", "COD") | inlist(ihme_loc_id, "COG", "GAB", "GHA", "GIN", "GNQ", "KEN") | inlist(ihme_loc_id, "MLI", "MOZ", "MWI", "NGA", "SSD") | inlist(ihme_loc_id, "TCD", "TGO", "TZA", "UGA", "ZMB", "ZWE") | inlist(ihme_loc_id, "KEN_35619", "KEN_35620", "KEN_35624", "KEN_35627", "KEN_35643") | inlist(ihme_loc_id, "BWA", "ETH", "GNB", "RWA", "SLE")
  
   merge m:1 ihme_loc_id year using "`inc_deaths_country_year'", nogen //vw: this merge assigns the same number of total_reported, undetected, and deaths per country-year to every country-sex-age e.g. in AGO 1980, total_reported = 306 for all combinations of age-sex

  generate age_adj = `adults' if age >= 20
  replace age_adj = `kids' if age < 20
  generate age0_20 = 0 
  replace age0_20 = 1 if age < 20
  
  bysort ihme_loc_id year age0_20: egen agegroup_pop = total(pop)
  generate perc_age = pop * age_adj / agegroup_pop

  foreach var of varlist total_reported undetected_* deaths_* {
    quietly replace `var' = `var' * perc_age
  }
  
  sort ihme_loc_id year age sex
  tempfile inc_deaths_country_year_age_sex
  save `inc_deaths_country_year_age_sex', replace

  keep ihme_loc_id location_id year sex age age_group_id pop total_reported undetected_* deaths_*
  save "`out_dir'/inc_deaths_country_year_age_sex.dta", replace

// Format for draw files
  forvalues i = 0/999 {
    quietly replace undetected_`i' = total_reported + undetected_`i'
    rename undetected_`i' inc_`i'
    quietly replace inc_`i' = inc_`i' / pop
  }

  tostring sex, replace
  tostring location_id, replace
  recast double age_group_id
  sort ihme_loc_id year age sex

// Set directories
   cap mkdir "`tmp_dir'/03_outputs/01_draws"
   cap mkdir "`tmp_dir'/03_outputs/01_draws/deaths"
   cap mkdir "`tmp_dir'/03_outputs/01_draws/cases"
  
  local death_dir "`tmp_dir'/03_outputs/01_draws/deaths"
  local inc_dir "`tmp_dir'/03_outputs/01_draws/cases"
  
 // Prep data for looping
  preserve
	keep location_id ihme_loc_id year sex age_group_id inc_*
    rename inc_* draw_*
    tempfile all_inc
    save `all_inc', replace
  restore, preserve
	keep location_id ihme_loc_id year sex age_group_id deaths_*
    rename deaths_* draw_*
    tempfile all_deaths
    save `all_deaths', replace
  restore, not

  use "`pop_env'", clear
  levelsof location_id, local(isos)
// Loop through sex, location_id, and year, keep only the relevant data, and outsheet the .csv of interest
  //Save incidence (measue id 6)
  foreach i of local isos {
    local iso "`i'"
	display in red "`iso'"
	
    use `all_inc', clear
    quietly keep if location_id=="`iso'"
    foreach sex in "1" "2" {
	foreach y in 1990 1995 2000 2005 2010 2015 {

      preserve
        quietly keep if year==`y' & sex == "`sex'"
		quietly count
		if r(N) > 0 {
			quietly keep age_group_id draw*
			append using `age0_1_zero_draws'
          }
          else {
            use `zeroes', clear
          }
          
		  quietly keep age_group_id draw*
		  sort age_group_id
		  format %16.0g draw_*
		  quietly outsheet using "`inc_dir'/6_`i'_`y'_`sex'.csv", comma replace
      restore
	  }
	  }
   }

   
    //Now Save deaths
  foreach i of local isos {
    local iso "`i'"
	display in red "`iso'"
	
    use `all_deaths', clear
    quietly keep if location_id=="`iso'"
    foreach sex in "1" "2" {
	forvalues y = 1980/2015 {

      preserve
        quietly keep if year==`y' & sex == "`sex'"
		quietly count
		if r(N) > 0 {
			quietly keep age_group_id draw*
			append using `age0_1_zero_draws'
          }
          else {
            use `zeroes', clear
          }
          
		  quietly keep age_group_id draw*
		  sort age_group_id
		  format %16.0g draw_*
		  quietly outsheet using "`death_dir'/death_`i'_`y'_`sex'.csv", comma replace
      restore	  

    }
    }
   }   

** ******************* NOW COMPUTE PREVALENCES *******************************

// Generate 1000 draws of the splitting proportion for sequela (Severe motor and cognitive impairment due
// to sleeping disorder and disfiguring skin disease): 70%-74% split based on GBD 2010, which refers to Blum et al. 2006,
// who report on presence of symptoms at admission of patients in treatment centers. For treated cases, we assume that
// duration of sleeping disorder is about half of the total duration of treated cases.
  clear
  local A1 = 1884  // cases with sleeping disorder (Blum et.al. 2006)
  local A2 = 2533 - `A1'  // cases without sleeping disorder
  forvalues i = 0/999 {
    local a1 = rgamma(`A1',1)
    local a2 = rgamma(`A2',1)
    local prop_sleep_`i' = `a1' / (`a1' + `a2')  // implies: prop_sleep ~ beta(positives,negatives)
  }
  
// Generate 1000 draws of total duration of symptoms in untreated cases (based on Checchi 2008 BMC Inf Dis)
  clear
  local mean = 1026 / 365  // average total duration in years
  local lower = 702 / 365
  local upper = 1602 / 365
  local sd = (ln(`upper')-ln(`lower'))/(invnormal(0.975)*2)
  local mu = ln(`mean') - 0.5*`sd'^2  // the mean of a log-normal distribution = exp(mu + 0.5*sigma^2)
  
  forvalues x = 0/999 {
    local duration_`x' = exp(rnormal(`mu',`sd'))
  }

// Estimate prevalence, based on reported cases (total_reported) and estimated undetected cases (deaths_*)
  use `inc_deaths_country_year', clear
  drop deaths_*

// Add bogus years as copies of last year to allow the following loop to estimate prevalence for the last year.
  forvalues y = 2015/2020 {
    quietly expand 2 if year == `y', g(new)
    quietly replace year = `y' + 1 if new == 1
    quietly drop new
  }

// Sum up prevalence of treated and untreated cases, assuming that untreated cases have been prevalent up to their death for a
// certain duration (stored in local "duration_#"). For untreated cases, we assume that halve the duration is spent with sleeping disorder
// (severe motor and cognitive impairment) and disfigurement (Checchi et al 2008). Treated (i.e. reported) cases are assumed to have
// been prevalent for 0.5 years, and for the fraction of treated cases that present with sleeping disorder, we assume that this is present
// for half the total duration and that the rest of the duration is spent suffering from disfiguring skin disease. Treated cases that don't
// present with sleeping disorder are assigned disfigurement for the entire duration.
  sort ihme_loc_id year
  forvalues y = 0/999 {
  // Calculate number of prevalent cases based on reported incident cases in the current year
    quietly generate prev_total_`y' = .5 * total_reported
    quietly generate prev_sleep_`y' = `prop_sleep_`y'' * total_reported * 0.25
    quietly generate prev_disf_`y' = prev_total_`y' - prev_sleep_`y'

  // Number of years from which we will add all mortality cases
    local full_year = floor(`duration_`y'')

  // Add undetected cases from coming years, as appropriate given the duration
    forvalues n = 1/`full_year' {
      quietly bysort ihme_loc_id: replace prev_total_`y' = prev_total_`y' + undetected_`y'[_n+`n'] if `n' > 0
      quietly bysort ihme_loc_id: replace prev_sleep_`y' = prev_sleep_`y' + 0.5 * undetected_`y'[_n+`n'] if `n' > 0
      quietly bysort ihme_loc_id: replace prev_disf_`y' = prev_disf_`y' + 0.5 * undetected_`y'[_n+`n'] if `n' > 0
      
      if `n' == `full_year' | `n' == 0 {
        quietly bysort ihme_loc_id: replace prev_total_`y' = prev_total_`y' + undetected_`y'[_n+`n'+1] * (`duration_`y'' - `full_year')
        quietly bysort ihme_loc_id: replace prev_sleep_`y' = prev_sleep_`y' + 0.5 * undetected_`y'[_n+`n'+1] * (`duration_`y'' - `full_year')
        quietly bysort ihme_loc_id: replace prev_disf_`y' = prev_disf_`y' + 0.5 * undetected_`y'[_n+`n'+1] * (`duration_`y'' - `full_year')
      }
	  
      quietly count if missing(prev_total_`y') & year <= 2015
      assert r(N) == 0
      quietly count if missing(prev_sleep_`y') & year <= 2015
      assert r(N) == 0
      quietly count if missing(prev_disf_`y') & year <= 2015
      assert r(N) == 0
      
    }
  }

  keep if year <= 2015
  keep ihme_loc_id location_id year prev_*

  tempfile prev
  save `prev', replace


// Split by age and sex
  use "`prev'", clear
  merge 1:m ihme_loc_id year using "`pop_env'", keep(master match) keepusing(ihme_loc_id location_id year sex age age_group_id pop envelope) nogen
  
  sort ihme_loc_id year age sex
  order ihme_loc_id location_id year age age_group_id sex pop env prev_total* prev_sleep* prev_disf*
  
  tempfile total_prevalence
  save `total_prevalence', replace

// Split prevalence estimates by same proportions as for incidence and deaths
  use `total_prevalence', clear

  generate age_adj = `adults' if age >= 20
  replace age_adj = `kids' if age < 20
  generate age0_20 = 0 
  replace age0_20 = 1 if age < 20
  sort ihme_loc_id year age sex
  
  bysort ihme_loc_id year age0_20: egen agegroup_pop = total(pop)
  generate perc_age = pop*age_adj/agegroup_pop

  foreach var of varlist prev_* {
    quietly replace `var' = `var' * perc_age
  }

  sort ihme_loc_id year age sex
  keep year ihme_loc_id location_id sex age age_group_id pop prev_*

  save "`out_dir'/prev_country_year_age_sex.dta", replace

// Format for draw files
  foreach var of varlist prev_* {
    quietly replace `var' = `var' / pop
  }
  
  keep if inlist(year,1990,1995,2000,2005,2010,2015)
  tostring sex, replace
  recast double age_group_id
  sort ihme_loc_id year age sex
  
// Create directories for draw files on cluster
  cap mkdir "`tmp_dir'/03_outputs/01_draws"
  cap mkdir "`tmp_dir'/03_outputs/01_draws/cases"
  cap mkdir "`tmp_dir'/03_outputs/01_draws/disfigure"
  cap mkdir "`tmp_dir'/03_outputs/01_draws/sleep"
  
  local cases_dir "`tmp_dir'/03_outputs/01_draws/cases"
  local disf_dir "`tmp_dir'/03_outputs/01_draws/disfigure"
  local sleep_dir "`tmp_dir'/03_outputs/01_draws/sleep"

// Get the current date for archiving the mother file
  levelsof location_id, local(isos)
  
  preserve
    keep ihme_loc_id location_id year sex age age_group_id prev_total_*
    rename prev_total_* draw_*
    tempfile cases
    save `cases', replace
  restore, preserve
    keep ihme_loc_id location_id year sex age age_group_id prev_disf_*
    rename prev_disf_* draw_*
    tempfile disf
    save `disf', replace
  restore, preserve
    keep ihme_loc_id location_id year sex age age_group_id prev_sleep_*
    rename prev_sleep_* draw_*
    tempfile sleep
    save `sleep', replace
  restore, not

  use `pop_env', clear
  levelsof location_id, local(isos)
  levelsof year, local(years)
  
// Loop through sex, location_id and year, keep only the relevant data, and outsheet the .csv of interest: prevalence (measue id 5) 
  foreach i of local isos {
    display in red "`i'"
    
    use `cases', clear
    quietly keep if location_id==`i'
    
    foreach sex in "1" "2" {
    foreach y of local years {

      preserve
        quietly keep if year==`y' & sex == "`sex'"
        quietly keep age_group_id draw*
        append using `age0_1_zero_draws'
		sort age_group_id
        format %16.0g draw_*
		quietly outsheet using "`cases_dir'/5_`i'_`y'_`sex'.csv", comma replace
      restore

    }
    }
    
    use `disf', clear
    quietly keep if location_id==`i'
    
    foreach sex in "1" "2" {
    foreach y of local years {

      preserve
        quietly keep if year==`y' & sex == "`sex'"
        quietly keep age_group_id draw*
        append using `age0_1_zero_draws'
		sort age_group_id
        format %16.0g draw_*
		quietly outsheet using "`disf_dir'/5_`i'_`y'_`sex'.csv", comma replace
      restore

    }
    }
    
    use `sleep', clear
    quietly keep if location_id==`i'
    
    foreach sex in "1" "2" {
    foreach y of local years {

      preserve
        quietly keep if year==`y' & sex == "`sex'"
        quietly keep age_group_id draw*
        append using `age0_1_zero_draws'
		sort age_group_id
        format %16.0g draw_*
		quietly outsheet using "`sleep_dir'/5_`i'_`y'_`sex'.csv", comma replace
      restore

    }
    }
  }

******************* NOW COMPUTE INCIDENCE OF SEQUELAE *******************************
clear
use "`out_dir'/inc_deaths_country_year_age_sex.dta", replace
drop deaths_*

// Format for draw files
  forvalues i = 0/999 {
    quietly replace undetected_`i' = total_reported + undetected_`i'
    rename undetected_`i' inc_`i'
  }
  
 // Prep data for looping
	keep location_id ihme_loc_id year sex age_group_id inc_* pop
    rename inc_* draw_*
    tempfile all_inc_cases
    save `all_inc_cases', replace

//Split incidence into the two sequela: skin disfigurement and sleeping disorder: 70%-74% split based on GBD 2010, which refers to Blum et al. 2006
  use "`all_inc_cases'", replace
  sort ihme_loc_id year age_group_id sex
  forvalues y = 0/999 {
  // Calculate number of incident cases based on all incident cases assume same proportion in treated and unterated cases
    quietly generate inc_total_`y' = draw_`y'
    quietly generate inc_sleep_`y' = `prop_sleep_`y'' * draw_`y'
    quietly generate inc_disf_`y' = inc_total_`y' - inc_sleep_`y'
	}

  sort ihme_loc_id year age_group_id sex
  keep ihme_loc_id location_id year age_group_id sex inc_* pop

  save "`out_dir'/all_inc_cases_country_year_age_sex.dta", replace
  
  // Format for draw files
  foreach var of varlist inc_* {
    quietly replace `var' = `var' / pop
  }
  
  tempfile inc
  save `inc', replace	

  keep if inlist(year,1990,1995,2000,2005,2010,2015)
  tostring sex, replace
  recast double age_group_id
  sort ihme_loc_id year age sex
 
// Save incidence by sequelae
  levelsof location_id, local(isos)
  preserve
    keep ihme_loc_id location_id year sex age age_group_id inc_disf_*
    rename inc_disf_* draw_*
    tempfile inc_disf
    save `inc_disf', replace
  restore, preserve
    keep ihme_loc_id location_id year sex age age_group_id inc_sleep_*
    rename inc_sleep_* draw_*
    tempfile inc_sleep
    save `inc_sleep', replace
  restore, not
  
// Loop through sex, location_id and year, keep only the relevant data, and outsheet the .csv of interest: incidence (measue id 6) 
  use `pop_env', clear
  levelsof location_id, local(isos)
  levelsof year, local(years)
  
  foreach i of local isos {
    display in red "`i'"

    use `inc_disf', clear
    quietly keep if location_id==`i'
    
    foreach sex in "1" "2" {
    foreach y in 1990 1995 2000 2005 2010 2015 {

      preserve
        quietly keep if year==`y' & sex == "`sex'"
		quietly count
		if r(N) > 0 {
			quietly keep age_group_id draw*
			append using `age0_1_zero_draws'
          }
          else {
            use `zeroes', clear
          }
        quietly keep age_group_id draw*
		sort age_group_id
        format %16.0g draw_*
		quietly outsheet using "`disf_dir'/6_`i'_`y'_`sex'.csv", comma replace
      restore

    }
    }
    
    use `inc_sleep', clear
    quietly keep if location_id==`i'
    
    foreach sex in "1" "2" {
    foreach y in 1990 1995 2000 2005 2010 2015 {

      preserve
        quietly keep if year==`y' & sex == "`sex'"
		quietly count
		if r(N) > 0 {
			quietly keep age_group_id draw*
			append using `age0_1_zero_draws'
          }
          else {
            use `zeroes', clear
          }
        quietly keep age_group_id draw*
		sort age_group_id
        format %16.0g draw_*
		quietly outsheet using "`sleep_dir'/6_`i'_`y'_`sex'.csv", comma replace
      restore

    }
    }
  }


// Save deaths (upload to the cod tool)
quietly do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
 save_results, cause_id(350) description("ntd_afrtryp deaths: undetected cases + 0.7-6.0 percent of detected cases; CDR predicted from screening coverage; agepattern from regression") in_dir("`death_dir'") mark_best(yes)

// Save incidence and prevalence (upload to the epi tool)
// disfigurement
  save_results, modelable_entity_id(1463) description("ntd_afrtryp disfigurement: untreated cases spend half their total duration in disfig; treated cases spend all time but duration spent in sleep disorder") in_dir("`disf_dir'") metrics(incidence prevalence) mark_best(yes)

// motor/cognitive impairment due to sleep disorder
  save_results, modelable_entity_id(1464) description("ntd_afrtryp sleep disorder: untreated cases spend half their total duration in sleep disorder; 75 percent of treated cases spend 0.25 of their time in sleep disorder") in_dir("`sleep_dir'") metrics(incidence prevalence) mark_best(yes)

// save the PARENT results, upload to the epi tool  
  save_results, modelable_entity_id(1462) description("ntd_afrtryp parent: undetected + 0.7-6.0 percent of detected = dead; CDR predicted from screening coverage; duration treated is 6 months, untreated 3 years") in_dir("`cases_dir'") metrics(incidence prevalence) mark_best(yes)

  
// CHECK FILES

	// write check file to indicate step has finished
		file open finished using "`out_dir'/finished.txt", replace write
		file close finished
		
	// if step is last step, write finished.txt file
		local i_last_step 0
		foreach i of local last_steps {
			if "`i'" == "`this_step'" local i_last_step 1
		}
		
		// only write this file if this is one of the last steps
		if `i_last_step' {
		
			// account for the fact that last steps may be parallel and don't want to write file before all steps are done
			local num_last_steps = wordcount("`last_steps'")
			
			// if only one last step
			local write_file 1
			
			// if parallel last steps
			if `num_last_steps' > 1 {
				foreach i of local last_steps {
					local dir: dir "root_j_dir/03_steps/`date'" dirs "`i'_*", respectcase
					local dir = subinstr(`"`dir'"',`"""',"",.)
					cap confirm file "root_j_dir/03_steps/`date'/`dir'/finished.txt"
					if _rc local write_file 0
				}
			}
			
			// write file if all steps finished
			if `write_file' {
				file open all_finished using "root_j_dir/03_steps/`date'/finished.txt", replace write
				file close all_finished
			}
		}
		
	// close log if open
		if `close_log' log close
		
  