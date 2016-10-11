// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 			October 30, 2013
// Modified:		--
// Project:		GBD
// Purpose:		Second Hand Smoke - Wales

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
					
// 2012 is a report
// 2011
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2011/GBR_WELSH_HEALTH_SURVEY_2011_ADULT_DATA_Y2013M10D15.DTA"
// currently smoking daily "smoked" (svy if smoked==0)
// shs: exposed to smoke indoors in own home "expinh"
// can't be exposed to shs if you're a daily smoker
// -9 is no answer/refused.
replace expinh=0 if smoked==1
replace expinh=. if expinh==-9
replace expinh=0 if expinh==2

// no psu or strata.
svyset [pweight=wt_adult]

// no actual age variable. Only variable is "age5yrm" - "5 year age bands with 75+ merged"
// tempfile age to merge on later
tempfile data
save `data', replace
gen year=2011
keep year age5yrm
collapse (mean) year, by(age5yrm) fast
decode age5yrm, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof age5yrm, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & age5yrm==`ages' & smoked==0): prop expinh, over(sex age5yrm) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 				
	}
}
}

	gen year=2011
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_age5yrm)string
	split sex_age5yrm, p("_")
	drop sex_age5yrm sex_age5yrm1
	rename sex_age5yrm2 sex
	rename sex_age5yrm3 age5yrm
	destring sex, replace
	destring age5yrm, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2011/GBR_WELSH_HEALTH_SURVEY_2011_ADULT_DATA_Y2013M10D15.DTA" 
	merge m:1 age5yrm using `age_m'
	drop _merge
	drop age5yrm
	gen definition="Exposed to smoke indoors - in own home"
	tempfile 2011
	save `2011', replace
	save "$j/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped/wales_health_survey_2011", replace

// 2010
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2010/GBR_WELSH_HEALTH_SURVEY_2010_ADULT_DATA_Y2013M10D15.DTA"
** took a look at the child file. There's no information on child shs exposure.
rename *, lower 
// currently smoking daily "smoked" (svy if smoked==0)
// shs: exposed to smoke indoors in own home "expinh"
// can't be exposed to shs if you're a daily smoker
// -9 is no answer/refused.
replace expinh=0 if smoked==1
replace expinh=. if expinh==-9
replace expinh=0 if expinh==2

svyset [pweight=wt_adult]

// no actual age variable. Only variable is "age5yrm" - "5 year age bands with 75+ merged"
// tempfile age to merge on later
tempfile data
save `data', replace
gen year=2010
keep year age5yrm
collapse (mean) year, by(age5yrm) fast
decode age5yrm, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof age5yrm, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & age5yrm==`ages' & smoked==0): prop expinh, over(sex age5yrm) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 				
	}
}
}

	gen year=2010
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_age5yrm)string
	split sex_age5yrm, p("_")
	drop sex_age5yrm sex_age5yrm1
	rename sex_age5yrm2 sex
	rename sex_age5yrm3 age5yrm
	destring sex, replace
	destring age5yrm, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2010/GBR_WELSH_HEALTH_SURVEY_2010_ADULT_DATA_Y2013M10D15.DTA" 
	merge m:1 age5yrm using `age_m'
	drop age5yrm
	drop _merge
	gen definition="Exposed to smoke indoors - in own home"
	tempfile 2010
	save `2010', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/2010", replace
	
// 2009
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2009/GBR_WELSH_HEALTH_SURVEY_2009_ADULT_DATA_Y2013M10D15.DTA"
** took a look at the child file. There's no information on child shs exposure.
rename *, lower 
// currently smoking daily "smoked" (svy if smoked==0)
// shs: exposed to smoke indoors in own home "expinh"
// can't be exposed to shs if you're a daily smoker
// -9 is no answer/refused.
replace expinh=0 if smoked==1
replace expinh=. if expinh==-9
replace expinh=0 if expinh==2

svyset [pweight=wt_adult]

// no actual age variable. Only variable is "age5yrm" - "5 year age bands with 75+ merged"
// tempfile age to merge on later
tempfile data
save `data', replace
gen year=2009
keep year age5yrm
collapse (mean) year, by(age5yrm) fast
decode age5yrm, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof age5yrm, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & age5yrm==`ages' & smoked==0): prop expinh, over(sex age5yrm) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 				
	}
}
}

	gen year=2009
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_age5yrm)string
	split sex_age5yrm, p("_")
	drop sex_age5yrm sex_age5yrm1
	rename sex_age5yrm2 sex
	rename sex_age5yrm3 age5yrm
	destring sex, replace
	destring age5yrm, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2009/GBR_WELSH_HEALTH_SURVEY_2009_ADULT_DATA_Y2013M10D15.DTA"
	merge m:1 age5yrm using `age_m'
	drop age5yrm
	drop _merge
	gen definition="Exposed to smoke indoors - in own home"
	tempfile 2009
	save `2009', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/2009", replace	

