** ****************************************************************************************************************************************************************
** INPUT: MEPS DATASET WITH MAPPED DW CODES
** PROCESS: MODEL THE CONTRIBUTION OF EACH CONDITION TO EACH MEASURE'S TOTAL DISABILITY (1000 Bootstraps -- Must be done on cluster)
** OUTPUT: 1000 Datasets with the counterfactual weight from each condition as modeled. For example: The anxiety files will have the estimated weight without anxiety. This is used in later steps to calculate severity distributions. Also save the predicted DWs for each condition for the model. This comes in useful in the COMO simulation done later on.
** ****************************************************************************************************************************************************************
** ****************************************************************************************************************************************************************
clear
set more off
set mem 1G

cd "$dir"

// bring in the dataset
use "$SAVE_DIR/2b_meps_lowess_r_interpolation", clear
merge 1:1 key using "$SAVE_DIR/2a_meps_prepped_to_crosswalk_chronic_conditions_only.dta", nogen

// these are not real observations - just an artifact of the crosswalk step
drop if dw != .

// the submit file will set the seeds as globals, this ensures each draw is independent from the other, and that the exact numbers are replicable.
di in red "$r"
set seed $r
bsample

// some dws were modeled as less than zero or more than 1, we truncate them here.
replace dw_hat = 1 if dw_hat > 1  & dw_hat != .
replace dw_hat = 0 if dw_hat < 0
drop if dw_hat == .

// furthermore, we use a logit transformation, so these need to be slightly apart from 1 and 0
replace dw_hat = .000001 if dw_hat < .000001
replace dw_hat = .999999 if dw_hat > .999999

// make a logit transformed DW, to be used as the response variable in the model
gen logit_dw_hat = logit(dw_hat)

// set up mata for reporting table
mata: COMO 	 		 		= J(1500, 1, "")
mata: AGE 		 			= J(1500, 1, .)
mata: DEPENDENT				= J(1500, 1, "")
mata: DW_T					= J(1500, 1, .)
mata: SE					= J(1500, 1, .)
mata: DW_S					= J(1500, 1, .)
mata: DW_O					= J(1500, 1, .)
mata: N						= J(1500, 1, .)
local c = 1

// the model.  the logit-transformed DW, all conditions, and random effect on individual ID.
xtmixed logit_dw_hat t*  || id:

// Loop through each condition and save the result
foreach como of varlist t*  {

	preserve
	di in red "CURRENTLY LOOPING THROUGH: `como'  "

	// keep only those with the condition in question
	predict re, reffects
	keep if  `como' == 1
		// predict for their DW and reverse logit it
		predict dw_obs // ADD RANDOM EFFECT IN@

		// replace dw_obs=dw_obs+re
		replace dw_obs = invlogit(dw_obs)

	// replace the condition in question to zero
	replace `como' = 0

	// now predict and inverse logit again. This will give the counterfactual DW (or their expected weight if they didnt have the condition in question)
	predict dw_s_`dependent'
		replace dw_s = dw_s // ADD RANDOM EFFECT IN@
		// replace dw_s_=dw_s_+re
		replace dw_s_`dependent' = invlogit(dw_s_`dependent')

	count

	// get the mean of the predictions above for the population with the condition
	sum dw_s
		if `r(N)' > 0 local mean_s = `r(mean)'
		else local mean_dw_s = .
	sum dw_obs
		if `r(N)' > 0 local mean_o = `r(mean)'
		else local mean_dw_o = .

	// Estimate the effect of the condition in question while correcting for comorbidities via the COMO equation
	gen dw_t_`dependent' = (1 - ((1-dw_obs)/(1-dw_s_`dependent')))

	// get the mean of this condition specific disability weight.
	count
	if `r(N)' != 0 {
		summ dw_t_`dependent'

		local mean_dw_tnoreplace = `r(mean)'
		local se = `r(sd)'
	}
	else {
		local mean_dw_tnoreplace = .
		local se = .
	}

	count
	local N = `r(N)'

	// fill in the reporting table with the summary measures captured above.
	mata: COMO[`c', 1]  	= "`como'"
	mata: DEPENDENT[`c', 1] = "logit"
	mata: DW_T[`c', 1] = `mean_dw_tnoreplace'
	mata: SE[`c', 1] = `se'
	mata: DW_S[`c', 1] 		= `mean_s'
	mata: DW_O[`c', 1]		= `mean_o'
	mata: N[`c', 1]     	= `N'

	keep id sex age_gr pcs mcs dw_hat dw_obs dw_s dw_t round
	rename dw_hat DW_data
	rename dw_obs DW_pred
	rename dw_s DW_counter
	rename dw_t DW_diff_pred
	g DW_diff_data = 1 - ((1- DW_data)/(1- DW_counter))

	// save bootstrap dataset
	cap mkdir "$SAVE_DIR/3a_meps_bootstrap_datasets"
	cap mkdir "$SAVE_DIR/3a_meps_bootstrap_datasets//${i}"
	save	  "$SAVE_DIR/3a_meps_bootstrap_datasets//${i}//`como'", replace

	restore
	local c = `c' + 1
}

clear

// grab complete reporting table and save it
getmata COMO DEPENDENT DW_T SE DW_S DW_O N

replace DW_S = . if DW_T == .
replace DW_O = . if DW_T == .
drop if COMO == ""

rename COMO como
rename DEPENDENT dependent
rename DW_T dw_t
rename SE se
rename DW_S dw_s
rename DW_O dw_o
rename N n

rename dw_t dw_t${i}
keep como dw_t
rename como condition

// save actual result
cap mkdir "$SAVE_DIR/3a_meps_dw_draws"
save	  "$SAVE_DIR/3a_meps_dw_draws//${i}.dta", replace

// END OF DO FILE
