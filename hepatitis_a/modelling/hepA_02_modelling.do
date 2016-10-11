* BOILERPLATE *
  clear all
  set more off
  set maxvar 5000

  
  if c(os) == "Unix" {
    local j "/home/j"
    set odbcmgr unixodbc
    }
  else if c(os) == "Windows" {
    local j "J:"
    }
	
  adopath + `j'/WORK/10_gbd/00_library/functions
  


* BRING IN DATA FOR MODELLING *	
use `j'/WORK/04_epi/02_models/01_code/06_custom/hepatitis/inputs/hepA_modellingData.dta,clear

gen highIncome = super_region_name=="High-income"
gen lnAge = ln(ageMid)
recode sex_id 1=-1 3=0 2=1, gen(sexOrdered)

gen include = is_outlier==0 & (mean>.5 | ageMid<20 | highIncome==1) & (mean>0.7 | ageMid<40 | highIncome==1) & !(super_region_name=="High-income" & mean>0.7 & !missing(mean) & ageMid<50) 

gen lnWlCapped = lnWL
replace lnWlCapped = 1.5 if lnWlCapped>1.5



* IMPLEMENT SYMMETRIC OFFSET *
generate adjustment = (0.5-mean)*0.00002
generate cllPrev = cloglog(mean+adjustment)

* RUN MODEL *
capture drop fixed random* prediction

meglm cllPrev lnWlCapped sexOrdered if include==1, offset(lnAge) || super_region_id: || region_id: || country_id: || location_id: 
  predict fixed, fixedonly
  predict fixedSe, fixedonly stdp
  predict random*, remeans reses(randomSe*) 
  
  foreach var of varlist randomSe* {
    quietly sum `=subinstr("`var'", "Se", "", .)'
	replace `var' = `r(sd)' if missing(`var')
    replace `=subinstr("`var'", "Se", "", .)' = 0 if missing(`=subinstr("`var'", "Se", "", .)')
	}
	
	


preserve
keep if toModel==1 | missing(mean)
keep location_id year_id age_group_id ageMid sex_id mean_pop cfAlpha cfBeta fixed* random* toModel
save J:/WORK/04_epi/02_models/01_code/06_custom/hepatitis/inputs/hepA_modelCoefficientsFull.dta, replace
restore


keep if toModel==1
keep location_id year_id age_group_id ageMid sex_id mean_pop cfAlpha cfBeta fixed* random*

save `j'/WORK/04_epi/02_models/01_code/06_custom/hepatitis/inputs/hepA_modelCoefficients.dta, replace