// 2008
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2008/GBR_WELSH_HEALTH_SURVEY_2008_ADULT_DATA_Y2013M10D15.DTA"
rename *, lower 
/*
tempfile adult
save `adult', replace

// merge child file
merge m:m archhsn using "J:\DATA\GBR\WELSH_HEALTH_SURVEY\2008\GBR_WELSH_HEALTH_SURVEY_2008_CHILD_DATA_Y2013M10D15.DTA"
decode hhchild, gen(children)
order children _merge
sort children
	// when _merge==2, this is because the "are there children in the household" question was missing
	// when _merge==1, this is because the adult responded that the house does have children, but the respective child questionnaire wasn't filled out.
*/
// currently smoking daily "smoked" (svy if smoked==0)
// shs: exposed to smoke indoors in own home "expinh"
// can't be exposed to shs if you're a daily smoker
// -9 is no answer/refused.
replace expinh=0 if smoked==1
replace expinh=. if expinh==-9
replace expinh=0 if expinh==2

svyset [pweight=wt_adult]

// no actual age variable. Only variable is "age5yrm" - "5 year age bands with 75+ merged"
// tempfile age to merge on later
tempfile data
save `data', replace
gen year=2008
keep year age5yrm
collapse (mean) year, by(age5yrm) fast
decode age5yrm, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof age5yrm, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & age5yrm==`ages' & smoked==0): prop expinh, over(sex age5yrm) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 				
	}
}
}

	gen year=2008
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_age5yrm)string
	split sex_age5yrm, p("_")
	drop sex_age5yrm sex_age5yrm1
	rename sex_age5yrm2 sex
	rename sex_age5yrm3 age5yrm
	destring sex, replace
	destring age5yrm, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2008/GBR_WELSH_HEALTH_SURVEY_2008_ADULT_DATA_Y2013M10D15.DTA"
	merge m:1 age5yrm using `age_m'
	drop age5yrm
	drop _merge
	gen definition="Exposed to smoke indoors - in own home"
	tempfile 2008
	save `2008', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/2008", replace	
	
// 2007
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2007/GBR_WELSH_HEALTH_SURVEY_2007_ADULT_DATA_Y2013M10D15.DTA"
rename *, lower 
// currently smoking daily "smoked" (svy if smoked==0)
// shs: exposed to smoke indoors in own home "exphome"
// can't be exposed to shs if you're a daily smoker
// -9 is no answer/refused.
replace exphome=0 if smoked==1
replace exphome=. if exphome==-9
replace exphome=0 if exphome==2

svyset [pweight=wt_adult]

// no actual age variable. Only variable is "age5yrm" - "5 year age bands with 75+ merged"
// tempfile age to merge on later
tempfile data
save `data', replace
gen year=2007
keep year age5yrm
collapse (mean) year, by(age5yrm) fast
decode age5yrm, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof age5yrm, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & age5yrm==`ages' & smoked==0): prop exphome, over(sex age5yrm) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 				
	}
}
}

	gen year=2007
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_age5yrm)string
	split sex_age5yrm, p("_")
	drop sex_age5yrm sex_age5yrm1
	rename sex_age5yrm2 sex
	rename sex_age5yrm3 age5yrm
	destring sex, replace
	destring age5yrm, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2007/GBR_WELSH_HEALTH_SURVEY_2007_ADULT_DATA_Y2013M10D15.DTA"
	merge m:1 age5yrm using `age_m'
	drop age5yrm
	drop _merge
	gen definition="Exposed to smoke indoors - in own home"
	tempfile 2007
	save `2007', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/2007", replace	
	
// 2005-2006
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2005_2006/GBR_WELSH_HEALTH_SURVEY_2005_2006_ADULT_DATA_Y2013M10D15.DTA"
rename *, lower 
// currently smoking daily "smoked" (svy if smoked==0)
// shs: exposed to smoke indoors in own home "q31home"
// can't be exposed to shs if you're a daily smoker
// -9 is no answer/refused.
replace q31home=0 if smoked==1
replace q31home=. if q31home==-9
replace q31home=0 if q31home==2

svyset [pweight=wt_adult]

// no actual age variable. Only variable is "age5yrm" - "5 year age bands with 75+ merged"
// tempfile age to merge on later
tempfile data
save `data', replace
gen year_start=2005
gen year_end=2006
keep year* age5yrm
collapse (mean) year_start year_end, by(age5yrm) fast
decode age5yrm, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof age5yrm, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & age5yrm==`ages' & smoked==0): prop q31home, over(sex age5yrm) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 				
	}
}
}

	gen year_start=2005
	gen year_end=2006
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year_start year_end) fast
	reshape long mean se lower upper sample, i(year_start year_end) j(sex_age5yrm)string
	split sex_age5yrm, p("_")
	drop sex_age5yrm sex_age5yrm1
	rename sex_age5yrm2 sex
	rename sex_age5yrm3 age5yrm
	destring sex, replace
	destring age5yrm, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2005_2006/GBR_WELSH_HEALTH_SURVEY_2005_2006_ADULT_DATA_Y2013M10D15.DTA"
	merge m:1 age5yrm using `age_m'
	drop age5yrm
	drop _merge
	gen definition="Exposed to smoke indoors - in own home"
	tempfile 2005_2006
	save `2005_2006', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/2005_2006", replace	

