
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
 
  local outDir /ihme/scratch/users/strUser/dengue

  tempfile dengue covariates pop deaths income

*** ONTO THE MODELLING ***

use `j'/WORK/04_epi/02_models/01_code/06_custom/dengue/data/modelingData.dta, clear


gen lnRr2010 = ln(rrMean2010)
gen lnRrMean = ln(rrMean)
gen lnMean = ln(meanM)
gen lnTrend = lnRr2010
replace lnTrend = lnRrMean if region_name=="Oceania"


mkspline scoreS = score, cubic knots(-2 0 3)

  
menbreg casesM scoreS* lnTrend if denguePr>0, exp(sampleM) intmethod(mvaghermite)  || location_id:

  predict randomModel, reffects reses(randomModelSe) nooffset
  predict fixed, fixedonly fitted nooffset
  predict fixedSe, stdp fixedonly nooffset
  

gen efTemp = randomModel + ln(efTotal)
metan efTemp randomModelSe if modelled==0, nograph
generate random   = `r(ES)'
generate randomSe = `r(seES)' 
 
 
 

* CREATE THE 1000 DRAWS *
forvalues i = 0/999 {
  local fixedTemp  = rnormal(0,1)
  local randomTemp = rnormal(0,1)
  
  quietly {
	 
	 generate draw_`i' = exp(rnormal(fixed, fixedSe) + rnormal(random, randomSe)) * ef_`i' * mean_pop  
	 replace  draw_`i' = exp(rnormal(fixed, fixedSe) + rnormal(randomModel, randomModelSe)) * ef_`i' * mean_pop if inrange(randomModel, random, .) & !missing(mean)
	 replace  draw_`i' = 0 if denguePr==0 
	 	 
	 }

  di "." _continue
  }

  
 
  
fastcollapse draw_* mean_pop, by(location_id location_name yearWindow is_estimate) type(mean)
rename yearWindow year_id





* BRING IN AGE DISTRIBUTION DATASET *
rename mean_pop allAgePop

merge 1:m location_id year_id using `j'/WORK/04_epi/02_models/01_code/06_custom/dengue/data/ageSpecific.dta, assert(2 3) keep(3) nogenerate
keep year_id age_group_id sex_id location_id draw* *pop incCurve is_estimate	


generate casesCurve = incCurve * mean_pop
bysort year_id location_id: egen totalCasesCurve = total(casesCurve)

forvalues i = 0/999 {
  quietly {
  replace draw_`i' = casesCurve * draw_`i' / totalCasesCurve
  replace  draw_`i' = draw_`i' / mean_pop
  }
  di "." _continue
  }
  
fastrowmean draw_*, mean_var_name(casesMean)
fastpctile draw_*, pct(2.5 97.5) names(casesLower casesUpper)
foreach var of varlist cases* {
  replace `var' = `var' * mean_pop
  format `var' %12.0fc
  tabstat `var' if is_estimate==1, by(year_id) stat(n mean sum)
  }

  
  
  
* SEQUELA SPLIT *  
  
keep year_id location_id age_group_id sex_id draw_*
tempfile incTemp
save `incTemp', replace

gen id = _n
expand 3
bysort year_id location_id age_group_id sex_id: gen index = _n
generate seq = "mod"  if index==1
replace  seq = "sev"  if index==2
replace  seq = "post" if index==3
generate post = seq=="post"

generate modelable_entity_id = 1506 if seq == "mod"
replace  modelable_entity_id = 1507 if seq == "sev"
replace  modelable_entity_id = 1508 if seq == "post"

generate duration  = 6/365  if seq == "mod"  // Source of duration: Whitehead et al, doi: 10.1038/nrmicro1690
replace  duration  = 14/365 if seq == "sev"  // Source of duration: Whitehead et al, doi: 10.1038/nrmicro1690
replace  duration  = 0.5    if seq == "post" 

local modMu = 0.945 
local sevMu = 0.055 
local postMu = 0.084

local modSigma = 0.074   
local sevSigma = 0.00765 
local postSigma = 0.02 
  
foreach seq in mod sev post {
  local `seq'Alpha = ``seq'Mu' * (``seq'Mu' - ``seq'Mu'^2 - ``seq'Sigma'^2) / ``seq'Sigma'^2
  local `seq'Beta  = ``seq'Alpha' * (1 - ``seq'Mu') / ``seq'Mu'
  } 
  
forvalues i = 0/999 {
  foreach seq in mod sev post {
    local `seq'Pr = rbeta(``seq'Alpha', ``seq'Beta')
	}
  local correction = `modPr' + `sevPr'	
  local modPr = `modPr' / `correction' 
  local sevPr = `sevPr' / `correction' 

  foreach seq in mod sev post {
    quietly replace draw_`i' = draw_`i' * ``seq'Pr'  if seq=="`seq'"
	}
  }
	
  expand 2, gen(measure_id)
  replace measure_id = measure_id + 5
  
  forvalues i = 0/999 {
	quietly replace draw_`i' =  draw_`i' * duration if measure_id==5
	}
	
	
* EXPORT DRAW FILES *		
  
  keep location_id year_id sex_id age_group_id modelable_entity_id measure_id draw_*  
  
  local modN  1506 
  local sevN  1507
  local postN 1508
  
  foreach seq in mod sev post {
 	outsheet if modelable_entity_id==``seq'N' using `outDir'/inf_`seq'/inf_`seq'_dengueDraws.csv, comma replace
	}
    

	
* UPLOAD RESULTS *

run /home/j/WORK/10_gbd/00_library/functions/save_results.do 

foreach seq in mod sev post {
  capture rm `outDir'/inf_`seq'/all_draws.h5
  }
  
local spaceVar scoreS
local timeVar lnRr2010
  
save_results, modelable_entity_id(1506) description("Dengue fever (using `spaceVar' & `timeVar')") in_dir("/share/scratch/users/strUser/dengue/inf_mod") file_pattern("inf_mod_dengueDraws.csv") mark_best(yes)	
save_results, modelable_entity_id(1507) description("Severe dengue fever (using `spaceVar' & `timeVar')") in_dir("/share/scratch/users/strUser/dengue/inf_sev") file_pattern("inf_sev_dengueDraws.csv") mark_best(yes)	
save_results, modelable_entity_id(1508) description("Post-dengue fatigue (using `spaceVar' & `timeVar')") in_dir("/share/scratch/users/strUser/dengue/inf_post") file_pattern("inf_post_dengueDraws.csv") mark_best(yes)	
  
	
	

