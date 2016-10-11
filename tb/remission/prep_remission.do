// Prep remission 

// get prevalence data
use "prev_custom_age_updated.dta", clear
duplicates drop (location_id year sex age_cat), force
// merged on prepped incidence data
merge 1:1 location_id year age_cat sex using "inc_custom_age_cdr_adj.dta", keep(3)nogen
// merge on emr
merge 1:1 location_id year age_cat sex using "TB_csmr.dta", keepusing(mean_csmr se_csmr) keep(3)nogen

// calculate EMR as EMR=CSMR/prevalence
gen emr=mean_csmr/mean_prev
// calculate standard error of EMR 
gen se_emr=emr*sqrt((se_csmr/mean_csmr)^2+(se_prev/mean_prev)^2)

// calculate inc prev ratio
gen inc_prev_ratio=mean_inc_cdr/mean_prev

// calculate se for inc prev ratio
gen se_inc_prev_ratio=inc_prev_ratio*sqrt((se_mean_inc_cdr/mean_inc_cdr)^2+(se_prev/mean_prev)^2)

// calculate remission as rem=I/P-emr
gen mean_rem=inc_prev_ratio-emr
replace mean_rem=0 if mean_rem<0

// calculate se for remission as SErem= SEratio*meanrem/meanratio 
gen se_rem=(se_inc_prev_ratio*mean_rem)/inc_prev_ratio

merge m:1 location_id using "iso3.dta", keepusing (location_name) keep(3)nogen

// drop if the age gap is wider than 20 years
gen age_gap=age_end-age_start
drop if age_gap>20

// drop outliers
gen rem_too_low=0
replace rem_too_low=1 if mean_rem<0.2
gen rem_too_high=0
replace rem_too_high=1 if mean_rem>1.5

drop if rem_too_low==1
drop if rem_too_high==1

export excel using "remission_prepped.xlsx", firstrow(variables) nolabel replace