// 2004-2005
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2004_2005/GBR_WELSH_HEALTH_SURVEY_2004_2005_ADULT_DATA_Y2013M10D15.DTA"
rename *, lower 
// currently smoking daily "smoked" (svy if smoked==0)
// shs: exposed to smoke indoors in own home "q31home"
// can't be exposed to shs if you're a daily smoker
// -9 is no answer/refused.
replace q31home=0 if smoked==1
replace q31home=. if q31home==-9
replace q31home=0 if q31home==2

levelsof q31home

svyset [pweight=wt_adult]

// no actual age variable. Only variable is "age5yrm" - "5 year age bands with 75+ merged"
// tempfile age to merge on later
tempfile data
save `data', replace
gen year_start=2004
gen year_end=2005
keep year* age5yrm
collapse (mean) year_start year_end, by(age5yrm) fast
decode age5yrm, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof age5yrm, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & age5yrm==`ages' & smoked==0): prop q31home, over(sex age5yrm) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 				
	}
}
}

	gen year_start=2004
	gen year_end=2005
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year_start year_end) fast
	reshape long mean se lower upper sample, i(year_start year_end) j(sex_age5yrm)string
	split sex_age5yrm, p("_")
	drop sex_age5yrm sex_age5yrm1
	rename sex_age5yrm2 sex
	rename sex_age5yrm3 age5yrm
	destring sex, replace
	destring age5yrm, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2004_2005/GBR_WELSH_HEALTH_SURVEY_2004_2005_ADULT_DATA_Y2013M10D15.DTA"
	merge m:1 age5yrm using `age_m'
	drop age5yrm
	drop _merge
	gen definition="Exposed to smoke indoors - in own home"
	tempfile 2004_2005
	save `2004_2005', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/2004_2005", replace	

// 2003-2004
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2003_2004/GBR_WELSH_HEALTH_SURVEY_2003_2004_ADULT_DATA_Y2013M10D15.DTA"
rename *, lower 
// currently smoking daily "smoked" (svy if smoked==0)
// shs: exposed to smoke indoors in own home "q31home"
// can't be exposed to shs if you're a daily smoker
// -9 is no answer/refused.
replace q31home=0 if smoked==1
replace q31home=. if q31home==-9
replace q31home=0 if q31home==2

levelsof q31home

svyset [pweight=int_wt]

// no actual age variable. Only variable is "age5yrm" - "5 year age bands with 75+ merged"
// tempfile age to merge on later
tempfile data
save `data', replace
gen year_start=2003
gen year_end=2004
keep year* age5yrm
collapse (mean) year_start year_end, by(age5yrm) fast
decode age5yrm, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof age5yrm, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & age5yrm==`ages' & smoked==0): prop q31home, over(sex age5yrm) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 				
	}
}
}

	gen year_start=2003
	gen year_end=2004
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year_start year_end) fast
	reshape long mean se lower upper sample, i(year_start year_end) j(sex_age5yrm)string
	split sex_age5yrm, p("_")
	drop sex_age5yrm sex_age5yrm1
	rename sex_age5yrm2 sex
	rename sex_age5yrm3 age5yrm
	destring sex, replace
	destring age5yrm, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2003_2004/GBR_WELSH_HEALTH_SURVEY_2003_2004_ADULT_DATA_Y2013M10D15.DTA"
	merge m:1 age5yrm using `age_m'
	drop age5yrm
	drop _merge
	gen definition="Exposed to smoke indoors - in own home"
	tempfile 2003_2004
	save `2003_2004', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/2003_2004", replace	
	
// 1998
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/1998/GBR_WELSH_HEALTH_SURVEY_1998_DATA_Y2013M10D15.DTA"
rename *, lower 
// age_1 is the 5 year age band for the respondent. It looks like q43b_* refer to the age of the children.  However, there is not information on the sex of the child.
// smoking status is q48
	// only current daily smokers are counted as smokers
	decode q48, gen(smoked)
	replace q48=0 if q48==2
	replace q48=0 if q48==3
	replace q48=0 if q48==4
	replace q48=0 if q48==5
// shs: "q49": "how many other people in household smoke now?"
	decode q49, gen(shs)
	order shs q49
	sort q49
	replace q49=0 if q49==1
	replace q49=1 if q49>=2
	replace q49=. if q49==-99.99
	// can't be exposed to shs if daily smoker
	replace q49=0 if q48==1
	levelsof q49
	
svyset [pweight=zzwght]

