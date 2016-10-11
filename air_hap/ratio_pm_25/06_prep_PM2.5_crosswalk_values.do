//Date: March 4 2015
//Purpose: Prep crosswalk values from the mixed effect model to generate Relative Risks


//Housekeeping
clear all
set more off
set maxvar 20000

//Set directories
	if c(os) == "Windows" {
		global j "J:"
		global i "I:"
		set mem 1g
	}
	if c(os) == "Unix" {
		global j "/home/j"
		global i "/home/i"
		set mem 2g
		set odbcmgr unixodbc
	}

//Set relevant locals
	local exp_factor_dir	"$j/WORK/2013/05_risk/01_database/02_data/air_hap/02_rr/04_models/output/pm_mapping/personal_exp_factor"
	local pm_output_2015	"$j/WORK/05_risk/risks/air_hap/02_rr/02_output/PM2.5 mapping/lit_db"
	local date 				"5Aug2016"
	set seed 				74658
	local filedate			"5Aug2016"
	
//Prep exposure factor extractions 
	insheet using "`exp_factor_dir'/personal_exposure_factor_PM2.5_03022015.csv", comma clear
//Generate necessary parameters in normal space
	**Ratio = estimate
	gen ratio = personal_pm/kitchen_pm
	
	**Calculate covariance: cov = Cov(X, Y ) = E(XY ) - E(X)E(Y)
	gen cov = ratio - (personal_pm*kitchen_pm)
	
	**Calculate sd if sd is not available
	replace personal_pm_sd = personal_pm_se*personal_ss^0.5 if personal_pm_sd==. & personal_pm_se!=.
	replace kitchen_pm_sd = kitchen_pm_se*kitchen_ss^0.5 if kitchen_pm_sd==. & kitchen_pm_se!=.
	
	**Calculate variance of the ratio 
	gen var = (personal_pm^2/kitchen_pm^2)*[(personal_pm_se^2/personal_pm^2) - ((2*0.6262*kitchen_pm_se*personal_pm_se)/(personal_pm*kitchen_pm)) +(kitchen_pm_se^2/kitchen_pm^2)]
	egen global_var = mean(var)
	
	**Standard error = standard error of the ratio
	gen se = var^0.5
	replace se = global_var^0.5 if se ==. 

//Transform parameters to log space
	gen estimate = ratio
	gen stderr = se
	
	gen logor = log(ratio)
	gen selogor = (se^2*(1/ratio^2))^0.5
	
//Meta-analysis 
	
	**Female
	metan logor selogor if group=="Female" & age_start>15, eform title(Personal Exposure Ratio: Women)
	local f_ratio = `r(ES)'
	local f_upper = `r(ci_upp)'
	local f_lower = `r(ci_low)'
	
	**Male
	metan logor selogor if group=="Male" & age_start>15, eform title(Personal Exposure Ratio: Men)
	local m_ratio = `r(ES)'
	local m_upper = `r(ci_upp)'
	local m_lower = `r(ci_low)'
	
	**Under5
	metan logor selogor if age_start<5, eform title(Personal Exposure Ratio: Children)
	local c_ratio = `r(ES)'
	local c_upper = `r(ci_upp)'
	local c_lower = `r(ci_low)'

	**generate draws
	local f_sd = ((ln(`f_upper')) - (ln(`f_lower'))) / (2*invnormal(.975))
	local m_sd = ((ln(`m_upper')) - (ln(`m_lower'))) / (2*invnormal(.975))
	local c_sd = ((ln(`c_upper')) - (ln(`c_lower'))) / (2*invnormal(.975))
	
	forvalues n = 0/999 {
	gen female_exp_factor_`n' = exp(rnormal(ln(`f_ratio'), `f_sd'))	
	gen male_exp_factor_`n' = exp(rnormal(ln(`m_ratio'), `m_sd'))
	gen child_exp_factor_`n' = exp(rnormal(ln(`c_ratio'), `c_sd'))
	}
		
	collapse child* male* female*, fast
	
	forvalues n = 0/999 {
	local f_ratio_`n' = female_exp_factor_`n'
	local m_ratio_`n' = male_exp_factor_`n'
	local c_ratio_`n' = child_exp_factor_`n'
}
	//Insheet GPR results
	use "`pm_output_2015'//lmer_pred_`date'.dta", clear

	keep ihme_loc_id year draw_*
	rename draw_1000 draw_0
	
	forvalues n = 0/999 {
			gen women_`n' = draw_`n'*`f_ratio_`n''
			gen men_`n' = draw_`n'*`m_ratio_`n''
			gen child_`n' = draw_`n'*`c_ratio_`n''
		}

foreach group in "women" "men" "child" 	{

	egen `group'_mean = rowmean(`group'_*)
	egen `group'_upper = rowpctile(`group'_*), p(97.5)
	egen `group'_lower = rowpctile(`group'_*), p(2.5)
	gen `group'_se = (`group'_upper - `group'_lower)/(2*1.96)
	
}

egen kitchen_mean = rowmean(draw_*)
egen kitchen_upper = rowpctile(draw_*), p(97.5)
egen kitchen_lower = rowpctile(draw_*), p(2.5)

//Clean up data
duplicates drop 

//Clean up data (draws of PM2.5)
keep ihme_loc_id year child_* women_* men_*
drop *mean *lower *upper *se

//Limit to GBD reporting years
keep if (year==1990 | year==1995 | year==2000 | year==2005 | year==2010 | year==2013| year==2015)

/* since there is no temperol difference/no covariates, only keep one year for speed */
keep if year==2015
drop year 
//Save 
outsheet using "`pm_output_2015'/PM2.5_draws_`filedate'.csv", comma replace

**************************************
************End of Code****************
**************************************