// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 			December 17, 2013
// Modified:		--
// Project:		GBD
// Purpose:		Physical activity extraction

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

					
// One STEPS survey to start off
clear
use J:\DATA\WHO_STEPS_NCD\SAU\2004_2005\SAU_STEPS_NCD_2004_2005.DTA 

keep if age >= 25  // only care about respondents 25 and above for physical inactivity risk

foreach var in p2 p5 p8 p11 p14 {
replace `var'=. if `var'>7
}

foreach var in p3 p6 p9 p12 p15 {
replace `var'=. if `var'>16
}

// total met-minutes per week
gen total_mets = ((p2 * p3 * 60 * 8) + (p5 * p6 * 60 * 4) + (p8 * p9 * 60 * 4) + (p11 * p12 * 60 * 8) + (p14 * p15 * 60 * 4)) 

gen total_hrs = p3 + p6 + p9 + p12 + p15
replace total_mets = . if total_hrs>16

gen sex=c1

	// Set age groups
		egen gbd_age = cut(age), at(0, 0.01917808, 0.07671233, 1, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 999)

	// Make categorical physical activity variables
		gen inactive = total_mets < 600
		gen modactive = total_mets >= 600 & total_mets < 3000
		gen highactive = total_mets >= 3000 & total_mets != .
		recode inactive modactive highactive (0=.) if total_mets == .	
		
	// Set survey weights
		svyset [pweight=combined_wt]
		gen filepath="J:\DATA\WHO_STEPS_NCD\SAU\2004_2005\SAU_STEPS_NCD_2004_2005.DTA"			
		
	// 3 loops: one for inactive, one for moderate active, one for high active
		forvalues loop=1/3 {		
			levelsof sex, local(sex)
			levelsof gbd_age, local(age)
		
	// inactive
			if `loop'==1 {
				foreach ages of local age {
				foreach sexs of local sex {
		
				capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages'): mean inactive
				if _rc {
				
				local mean_inactive=0 
				local variance_inactive=0
				local se_inactive=0
				
				count if sex==`sexs' & gbd_age==`ages' & `loop'==1
				local total=`r(N)'
				gen sample_inactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
				
				gen mean_inactive_`sexs'_`ages'=.
				replace mean_inactive_`sexs'_`ages'=`mean_inactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_inactive_`sexs'_`ages'=.
				replace se_inactive_`sexs'_`ages'=`se_inactive' if sex==`sexs' & gbd_age==`ages' 	
			
			}
			else {
							
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean_inactive=mean_matrix[1,1]
			local variance_inactive=variance_matrix[1,1]
			local se_inactive=sqrt(`variance_inactive')
			
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_inactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_inactive_`sexs'_`ages'=.
			replace mean_inactive_`sexs'_`ages'=`mean_inactive' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_inactive_`sexs'_`ages'=.
			replace se_inactive_`sexs'_`ages'=`se_inactive' if sex==`sexs' & gbd_age==`ages' 
						
	}
}
}
	}
	// moderate activity
			if `loop'==2 {
	
				foreach ages of local age {
				foreach sexs of local sex {
	
				capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages'): mean modactive
				if _rc {
				
				local mean_modactive=0
				local variance_modactive=0
				local se_modactive=0
				
				count if sex==`sexs' & gbd_age==`ages' 
				local total=`r(N)'
				gen sample_modactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages'
				
				gen mean_modactive_`sexs'_`ages'=.
				replace mean_modactive_`sexs'_`ages'=`mean_modactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_modactive_`sexs'_`ages'=.
				replace se_modactive_`sexs'_`ages'=`se_modactive' if sex==`sexs' & gbd_age==`ages' 
			
			}
			else {
							
				matrix mean_matrix=e(b)
				matrix variance_matrix=e(V)
				local mean_modactive=mean_matrix[1,1]
				local variance_modactive=variance_matrix[1,1]
				local se_modactive=sqrt(`variance_modactive')
				
				count if sex==`sexs' & gbd_age==`ages' 
				local total=`r(N)'
				gen sample_modactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
				
				gen mean_modactive_`sexs'_`ages'=.
				replace mean_modactive_`sexs'_`ages'=`mean_modactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_modactive_`sexs'_`ages'=.
				replace se_modactive_`sexs'_`ages'=`se_modactive' if sex==`sexs' & gbd_age==`ages' 

	}
}
}
	}
	// vigorous activity
			if `loop'==3 {
	
				foreach ages of local age {
				foreach sexs of local sex {
	
				capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages'): mean highactive
				if _rc {
				
				local mean_highactive=0
				local variance_highactive=0
				local se_highactive=0
				
				count if sex==`sexs' & gbd_age==`ages' 
				local total=`r(N)'
				gen sample_highactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages'
				
				gen mean_highactive_`sexs'_`ages'=.
				replace mean_highactive_`sexs'_`ages'=`mean_highactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_highactive_`sexs'_`ages'=.
				replace se_highactive_`sexs'_`ages'=`se_highactive' if sex==`sexs' & gbd_age==`ages' 
			
			}
			else {
							
				matrix mean_matrix=e(b)
				matrix variance_matrix=e(V)
				local mean_highactive=mean_matrix[1,1]
				local variance_highactive=variance_matrix[1,1]
				local se_highactive=sqrt(`variance_highactive')
				
				count if sex==`sexs' & gbd_age==`ages' 
				local total=`r(N)'
				gen sample_highactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
				
				gen mean_highactive_`sexs'_`ages'=.
				replace mean_highactive_`sexs'_`ages'=`mean_highactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_highactive_`sexs'_`ages'=.
				replace se_highactive_`sexs'_`ages'=`se_highactive' if sex==`sexs' & gbd_age==`ages' 

	}
}
}
	}

}

	
	gen file="J:\DATA\WHO_STEPS_NCD\SAU\2004_2005\SAU_STEPS_NCD_2004_2005.DTA"
	collapse (mean) mean_* se_* sample_*, by(file) fast
	reshape long mean_inactive mean_modactive mean_highactive se_inactive se_modactive se_highactive sample_inactive sample_modactive sample_highactive, i(file) j(sex_gbd_age)string
	split sex_gbd_age, p("_")
	drop sex_gbd_age sex_gbd_age1
	rename sex_gbd_age2 sex
	rename sex_gbd_age3 gbd_age
	destring gbd_age, replace	
	destring sex, replace
	gen age_start = gbd_age
	gen age_end = gbd_age + 4
	drop gbd_age
	drop sample_modactive sample_highactive
	rename sample_inactive sample_size
		
		// save
		save "J:/WORK/05_risk/risks/activity/data/exp/raw/SAU_2004_2005", replace