// no actual age variable. Only variable is "age5yrm" - "5 year age bands with 75+ merged"
// tempfile age to merge on later
rename q50 sex
rename age_1 age5yrm
// there are no response/refusal ages
replace age5yrm=. if age5yrm==-99.99
tempfile data
save `data', replace
gen year=1998
keep year age5yrm
collapse (mean) year, by(age5yrm) fast
decode age5yrm, gen(age_cat)
drop if age5yrm==.
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof age5yrm, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & age5yrm==`ages' & q48==0): prop q49, over(sex age5yrm) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 				
	}
}
}

	gen year=1998
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_age5yrm)string
	split sex_age5yrm, p("_")
	drop sex_age5yrm sex_age5yrm1
	rename sex_age5yrm2 sex
	rename sex_age5yrm3 age5yrm
	destring sex, replace
	destring age5yrm, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/1998/GBR_WELSH_HEALTH_SURVEY_1998_DATA_Y2013M10D15.DTA"
	merge m:1 age5yrm using `age_m'
	drop age5yrm
	drop _merge
	gen definition="how many other people in household smoke now?"
	tempfile 1998
	save `1998', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/1998", replace	
	
// Children
// 2011
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2011/GBR_WELSH_HEALTH_SURVEY_2011_ADULT_DATA_Y2013M10D15.DTA"
rename *, lower 
// decode children in household
decode hhchild, gen(children)
order children archhsn
sort archhsn children
// collapse file for household - either parent smokes
replace smoked=. if smoked==-8
replace smoked=. if smoked==-9
keep smoked hhchild archpsn archhsn
collapse (mean) smoked hhchild archpsn, by(archhsn)  
// if smoked is>0, that means someone in the household smokes daily
tempfile adult
save `adult', replace

clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2011/GBR_WELSH_HEALTH_SURVEY_2011_CHILD_DATA_Y2013M10D15.DTA"
merge m:1 archhsn using `adult'

/*
when _merge==1 (19 observations), this is data for children, but the adult questionnaire wasn't filled out by the household
count if _merge==2 & hhchild==1
when _merge==2 (6908), this is when the adult said there are no children in the household, or the adult said there are children in the household, but the child questionnaire wasn't filled out (152 of the 6908)
this should all be adjusted for in the weights
*/
keep if _merge==3
drop _merge
/*
"Non-response weights adjusted for non-response at the household and individual level to account for non-contact and refusals of entire households, and for non-response among individuals within responding households. The final weights arrived at are applied at the individual level separately for adults and children (wt_adult and wt_child)."
*/
		
svyset [pweight=wt_child]

// someone in the household smokes
replace smoked=1 if smoked>0 
tempfile data
save `data', replace
gen year=2011
keep year childage
collapse (mean) year, by(childage) fast
decode childage, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof childage, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & childage==`ages'): prop smoked, over(sex childage) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 				
	}
}
}


	gen year=2011
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_childage)string
	split sex_childage, p("_")
	drop sex_childage sex_childage1
	rename sex_childage2 sex
	rename sex_childage3 childage
	destring sex, replace
	destring childage, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2011/GBR_WELSH_HEALTH_SURVEY_2011_CHILD_DATA_Y2013M10D15.DTA" 
	merge m:1 childage using `age_m'
	drop _merge
	drop childage
	gen definition="Proportion of children living in a household where someone smokes daily"
	tempfile 2011
	save `2011', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/ch_2011", replace

// 2010
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2010/GBR_WELSH_HEALTH_SURVEY_2010_ADULT_DATA_Y2013M10D15.DTA"
rename *, lower 
// decode children in household
decode hhchild, gen(children)
order children archhsn
sort archhsn children
// collapse file for household - either parent smokes
replace smoked=. if smoked==-8
replace smoked=. if smoked==-9
keep smoked hhchild archpsn archhsn
collapse (mean) smoked hhchild archpsn, by(archhsn)  
// if smoked is>0, that means someone in the household smokes daily
tempfile adult
save `adult', replace

clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2010/GBR_WELSH_HEALTH_SURVEY_2010_CHILD_DATA_Y2013M10D15.DTA"
merge m:1 archhsn using `adult'

/*
when _merge==1 (26 observations), this is data for children, but the adult questionnaire wasn't filled out by the household
count if _merge==2 & hhchild==1
when _merge==2 (6999), this is when the adult said there are no children in the household, or the adult said there are children in the household, but the child questionnaire wasn't filled out (123 of the 6999)
this should all be adjusted for in the weights
*/
keep if _merge==3
drop _merge
/*
"Non-response weights adjusted for non-response at the household and individual level to account for non-contact and refusals of entire households, and for non-response among individuals within responding households. The final weights arrived at are applied at the individual level separately for adults and children (wt_adult and wt_child)."
*/
		
svyset [pweight=wt_child]

