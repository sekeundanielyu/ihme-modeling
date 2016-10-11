** *******************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 			2 March 2015
// Project:		RISK
// Purpose:		Run custom meta-analysis for intimate partner violence and abortion, then save draws on clustertmp and mean and 95% CI on J drive. Note that we are using the same relative risks for other IPV-related outcomes that we did for GBD 2010. 
** **************************************************************************
** RUNTIME CONFIGURATION
** **************************************************************************
// Set preferences for STATA
		clear all
		set more off
		set scheme s1color
		cap restore, not
	
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}

// Set seed for random draws
	set seed 55616167
	
// Set macros for relevant file locations
	local version 1 // increase by 1 every time something changes
	cd "$prefix/WORK/05_risk/risks/abuse_ipv_exp/data/rr/prepped"
	cap mkdir "/WORK/05_risk/risks/abuse_ipv_exp/data/rr/prepped/`version'"
	local clustertmpdir "/snfs3/WORK/05_risk/02_models/02_results/abuse_ipv_exp/rr/`version'"
	cap mkdir "`clustertmpdir'"
	
// Bring in component study citations and effect sizes and run meta-analysis
	import excel using "J:/WORK/05_risk/risks/abuse_ipv_exp/data/rr/raw/rr_component_studies.xlsx", firstrow clear
	rename *, lower
	keep if relativerisk == "IPV-abortion"
	metan effectsize lower upper, random

// Construct standard relative risk dataset in the format Stan would like
	** Make age variables even though the same relative risk is used for all ages
	clear 
	local ages 15 20 25 30 35 40 45
	local n_obs: word count `ages'
	set obs `n_obs'
	
	gen gbd_age_start = .
	forvalues i = 1/`n_obs' {
		local value: word `i' of `ages'
		replace gbd_age_start = `value' in `i'
	}
	gen gbd_age_end = gbd_age_start
	
	** Fill in other variables
	gen rr_mean = round(`r(ES)', .01)
	gen rr_lower = round(`r(ci_low)', .01)
	gen rr_upper = round(`r(ci_upp)', .01)
	gen risk = "abuse_ipv_exp"
	gen acause = "maternal_abort"
	gen sex = 2
	gen mortality = 1
	gen morbidity = 1
	gen parameter = "cat1"
	gen year = 0
		
	** Specify TMRED of zero IPV
	expand 2 if gbd_age_start == 0, gen(dup)
	replace gbd_age_end = 45 if dup == 1
	replace parameter = "cat2" if dup == 1
	foreach var in rr_mean rr_lower rr_upper {
		replace `var' = 1 if dup == 1
	}
	drop dup
	
	tempfile updated
	save `updated', replace
	
// Bring in most recent version of relative risks for all causes so that we can update abortion
	local old = `version' - 1
	insheet using "./`old'/rr_G.csv", comma clear
	merge 1:1 acause gbd_age_start gbd_age_end parameter using `updated', update replace nogen
	sort acause gbd_age_start gbd_age_end
	
// Save effect size and 95% CI  on J drive
	outsheet using "./`version'/rr_G.csv", comma replace
	
// Save draws on clustertmp for access by central PAF calculation
	** 1,000 draws from normal distribution
	gen stdev = ((ln(rr_upper)) - (ln(rr_lower))) / (2*invnormal(.975))
	forvalues d = 0/999 {
		gen rr_`d' = exp(rnormal(ln(rr_mean), stdev))
	}
	drop rr_mean rr_lower rr_upper stdev
	order risk acause gbd_age_start gbd_age_end sex mortality morbidity parameter year 
	outsheet using "`clustertmpdir'/rr_G.csv", comma replace
	
	
