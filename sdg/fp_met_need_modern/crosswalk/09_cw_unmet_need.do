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
	use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\unmet_need\unmet_need_for_crosswalking.dta", clear
	qui levelsof gbd_super_region, local(sr)
	qui levelsof agegroup, local(age)
	
// logit transform the variables
	gen logit_met_need_all = logit(met_need_modern_prev)
	gen logit_met_need_cm = logit(met_need_modern_curr_prev)
	gen pred_logit_met_need_cm=.
	gen pred_logit_met_need_all2=.
	

// II) regress at the super-regional level withOUT fraction-married as covariate
	foreach s of local sr {
		foreach a of local age {
		
			disp "***********************************"
			disp "***********************************"
			disp "Regression for super-region `s' & agegroup `a' WITHOUT fraction-married"
		
			** determine if there's any data in the superregion-agegroup
			sum logit_met_need_all if gbd_super_region==`s' & agegroup==`a' & logit_met_need_cm !=., meanonly
			
			if r(N)>0 {
					
					
				** B) currently-married
					regress logit_met_need_all logit_met_need_cm if gbd_super_region==`s' & agegroup==`a'
					qui predict y if gbd_super_region==`s' & agegroup==`a'
					
					replace pred_logit_met_need_all2 = y if pred_logit_met_need_all2==.
					drop y
			}
			
			** if there's no data in superregion-agegroup, go back to top of loop
			else continue
		}
	}
	cap log close
	
// generate a tag to indicate whether a variable was estimated or is in its original form
	gen cw_mstatus=1 if met_need_modern_prev ==. & met_need_modern_curr_prev !=.
	replace cw_mstatus=0 if met_need_modern_prev!=.
	label var cw_mstatus "Met_need_modern_prev estimate used mstatus cross-walk"
	
// inverse logit the predictions
	foreach x in met_need_cm  met_need_all2 {
		replace pred_logit_`x' = invlogit(pred_logit_`x')
		rename pred_logit_`x' pred_`x'
	}
	
// replace modall_prev with prediction (in rank order) if missing
	replace met_need_modern_prev = pred_met_need_cm if met_need_modern_prev==.
	replace met_need_modern_prev = pred_met_need_all2 if met_need_modern_prev==.
	
// drop extraneous variables
	drop logit_met_need_all logit_met_need_cm  pred_met_need_cm pred_met_need_all2  
	order iso3 year agegroup countryname_ihme ihme_country gbd_developing gbd_region ///
		gbd_super_region wb_income_group_short survey filename sample report_data ///
		cw_mstatus met_need_modern_prev met_need_modern_var  
	

// save as new dataset
	save "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\output\crosswalked_met_need_marital_status.dta", replace
	