// someone in the household smokes
replace smoked=1 if smoked>0 
tempfile data
save `data', replace
gen year=2010
keep year childage
collapse (mean) year, by(childage) fast
decode childage, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof childage, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & childage==`ages'): prop smoked, over(sex childage) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 				
	}
}
}


	gen year=2010
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_childage)string
	split sex_childage, p("_")
	drop sex_childage sex_childage1
	rename sex_childage2 sex
	rename sex_childage3 childage
	destring sex, replace
	destring childage, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2010/GBR_WELSH_HEALTH_SURVEY_2010_CHILD_DATA_Y2013M10D15.DTA"
	merge m:1 childage using `age_m'
	drop _merge
	drop childage
	gen definition="Proportion of children living in a household where someone smokes daily"
	tempfile 2010
	save `2010', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/ch_2010", replace
	
// 2009
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2009/GBR_WELSH_HEALTH_SURVEY_2009_ADULT_DATA_Y2013M10D15.DTA"
rename *, lower 
// decode children in household
decode hhchild, gen(children)
order children archhsn
sort archhsn children
// collapse file for household - either parent smokes
replace smoked=. if smoked==-8
replace smoked=. if smoked==-9
keep smoked hhchild archpsn archhsn
collapse (mean) smoked hhchild archpsn, by(archhsn)  
// if smoked is>0, that means someone in the household smokes daily
tempfile adult
save `adult', replace

clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2009/GBR_WELSH_HEALTH_SURVEY_2009_CHILD_DATA_Y2013M10D15.DTA"
merge m:1 archhsn using `adult'

/*
when _merge==1 (19 observations), this is data for children, but the adult questionnaire wasn't filled out by the household
count if _merge==2 & hhchild==1
when _merge==2 (6870), this is when the adult said there are no children in the household, or the adult said there are children in the household, but the child questionnaire wasn't filled out (124 of the 6870)
this should all be adjusted for in the weights
*/
keep if _merge==3
drop _merge
/*
"Non-response weights adjusted for non-response at the household and individual level to account for non-contact and refusals of entire households, and for non-response among individuals within responding households. The final weights arrived at are applied at the individual level separately for adults and children (wt_adult and wt_child)."
*/
		
svyset [pweight=wt_child]

// someone in the household smokes
replace smoked=1 if smoked>0 
tempfile data
save `data', replace
gen year=2009
keep year childage
collapse (mean) year, by(childage) fast
decode childage, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof childage, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & childage==`ages'): prop smoked, over(sex childage) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 				
	}
}
}


	gen year=2009
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_childage)string
	split sex_childage, p("_")
	drop sex_childage sex_childage1
	rename sex_childage2 sex
	rename sex_childage3 childage
	destring sex, replace
	destring childage, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2009/GBR_WELSH_HEALTH_SURVEY_2009_CHILD_DATA_Y2013M10D15.DTA"
	merge m:1 childage using `age_m'
	drop _merge
	drop childage
	gen definition="Proportion of children living in a household where someone smokes daily"
	tempfile 2009
	save `2009', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/ch_2009", replace
	
	
// 2008
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2008/GBR_WELSH_HEALTH_SURVEY_2008_ADULT_DATA_Y2013M10D15.DTA"
rename *, lower 
// decode children in household
decode hhchild, gen(children)
order children archhsn
sort archhsn children
// collapse file for household - either parent smokes
replace smoked=. if smoked==-8
replace smoked=. if smoked==-9
keep smoked hhchild archpsn archhsn
collapse (mean) smoked hhchild archpsn, by(archhsn)  
// if smoked is>0, that means someone in the household smokes daily
tempfile adult
save `adult', replace

clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2008/GBR_WELSH_HEALTH_SURVEY_2008_CHILD_DATA_Y2013M10D15.DTA"
merge m:1 archhsn using `adult'

/*
when _merge==1 (27 observations), this is data for children, but the adult questionnaire wasn't filled out by the household
when _merge==2 (5693), this is when the adult said there are no children in the household, or the adult said there are children in the household, but the child questionnaire wasn't filled out (103 of the 5693)
this should all be adjusted for in the weights
*/
keep if _merge==3
drop _merge
/*
"Non-response weights adjusted for non-response at the household and individual level to account for non-contact and refusals of entire households, and for non-response among individuals within responding households. The final weights arrived at are applied at the individual level separately for adults and children (wt_adult and wt_child)."
*/
svyset [pweight=wt_child]

// someone in the household smokes
replace smoked=1 if smoked>0 
tempfile data
save `data', replace
gen year=2008
keep year childage
collapse (mean) year, by(childage) fast
decode childage, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof childage, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & childage==`ages'): prop smoked, over(sex childage) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 				
	}
}
}

	gen year=2008
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_childage)string
	split sex_childage, p("_")
	drop sex_childage sex_childage1
	rename sex_childage2 sex
	rename sex_childage3 childage
	destring sex, replace
	destring childage, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2008/GBR_WELSH_HEALTH_SURVEY_2008_CHILD_DATA_Y2013M10D15.DTA"
	merge m:1 childage using `age_m'
	drop childage
	drop _merge
	gen definition="Proportion of children living in a household where someone smokes daily"
	tempfile 2008
	save `2008', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/ch_2008", replace	

