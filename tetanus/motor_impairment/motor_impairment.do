
** Prep : (1) Mild motor impairment due to neonatal tetanus parent; (2) Moderate to severe motor impairment due to neonatal tetanus parent

** set up
	clear *
	set more off
	
	// locals 
	            local acause tetanus
				local model_version_id v2
				local measure prevalence
				local measure_id 5	

** Bring in incidence draws
use "`acause'_inc_draws_`model_version_id'.dta", clear

** Keep only neonates
   keep if age_group_id<=3
   tempfile inc_draw
   save `inc_draw', replace

**calculate "incidence of survival" and "proportion of mild mortor impairment" among survival 
use `inc_draw', clear
forvalues x = 0/999 {
		** calculate incidence of survival= incidence*(1-cfr)
		gen surv_draw_`x' = inc_draw_`x'*(1-cfr_draw_`x')
		** apply proportion of mild mortor impairment based on a meta-anlaysis
		gen mild_draw_`x' =surv_draw_`x' * 0.11
			}
** calculate mean and standard error 			
egen mild_mean = rowmean(mild_draw*)
egen mild_lower=rowpctile(mild_draw*), p(2.5)
replace mild_lower=0 if mild_lower<0
egen mild_upper=rowpctile(mild_draw*), p(97.5)

export excel using "mild_impairment.xlsx", firstrow(variables) nolabel replace


**calculate "incidence of survival" and "proportion of moderate to severe mortor impairment" among survival 
use `inc_draw', clear
forvalues x = 0/999 {
		** calculate incidence of survival= incidence*(1-cfr)
		gen surv_draw_`x' = inc_draw_`x'*(1-cfr_draw_`x')
		** apply proportion of moderate to severe motor impairment based on a meta-anlaysis 
		gen modsev_draw_`x' =surv_draw_`x' * 0.07
			}

** calculate mean and standard error 			
egen modsev_mean = rowmean(modsev_draw*)
egen modsev_lower=rowpctile(modsev_draw*), p(2.5)
replace modsev_lower=0 if modsev_lower<0
egen modsev_upper=rowpctile(modsev_draw*), p(97.5)

tempfile modsev
save `modsev', replace

export excel using "modsev_impairment.xlsx", firstrow(variables) nolabel replace



