//Estimates proportion of severity subgroups for Parkinson's Disease based on meta-analysis

use "C:\Users\strUser\Documents\GBD\Neurological\Fractions\PD_for_fractions.dta", clear

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

metan sev_prop lower_sev upper_sev, random lcols( Country mid_year) rcols(sample_size)  textsize(100)

metan mod_prop lower_mod upper_mod, random lcols( Country mid_year) rcols(sample_size)  textsize(100)

metan mild_prop lower_mild upper_mild, random lcols( Country mid_year) rcols(sample_size)  textsize(100)