// 2007
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2007/GBR_WELSH_HEALTH_SURVEY_2007_ADULT_DATA_Y2013M10D15.DTA"
rename *, lower 
// decode children in household
decode hhchild, gen(children)
order children archhsn
sort archhsn children
// collapse file for household - either parent smokes
replace smoked=. if smoked==-8
replace smoked=. if smoked==-9
keep smoked hhchild archpsn archhsn
collapse (mean) smoked hhchild archpsn, by(archhsn)  
// if smoked is>0, that means someone in the household smokes daily
tempfile adult
save `adult', replace

clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2007/GBR_WELSH_HEALTH_SURVEY_2007_CHILD_DATA_Y2013M10D15.DTA"
merge m:1 archhsn using `adult'

/*
when _merge==1 (17 observations), this is data for children, but the adult questionnaire wasn't filled out by the household
count if _merge==2 & hhchild==1
when _merge==2 (6009), this is when the adult said there are no children in the household, or the adult said there are children in the household, but the child questionnaire wasn't filled out (125 of the 6009)
this should all be adjusted for in the weights
*/
keep if _merge==3
drop _merge
/*
"Non-response weights adjusted for non-response at the household and individual level to account for non-contact and refusals of entire households, and for non-response among individuals within responding households. The final weights arrived at are applied at the individual level separately for adults and children (wt_adult and wt_child)."
*/
svyset [pweight=wt_child]

// someone in the household smokes
replace smoked=1 if smoked>0 
tempfile data
save `data', replace
gen year=2008
keep year childage
collapse (mean) year, by(childage) fast
decode childage, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof childage, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & childage==`ages'): prop smoked, over(sex childage) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 				
	}
}
}

	gen year=2007
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_childage)string
	split sex_childage, p("_")
	drop sex_childage sex_childage1
	rename sex_childage2 sex
	rename sex_childage3 childage
	destring sex, replace
	destring childage, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2007/GBR_WELSH_HEALTH_SURVEY_2007_CHILD_DATA_Y2013M10D15.DTA"
	merge m:1 childage using `age_m'
	drop childage
	drop _merge
	gen definition="Proportion of children living in a household where someone smokes daily"
	tempfile 2007
	save `2007', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/ch_2007", replace	

// 2005 - 2006
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2005_2006/GBR_WELSH_HEALTH_SURVEY_2005_2006_ADULT_DATA_Y2013M10D15.DTA"
rename *, lower 
// decode children in household
decode hhchild, gen(children)
order children archhsn
sort archhsn children
// collapse file for household - either parent smokes
replace smoked=. if smoked==-8
replace smoked=. if smoked==-9
keep smoked hhchild archpsn archhsn
collapse (mean) smoked hhchild archpsn, by(archhsn)  
// if smoked is>0, that means someone in the household smokes daily
tempfile adult
save `adult', replace

clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2005_2006/GBR_WELSH_HEALTH_SURVEY_2005_2006_CHILD_DATA_Y2013M10D15.DTA"
merge m:1 archhsn using `adult'

/*
when _merge==1 (18 observations), this is data for children, but the adult questionnaire wasn't filled out by the household
count if _merge==2 & hhchild==1
when _merge==2 (6148), this is when the adult said there are no children in the household, or the adult said there are children in the household, but the child questionnaire wasn't filled out (321 of the 6148)
this should all be adjusted for in the weights
*/
keep if _merge==3
drop _merge
/*
"Non-response weights adjusted for non-response at the household and individual level to account for non-contact and refusals of entire households, and for non-response among individuals within responding households. The final weights arrived at are applied at the individual level separately for adults and children (wt_adult and wt_child)."
*/
svyset [pweight=wt_child]

// someone in the household smokes
replace smoked=1 if smoked>0 
tempfile data
save `data', replace
gen year_start=2005
gen year_end=2006
keep year* childage
collapse (mean) year_start year_end, by(childage) fast
decode childage, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof childage, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & childage==`ages'): prop smoked, over(sex childage) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 				
	}
}
}

	gen year_start=2005
	gen year_end=2006
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year_start year_end) fast
	reshape long mean se lower upper sample, i(year_start year_end) j(sex_childage)string
	split sex_childage, p("_")
	drop sex_childage sex_childage1
	rename sex_childage2 sex
	rename sex_childage3 childage
	destring sex, replace
	destring childage, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2005_2006/GBR_WELSH_HEALTH_SURVEY_2005_2006_CHILD_DATA_Y2013M10D15.DTA"
	merge m:1 childage using `age_m'
	drop childage
	drop _merge
	gen definition="Proportion of children living in a household where someone smokes daily"
	tempfile 2005_2006
	save `2005_2006', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/ch_2005_2006", replace	
	
