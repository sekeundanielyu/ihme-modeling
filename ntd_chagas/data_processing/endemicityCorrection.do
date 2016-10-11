


/********************************************************************************\		
                                BOILERPLATE & SETUP 
\********************************************************************************/ 

	clear all 
	set maxvar 30000
	set more off 
	
  if c(os) == "Unix" {
    local j "/home/j"
    set odbcmgr unixodbc
    }
  else if c(os) == "Windows" {
    local j "J:"
    }
	
  * RUN & EXECUTE 'GRABLOCALS' FUNCTION THAT PASSES IN NEEDED LOCALS *
	run `j'/WORK/04_epi/02_models/01_code/06_custom/chagas/code/grabLocals.ado
	grabLocals
	
  * PUT RETURNED RESULTS FROM 'GRABLOCALS' INTO STANDARD LOCALS *	
	foreach i in currentModel dirDismodPosterior dirCustomChagas dirYldMother dirYldCustom { 
		local `i' `r(`i')'
		}
		
  * DEFINE OUTPUT DIRECTORIES *
	local acuteOutDir  `j'/temp/strUser/chagasTemp/acute
	local cardioOutDir `j'/temp/strUser/chagasTemp/cardio
	local digestOutDir `j'/temp/strUser/chagasTemp/digest
	
	
	run `j'/WORK/10_gbd/00_library/prod/fastcollapse.ado
	
  tempfile par
  use `dirCustomChagas'/data/chagasPopulationAtRisk.dta, clear
  save `par'

  
  
/********************************************************************************\		
      MERGE CHAGAS PREVALENCE DRAWS DATASET & PROPORTION @ RISK DATASET 
\********************************************************************************/ 

    import excel "J:\WORK\04_epi\01_database\02_data\ntd_chagas\03_review\03_temp\Chagas Seroprevalence Extraction_20140904-JDS.xlsx", sheet("Sheet1") firstrow clear
	drop if missing(acause)
	tempfile appendTemp
	save `appendTemp', replace
	
	import excel "J:\WORK\04_epi\01_database\02_data\ntd_chagas\03_review\03_temp\Chagas Seroprevalence Extraction_part2b.xlsx", sheet("Sheet2") firstrow clear
	drop if missing(acause)
	tempfile appendTemp
	save `appendTemp', replace
	
	import delimited J:\WORK\04_epi\01_database\02_data\ntd_chagas\03_review\03_temp\ntd_chagas_2014_08_08-cleaningJDS.csv, bindquote(strict) clear
	append using `appendTemp', force
	
	replace description = "gbd 2013 review: ntd_chagas" if missing(description)
	replace orig_unit_type = "Rate per capita" if missing(orig_unit_type)
	replace orig_uncertainty_type = "ESS" if missing(orig_uncertainty_type)
	replace parameter_type = "Prevalence" if missing(parameter_type)
	replace is_raw = "raw" if missing(is_raw)
	replace sample_size = denominator if missing(sample_size)
	
	gen year = round((year_start + year_end)/2)
	
	replace iso3 = "MEX" + "_" + string(location_id) if missing(iso3) & inrange(location_id, 1000, .)
	
	merge m:1 iso3 year using `par', keep(master match)  nogenerate
 
	replace numerator = mean * sample_size if missing(numerator)
	
	expand 2 if cv_endemic==1 & !missing(prAtRisk), gen(newObs)
	replace newObs = . if !(cv_endemic==1 & !missing(prAtRisk))
	
	* mark and exclude old raw values *
	replace data_status = "exclude" if newObs==0
	replace notes = "Original values from endemic areas, not adjusted for population at risk." + notes if newObs==0
	
	* mark and adjust new values to account for population at risk *
	replace is_raw = "adjusted" if newObs==1
	replace notes = "Values have been adjusted to account for population at risk." + notes if newObs==1
	
	replace numerator = numerator * prAtRisk if newObs==1
	replace mean = numerator / sample_size if missing(mean) | newObs==1
	
	foreach var of varlist lower upper standard_error {
		replace `var' = . if newObs==1
		}
	
   replace standard_error = sqrt(1/sample_size * mean * (1 - mean) + 1/(4 * sample_size^2) * invnormal(0.975)^2)  if missing(standard_error)  
 
   replace lower = 1/(1 + 1/sample_size * invnormal(0.975)^2) * (mean + 1/(2*sample_size) * invnormal(0.975)^2 - invnormal(0.975) * sqrt(1/sample_size * mean * (1 - mean) + 1/(4*sample_size^2) * invnormal(0.975)^2)) if missing(lower)
   
   replace lower = 0 if mean==0 | lower<0
   
   replace upper = 1/(1 + 1/sample_size * invnormal(0.975)^2) * (mean + 1/(2*sample_size) * invnormal(0.975)^2 + invnormal(0.975) * sqrt(1/sample_size * mean * (1 - mean) + 1/(4*sample_size^2) * invnormal(0.975)^2))  ///
   if missing(upper)
   
   replace upper = 1 if mean==1 | upper>1
   
   replace cv_donors = 0 if missing(cv_donors)
   replace cv_endemic = 0 if missing(cv_endemic)
   
   drop year - prAtRisk newObs
   
   export delimited using J:\WORK\04_epi\01_database\02_data\ntd_chagas\03_review\05_upload\ntd_chagas_2014_10_03.csv, replace
