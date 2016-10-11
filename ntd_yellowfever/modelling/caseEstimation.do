
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
	 
  tempfile crossTemp appendTemp mergingTemp envTemp drawMaster sevInc zero
  
  local date = subinstr(trim("`: display %td_CCYY_NN_DD date(c(current_date), "DMY")'"), " ", "_", .)
   
  adopath + `j'/WORK/10_gbd/00_library/functions

   
* CREATE A LOCAL CONTAINING THE ISO3 CODES OF COUNTRIES WITH YELLOW FEVER *
  local yfCountries AGO ARG BEN BOL BRA BFA BDI CMR CAF TCD COL COG CIV COD ECU GNQ ETH GAB GHA GIN GMB GNB ///
     GUY KEN LBR MLI MRT NER NGA PAN PRY PER RWA SEN SLE SDN SSD SUR TGO TTO UGA VEN ERI SOM STP TZA ZMB
	 

* STORE FILE PATHS IN LOCALS *	
  local inputDir `j'/WORK/04_epi/02_models/01_code/06_custom/ntd_yellowfever/inputs 
  local ageDist  `inputDir'/ageDistribution.dta
  local cf       `inputDir'/caseFatalityAB.dta
  local ef       `inputDir'/expansionFactors.dta
  local data     `inputDir'/dataToModel.dta
  local skeleton `inputDir'/skeleton.dta
  
  local outDir /ihme/scratch/users/strUser/yellowFever
  capture mkdir `outDir'



/******************************************************************************\	
                            MODEL YELLOW FEVER CASES
\******************************************************************************/ 

  use `data', clear
  
  rename sex_id dataSexId
  rename year_start year_id
 
  replace effective_sample_size = mean_pop if missing(effective_sample_size)


  menbreg cases yearC if cases>0, exp(effective_sample_size) || countryIso:
    predict predFixed, fixedonly fitted nooffset
    predict predFixedSe, stdp nooffset
    predict predRandom, remeans reses(predRandomSe) nooffset

	bysort  region_id: egen regionRandom = mean(predRandom)
    replace predRandom = regionRandom if missing(predRandom)
	
	bysort  super_region_id: egen superRegionRandom = mean(predRandom)
    replace predRandom = superRegionRandom if missing(predRandom)

	replace predRandomSe = _se[var(_cons[countryIso]):_cons] if missing(predRandomSe)




  bysort countryIso year_id: egen cntryCases = mean(cases)
  replace cases = cntryCases if inlist(countryIso, "BRA", "KEN") & missing(cases) & !missing(cntryCases)
  bysort countryIso year_id: egen cntryMean = mean(mean)
  replace mean = cntryMean if inlist(countryIso, "BRA", "KEN") & missing(mean) & !missing(cntryMean)
  bysort countryIso year_id: egen cntrySe = mean(standard_error)
  replace standard_error = cntrySe if inlist(countryIso, "BRA", "KEN") & missing(standard_error) & !missing(cntrySe)


   drop age_group_id sex year_end
   rename mean_pop allAgePop

  
 
/******************************************************************************\	
   BRING IN THE DATA ON YELLOW FEVER AGE-SEX DISTRIBUTION, EF, & CASE FATALITY
\******************************************************************************/ 

  cross using `ageDist'
  merge m:1 countryIso using `ef', assert(3) nogenerate
  merge 1:1 location_id year_id age_group_id sex_id using `skeleton', assert(2 3) keep(3) nogenerate

 
  rename mean_pop ageSexPop
 
  keep ef_* year_id age_group_id sex sex_id location_id countryIso ihme_loc_id ageSexCurve pred* ageSexPop allAgePop mean standard_error cases effective sample_size location_name yfCountry 


  gen ageSexCurveCases = ageSexCurve * ageSexPop
  bysort location_id year_id: egen totalCurveCases = total(ageSexCurveCases)
  gen prAgeSex = ageSexCurveCases / totalCurveCases
  
  
  merge m:1 location_id year_id using `j'/WORK/04_epi/02_models/01_code/06_custom/ntd_yellowfever/inputs/braSubPr.dta, assert(1 3) nogenerate
  replace allAgePop = mean_pop_bra if !missing(mean_pop_bra)
  forvalues i = 0/999 {
    quietly replace braSubPr_`i' = 1 if missing(braSubPr_`i')
	}
	
  
  
/******************************************************************************\	
 
                                   CREATE DRAWS
								   
\******************************************************************************/ 

preserve
use `cf', clear
local deathsAlpha = alphaCf in 1
local deathsBeta = betaCf in 1
restore


local asympMu 0.55 
local asympSigma = (0.74 - 0.37) / (2 * invnormal(0.975))
local asympAlpha = `asympMu' * (`asympMu' - `asympMu' ^ 2 - `asympSigma' ^2) / `asympSigma' ^2 
local asympBeta  = `asympAlpha' * (1 - `asympMu') / `asympMu'
	
local modMu 0.33 
local modSigma = (0.52 - 0.13) / (2 * invnormal(0.975)) 
local modAlpha = `modMu' * (`modMu' - `modMu' ^ 2 - `modSigma' ^2) / `modSigma' ^2 
local modBeta  = `modAlpha' * (1 - `modMu') / `modMu'

local sevMu = logit(0.12)  
local sevSigma = (logit(0.26) - logit(0.05)) / (2 * invnormal(0.975)) 
	