// 2004-2005
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2004_2005/GBR_WELSH_HEALTH_SURVEY_2004_2005_ADULT_DATA_Y2013M10D15.DTA"
rename *, lower 
// decode children in household
decode hhchild, gen(children)
order children archhsn
sort archhsn children
// collapse file for household - either parent smokes
replace smoked=. if smoked==-8
replace smoked=. if smoked==-9
keep smoked hhchild archpsn archhsn
collapse (mean) smoked hhchild archpsn, by(archhsn)  
// if smoked is>0, that means someone in the household smokes daily
tempfile adult
save `adult', replace

clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2004_2005/GBR_WELSH_HEALTH_SURVEY_2004_2005_CHILD_DATA_Y2013M10D15.DTA"
merge m:1 archhsn using `adult'

/*
when _merge==1 (23 observations), this is data for children, but the adult questionnaire wasn't filled out by the household
count if _merge==2 & hhchild==1
when _merge==2 (6535), this is when the adult said there are no children in the household, or the adult said there are children in the household, but the child questionnaire wasn't filled out (53 of the 6535)
this should all be adjusted for in the weights
*/
keep if _merge==3
drop _merge
/*
"Non-response weights adjusted for non-response at the household and individual level to account for non-contact and refusals of entire households, and for non-response among individuals within responding households. The final weights arrived at are applied at the individual level separately for adults and children (wt_adult and wt_child)."
*/
svyset [pweight=wt_child]

// someone in the household smokes
replace smoked=1 if smoked>0 
tempfile data
save `data', replace
gen year_start=2004
gen year_end=2005
keep year* childage
collapse (mean) year_start year_end, by(childage) fast
decode childage, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof childage, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & childage==`ages'): prop smoked, over(sex childage) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 				
	}
}
}

	gen year_start=2004
	gen year_end=2005
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year_start year_end) fast
	reshape long mean se lower upper sample, i(year_start year_end) j(sex_childage)string
	split sex_childage, p("_")
	drop sex_childage sex_childage1
	rename sex_childage2 sex
	rename sex_childage3 childage
	destring sex, replace
	destring childage, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2004_2005/GBR_WELSH_HEALTH_SURVEY_2004_2005_CHILD_DATA_Y2013M10D15.DTA"
	merge m:1 childage using `age_m'
	drop childage
	drop _merge
	gen definition="Proportion of children living in a household where someone smokes daily"
	tempfile 2004_2005
	save `2004_2005', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/ch_2004_2005", replace	
	
// 2003-2004
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2003_2004/GBR_WELSH_HEALTH_SURVEY_2003_2004_ADULT_DATA_Y2013M10D15.DTA"
rename *, lower 
// decode children in household
decode hhchild, gen(children)
order children archhsn
sort archhsn children
// collapse file for household - either parent smokes
replace smoked=. if smoked==-8
replace smoked=. if smoked==-9
keep smoked hhchild archpsn archhsn
collapse (mean) smoked hhchild archpsn, by(archhsn)  
// if smoked is>0, that means someone in the household smokes daily
tempfile adult
save `adult', replace

clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/2003_2004/GBR_WELSH_HEALTH_SURVEY_2003_2004_CHILD_DATA_Y2013M10D15.DTA"
merge m:1 archhsn using `adult'

/*
when _merge==1 (99 observations), this is data for children, but the adult questionnaire wasn't filled out by the household
count if _merge==2 & hhchild==1
when _merge==2 (6597), this is when the adult said there are no children in the household, or the adult said there are children in the household, but the child questionnaire wasn't filled out (59 of the 6597)
this should all be adjusted for in the weights
*/
keep if _merge==3
drop _merge
/*
"The final weights arrived at are applied at the individual level for both adults and children (int_wt)."
*/
svyset [pweight=int_wt]

// someone in the household smokes
replace smoked=1 if smoked>0 
tempfile data
save `data', replace
gen year_start=2003
gen year_end=2004
keep year* childage
collapse (mean) year_start year_end, by(childage) fast
decode childage, gen(age_cat)
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof childage, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & childage==`ages'): prop smoked, over(sex childage) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & childage==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & childage==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & childage==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & childage==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & childage==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & childage==`ages' 				
	}
}
}

	gen year_start=2003
	gen year_end=2004
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year_start year_end) fast
	reshape long mean se lower upper sample, i(year_start year_end) j(sex_childage)string
	split sex_childage, p("_")
	drop sex_childage sex_childage1
	rename sex_childage2 sex
	rename sex_childage3 childage
	destring sex, replace
	destring childage, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/2003_2004/GBR_WELSH_HEALTH_SURVEY_2003_2004_CHILD_DATA_Y2013M10D15.DTA"
	merge m:1 childage using `age_m'
	drop childage
	drop _merge
	gen definition="Proportion of children living in a household where someone smokes daily"
	tempfile 2003_2004
	save `2003_2004', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/ch_2003_2004", replace	

