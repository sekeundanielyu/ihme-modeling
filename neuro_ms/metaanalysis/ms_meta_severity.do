//Estimates proportion of severity subgroups for Multiple Sclerosis based on meta-analysis

use "C:\Users\strUser\Documents\GBD\Neurological\Fractions\MS_for_frctions.dta", clear

//Preparation of data; generating SEs and CIs
gen se_prop_sev= (sev_prop*(1-sev_prop)/sample_size)^0.5
gen lower_sev= sev_prop-1.96* se_prop_sev
gen upper_sev= sev_prop+1.96* se_prop_sev
replace lower_sev=0 if  lower_sev<0
replace upper_sev=1 if  (upper_sev>1 & upper_sev!=.)

gen se_prop_mod= (mod_prop*(1-mod_prop)/sample_size)^0.5
gen lower_mod= mod_prop-1.96* se_prop_mod
gen upper_mod= mod_prop+1.96* se_prop_mod
replace lower_mod=0 if  lower_mod<0
replace upper_mod=1 if  (upper_mod>1 & upper_mod!=.)

gen se_prop_mild= (mild_prop*(1-mild_prop)/sample_size)^0.5
gen lower_mild= mild_prop-1.96* se_prop_mild
gen upper_mild= mild_prop+1.96* se_prop_mild
replace lower_mild=0 if  lower_mild<0
replace upper_mild=1 if  (upper_mild>1 & upper_mild!=.)

//Meta-analysis by income level(LMI vs. HI)
metan sev_prop lower_sev upper_sev, random lcols( Country midyear) rcols(sample_size)  textsize(100) by(income)

metan mod_prop lower_mod upper_mod, random lcols( Country midyear) rcols(sample_size)  textsize(100) by(income)

metan mild_prop lower_mild upper_mild, random lcols( Country midyear) rcols(sample_size)  textsize(100) by(income) 

//Metaregression by combinations of HSA2, LDI, i.income
metareg sev_prop health_system_access2 LDI_pc, wsse(se_prop_sev)
xi: metareg sev_prop health_system_access2 i.income, wsse(se_prop_sev)
xi: metareg sev_prop  i.income, wsse(se_prop_sev)

metareg mod_prop health_system_access2 LDI_pc, wsse(se_prop_mod)
xi: metareg mod_prop health_system_access2 i.income, wsse(se_prop_mod)
xi: metareg mod_prop  i.income, wsse(se_prop_mod)

metareg mild_prop health_system_access2 LDI_pc, wsse(se_prop_mild)
xi: metareg mild_prop health_system_access2 i.income, wsse(se_prop_mild)
xi: metareg mild_prop  i.income, wsse(se_prop_mild)
