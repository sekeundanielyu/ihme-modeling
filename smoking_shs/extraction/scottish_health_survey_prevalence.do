// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 			October 30, 2013
// Modified:		--
// Project:		GBD
// Purpose:		Second Hand Smoke - Scotland

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
					
	
// 2011
clear
use J:\DATA\GBR\SCOTTISH_HEALTH_SURVEY\2011\GBR_SCOTTISH_HEALTH_SURVEY_2011_INDIV_DATA_Y2013M10D15.DTA 
rename *, lower 
// weights
	egen wgt=rowtotal(int11wt cint11wt)
// shs: "passm" "persons smoking in accommodation"
	replace passm=0 if passm==2
// smoke: "cigdyal"
	// -2 for children and =6 for teens
	// -9=don't know
	// -8=refusal
	// -1=not applicable: "Used to signify that a particular variable did not apply to a given respondent usually because of internal routing. For example, men in women only questions"
replace cigdyal=0 if (cigdyal==-2 | cigdyal==-6)
replace cigdyal=. if (cigdyal==-9 | cigdyal==-8)
replace cigdyal=. if cigdyal==-1
// include not-daily smokers as being exposed to shs
replace cigdyal=0 if cigdyal<1

svyset psu [pweight=wgt], strata(strata)

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
		
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & cigdyal==0): prop passm, over(sex gbd_age) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' 				
	}
}
}

	gen year=2011
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_gbd_age)string
	split sex_gbd_age, p("_")
	drop sex_gbd_age sex_gbd_age1
	rename sex_gbd_age2 sex
	rename sex_gbd_age3 gbd_age
	destring sex, replace
	destring gbd_age, replace
	gen file="J:/DATA/GBR/SCOTTISH_HEALTH_SURVEY/2011/GBR_SCOTTISH_HEALTH_SURVEY_2011_INDIV_DATA_Y2013M10D15.DTA" 
	tempfile 2011
	save `2011', replace
	
// 2010
clear
use "J:\DATA\GBR\SCOTTISH_HEALTH_SURVEY\2010\GBR_SCOTTISH_HEALTH_SURVEY_2010_INDIV_DATA_Y2013M10D15.DTA"
rename *, lower 
// weights
	egen wgt=rowtotal(int10wt cint10wt)
// shs: "passm" "persons smoking in accommodation"
	replace passm=0 if passm==2
	replace passm=. if (passm==-8 | passm==-9)
// smoke: "cigdyal"
	// -2 for children and =6 for teens
	// -9=don't know
	// -8=refusal
	// -1=not applicable: "Used to signify that a particular variable did not apply to a given respondent usually because of internal routing. For example, men in women only questions"
replace cigdyal=0 if (cigdyal==-2 | cigdyal==-6)
replace cigdyal=. if (cigdyal==-9 | cigdyal==-8)
replace cigdyal=. if cigdyal==-1
// include not-daily smokers as being exposed to shs
replace cigdyal=0 if cigdyal<1

levelsof passm
levelsof cigdyal


svyset psu [pweight=wgt], strata(strata)

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
		
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & cigdyal==0): prop passm, over(sex gbd_age) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' 				
	}
}
}

	gen year=2010
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_gbd_age)string
	split sex_gbd_age, p("_")
	drop sex_gbd_age sex_gbd_age1
	rename sex_gbd_age2 sex
	rename sex_gbd_age3 gbd_age
	destring sex, replace
	destring gbd_age, replace
	gen file="J:/DATA/GBR/SCOTTISH_HEALTH_SURVEY/2010/GBR_SCOTTISH_HEALTH_SURVEY_2010_INDIV_DATA_Y2013M10D15.DTA" 
	tempfile 2010
	save `2010', replace
	
// 2009
clear
use "J:\DATA\GBR\SCOTTISH_HEALTH_SURVEY\2009\GBR_SCOTTISH_HEALTH_SURVEY_2009_INDIVIDUAL_DATA_Y2013M10D15.DTA"
rename *, lower 
// weights
	egen wgt=rowtotal(int09wt cint09wt)
// shs: "passm" "persons smoking in accommodation"
	replace passm=0 if passm==2
	replace passm=. if (passm==-8 | passm==-9)
// smoke: "cigdyal"
	// -2 for children and =6 for teens
	// -9=don't know
	// -8=refusal
	// -1=not applicable: "Used to signify that a particular variable did not apply to a given respondent usually because of internal routing. For example, men in women only questions"
replace cigdyal=0 if (cigdyal==-2 | cigdyal==-6)
replace cigdyal=. if (cigdyal==-9 | cigdyal==-8)
replace cigdyal=. if cigdyal==-1
// include not-daily smokers as being exposed to shs
replace cigdyal=0 if cigdyal<1