/*	
// 1998
clear
use "J:/DATA/GBR/WELSH_HEALTH_SURVEY/1998/GBR_WELSH_HEALTH_SURVEY_1998_DATA_Y2013M10D15.DTA"
rename *, lower 
// age_1 is the 5 year age band for the adult respondent. It looks like q43b_* refer to the age of the children.  However, there is not information on the sex of the child.
order q43b_*
foreach v in q43b_1 q43b_2 q43b_3 q43b_4 {
replace `v'=. if `v'==-99.99
}

// smoking status is q48
	// only current daily smokers are counted as smokers
	decode q48, gen(smoked)
	replace q48=0 if q48==2
	replace q48=0 if q48==3
	replace q48=0 if q48==4
	replace q48=0 if q48==5
// shs: "q49": "how many other people in household smoke now?"
	decode q49, gen(shs)
	order shs q49
	sort q49
	replace q49=0 if q49==1
	replace q49=1 if q49>=2
	replace q49=. if q49==-99.99
	// can't be exposed to shs if daily smoker
	replace q49=0 if q48==1
	levelsof q49
	
svyset [pweight=zzwght]

// no actual age variable. Only variable is "age5yrm" - "5 year age bands with 75+ merged"
// tempfile age to merge on later
rename q50 sex
rename age_1 age5yrm
// there are no response/refusal ages
replace age5yrm=. if age5yrm==-99.99
tempfile data
save `data', replace
gen year=1998
keep year age5yrm
collapse (mean) year, by(age5yrm) fast
decode age5yrm, gen(age_cat)
drop if age5yrm==.
tempfile age_m
save `age_m', replace
clear
use `data'
		
		levelsof sex, local(sex)
		levelsof age5yrm, local(age)
			
		foreach ages of local age {
		foreach sexs of local sex {
		
			capture noisily svy, subpop(if sex==`sexs' & age5yrm==`ages' & q48==0): prop q49, over(sex age5yrm) 
			if _rc {
			
			local mean=0
			local variance=0
			local se=0
			local degrees_freedom=0
			
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 	
			
			
			}
			else {
			
					
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean=mean_matrix[1,2]
			local variance=variance_matrix[1,1]
			local se=sqrt(`variance')
			local degrees_freedom=`e(df_r)' 
			count if sex==`sexs' & age5yrm==`ages' 
			local total=`r(N)'
			gen sample_`sexs'_`ages'=`total' if sex==`sexs' & age5yrm==`ages' 
			
			gen mean_`sexs'_`ages'=.
			replace mean_`sexs'_`ages'=`mean' if sex==`sexs' & age5yrm==`ages' 
								
			gen se_`sexs'_`ages'=.
			replace se_`sexs'_`ages'=`se' if sex==`sexs' & age5yrm==`ages' 
			
			gen upper_`sexs'_`ages'=.
			replace upper_`sexs'_`ages'=invlogit(logit(`mean') + (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean'))) if sex==`sexs' & age5yrm==`ages' 
			
			gen lower_`sexs'_`ages'=.
			replace lower_`sexs'_`ages'=invlogit(logit(`mean') - (invttail(`degrees_freedom', .025) * `se') / (`mean' * (1 - `mean')))  if sex==`sexs' & age5yrm==`ages' 				
	}
}
}

	gen year=1998
	collapse (mean) mean_* se_* lower_* upper_* sample_*, by(year) fast
	reshape long mean se lower upper sample, i(year) j(sex_age5yrm)string
	split sex_age5yrm, p("_")
	drop sex_age5yrm sex_age5yrm1
	rename sex_age5yrm2 sex
	rename sex_age5yrm3 age5yrm
	destring sex, replace
	destring age5yrm, replace
	gen file="J:/DATA/GBR/WELSH_HEALTH_SURVEY/1998/GBR_WELSH_HEALTH_SURVEY_1998_DATA_Y2013M10D15.DTA"
	merge m:1 age5yrm using `age_m'
	drop age5yrm
	drop _merge
	gen definition="how many other people in household smoke now?"
	tempfile 1998
	save `1998', replace
	save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey/1998", replace	
*/

// append adult and child
	clear
	cd "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/raw/wales_health_survey"

	local i=0
	cap erase wales_1998_2011_miss_1998_child.dta
	local files : dir . files "*.dta"

	foreach f of local files {
		drop _all
		use "`f'"
		if `i'>0 append using wales_1998_2011_miss_1998_child
		save wales_1998_2011_miss_1998_child, replace
		local i=1
		}

// some fixes
replace year_start=year if year_start==.
replace year_end=year_start if year_end==.
drop year

// save
save "J:/WORK/05_risk/02_models/02_data/smoking/smoking_shs/exp/prepped/wales_1998_2011_miss_1998_child"






