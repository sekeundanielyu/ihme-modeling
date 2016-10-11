
	** 1. create crosswalks to make to put all data in the hearing data base into GBD severity categories: 20+, 35+, 50+, 65+, 80+, 95+

**************************************
** Prep Stata
**************************************	
	
	clear all
	cap log close
	set mem 1g
	set maxvar 20000
	set more off
	cap restore, not
	set type double, perm

	// reassign locals for group, date, and paths and directories (provided as arguments to this do-file from within 00_master.do)
		local group     = "`1'"
		local date      = "`2'"
		local prefix    = "`3'"
		local out_dir   = "`4'"
		local temp_dir  = "`5'"

	// define the date of the data prep run (YYYY_MM_DD)
	local date: display %td_CCYY_NN_DD date(c(current_date), "DMY")
	local date = subinstr(trim("`date'"), " ", "_", .)


if 1==1 {
	// loop through each year type
	local year_start 1999
	forvalues year_start=1999(2)2015 {
		local year_end=`year_start'+1
		local yrs "`year_start'_`year_end'"
		
		use `data_`yrs'', clear
		renvars, lower // Force variable names lower case
		gen year_start = "`year_start'"
		gen year_end = "`year_end'"
		tempfile NHANES_`yrs'_hearing
		save `NHANES_`yrs'_hearing', replace
		use `wts_`yrs'', clear
		renvars, lower // Force variable names lower case
		merge 1:1 seqn using `NHANES_`yrs'_hearing', keep(3)

		// set missingness to .
		local count=0
		foreach var in auxu1k1r auxu500r auxu2kr auxu3kr auxu4kr auxu6kr auxu8kr auxu1k1l auxu500l auxu2kl auxu3kl auxu4kl auxu6kl auxu8kl auxr1k1r auxr5cr auxr2kr auxr3kr auxr4kr auxr6kr auxr8kr auxr1k1l auxr5cl auxr2kl auxr3kl auxr4kl auxr6kl auxr8kl {
			replace `var'=. if `var'==888
			replace `var'=. if `var'==666
		}
		
		// replace with retest info if necessary
		rename *5c* *500*
		
		foreach x in 1k1 500 2k 3k 4k 6k 8k {
			replace auxu`x'r=auxr`x'r if auxr`x'r!=.
			replace auxu`x'l=auxr`x'l if auxr`x'l!=.
		}	
		
		// average decibel level at which hearing is lost across all frequencies for right and left ear separately 
		egen db_loss_right = rowmean(auxu1k1r auxu500r auxu2kr auxu3kr auxu4kr)
		egen db_loss_left = rowmean(auxu1k1l auxu500l auxu2kl auxu3kl auxu4kl)
		
		// define hearing loss as what is from best ear
		gen db_loss=db_loss_right
		replace db_loss=db_loss_left if db_loss_left<db_loss_right
		
		// make psu- year specific
		tostring sdmvpsu, replace
		replace sdmvpsu=sdmvpsu+"_`yrs'"
		
		keep db_loss year_start year_end ridageyr sdmvstra wtmec2yr sdmvpsu riagendr
		tempfile clean_`yrs'
		save `clean_`yrs'', replace
	}
		
	** Combine years
	use `clean_2009_2015', clear
	tempfile clean
	save `clean', replace
	forvalues year_start=2001(2)2005 {
		local year_end=`year_start'+1
		local yrs "`year_start'_`year_end'"	
		append using `clean_`yrs''
		save `clean', replace
	}
	
	// Apply survey weighting and generate means for age/sex groups
	svyset sdmvpsu [pw=wtmec2yr], strata(sdmvstra) 
	
	// Create variable to store GBD age groups
		rename ridageyr age
		rename riagendr sex
		gen gbd_age = .
		
		// 1 - 4 years
			replace gbd_age = 1 if age>=1 & age<5
		// 5 - 9 years
			replace gbd_age = 5 if age>=5 & age<10
		// 10 - 14 years
			replace gbd_age = 10 if age>=10 & age<15
		// 15 - 19 years
			replace gbd_age = 15 if age>=15 & age<20	
		// 20 - 24 years
			replace gbd_age = 20 if age>=20 & age<25
		// 25 - 29 years
			replace gbd_age = 25 if age>=25 & age<30
		// 30 - 34 years
			replace gbd_age = 30 if age>=30 & age<35
		// 35 - 39 years
			replace gbd_age = 35 if age>=35 & age<40
		// 40 - 44 years
			replace gbd_age = 40 if age>=40 & age<45
		// 45 - 49 years
			replace gbd_age = 45 if age>=45 & age<50
		// 50 - 54 years
			replace gbd_age = 50 if age>=50 & age<55
		// 55 - 59 years
			replace gbd_age = 55 if age>=55 & age<60
		// 60 - 64 years
			replace gbd_age = 60 if age>=60 & age<65
		// 65 - 69 years
			replace gbd_age = 65 if age>=65 & age<70
		// 70 - 74 years
			replace gbd_age = 70 if age>=70 & age<75
		// 75 - 79 years
			replace gbd_age = 75 if age>=75 & age<80
		// 80+ years
			replace gbd_age = 80 if age>=80 & age<120
			
	tempfile data
	save `data', replace
}

*****************************************************************************
** Make crosswalk estimates
*****************************************************************************
** if 1==1 {
	// do cross walk for these paticular thresholds, add any to this list if they come up
	local other_thresholds "16 21 25 26 30 31 40 41 45 55 56 60 61 70 71 81 90"
	
	local gbd_thresholds = "20 35 50 65 80 95"
	
	local all_thresholds = "`other_thresholds'" + " " + "`gbd_thresholds'"
	
	// create cutoffs for different hearing thresholds (ex: 25+ db hearing loss, etc)
	// this is as a binary indicator for every observation from NHANES
	use `data', clear
	foreach t of local all_thresholds {
		gen threshold_`t'=0
		replace threshold_`t'=1 if db_loss>=`t'
	}	
	
	tempfile data_crosses
	save `data_crosses', replace
	
	svyset sdmvpsu [pw=wtmec2yr], strata(sdmvstra) 
	
	// Apply survey weighting and generate mean prevalence by threshold combining all data
	local t 16
	foreach t of local all_thresholds {
		svy: mean threshold_`t'
		matrix mean_matrix = e(b)
		matrix variance_matrix = e(V)
		local mean = mean_matrix[1,1]
		local variance = variance_matrix[1,1]
		local se = sqrt(`variance')		

		gen prev`t'= `mean'
		gen prev_se`t' = `se'
	}
		
	keep prev*
	keep in 1
	gen x=1

	
	clear all
	set obs 1000
	gen draw=_n - 1
	
	foreach x in numerator denominator {
		local mu ``x''
		local sigma ``x'_se'
		local alpha = `mu' * (`mu' - `mu' ^ 2 - `sigma' ^2) / `sigma' ^2 
		local beta  = `alpha' * (1 - `mu') / `mu'	
		
		gen `x' = rbeta(`alpha', `beta')
	}
	
	gen crosswalk=numerator/denominator
	keep draw crosswalk
	gen x=1
	reshape wide crosswalk, i(x) j(draw)
	
	save "`crosswalks_map'", replace
}