forvalues i = 0/999 {
    local _asympPr  = rbeta(`asympAlpha', `asympBeta')
	local inf_modPr = rbeta(`modAlpha', `modBeta')
	local inf_sevPr = invlogit(rnormal(`sevMu', `sevSigma'))
	local deathsPr  = rbeta(`deathsAlpha', `deathsBeta')
  
	local correction = `_asympPr' + `inf_modPr' + `inf_sevPr'
  
  
 	quietly {
	
	generate inc_`i' = exp(rnormal(predFixed, predFixedSe) + rnormal(predRandom, predRandomSe)) * allAgePop   
	replace  inc_`i' = rnormal(mean, standard_error) * exp(rnormal(0, predRandomSe)) * allAgePop if !missing(cases) & inc_`i'<cases  
	replace  inc_`i' = inc_`i' * prAgeSex * (ef_`i' / ((1 - `_asympPr') / `correction')) * braSubPr_`i' / ageSexPop  // convert to age-specific subnational rates for Brazil
	replace  inc_`i' = 0 if inc_`i'<0 | yfCountry==0 
	
	foreach state in _asymp inf_mod inf_sev {
		local `state'Pr = ``state'Pr' / `correction'
		generate `state'_`i' = inc_`i' * ``state'Pr' 
		}
	
	generate deaths_`i' = inf_sev_`i' * `deathsPr' * ageSexPop
	
	capture assert inc_`i' >= 0
	}
	if _rc!=0 {
	  di "NEGATIVE VALUES for draw_`i'!!!" 
	  local errors `errors' draw_`i'<0
	  }
	di "." _continue
	}



/******************************************************************************\	
 
                                  EXPORT DRAWS
								     
\******************************************************************************/ 


preserve

clear
set obs 20
generate age_group_id = _n + 1
forvalues i = 0/999 {
  quietly generate draw_`i' = 0
  }
export delimited using `outDir'/zero.csv, replace

restore


get_demographics, gbd_team(cod)
levelsof location_id if yfCountry==1, local(yfCntryIds) clean

generate int yearWindow = round(year_id, 5)
fastcollapse _asymp_* inf_mod_* inf_sev_*, by(location_id sex_id age_group_id yearWindow) type(mean)

rename yearWindow year
levelsof year, local(years) clean
levelsof location_id , local(yfCntryIds) clean


* NOTE: file name structure = `metric'_`location_id'_`year'_`sex'.csv"

foreach state in _asymp inf_mod inf_sev {	
  
  capture mkdir `outDir'/`state'	
  rename `state'_* draw_*
  
  foreach year in `years' {
    foreach location in $location_ids {
      foreach sex in $sex_ids {
	
	   	if `: list location in yfCntryIds' == 0 {
	      copy `outDir'/zero.csv `outDir'/`state'/6_`location'_`year'_`sex'.csv, replace
          }

		else {
		  export delimited age_group_id draw_* using `outDir'/`state'/6_`location'_`year'_`sex'.csv ///
            if location_id==`location' & sex_id==`sex' & year==`year', replace
		  }
		  
		  di "." _continue
		  }
		}
	  }
	rename draw_*  `state'_*
	}
	  


   
levelsof year, local(years) clean

   
	local u = 10                
	local s = 4/invnormal(0.975)
	local a = `u'^2 / `s'^2     
	local b = `s'^2 / `u'       
  
 foreach state in _asymp inf_mod inf_sev {	
    rename `state'_* draw_*
	forvalues i = 0/999 {
	  quietly {
	  local duration = rgamma(`a', `b') / 365.25 
      replace draw_`i' = draw_`i' * `duration' 
	  capture assert draw_`i' >= 0
	  }
	
	  if _rc!=0 {
	    di "NEGATIVE VALUES for draw_`i'!!!" 
	    local errors `errors' draw_`i'<0
	    } 
	  di "." _continue
      }  
    
				
  foreach year in `years' {
    foreach location in $location_ids {
      foreach sex in $sex_ids {
	
	   	if `: list location in yfCntryIds' == 0 {
	      copy `outDir'/zero.csv `outDir'/`state'/5_`location'_`year'_`sex'.csv, replace
          }

		else {
		  export delimited age_group_id draw_* using `outDir'/`state'/5_`location'_`year'_`sex'.csv ///
            if location_id==`location' & sex_id==`sex' & year==`year', replace
		  }
		  
		  di "." _continue
		  }
		}
	  }
	drop draw_*
	}
	


 
  
/******************************************************************************\	
                                SAVE RESULTS
\******************************************************************************/  


   
  run `j'/WORK/10_gbd/00_library/functions/save_results.do

  local _asympN  3338
  local inf_sevN 1511
  local inf_modN 1510 
  local deathsN  358
 
  save_results, cause_id(`deathsN') description("Deaths from yellow fever (version `version')") in_dir("`outDir'/deaths")  
  
  save_results, modelable_entity_id(`_asympN')  metrics(incidence prevalence) description("Asymptomatic infection with yellow fever (`date')") in_dir("`outDir'/_asymp")
  save_results, modelable_entity_id(`inf_modN') metrics(incidence prevalence) description("Moderate infection with yellow fever (`date')") in_dir("`outDir'/inf_mod")
  save_results, modelable_entity_id(`inf_sevN') metrics(incidence prevalence) description("Severe infection with yellow fever (`date')") in_dir("`outDir'/inf_sev")  

  
  di "ERROR REPORT:"
  di "`errors'"
  
/******************************************************************************\	
                                 ~ FIN ~
\******************************************************************************/    







