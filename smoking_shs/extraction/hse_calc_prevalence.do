// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 			October 29, 2013
// Modified:		--
// Project:		GBD
// Purpose:		Second Hand Smoke - UK subnational

** **************************************************************************
** CONFIGURATION
** **************************************************************************
	
	** ****************************************************************
	** Prepare STATA for use
	**
	** This section sets the application perferences and defines the local variables.  
	** 	The local applications preferences include memory allocation, variables 
	**	limits, color scheme, and defining the J drive (data).
	**
	** ****************************************************************
		// Set application preferences
			// Clear memory and set memory and variable limits
				clear 
			// Set to run all selected code without pausing
				set more off
			// Set graph output color scheme
				set scheme s1color
			// Define J drive (data) for cluster (UNIX) and Windows (Windows)
				if c(os) == "Unix" {
					global prefix "/home/j"
					set odbcmgr unixodbc
					set mem 10g
				}
				else if c(os) == "Windows" {
					global prefix "J:"
					set mem 5g
					}

// Prepare location names & demographics for 2015

	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & inlist(level, 3, 4)

	keep ihme_loc_id location_id location_ascii_name super_region_name super_region_id region_name region_id

	tempfile countrycodes
	save `countrycodes', replace


				
// 1998
// adults & children
clear
use "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/1998/GBR_HEALTH_SURVEY_FOR_ENGLAND_1998_INDIVIDUAL.DTA"
	// subregion: gor
	// psu: "area"
	// strata: hhold? - nothing in the documentation
	// There is no weighted variable for adult data. For children aged 2-15, the variable CH_WT should be used.
	svyset area [pweight=ch_wt]
	
		// age = "age"
		// sex = "sex"
	
	gen gbd_age = .
			// GBD age
			// under 5
				replace gbd_age = 97 if age<5
			// 5-9 years
				replace gbd_age = 5 if age>=5 & age<10
			// 10-14 years
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

	// count
	// estat size, obs	
	// keep gor for later & drop when gor is missing
	drop if gor==.
	tempfile data
	save `data', replace
	decode gor, gen(sub)
	keep gor sub 
	collapse (mean) gor, by(sub)
	tempfile regions
	save `regions', replace
	clear
	use `data'
	// lookfor smoking vars
	lookfor smok
	// "if an individual smokes less than daily they can still be in the denominator for secondhand smoke"
		// "number of cigarettes smoked per day" = cigdyal
		// cigdyal missing for kids
		replace cigdyal=0 if cigdyal==.
		replace cigdyal=. if cigdyal==-9
		replace cigdyal=. if cigdyal==-8
		replace cigdyal=. if cigdyal==-6
		// "not applicable for children"
		replace cigdyal=0 if cigdyal==-1
		replace cigdyal=0 if cigdyal<1
		
		// "how regularly smokes cigars" = cigarreg
		// largest response is "smokes them only occasionally", so disregard adding this
		
		// "do you smoke a pipe at all nowadays" = pipenowa
		// disregard because there are no yes responses

		// "smokers in household" = passm
		replace passm=. if passm==-8
		replace passm=0 if passm==2
		
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
		levelsof gor, local(sub)
		
		foreach subs of local sub {
		foreach ages of local age {
		foreach sexs of local sex {
		

			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & gor==`subs' & cigdyal==0): prop passm, over(sex gbd_age gor) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'				
	}
			

}
}
}
	gen year=1998
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sub_sex_gbd_age)string
	split sub_sex_gbd_age, p("_")
	drop sub_sex_gbd_age sub_sex_gbd_age1
	rename sub_sex_gbd_age2 gor
	rename sub_sex_gbd_age3 sex
	rename sub_sex_gbd_age4 gbd_age
	destring gor, replace
	destring gbd_age, replace
	destring  sex, replace
	merge m:1 gor using `regions'
	keep if _merge==3
	drop _merge
	// drop no observations for women gbd_age=70 from "eastern"
	drop if mean==0
	// gen definition
	gen definition="smokers in household?"
	gen file_path="$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/1998/GBR_HEALTH_SURVEY_FOR_ENGLAND_1998_INDIVIDUAL.DTA"
	tempfile 1998
	save `1998', replace
	// save
	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/hse/1998.dta"


// 1999
clear
use "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/1999/GBR_HEALTH_SURVEY_FOR_ENGLAND_1999_GEN_POP.DTA"

// append ethnic boost
drop if (dmethn>=1 & dmethn<=7) 
append using "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/1999/GBR_HEALTH_SURVEY_FOR_ENGLAND_1999_ETHNIC.DTA"

	// subregion: gor
	// psu: "area"
	// hhold? for strata. no mention in documentation
	// pweight = errorwt for both the ethnic boost and children 2-15
	svyset area [pweight=errorwt]
	
	gen gbd_age = .
			// GBD age
			// under 5
				replace gbd_age = 97 if age<5
			// 5-9 years
				replace gbd_age = 5 if age>=5 & age<10
			// 10-14 years
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

	// count
	// estat size, obs	
	// keep gor for later & drop when gor is missing
	drop if gor==.
	tempfile data
	save `data', replace
	decode gor, gen(sub)
	keep gor sub 
	collapse (mean) gor, by(sub)
	tempfile regions
	save `regions', replace
	clear
	use `data'
	// lookfor smoking vars
	lookfor smok
	// "if an individual smokes less than daily they can still be in the denominator for secondhand smoke"
	// "number of cigarettes smoked per day" = cigdyal
	// cigdyal missing for kids
	replace cigdyal=0 if cigdyal==.
	replace cigdyal=. if cigdyal==-9
	replace cigdyal=. if cigdyal==-8
	replace cigdyal=. if cigdyal==-6
	// "not applicable for children"
	replace cigdyal=0 if cigdyal==-1
	replace cigdyal=0 if cigdyal<1
	
	// shs
	// "smokers in household" = passm
	replace passm=. if passm==-8
	replace passm=. if passm==-9
	replace passm=0 if passm==2
	replace passm=0 if passm==-1
		
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
		levelsof gor, local(sub)
		
		foreach subs of local sub {
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & gor==`subs' & cigdyal==0): prop passm, over(sex gbd_age gor) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'				
	}
			

}
}
}
	gen year=1999
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sub_sex_gbd_age)string
	split sub_sex_gbd_age, p("_")
	drop sub_sex_gbd_age sub_sex_gbd_age1
	rename sub_sex_gbd_age2 gor
	rename sub_sex_gbd_age3 sex
	rename sub_sex_gbd_age4 gbd_age
	destring gor, replace
	destring gbd_age, replace
	destring  sex, replace
	merge m:1 gor using `regions'
	keep if _merge==3
	drop _merge
	// drop no observations 
	drop if mean==0
	// gen definition
	gen definition="smokers in household?"
	gen file_path="$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/1999/GBR_HEALTH_SURVEY_FOR_ENGLAND_1999_GEN_POP.DTA"
	tempfile 1999
	save `1999', replace
	// save
	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/hse/1999.dta"

// 2000
clear
use "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2000/GBR_HEALTH_SURVEY_FOR_ENGLAND_2000_INDIVIDUAL.DTA"

	// subregion: gor
	// psu: area like all others? no mention that it's the "primary sampling unit"
	// 2 seperate weights for 65+ and children 2-15
	egen wgt=rowtotal(wt_65 wt_child)
	replace wgt=1 if wgt==0
	
	svyset area [pweight=wgt]
	
	gen gbd_age = .
			// GBD age
			// under 5
				replace gbd_age = 97 if age<5
			// 5-9 years
				replace gbd_age = 5 if age>=5 & age<10
			// 10-14 years
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

	// count
	// estat size, obs	
	// keep gor for later & drop when gor is missing
	drop if gor==.
	tempfile data
	save `data', replace
	decode gor, gen(sub)
	keep gor sub 
	collapse (mean) gor, by(sub)
	tempfile regions
	save `regions', replace
	clear
	use `data'
	// lookfor smoking vars
	lookfor smok
	// "if an individual smokes less than daily they can still be in the denominator for secondhand smoke"
	// "number of cigarettes smoked per day" = cigdyal
	// cigdyal missing for kids
	replace cigdyal=0 if cigdyal==.
	replace cigdyal=. if cigdyal==-9
	replace cigdyal=. if cigdyal==-8
	replace cigdyal=. if cigdyal==-6
	// "not applicable for children"
	replace cigdyal=0 if cigdyal==-1
	replace cigdyal=0 if cigdyal<1
	
	// shs
	// "smokers in household" = passm
	replace passm=. if passm==-8
	replace passm=. if passm==-9
	replace passm=0 if passm==2
	replace passm=0 if passm==-1
	
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
		levelsof gor, local(sub)
		
		foreach subs of local sub {
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & gor==`subs' & cigdyal==0): prop passm, over(sex gbd_age gor) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'				
	}
}
}
}

	gen year=2000
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sub_sex_gbd_age)string
	split sub_sex_gbd_age, p("_")
	drop sub_sex_gbd_age sub_sex_gbd_age1
	rename sub_sex_gbd_age2 gor
	rename sub_sex_gbd_age3 sex
	rename sub_sex_gbd_age4 gbd_age
	destring gor, replace
	destring gbd_age, replace
	destring  sex, replace
	merge m:1 gor using `regions'
	keep if _merge==3
	drop _merge
	// drop no observations 
	drop if mean==0
	// gen definition
	gen definition="smokers in household?"
	gen file_path="$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2000/GBR_HEALTH_SURVEY_FOR_ENGLAND_2000_INDIVIDUAL.DTA"
	tempfile 2000
	save `2000', replace
	// save
	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/hse/2000.dta"

	
// 2001
clear
use "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2001/GBR_HEALTH_SURVEY_FOR_ENGLAND_2001_INDIVIDUAL.DTA"

	// subregion: gor
	// psu: area like all others? no mention that it's the "primary sampling unit"
	// children under 16: child_wt should be used
	
	svyset area [pweight=child_wt]
	
	gen gbd_age = .
			// GBD age
			// under 5
				replace gbd_age = 97 if age<5
			// 5-9 years
				replace gbd_age = 5 if age>=5 & age<10
			// 10-14 years
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

	// count
	// estat size, obs	
	// keep gor for later & drop when gor is missing
	replace gora="north east" if gora=="A"
	replace gora="north west" if gora=="B"
	replace gora="yorkshire" if gora=="D"
	replace gora="east mids" if gora=="E"
	replace gora="west mids" if gora=="F"
	replace gora="east england" if gora=="G"
	replace gora="london" if gora=="H"
	replace gora="south east" if gora=="J"
	replace gora="south west" if gora=="K"

	// gora="W"? not in codebook and only one observation
	replace gora="" if gora=="W"
	rename gora sub
	encode sub, gen(gor)
	tempfile data
	save `data', replace

	keep gor sub
	collapse (mean) gor, by(sub)
	tempfile regions
	save `regions', replace
	clear
	use `data'
	// lookfor smoking vars
	lookfor smok
	// "if an individual smokes less than daily they can still be in the denominator for secondhand smoke"
	// "number of cigarettes smoked per day" = cigdyal
	// cigdyal missing for kids
	replace cigdyal=0 if cigdyal==.
	replace cigdyal=. if cigdyal==-9
	replace cigdyal=. if cigdyal==-8
	replace cigdyal=. if cigdyal==-6
	// "not applicable for children"
	replace cigdyal=0 if cigdyal==-1
	replace cigdyal=0 if cigdyal<1
	
	// shs
	// "smokers in household" = passm
	replace passm=. if passm==-8
	replace passm=. if passm==-9
	replace passm=0 if passm==2
	replace passm=0 if passm==-1
	
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
		levelsof gor, local(sub)
		
	
		
		foreach subs of local sub {
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & gor==`subs' & cigdyal==0): prop passm, over(sex gbd_age gor) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'				
	}
}
}
}

	gen year=2001
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sub_sex_gbd_age)string
	split sub_sex_gbd_age, p("_")
	drop sub_sex_gbd_age sub_sex_gbd_age1
	rename sub_sex_gbd_age2 gor
	rename sub_sex_gbd_age3 sex
	rename sub_sex_gbd_age4 gbd_age
	destring gor, replace
	destring gbd_age, replace
	destring  sex, replace
	merge m:1 gor using `regions'
	keep if _merge==3
	drop _merge
	// drop no observations 
	drop if mean==0
	// gen definition
	gen definition="does anyone smoke inside this (house/flat) on most days?"
	gen file_path="$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2001/GBR_HEALTH_SURVEY_FOR_ENGLAND_2001_INDIVIDUAL.DTA"
	tempfile 2001
	save `2001', replace
	// save
	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/hse/2001.dta"
	
// 2002
clear
use "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2002/GBR_HEALTH_SURVEY_FOR_ENGLAND_2002_INDIVIDUAL.DTA"

	// subregion: gor
	// psu: area like all others? no mention that it's the "primary sampling unit". label is "sample point"	
	// "In HSE 2002, the sample was boosted in order to obtain greater numbers of children, young adults (aged 16-24) and mothers of infants under 1."
	// "The variable child_wt contains the appropriate weights for each of the three age groups described above."
	
	svyset area [pweight=child_wt]
	
	gen gbd_age = .
			// GBD age
			// under 5
				replace gbd_age = 97 if age<5
			// 5-9 years
				replace gbd_age = 5 if age>=5 & age<10
			// 10-14 years
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

	// count
	// estat size, obs	
	// keep gor for later & drop when gor is missing
	replace gor="north east" if gor=="A"
	replace gor="north west" if gor=="B"
	replace gor="yorkshire and the humberside" if gor=="D"
	replace gor="east mids" if gor=="E"
	replace gor="west mids" if gor=="F"
	replace gor="east england" if gor=="G"
	replace gor="london" if gor=="H"
	replace gor="south east" if gor=="J"
	replace gor="south west" if gor=="K"

	rename gor sub
	encode sub, gen(gor)
	tempfile data
	save `data', replace

	keep gor sub
	collapse (mean) gor, by(sub)
	tempfile regions
	save `regions', replace
	clear
	use `data'
	// lookfor smoking vars
	lookfor smok
	// "if an individual smokes less than daily they can still be in the denominator for secondhand smoke"
	// "number of cigarettes smoked per day" = cigdyal
	// cigdyal missing for kids
	replace cigdyal=0 if cigdyal==.
	replace cigdyal=. if cigdyal==-9
	replace cigdyal=. if cigdyal==-8
	replace cigdyal=. if cigdyal==-6
	// "not applicable for children"
	replace cigdyal=0 if cigdyal==-1
	replace cigdyal=0 if cigdyal<1
	
	// shs
	// "smokers in household" = passm
	replace passm=. if passm==-8
	replace passm=. if passm==-9
	replace passm=0 if passm==2
	replace passm=0 if passm==-1
	
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
		levelsof gor, local(sub)
		
	
		
		foreach subs of local sub {
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & gor==`subs' & cigdyal==0): prop passm, over(sex gbd_age gor) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'				
	}
}
}
}

	gen year=2002
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sub_sex_gbd_age)string
	split sub_sex_gbd_age, p("_")
	drop sub_sex_gbd_age sub_sex_gbd_age1
	rename sub_sex_gbd_age2 gor
	rename sub_sex_gbd_age3 sex
	rename sub_sex_gbd_age4 gbd_age
	destring gor, replace
	destring gbd_age, replace
	destring  sex, replace
	merge m:1 gor using `regions'
	keep if _merge==3
	drop _merge
	// drop no observations 
	drop if mean==0
	// gen definition
	gen definition="does anyone smoke inside this (house/flat) on most days?"
	gen file_path="$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2002/GBR_HEALTH_SURVEY_FOR_ENGLAND_2002_INDIVIDUAL.DTA"
	tempfile 2002
	save `2002', replace
	// save
	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/hse/2002.dta"
	
// 2003
clear
use "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2003/GBR_HEALTH_SURVEY_FOR_ENGLAND_2003_INDIVIDUAL.DTA"

	// subregion: gor
	// psu: area like all others? no mention that it's the "primary sampling unit". label is "sample point"	
	// "The variables int_wt and nurse_wt for children aged 0-15 includes both the child selection weights and non- response weights."
	// 2003 includes stratification variable "cluster"
	
	svyset area [pweight=int_wt], strata(cluster)
	
	gen gbd_age = .
			// GBD age
			// under 5
				replace gbd_age = 97 if age<5
			// 5-9 years
				replace gbd_age = 5 if age>=5 & age<10
			// 10-14 years
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

	// keep gor for later & drop when gor is missing
	tempfile data
	save `data', replace
	decode gor, gen(sub)
	keep gor sub
	collapse (mean) gor, by(sub)
	tempfile regions
	save `regions', replace
	clear
	use `data'
	// lookfor smoking vars
	lookfor smok
	// "if an individual smokes less than daily they can still be in the denominator for secondhand smoke"
	// "number of cigarettes smoked per day" = cigdyal
	// cigdyal missing for kids
	replace cigdyal=0 if cigdyal==.
	replace cigdyal=. if cigdyal==-9
	replace cigdyal=. if cigdyal==-8
	replace cigdyal=. if cigdyal==-6
	// "not applicable for children"
	replace cigdyal=0 if cigdyal==-1
	replace cigdyal=0 if cigdyal<1
	
	// shs
	// "smokers in household" = passm
	replace passm=. if passm==-8
	replace passm=. if passm==-9
	replace passm=0 if passm==2
	replace passm=0 if passm==-1
	
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
		levelsof gor, local(sub)
		
	
		
		foreach subs of local sub {
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & gor==`subs' & cigdyal==0): prop passm, over(sex gbd_age gor) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'				
	}
}
}
}

	gen year=2003
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sub_sex_gbd_age)string
	split sub_sex_gbd_age, p("_")
	drop sub_sex_gbd_age sub_sex_gbd_age1
	rename sub_sex_gbd_age2 gor
	rename sub_sex_gbd_age3 sex
	rename sub_sex_gbd_age4 gbd_age
	destring gor, replace
	destring gbd_age, replace
	destring  sex, replace
	merge m:1 gor using `regions'
	keep if _merge==3
	drop _merge
	// drop no observations 
	drop if mean==0
	// gen definition
	gen definition="persons smoking in accommodation"
	gen file_path="$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2003/GBR_HEALTH_SURVEY_FOR_ENGLAND_2003_INDIVIDUAL.DTA"
	tempfile 2003
	save `2003', replace
	// save
	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/hse/2003.dta"
	
// 2004
clear
use "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2004/GBR_HEALTH_SURVEY_FOR_ENGLAND_2004_GEN_POP.DTA"
// working with both general file and ethnic boost file, as per instructions: http://www.esds.ac.uk/government/resources/weights/index.asp
drop if (dmethn04>=1 & dmethn04<=7)
// ethnic boost sample
append using "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2004/GBR_HEALTH_SURVEY_FOR_ENGLAND_2004_ETHNIC.DTA"
	// subregion: gor
	// psu: area like all others? no mention that it's the "primary sampling unit". label is "sample point"	
	// "For analyses at the individual level, the weighting variable to use is wt_int"
	// 2004 includes stratification variable "cluster"
	
	svyset area [pweight=wt_int], strata(cluster)
	
	gen gbd_age = .
			// GBD age
			// under 5
				replace gbd_age = 97 if age<5
			// 5-9 years
				replace gbd_age = 5 if age>=5 & age<10
			// 10-14 years
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

	// keep gor for later & drop when gor is missing
	tempfile data
	save `data', replace
	decode gor, gen(sub)
	keep gor sub
	collapse (mean) gor, by(sub)
	tempfile regions
	save `regions', replace
	clear
	use `data'
	// lookfor smoking vars
	lookfor smok
	// "if an individual smokes less than daily they can still be in the denominator for secondhand smoke"
	// "number of cigarettes smoked per day" = cigdyal
	// cigdyal missing for kids
	replace cigdyal=0 if cigdyal==.
	replace cigdyal=. if cigdyal==-9
	replace cigdyal=. if cigdyal==-8
	replace cigdyal=. if cigdyal==-6
	// "not applicable for children"
	replace cigdyal=0 if cigdyal==-1
	replace cigdyal=0 if cigdyal<1
	
	// shs
	// "smokers in household" = passm
	replace passm=. if passm==-8
	replace passm=. if passm==-9
	replace passm=0 if passm==2
	replace passm=0 if passm==-1
	
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
		levelsof gor, local(sub)
		
	
		
		foreach subs of local sub {
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & gor==`subs' & cigdyal==0): prop passm, over(sex gbd_age gor) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'				
	}
}
}
}

	gen year=2004
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sub_sex_gbd_age)string
	split sub_sex_gbd_age, p("_")
	drop sub_sex_gbd_age sub_sex_gbd_age1
	rename sub_sex_gbd_age2 gor
	rename sub_sex_gbd_age3 sex
	rename sub_sex_gbd_age4 gbd_age
	destring gor, replace
	destring gbd_age, replace
	destring  sex, replace
	merge m:1 gor using `regions'
	keep if _merge==3
	drop _merge
	// drop no observations 
	drop if mean==0
	// gen definition
	gen definition="does anyone smoke inside this (house/flat) on most days?"
	gen file_path="$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2004/GBR_HEALTH_SURVEY_FOR_ENGLAND_2004_GEN_POP.DTA"
	tempfile 2004
	save `2004', replace
	// save
	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/hse/2004.dta"
	
// 2005
clear
use "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2005/GBR_HEALTH_SURVEY_FOR_ENGLAND_2005_INDIVIDUAL.DTA"

	// subregion: gor
	// psu: area like all others? no mention that it's the "primary sampling unit". label is "sample point"	
	// "For analyses at the individual level, the weighting variable to use is wt_int."
	// 2005 includes stratification variable "cluster"
	
	svyset area [pweight=wt_int], strata(cluster)
	
	gen gbd_age = .
			// GBD age
			// under 5
				replace gbd_age = 97 if age<5
			// 5-9 years
				replace gbd_age = 5 if age>=5 & age<10
			// 10-14 years
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

	// keep gor for later & drop when gor is missing
	tempfile data
	save `data', replace
	decode gor, gen(sub)
	keep gor sub
	collapse (mean) gor, by(sub)
	tempfile regions
	save `regions', replace
	clear
	use `data'
	// lookfor smoking vars
	lookfor smok
	// "if an individual smokes less than daily they can still be in the denominator for secondhand smoke"
	// "number of cigarettes smoked per day" = cigdyal
	// cigdyal missing for kids
	replace cigdyal=0 if cigdyal==.
	replace cigdyal=. if cigdyal==-9
	replace cigdyal=. if cigdyal==-8
	replace cigdyal=. if cigdyal==-6
	// "not applicable for children"
	replace cigdyal=0 if cigdyal==-1
	replace cigdyal=0 if cigdyal<1
	
	// shs
	// "smokers in household" = passm
	replace passm=. if passm==-8
	replace passm=. if passm==-9
	replace passm=0 if passm==2
	replace passm=0 if passm==-1
	
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
		levelsof gor, local(sub)
		
	
		
		foreach subs of local sub {
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & gor==`subs' & cigdyal==0): prop passm, over(sex gbd_age gor) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'				
	}
}
}
}

	gen year=2005
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sub_sex_gbd_age)string
	split sub_sex_gbd_age, p("_")
	drop sub_sex_gbd_age sub_sex_gbd_age1
	rename sub_sex_gbd_age2 gor
	rename sub_sex_gbd_age3 sex
	rename sub_sex_gbd_age4 gbd_age
	destring gor, replace
	destring gbd_age, replace
	destring  sex, replace
	merge m:1 gor using `regions'
	keep if _merge==3
	drop _merge
	// drop no observations 
	drop if mean==0
	// gen definition
	gen definition="does anyone smoke inside this (house/flat) on most days?"
	gen file_path="$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2005/GBR_HEALTH_SURVEY_FOR_ENGLAND_2005_INDIVIDUAL.DTA"
	tempfile 2005
	save `2005', replace
	// save
	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/hse/2005.dta"

// 2006
clear
use "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2006/GBR_HEALTH_SURVEY_FOR_ENGLAND_2006_INDIVIDUAL.DTA"

	// subregion: gor
	// psu: "psu"
	// "For analyses at the individual level, the weighting variable to use is (wt_int)."
	// 2006 includes stratification variable "cluster"
	
	svyset psu [pweight=wt_int], strata(cluster)
	
	gen gbd_age = .
			// GBD age
			// under 5
				replace gbd_age = 97 if age<5
			// 5-9 years
				replace gbd_age = 5 if age>=5 & age<10
			// 10-14 years
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

	// keep gor for later & drop when gor is missing
	rename gor06 gor	
	tempfile data
	save `data', replace
	decode gor, gen(sub)
	keep gor sub
	collapse (mean) gor, by(sub)
	tempfile regions
	save `regions', replace
	clear
	use `data'
	// lookfor smoking vars
	lookfor smok
	// "if an individual smokes less than daily they can still be in the denominator for secondhand smoke"
	// "number of cigarettes smoked per day" = cigdyal
	// cigdyal missing for kids
	replace cigdyal=0 if cigdyal==.
	replace cigdyal=. if cigdyal==-9
	replace cigdyal=. if cigdyal==-8
	replace cigdyal=. if cigdyal==-6
	// "not applicable for children"
	replace cigdyal=0 if cigdyal==-1
	replace cigdyal=0 if cigdyal<1
	
	// shs
	// "smokers in household" = passm
	replace passm=. if passm==-8
	replace passm=. if passm==-9
	replace passm=0 if passm==2
	replace passm=0 if passm==-1
	
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
		levelsof gor, local(sub)
		
	
		
		foreach subs of local sub {
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & gor==`subs' & cigdyal==0): prop passm, over(sex gbd_age gor) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'				
	}
}
}
}

	gen year=2006
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sub_sex_gbd_age)string
	split sub_sex_gbd_age, p("_")
	drop sub_sex_gbd_age sub_sex_gbd_age1
	rename sub_sex_gbd_age2 gor
	rename sub_sex_gbd_age3 sex
	rename sub_sex_gbd_age4 gbd_age
	destring gor, replace
	destring gbd_age, replace
	destring  sex, replace
	merge m:1 gor using `regions'
	keep if _merge==3
	drop _merge
	// drop no observations 
	drop if mean==0
	// gen definition
	gen definition="persons smoking in accommodation"
	gen file_path="$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2006/GBR_HEALTH_SURVEY_FOR_ENGLAND_2006_INDIVIDUAL.DTA"
	tempfile 2006
	save `2006', replace
	// save
	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/hse/2006.dta"
	
// 2007
clear
use "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2007/GBR_HEALTH_SURVEY_FOR_ENGLAND_2007_INDIVIDUAL_Y2013M05D08.DTA"

	// subregion: gor
	// no labeled psu as in 2006. I believe it's "area", the same variable I used for the later 90s surveys
	// "For analyses at the individual level, the weighting variable to use is (wt_int)."
	
	svyset area [pweight=wt_int], strata(cluster)
	
	gen gbd_age = .
			// GBD age
			// under 5
				replace gbd_age = 97 if age<5
			// 5-9 years
				replace gbd_age = 5 if age>=5 & age<10
			// 10-14 years
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

	// keep gor for later & drop when gor is missing
	rename gor07 gor
	tempfile data
	save `data', replace
	decode gor, gen(sub)
	keep gor sub
	collapse (mean) gor, by(sub)
	tempfile regions
	save `regions', replace
	clear
	use `data'
	// lookfor smoking vars
	lookfor smok
	// "if an individual smokes less than daily they can still be in the denominator for secondhand smoke"
	// "number of cigarettes smoked per day" = cigdyal
	// cigdyal missing for kids
	replace cigdyal=0 if cigdyal==.
	replace cigdyal=. if cigdyal==-9
	replace cigdyal=. if cigdyal==-8
	replace cigdyal=. if cigdyal==-6
	// "not applicable for children"
	replace cigdyal=0 if cigdyal==-1
	replace cigdyal=0 if cigdyal<1
	
	// shs
	// "smokers in household" = passm
	replace passm=. if passm==-8
	replace passm=. if passm==-9
	replace passm=0 if passm==2
	replace passm=0 if passm==-1
	
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
		levelsof gor, local(sub)
		
	
		
		foreach subs of local sub {
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & gor==`subs' & cigdyal==0): prop passm, over(sex gbd_age gor) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'				
	}
}
}
}

	gen year=2007
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sub_sex_gbd_age)string
	split sub_sex_gbd_age, p("_")
	drop sub_sex_gbd_age sub_sex_gbd_age1
	rename sub_sex_gbd_age2 gor
	rename sub_sex_gbd_age3 sex
	rename sub_sex_gbd_age4 gbd_age
	destring gor, replace
	destring gbd_age, replace
	destring  sex, replace
	merge m:1 gor using `regions'
	keep if _merge==3
	drop _merge
	// drop no observations 
	drop if mean==0
	// gen definition
	gen definition="persons smoking in accommodation"
	gen file_path="$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2007/GBR_HEALTH_SURVEY_FOR_ENGLAND_2007_INDIVIDUAL_Y2013M05D08.DTA"
	tempfile 2007
	save `2007', replace
	// save
	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/hse/2007.dta"
	
// 2008
clear
use "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2008/GBR_HEALTH_SURVEY_FOR_ENGLAND_2008_INDIVIDUAL_Y2013M05D08.DTA"
	// subregion: gor
	// psu: "psu". the label is"sample point number", which was ofen the same label as "area" in previous survey-years, so that's a good check that "area" was the correct psu to use
	// "For analyses at the individual level, the weighting variable to use is (wt_int)."
	
	svyset psu [pweight=wt_int], strata(cluster)
	
	gen gbd_age = .
			// GBD age
			// under 5
				replace gbd_age = 97 if age<5
			// 5-9 years
				replace gbd_age = 5 if age>=5 & age<10
			// 10-14 years
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

	// keep gor for later & drop when gor is missing
	tempfile data
	save `data', replace
	decode gor, gen(sub)
	keep gor sub
	collapse (mean) gor, by(sub)
	tempfile regions
	save `regions', replace
	clear
	use `data'
	// lookfor smoking vars
	lookfor smok
	// "if an individual smokes less than daily they can still be in the denominator for secondhand smoke"
	// "number of cigarettes smoked per day" = cigdyal
	// cigdyal missing for kids
	replace cigdyal=0 if cigdyal==.
	replace cigdyal=. if cigdyal==-9
	replace cigdyal=. if cigdyal==-8
	replace cigdyal=. if cigdyal==-6
	// "not applicable for children"
	replace cigdyal=0 if cigdyal==-1
	replace cigdyal=0 if cigdyal<1
	
	// shs
	// "smokers in household" = passm
	replace passm=. if passm==-8
	replace passm=. if passm==-9
	replace passm=0 if passm==2
	replace passm=0 if passm==-1
	
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
		levelsof gor, local(sub)
		
	
		
		foreach subs of local sub {
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & gor==`subs' & cigdyal==0): prop passm, over(sex gbd_age gor) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'				
	}
}
}
}

	gen year=2008
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sub_sex_gbd_age)string
	split sub_sex_gbd_age, p("_")
	drop sub_sex_gbd_age sub_sex_gbd_age1
	rename sub_sex_gbd_age2 gor
	rename sub_sex_gbd_age3 sex
	rename sub_sex_gbd_age4 gbd_age
	destring gor, replace
	destring gbd_age, replace
	destring  sex, replace
	merge m:1 gor using `regions'
	keep if _merge==3
	drop _merge
	// drop no observations 
	drop if mean==0
	// gen definition
	gen definition="persons smoking in accommodation"
	gen file_path="$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2008/GBR_HEALTH_SURVEY_FOR_ENGLAND_2008_INDIVIDUAL_Y2013M05D08.DTA"
	tempfile 2008
	save `2008', replace	
	// save
	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/hse/2008.dta"
	
// 2009
clear
use "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2009/GBR_HEALTH_SURVEY_FOR_ENGLAND_2009_INDIVIDUAL_Y2013M05D08.DTA"
	// subregion: gor
	// psu: "psu". the label is"sample point number", which was ofen the same label as "area" in previous survey-years, so that's a good check that "area" was the correct psu to use
	// "For analyses at the individual level, the weighting variable to use is (wt_int)."
	
	svyset psu [pweight=wt_int], strata(cluster)
	
	gen gbd_age = .
			// GBD age
			// under 5
				replace gbd_age = 97 if age<5
			// 5-9 years
				replace gbd_age = 5 if age>=5 & age<10
			// 10-14 years
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

	// keep gor for later & drop when gor is missing
	drop gor
	rename gor07 gor
	tempfile data
	save `data', replace
	decode gor, gen(sub)
	keep gor sub
	collapse (mean) gor, by(sub)
	tempfile regions
	save `regions', replace
	clear
	use `data'
	// lookfor smoking vars
	lookfor smok
	// "if an individual smokes less than daily they can still be in the denominator for secondhand smoke"
	// "number of cigarettes smoked per day" = cigdyal
	// cigdyal missing for kids
	replace cigdyal=0 if cigdyal==.
	replace cigdyal=. if cigdyal==-9
	replace cigdyal=. if cigdyal==-8
	replace cigdyal=. if cigdyal==-6
	// "not applicable for children"
	replace cigdyal=0 if cigdyal==-1
	replace cigdyal=0 if cigdyal<1
	
	// shs
	// "smokers in household" = passm
	replace passm=. if passm==-8
	replace passm=. if passm==-9
	replace passm=0 if passm==2
	replace passm=0 if passm==-1
	
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
		levelsof gor, local(sub)
		
	
		
		foreach subs of local sub {
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & gor==`subs' & cigdyal==0): prop passm, over(sex gbd_age gor) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'				
	}
}
}
}

	gen year=2009
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sub_sex_gbd_age)string
	split sub_sex_gbd_age, p("_")
	drop sub_sex_gbd_age sub_sex_gbd_age1
	rename sub_sex_gbd_age2 gor
	rename sub_sex_gbd_age3 sex
	rename sub_sex_gbd_age4 gbd_age
	destring gor, replace
	destring gbd_age, replace
	destring  sex, replace
	merge m:1 gor using `regions'
	keep if _merge==3
	drop _merge
	// drop no observations 
	drop if mean==0
	// gen definition
	gen definition="persons smoking in accommodation"
	gen file_path="$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2009/GBR_HEALTH_SURVEY_FOR_ENGLAND_2009_INDIVIDUAL_Y2013M05D08.DTA"
	tempfile 2009
	save `2009', replace	
	// save
	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/hse/2009.dta"	
	
// 2010
clear
use "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2010/GBR_HEALTH_SURVEY_FOR_ENGLAND_2010_INDIVIDUAL_Y2013M05D08.DTA"
	// subregion: gor
	// psu: "psu". the label is"sample point number", which was ofen the same label as "area" in previous survey-years, so that's a good check that "area" was the correct psu to use
	// "For analyses at the individual level, the weighting variable to use is (wt_int)."
	
	svyset psu [pweight=wt_int], strata(cluster)
	
	gen gbd_age = .
			// GBD age
			// under 5
				replace gbd_age = 97 if age<5
			// 5-9 years
				replace gbd_age = 5 if age>=5 & age<10
			// 10-14 years
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

	// keep gor for later & drop when gor is missing
	drop gor
	rename gor1 gor
	tempfile data
	save `data', replace
	decode gor, gen(sub)
	keep gor sub
	collapse (mean) gor, by(sub)
	tempfile regions
	save `regions', replace
	clear
	use `data'
	// lookfor smoking vars
	lookfor smok
	// "if an individual smokes less than daily they can still be in the denominator for secondhand smoke"
	// "number of cigarettes smoked per day" = cigdyal
	// cigdyal missing for kids
	replace cigdyal=0 if cigdyal==.
	replace cigdyal=. if cigdyal==-9
	replace cigdyal=. if cigdyal==-8
	replace cigdyal=. if cigdyal==-6
	// "not applicable for children"
	replace cigdyal=0 if cigdyal==-1
	replace cigdyal=0 if cigdyal<1
	
	// shs
	// "smokers in household" = passm
	replace passm=. if passm==-8
	replace passm=. if passm==-9
	replace passm=0 if passm==2
	replace passm=0 if passm==-1
	
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
		levelsof gor, local(sub)
		
	
		
		foreach subs of local sub {
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & gor==`subs' & cigdyal==0): prop passm, over(sex gbd_age gor) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'				
	}
}
}
}

	gen year=2010
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sub_sex_gbd_age)string
	split sub_sex_gbd_age, p("_")
	drop sub_sex_gbd_age sub_sex_gbd_age1
	rename sub_sex_gbd_age2 gor
	rename sub_sex_gbd_age3 sex
	rename sub_sex_gbd_age4 gbd_age
	destring gor, replace
	destring gbd_age, replace
	destring  sex, replace
	merge m:1 gor using `regions'
	keep if _merge==3
	drop _merge
	// drop no observations 
	drop if mean==0
	// gen definition
	gen definition="Does anyone smoke inside this house/flat on most days?"
	gen file_path="$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2010/GBR_HEALTH_SURVEY_FOR_ENGLAND_2010_INDIVIDUAL_Y2013M05D08.DTA"
	tempfile 2010
	save `2010', replace
	// save
	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/hse/2010.dta"
	
// 2011
clear
use "$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2011/GBR_HEALTH_SURVEY_FOR_ENGLAND_2011_INDIVIDUAL_Y2013M05D08.DTA"
/*
	// subregion: gor
	// psu: "psu". the label is"sample point number", which was ofen the same label as "area" in previous survey-years, so that's a good check that "area" was the correct psu to use
	// "For analyses at the individual level, the weighting variable to use is (wt_int)."
*/	
** ? code errors out here when run on cluster. Save each year individually, then compile.

	rename *, lower
	svyset psu [pweight=wt_int], strata(cluster)
	
	gen gbd_age = .
			// GBD age
			// under 5
				replace gbd_age = 97 if age<5
			// 5-9 years
				replace gbd_age = 5 if age>=5 & age<10
			// 10-14 years
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

	// keep gor for later & drop when gor is missing
	rename gor1 gor
	tempfile data
	save `data', replace
	decode gor, gen(sub)
	keep gor sub
	collapse (mean) gor, by(sub)
	tempfile regions
	save `regions', replace
	clear
	use `data'
	// lookfor smoking vars
	lookfor smok
	// "if an individual smokes less than daily they can still be in the denominator for secondhand smoke"
	// "number of cigarettes smoked per day" = cigdyal
	// cigdyal missing for kids
	replace cigdyal=0 if cigdyal==.
	replace cigdyal=. if cigdyal==-9
	replace cigdyal=. if cigdyal==-8
	replace cigdyal=. if cigdyal==-6
	// "not applicable for children"
	replace cigdyal=0 if cigdyal==-1
	replace cigdyal=0 if cigdyal<1
	
	// shs
	// "smokers in household" = passm
	replace passm=. if passm==-8
	replace passm=. if passm==-9
	replace passm=0 if passm==2
	replace passm=0 if passm==-1
	
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
		levelsof gor, local(sub)
		
	
		
		foreach subs of local sub {
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & gor==`subs' & cigdyal==0): prop passm, over(sex gbd_age gor) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			local total=`r(N)'
			gen sample_`subs'_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen mean_`subs'_`sexs'_`ages'=.
			replace mean_`subs'_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
								
			gen se_`subs'_`sexs'_`ages'=.
			replace se_`subs'_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen upper_`subs'_`sexs'_`ages'=.
			replace upper_`subs'_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' & gor==`subs'
			
			gen lower_`subs'_`sexs'_`ages'=.
			replace lower_`subs'_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' & gor==`subs'				
	}
}
}
}

	gen year=2011
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sub_sex_gbd_age)string
	split sub_sex_gbd_age, p("_")
	drop sub_sex_gbd_age sub_sex_gbd_age1
	rename sub_sex_gbd_age2 gor
	rename sub_sex_gbd_age3 sex
	rename sub_sex_gbd_age4 gbd_age
	destring gor, replace
	destring gbd_age, replace
	destring  sex, replace
	merge m:1 gor using `regions'
	keep if _merge==3
	drop _merge
	// drop no observations 
	drop if mean==0
	// gen definition
	gen definition="Does anyone smoke inside this house/flat on most days?"
	gen file_path="$prefix/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND/2011/GBR_HEALTH_SURVEY_FOR_ENGLAND_2011_INDIVIDUAL_Y2013M05D08.DTA"
	tempfile 2011
	save `2011', replace	
	// save
	save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/hse/2011.dta"
	
// append
	clear
	cd "$prefix/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/hse"

	local i=0
	cap erase hse_1998_2011.dta
	local files : dir . files "*.dta"

	foreach f of local files {
		drop _all
		use "`f'"
		if `i'>0 append using hse_1998_2011
		save hse_1998_2011, replace
		local i=1
		}

tempfile hse_1998_2011
save `hse_1998_2011', replace

// do some consistency fixes
replace definition="does anyone smoke inside this (house/flat) on most days?" if definition=="Does anyone smoke inside this house/flat on most days?"
gen sub_region=proper(sub)
drop sub
replace sub_region="East Midlands" if sub_region=="East Mids"
replace sub_region="West Midlands" if sub_region=="West Mids"
replace sub_region="Yorkshire and the Humber" if (regexm(sub_region,"York") & regexm(sub_region,"Humber"))

// save
save "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped/HSE_1998_2011", replace