levelsof passm
levelsof cigdyal


svyset psu [pweight=wgt], strata(strata)

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
		
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & cigdyal==0): prop passm, over(sex gbd_age) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' 				
	}
}
}

	gen year=2009
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_gbd_age)string
	split sex_gbd_age, p("_")
	drop sex_gbd_age sex_gbd_age1
	rename sex_gbd_age2 sex
	rename sex_gbd_age3 gbd_age
	destring sex, replace
	destring gbd_age, replace
	gen file="J:/DATA/GBR/SCOTTISH_HEALTH_SURVEY/2009/GBR_SCOTTISH_HEALTH_SURVEY_2009_INDIVIDUAL_DATA_Y2013M10D15.DTA"
	tempfile 2009
	save `2009', replace
	
// 2008
clear
use "J:\DATA\GBR\SCOTTISH_HEALTH_SURVEY\2008\GBR_SCOTTISH_HEALTH_SURVEY_2008_INDIVIDUAL_DATA_Y2013M10D15.DTA"
rename *, lower 
// weights
	egen wgt=rowtotal(int08wt cint08wt)
// shs: "passm" "persons smoking in accommodation"
	replace passm=0 if passm==2
	replace passm=. if (passm==-8 | passm==-9)
// smoke: "cigdyal"
	// -2 for children and =6 for teens
	// -9=don't know
	// -8=refusal
	// -1=not applicable: "Used to signify that a particular variable did not apply to a given respondent usually because of internal routing. For example, men in women only questions"
replace cigdyal=0 if (cigdyal==-2 | cigdyal==-6)
replace cigdyal=. if (cigdyal==-9 | cigdyal==-8)
replace cigdyal=. if cigdyal==-1
// include not-daily smokers as being exposed to shs
replace cigdyal=0 if cigdyal<1

levelsof passm
levelsof cigdyal


svyset psu [pweight=wgt], strata(strata)

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
		
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & cigdyal==0): prop passm, over(sex gbd_age) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' 				
	}
}
}

	gen year=2008
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_gbd_age)string
	split sex_gbd_age, p("_")
	drop sex_gbd_age sex_gbd_age1
	rename sex_gbd_age2 sex
	rename sex_gbd_age3 gbd_age
	destring sex, replace
	destring gbd_age, replace
	gen file="J:/DATA/GBR/SCOTTISH_HEALTH_SURVEY/2008/GBR_SCOTTISH_HEALTH_SURVEY_2008_INDIVIDUAL_DATA_Y2013M10D15.DTA"
	tempfile 2008
	save `2008', replace

// 2003
clear
use "J:\DATA\GBR\SCOTTISH_HEALTH_SURVEY\2003\GBR_SCOTTISH_HEALTH_SURVEY_2003_INDIVIDUAL_DATA.DTA"
rename *, lower 
// weights
	egen wgt=rowtotal(int_wt cint_wt)
// shs: "passm" "persons smoking in accommodation"
	replace passm=0 if passm==2
	replace passm=. if (passm==-8 | passm==-9)
// smoke: "cigdyal"
	// -2 for children and =6 for teens
	// -9=don't know
	// -8=refusal
	// -1=not applicable: "Used to signify that a particular variable did not apply to a given respondent usually because of internal routing. For example, men in women only questions"
replace cigdyal=0 if (cigdyal==-2 | cigdyal==-6)
replace cigdyal=. if (cigdyal==-9 | cigdyal==-8)
replace cigdyal=. if cigdyal==-1
// cigdyal=. for gbd_age<=10, unlike later years where it is 0
replace cigdyal=0 if age<15 & cigdyal==.

// include not-daily smokers as being exposed to shs
replace cigdyal=0 if cigdyal<1

levelsof passm
levelsof cigdyal

