* July 16, 2010
* Crosswalk from curr-marr'd and ever-marr'd to all women

clear all 
set mem 700m
set more off
set maxvar 32000
cap restore, not
set trace off
cap log close


// open the dataset
	use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\modern_contra\modern_contra_for_crosswalking.dta", clear
	qui levelsof gbd_super_region, local(sr)
	qui levelsof agegroup, local(age)
	
// logit transform the variables
	gen logit_modall = logit(modall_prev)
	gen logit_modcm = logit(modcurrmarr_prev)
	gen logit_modem = logit(modevermarr_prev)
	gen pred_logit_modall_em=.
	gen pred_logit_modall_cm=.
	gen pred_logit_modall2=.
	

// II) regress at the super-regional level withOUT fraction-married as covariate
	foreach s of local sr {
		foreach a of local age {
		
			disp "***********************************"
			disp "***********************************"
			disp "Regression for super-region `s' & agegroup `a' WITHOUT fraction-married"
		
			** determine if there's any data in the superregion-agegroup
			sum logit_modall if gbd_super_region==`s' & agegroup==`a' & (logit_modem!=. | logit_modcm!=.), meanonly
			
			if r(N)> 5 {
					
				** A) ever-married
					regress logit_modall logit_modem if gbd_super_region==`s' & agegroup==`a'
					qui predict x if gbd_super_region==`s' & agegroup==`a'
					
					replace pred_logit_modall2 = x if pred_logit_modall2==.
					drop x
					
				** B) currently-married
					regress logit_modall logit_modcm if gbd_super_region==`s' & agegroup==`a'
					qui predict y if gbd_super_region==`s' & agegroup==`a'
					
					replace pred_logit_modall2 = y if pred_logit_modall2==.
					drop y
			}
			
			** if there's no data in superregion-agegroup, go back to top of loop
			else continue
		}
	}
	cap log close
	
// generate a tag to indicate whether a variable was estimated or is in its original form
	gen cw_mstatus=1 if modall_prev==. & (modevermarr_prev!=. | modcurrmarr_prev!=.)
	replace cw_mstatus=0 if modall_prev!=.
	label var cw_mstatus "Modall_prev estimate used mstatus cross-walk"
	
// inverse logit the predictions
	foreach x in modall_em modall_cm modall2 {
		replace pred_logit_`x' = invlogit(pred_logit_`x')
		rename pred_logit_`x' pred_`x'
	}
	
// replace modall_prev with prediction (in rank order) if missing
	replace modall_prev = pred_modall_em if modall_prev==.
	replace modall_prev = pred_modall_cm if modall_prev==.
	replace modall_prev = pred_modall2 if modall_prev==.
	
// drop extraneous variables
	drop logit_modall logit_modcm logit_modem pred_modall_em pred_modall_cm pred_modall2 
	order iso3 year agegroup countryname_ihme ihme_country gbd_developing gbd_region ///
		gbd_super_region wb_income_group_short survey filename sample report_data ///
		cw_age cw_mstatus modall_prev 
	

// save as new dataset
	save "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\output\crosswalked_modern_contra_marital_status.dta", replace
	