/*
// Brazil
clear
use J:\DATA\BRA\RISK_FACTOR_MORBIDITY_NCD_SURVEY\2002_2005\BRA_RISK_FACTOR_MORBIDITY_NCD_SURVEY_2002_2005_PHYSICAL_ACTIVITY.DTA 
rename idade age
gen sex = sexo

















		
// Cebu - Mother_girls_activity
clear
use "J:\DATA\PHL\CEBU_LONGITUDINAL_HEALTH_AND_NUTRITION_SURVEY\1998_2000\PHL_CEBU_CLHNS_1998_2000_MOTHER_GIRLS_ACTIVITY.DTA"
merge 1:1 basebrgy basehhno basewman mobrgy94 mohhno94 mowman94 using "J:\DATA\PHL\CEBU_LONGITUDINAL_HEALTH_AND_NUTRITION_SURVEY\1998_2000\PHL_CEBU_CLHNS_1998_2000_MOTHER_BOYS_ACTIVITY.DTA"

// wakeact coding:









// 81162	TUR	Turkey Health Interview Survey 2008
clear
use J:\DATA\TUR\HEALTH_INTERVIEW_SURVEY\2008\TUR_HEALTH_INTERVIEW_SURVEY_2008_Y2012M01D09.DTA
// self-report height and weight only for 15+
rename S114000000 moderate_days
rename S112000000 vigorous_days
rename S116000000 walk_days



rename B02S04 sex
encode(YAS_GRUBU), gen(gbd_age)		
svyset [pweight=yeni_faktor]


// NHIS
clear
use "J:\WORK\05_risk\02_models\02_data\physical_inactivity\exp\raw\nhis\samadult_2009.dta"
svyset psu_p [pweight=wtfa_sa], strata(strat_p)
rename age_p age

keep if age >= 25  // only care about respondents 25 and above for physical inactivity risk

foreach var in p2 p5 p8 p11 p14 {
replace `var'=. if `var'>7
}

foreach var in p3 p6 p9 p12 p15 {
replace `var'=. if `var'>16
}

// total met-minutes per week
gen total_mets = (vigtp 
gen total_mets = ((p2 * p3 * 60 * 8) + (p5 * p6 * 60 * 4) + (p8 * p9 * 60 * 4) + (p11 * p12 * 60 * 8) + (p14 * p15 * 60 * 4)) 

gen total_hrs = p3 + p6 + p9 + p12 + p15
replace total_mets = . if total_hrs>16

gen sex=c1

	// Set age groups
		egen gbd_age = cut(age), at(0, 0.01917808, 0.07671233, 1, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 999)

	// Make categorical physical activity variables
		gen inactive = total_mets < 600
		gen modactive = total_mets >= 600 & total_mets < 3000
		gen highactive = total_mets >= 3000 & total_mets != .
		recode inactive modactive highactive (0=.) if total_mets == .	
		
	// Set survey weights
		svyset [pweight=combined_wt]
		gen filepath="J:\DATA\WHO_STEPS_NCD\SAU\2004_2005\SAU_STEPS_NCD_2004_2005.DTA"			
		
	// 3 loops: one for inactive, one for moderate active, one for high active
		forvalues loop=1/3 {		
			levelsof sex, local(sex)
			levelsof gbd_age, local(age)
		
	// inactive
			if `loop'==1 {
				foreach ages of local age {
				foreach sexs of local sex {
		
				capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages'): mean inactive
				if _rc {
				
				local mean_inactive=0 
				local variance_inactive=0
				local se_inactive=0
				
				count if sex==`sexs' & gbd_age==`ages' & `loop'==1
				local total=`r(N)'
				gen sample_inactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
				
				gen mean_inactive_`sexs'_`ages'=.
				replace mean_inactive_`sexs'_`ages'=`mean_inactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_inactive_`sexs'_`ages'=.
				replace se_inactive_`sexs'_`ages'=`se_inactive' if sex==`sexs' & gbd_age==`ages' 	
			
			}
			else {
							
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean_inactive=mean_matrix[1,1]
			local variance_inactive=variance_matrix[1,1]
			local se_inactive=sqrt(`variance_inactive')
			
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_inactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_inactive_`sexs'_`ages'=.
			replace mean_inactive_`sexs'_`ages'=`mean_inactive' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_inactive_`sexs'_`ages'=.
			replace se_inactive_`sexs'_`ages'=`se_inactive' if sex==`sexs' & gbd_age==`ages' 
						
	}
}
}
	}
	// moderate activity
			if `loop'==2 {
	
				foreach ages of local age {
				foreach sexs of local sex {
	
				capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages'): mean modactive
				if _rc {
				
				local mean_modactive=0
				local variance_modactive=0
				local se_modactive=0
				
				count if sex==`sexs' & gbd_age==`ages' 
				local total=`r(N)'
				gen sample_modactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages'
				
				gen mean_modactive_`sexs'_`ages'=.
				replace mean_modactive_`sexs'_`ages'=`mean_modactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_modactive_`sexs'_`ages'=.
				replace se_modactive_`sexs'_`ages'=`se_modactive' if sex==`sexs' & gbd_age==`ages' 
			
			}
			else {
							
				matrix mean_matrix=e(b)
				matrix variance_matrix=e(V)
				local mean_modactive=mean_matrix[1,1]
				local variance_modactive=variance_matrix[1,1]
				local se_modactive=sqrt(`variance_modactive')
				
				count if sex==`sexs' & gbd_age==`ages' 
				local total=`r(N)'
				gen sample_modactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
				
				gen mean_modactive_`sexs'_`ages'=.
				replace mean_modactive_`sexs'_`ages'=`mean_modactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_modactive_`sexs'_`ages'=.
				replace se_modactive_`sexs'_`ages'=`se_modactive' if sex==`sexs' & gbd_age==`ages' 

	}
}
}
	}
	// vigorous activity
			if `loop'==3 {
	
				foreach ages of local age {
				foreach sexs of local sex {
	
				capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages'): mean highactive
				if _rc {
				
				local mean_highactive=0
				local variance_highactive=0
				local se_highactive=0
				
				count if sex==`sexs' & gbd_age==`ages' 
				local total=`r(N)'
				gen sample_highactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages'
				
				gen mean_highactive_`sexs'_`ages'=.
				replace mean_highactive_`sexs'_`ages'=`mean_highactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_highactive_`sexs'_`ages'=.
				replace se_highactive_`sexs'_`ages'=`se_highactive' if sex==`sexs' & gbd_age==`ages' 
			
			}
			else {
							
				matrix mean_matrix=e(b)
				matrix variance_matrix=e(V)
				local mean_highactive=mean_matrix[1,1]
				local variance_highactive=variance_matrix[1,1]
				local se_highactive=sqrt(`variance_highactive')
				
				count if sex==`sexs' & gbd_age==`ages' 
				local total=`r(N)'
				gen sample_highactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
				
				gen mean_highactive_`sexs'_`ages'=.
				replace mean_highactive_`sexs'_`ages'=`mean_highactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_highactive_`sexs'_`ages'=.
				replace se_highactive_`sexs'_`ages'=`se_highactive' if sex==`sexs' & gbd_age==`ages' 

	}
}
}
	}

}

	
	gen file="J:\WORK\05_risk\02_models\02_data\physical_inactivity\exp\raw\nhis\samadult_2009.dta"
	collapse (mean) mean_* se_* sample_*, by(file) fast
	reshape long mean_inactive mean_modactive mean_highactive se_inactive se_modactive se_highactive sample_inactive sample_modactive sample_highactive, i(file) j(sex_gbd_age)string
	split sex_gbd_age, p("_")
	drop sex_gbd_age sex_gbd_age1
	rename sex_gbd_age2 sex
	rename sex_gbd_age3 gbd_age
	destring gbd_age, replace	
	destring sex, replace
	gen age_start = gbd_age
	gen age_end = gbd_age + 4
	drop gbd_age
	drop sample_modactive sample_highactive
	rename sample_inactive sample_size
		
		// save
		save "J:\WORK\05_risk\02_models\02_data\physical_inactivity\exp\raw\nhis\2009", replace
*/