// no psu
// strata is health area ("harea") for 2003, according to user guide
svyset [pweight=wgt], strata(harea)

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
		
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & cigdyal==0): prop passm, over(sex gbd_age) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' 				
	}
}
}

	gen year=2003
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_gbd_age)string
	split sex_gbd_age, p("_")
	drop sex_gbd_age sex_gbd_age1
	rename sex_gbd_age2 sex
	rename sex_gbd_age3 gbd_age
	destring sex, replace
	destring gbd_age, replace
	gen file="J:/DATA/GBR/SCOTTISH_HEALTH_SURVEY/2003/GBR_SCOTTISH_HEALTH_SURVEY_2003_INDIVIDUAL_DATA.DTA"
	tempfile 2003
	save `2003', replace
	
// 1998
clear
use "J:\DATA\GBR\SCOTTISH_HEALTH_SURVEY\1998\GBR_SCOTTISH_HEALTH_SURVEY_1998_INDIVIDUAL_DATA.dta"
rename *, lower 
// "The weighting variable is called weighta"
// no psu or strata
// psu is address, which is in the household file
tempfile ind
save `ind', replace
clear
use "J:\DATA\GBR\SCOTTISH_HEALTH_SURVEY\1998\GBR_SCOTTISH_HEALTH_SURVEY_1998_HOUSEHOLD_DATA.dta"
drop if archsn==-1
merge 1:1 archsn using `ind'
keep if _merge==3
drop _merge
// shs: "passive1-6 variables". Each with different definition. Goal: "Are you regularly exposed to other people's tobacco smoke at home?"
	gen shs=.
	replace shs=1 if (passive1==1 | passive2==1 | passive3==1 | passive4==1 | passive5==1 | passive6==1)
	order shs passive1-passive6
	replace shs=0 if shs==.
	// 3 other sets of variables for shs exposure at home...
	replace shs=1 if (anosmok1==1 | anosmok2==1 | anosmok3==1 | anosmok4==1)
	replace shs=1 if (cnosmok1==1 | cnosmok2==1 | cnosmok3==1 | cnosmok4==1)	
	replace shs=1 if (nosmoke1==1 | nosmoke2==1 | nosmoke3==1 | nosmoke4==1 | nosmoke5==1 | nosmoke6==1)		
	// daily smoke "not applicable" for kids and smokers
	replace dlysmoke=0 if dlysmoke==-1 & age<18
	replace dlysmoke=0 if dlysmoke<1
	replace dlysmoke=1 if dlysmoke==-90
	replace dlysmoke=. if dlysmoke==-8
	replace dlysmoke=0 if smokever==2
	replace dlysmoke=0 if smokenow==2
	
// no observations for children under5

levelsof dlysmoke
levelsof shs

// no strata
svyset archadd [pweight=weighta]

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
		
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & dlysmoke==0): prop shs, over(sex gbd_age) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' 				
	}
}
}

	gen year=1998
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_gbd_age)string
	split sex_gbd_age, p("_")
	drop sex_gbd_age sex_gbd_age1
	rename sex_gbd_age2 sex
	rename sex_gbd_age3 gbd_age
	destring sex, replace
	destring gbd_age, replace
	gen file="J:/DATA/GBR/SCOTTISH_HEALTH_SURVEY/1998/GBR_SCOTTISH_HEALTH_SURVEY_1998_INDIVIDUAL_DATA.dta"
	// drop no observations (under5)
	drop if mean==0
	tempfile 1998
	save `1998', replace
	
// 1995
clear
use "J:\DATA\GBR\SCOTTISH_HEALTH_SURVEY\1995\GBR_SCOTTISH_HEALTH_SURVEY_1995_INDIVIDUAL_DATA.dta"
rename *, lower 
// smoke: never regularly smoked==1
replace fagsta=. if fagsta==-9
replace fagsta=. if (fagsta==-8 | fagsta==-6)

// shs
replace athome=0 if athome==2
replace athome=0 if athome==-1

// 2 other shs variables
replace athome=1 if (passive1==1 | passive2==1 | passive3==1 | passive4==1 | passive5==1)
replace athome=1 if (nosmoke1==1 | nosmoke2==1 | nosmoke3==1 | nosmoke4==1 | nosmoke5==1 | nosmoke6==1)

levelsof athome
levelsof fagsta

// no strata or psu
svyset [pweight=weighta]

rename respage age
rename respsex sex

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
		
		levelsof sex, local(sex)
		levelsof gbd_age, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages' & fagsta==1): prop athome, over(sex gbd_age) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & gbd_age==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & gbd_age==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & gbd_age==`ages' 				
	}
}
}

	gen year=1995
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_gbd_age)string
	split sex_gbd_age, p("_")
	drop sex_gbd_age sex_gbd_age1
	rename sex_gbd_age2 sex
	rename sex_gbd_age3 gbd_age
	destring sex, replace
	destring gbd_age, replace
	gen file="J:/DATA/GBR/SCOTTISH_HEALTH_SURVEY/1995/GBR_SCOTTISH_HEALTH_SURVEY_1995_INDIVIDUAL_DATA.dta"
	// drop no observations (under5)
	drop if mean==0
	tempfile 1995
	save `1995', replace
	
// append
append using `1998'
append using `2003'
append using `2008'
append using `2009'
append using `2010'
append using `2011'

save "J:/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped/scotland_1998_2011", replace

tempfile all
save `all', replace

// graph
levelsof year, local(years)
foreach year of local years {
clear
use `all'
keep if year==`year'
twoway (scatter mean gbd_age), yscale(range(0 1)) ylabel(#5) title(`year') 
graph export "C:\Users\strUser\Documents\scotland_shs_`year'.pdf", as(pdf) replace
}