// NHIS - PA started to be measured in 98

forvalues year = 1998(1)2012 {

clear
use "J:\WORK\05_risk\02_models\02_data\physical_inactivity\exp\raw\nhis\samadult_`year'.dta"

// times per week

foreach domain in vig mod {
 
decode (`domain'freqw), gen (`domain'_t_w_decode)
replace `domain'_t_w_decode = lower(`domain'_t_w_decode)
gen `domain'_t_w=`domain'freqw


replace `domain'_t_w = . if regexm(`domain'_t_w_decode,"don't know") | regexm(`domain'_t_w_decode,"dont know") | regexm(`domain'_t_w_decode,"don't know") | regexm(`domain'_t_w_decode,"not ascertained") | regexm(`domain'_t_w_decode,"refused") 
replace `domain'_t_w = 0 if regexm(`domain'_t_w_decode,"unable") |  regexm(`domain'_t_w_decode,"never")

// month or year response
decode `domain'tp, gen(`domain'_month_year_decode)
replace `domain'_t_w = `domain'no / 4 if regexm(`domain'_month_year_decode,"month")  

replace `domain'_t_w = `domain'no / 12 / 4 if regexm(`domain'_month_year_decode,"year") 


}


// minutes 
foreach domain in vig mod {
 
decode (`domain'min), gen (`domain'_min_decode)
replace `domain'_min_decode = lower(`domain'_min_decode)
gen `domain'_min=`domain'min


replace `domain'_min = . if regexm(`domain'_t_w_decode,"don't know") | regexm(`domain'_t_w_decode,"dont know") | regexm(`domain'_t_w_decode,"don't know") | regexm(`domain'_t_w_decode,"not ascertained") | regexm(`domain'_t_w_decode,"refused") 
replace `domain'_min = 0 if regexm(`domain'_t_w_decode,"unable") |  regexm(`domain'_t_w_decode,"never")

}

// total met minutes per week
gen total_mets = (vig_t_w * vig_min * 8) + (mod_t_w * mod_min * 4)


rename age_p age
keep if age>=25

lookfor wtfa_
local weight = r(varlist)
rename `weight' weight

lookfor stratum
local strata = r(varlist)
rename `strata' strat

lookfor psu
local psu = r(varlist)
rename `psu' primary_sample_unit

svyset primary_sample_unit [pweight=weight], strata(strat)

	// Set age groups
		egen gbd_age = cut(age), at(0, 0.01917808, 0.07671233, 1, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 999)
		// 85+
		decode age, gen(age_decode)
		replace gbd_age=85 if regexm(age_decode,"85+")

	// Make categorical physical activity variables
		gen inactive = total_mets < 600
		gen modactive = total_mets >= 600 & total_mets < 3000
		gen highactive = total_mets >= 3000 & total_mets != .
		recode inactive modactive highactive (0=.) if total_mets == .	

		gen filepath="J:\WORK\05_risk\02_models\02_data\physical_inactivity\exp\raw\nhis\samadult_`year'.dta"	
		
	// 3 loops: one for inactive, one for moderate active, one for high active
		forvalues loop=1/3 {		
			levelsof sex, local(sex)
			levelsof gbd_age, local(age)
		
	// inactive
			if `loop'==1 {
				foreach ages of local age {
				foreach sexs of local sex {
		
				capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages'): mean inactive
				if _rc {
				
				local mean_inactive=0 
				local variance_inactive=0
				local se_inactive=0
				
				count if sex==`sexs' & gbd_age==`ages' & `loop'==1
				local total=`r(N)'
				gen sample_inactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
				
				gen mean_inactive_`sexs'_`ages'=.
				replace mean_inactive_`sexs'_`ages'=`mean_inactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_inactive_`sexs'_`ages'=.
				replace se_inactive_`sexs'_`ages'=`se_inactive' if sex==`sexs' & gbd_age==`ages' 	
			
			}
			else {
							
			matrix mean_matrix=e(b)
			matrix variance_matrix=e(V)
			local mean_inactive=mean_matrix[1,1]
			local variance_inactive=variance_matrix[1,1]
			local se_inactive=sqrt(`variance_inactive')
			
			count if sex==`sexs' & gbd_age==`ages' 
			local total=`r(N)'
			gen sample_inactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
			
			gen mean_inactive_`sexs'_`ages'=.
			replace mean_inactive_`sexs'_`ages'=`mean_inactive' if sex==`sexs' & gbd_age==`ages' 
								
			gen se_inactive_`sexs'_`ages'=.
			replace se_inactive_`sexs'_`ages'=`se_inactive' if sex==`sexs' & gbd_age==`ages' 
						
	}
}
}
	}
	// moderate activity
			if `loop'==2 {
	
				foreach ages of local age {
				foreach sexs of local sex {
	
				capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages'): mean modactive
				if _rc {
				
				local mean_modactive=0
				local variance_modactive=0
				local se_modactive=0
				
				count if sex==`sexs' & gbd_age==`ages' 
				local total=`r(N)'
				gen sample_modactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages'
				
				gen mean_modactive_`sexs'_`ages'=.
				replace mean_modactive_`sexs'_`ages'=`mean_modactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_modactive_`sexs'_`ages'=.
				replace se_modactive_`sexs'_`ages'=`se_modactive' if sex==`sexs' & gbd_age==`ages' 
			
			}
			else {
							
				matrix mean_matrix=e(b)
				matrix variance_matrix=e(V)
				local mean_modactive=mean_matrix[1,1]
				local variance_modactive=variance_matrix[1,1]
				local se_modactive=sqrt(`variance_modactive')
				
				count if sex==`sexs' & gbd_age==`ages' 
				local total=`r(N)'
				gen sample_modactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
				
				gen mean_modactive_`sexs'_`ages'=.
				replace mean_modactive_`sexs'_`ages'=`mean_modactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_modactive_`sexs'_`ages'=.
				replace se_modactive_`sexs'_`ages'=`se_modactive' if sex==`sexs' & gbd_age==`ages' 

	}
}
}
	}
	// vigorous activity
			if `loop'==3 {
	
				foreach ages of local age {
				foreach sexs of local sex {
	
				capture noisily svy, subpop(if sex==`sexs' & gbd_age==`ages'): mean highactive
				if _rc {
				
				local mean_highactive=0
				local variance_highactive=0
				local se_highactive=0
				
				count if sex==`sexs' & gbd_age==`ages' 
				local total=`r(N)'
				gen sample_highactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages'
				
				gen mean_highactive_`sexs'_`ages'=.
				replace mean_highactive_`sexs'_`ages'=`mean_highactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_highactive_`sexs'_`ages'=.
				replace se_highactive_`sexs'_`ages'=`se_highactive' if sex==`sexs' & gbd_age==`ages' 
			
			}
			else {
							
				matrix mean_matrix=e(b)
				matrix variance_matrix=e(V)
				local mean_highactive=mean_matrix[1,1]
				local variance_highactive=variance_matrix[1,1]
				local se_highactive=sqrt(`variance_highactive')
				
				count if sex==`sexs' & gbd_age==`ages' 
				local total=`r(N)'
				gen sample_highactive_`sexs'_`ages'=`total' if sex==`sexs' & gbd_age==`ages' 
				
				gen mean_highactive_`sexs'_`ages'=.
				replace mean_highactive_`sexs'_`ages'=`mean_highactive' if sex==`sexs' & gbd_age==`ages'
									
				gen se_highactive_`sexs'_`ages'=.
				replace se_highactive_`sexs'_`ages'=`se_highactive' if sex==`sexs' & gbd_age==`ages' 

	}
}
}
	}

}

	
	gen file="J:\WORK\05_risk\02_models\02_data\physical_inactivity\exp\raw\nhis\samadult_`year'.dta"
	collapse (mean) mean_* se_* sample_*, by(file) fast
	reshape long mean_inactive mean_modactive mean_highactive se_inactive se_modactive se_highactive sample_inactive sample_modactive sample_highactive, i(file) j(sex_gbd_age)string
	split sex_gbd_age, p("_")
	drop sex_gbd_age sex_gbd_age1
	rename sex_gbd_age2 sex
	rename sex_gbd_age3 gbd_age
	destring gbd_age, replace	
	destring sex, replace
	gen age_start = gbd_age
	gen age_end = gbd_age + 4
		// 85+
		replace age_end=100 if age_end==89
	drop gbd_age
	drop sample_modactive sample_highactive
	rename sample_inactive sample_size
		
		// save
		tempfile `year'
		save ``year'', replace

}

clear
use `1998'
forvalues year = 1999(1)2012 {
append using ``year''
}

gen year=.
forvalues year = 1998(1)2012 {
replace year=`year' if regexm(file,"`year'")
}

save "J:\WORK\05_risk\02_models\02_data\physical_inactivity\exp\raw\nhis\analyzed\1998_2012", replace


// BOL 2008 DHS - Woman
clear
use J:\DATA\MACRO_DHS\BOL\2008\BOL_DHS5_2008_WN_Y2010M06D18.DTA 























/*
// compare with nhanes
levelsof age_start, local(ages)
foreach sex in 1 2 {
foreach age of local ages {
foreach active in mean_highactive mean_modactive mean_inactive {

twoway (scatter `active' year if sex==`sex' & age_start==`age' & source=="NHANES", sort msymbol(circle) mlabel(source)) (scatter `active' year if sex==`sex' & age_start==`age' & source=="NHIS", sort msymbol(square) mlabel(source)), yscale(range(0 1)) ylabel(#5) title(`sex'_`age'_`active')

graph export "C:\Users\strUser\Documents\Physical activity\nhanes_nhis_graph_`sex'_`age'_`active'.pdf"
}
}
}
*/















