// 03_maln_micro_prop_global 
// Using DHS, MICS microdata, calculate the proportion of undernutrition in most detailed severity categories (e.g <-3SD) over that in the broader severity categories (e.g. <-2SD) by GBD age-sex groups

clear all
set more off
cap log close 
//Set directories
	if c(os) == "Unix" {
		global j "/home/j"
		set more off
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j "J:"
	}
**************************************
local maltype "heightforage"
local malnutrition "stunting"
**************************************
local database "$j/WORK/05_risk/risks/nutrition_`malnutrition'/01_exposure/02_analysis/02_data/04_split_age_sex_sev/split_age_sex_sev_micro"
local output "$j/WORK/05_risk/risks/nutrition_`malnutrition'/01_exposure/02_analysis/02_data/04_split_age_sex_sev"


// Calculate the proportion of <3sd, 2_3sd out of <2sd by GBD age-sex groups
use `database', clear
keep if `maltype'_2sdneg==1 // all the cases for moderate and severe undernutrition, broader severity category 
gen count=.
tempfile total
save `total',replace 

local sev 2_3 //most-detailed severity cat, first calculate the prop for 2_3sd over <2 sd, then calculate for <-3sd over <-2sd by 1-the prop of -2to -3sd by age group and sex 
foreach v of local sev {
	use `total',clear
	gen str sev="`v'"
	local sex 1 2 
	foreach x of local sex {
		local agegrp 1 2 3 
		foreach a of local agegrp{
			count if `maltype'_`v'sd==1 & sex==`x' & agegrp==`a'
			replace count=r(N) if `maltype'_`v'sd==1 & sex==`x' & agegrp==`a'
			count if `maltype'_`v'sd==0 & sex==`x' & agegrp==`a'
			replace count=r(N) if `maltype'_`v'sd==0 & sex==`x' & agegrp==`a'
					}
				}
			collapse count, by (sex agegrp sev `maltype'_`v'sd)
			logit `maltype'_`v'sd i.agegrp i.sex [fweight=count]
			// generate variance-covariance matrix
			mat mean = e(b)
			mat cov = e(V)
	
	// get draws for coefficients using variance-covariance matrix		
	clear 
	drawnorm ag1c ag2c ag3c s1c s2c cons, n(1000) means(mean) cov(cov) cstorage(full)  // get 1000 draws using variance-covariance matrix
	// gen a square for each age sex group
	local age 1 2 3 
	foreach a of local age {
	gen ag`a'=0
	}
	local sex 1 2 
	foreach x of local sex {
		gen s`x'=0
	}
	tempfile temp
	save `temp',replace 

	// calculate the prop for each age-sex group
	local agegrp "ag1 ag2 ag3"
	foreach ag of local agegrp {
		use `temp',clear
		replace `ag'=1
		tempfile temp2
		save `temp2',replace 
		local sex "s1 s2"
		foreach se of local sex {
			use `temp2',clear 
			replace `se'=1 
			// calculate the prop for 2_3sd 
			gen p=invlogit(ag1*ag1c+ag2*ag2c+ag3*ag3c+s1*s1c+s2*s2c+cons) 
			gen obs=_n 
			drop *c cons
			quie reshape wide p,i(ag1 ag2 ag3 s1 s2) j(obs)
			forvalues i=1(1)1000{
			rename p`i' draw_`i'_prop
			}
			tempfile `ag'_`se'
			save ``ag'_`se'',replace 
		}
	}
		// append all proportions
 		use `ag1_s1',clear
 		append using `ag2_s1'
		append using `ag3_s1'
 		append using `ag1_s2'
		append using `ag2_s2'
 		append using `ag3_s2'

	// Expand and calculate the prop for <-3sd over <-2sd 
	gen str sev=""
	expand 2, gen(exp)
	replace sev="3" if exp==0
	replace sev="2_3" if exp==1 
	drop exp
	
	// replace draws of prop for <3sd=1-prop(2_3sd)
	forvalues i=1(1)1000{
		replace draw_`i'_prop=1-draw_`i'_prop if sev=="3"
	}
}
	tempfile severe_moderate
	save `severe_moderate',replace 


************************************************
// Calculate >-1SD/>-2SD: What proportion of over -1SD is over -2SD and the proportion of -1to-2 SD is over -2SD 
************************************************
use "`database'",clear 
gen `maltype'_over2=1- `maltype'_2sdneg // over -2sd 
gen `maltype'_over1=1- `maltype'_1sdneg // over -1sd 
keep if `maltype'_over2==1 // all the cases that are NOT moderate and severe malnutriton (mild + non-malnutrtion) 
gen count=.
save `total',replace 
local sev "over1"  // non-malnutrition
foreach v of local sev {
	use `total',clear
	gen str sev="`v'"
	local sex 1 2 
	foreach x of local sex {
		local agegrp 1 2 3 
		foreach a of local agegrp{
			count if `maltype'_`v'==1 & sex==`x' & agegrp==`a'
			replace count=r(N) if `maltype'_`v'==1 & sex==`x' & agegrp==`a'
			count if `maltype'_`v'==0 & sex==`x' & agegrp==`a'
			replace count=r(N) if `maltype'_`v'==0 & sex==`x' & agegrp==`a'
					}
				}
			collapse count, by (sex agegrp sev `maltype'_`v')
			logit `maltype'_`v' i.agegrp i.sex [fweight=count]
			// generate variance-covariance matrix
			mat mean = e(b)
			mat cov = e(V)
	
	// get draws for coefficients using variance-covariance matrix		
	clear 
	drawnorm ag1c ag2c ag3c s1c s2c cons, n(1000) means(mean) cov(cov) cstorage(full)  
	// gen a square for each age sex group
	local age 1 2 3 
	foreach a of local age {
	gen ag`a'=0
	}
	local sex 1 2 
	foreach x of local sex {
		gen s`x'=0
	}
	save `temp',replace 

	// calculate the prop for each age sex group
	local agegrp "ag1 ag2 ag3"
	foreach ag of local agegrp {
		use `temp',clear
		replace `ag'=1
		save `temp2',replace 
		local sex "s1 s2"
		foreach se of local sex {
			use `temp2',clear 
			replace `se'=1 
			// calculate the prop for 2_3sd 
			gen p=invlogit(ag1*ag1c+ag2*ag2c+ag3*ag3c+s1*s1c+s2*s2c+cons) // since the prop was in logit format 
			gen obs=_n 
			drop *c cons
			quie reshape wide p,i(ag1 ag2 ag3 s1 s2) j(obs)
			forvalues i=1(1)1000{
			rename p`i' draw_`i'_prop
			}
			save ``ag'_`se'',replace 
		}
	}
		// append all propotions for age sex groups together 
 		use `ag1_s1',clear
 		append using `ag2_s1'
		append using `ag3_s1'
 		append using `ag1_s2'
		append using `ag2_s2'
 		append using `ag3_s2'


	gen str sev="over1/over2"
	
// expand and the prop for 1_2/over2= 1-over1/_over2
	expand 2, gen(exp)
	replace sev="1_2/over2" if exp==1
	drop exp 


	// replace draws of proportion for 1_2sd=1-prop(over1/over2)
	forvalues i=1(1)1000{
		replace draw_`i'_prop=1-draw_`i'_prop if sev=="1_2/over2"
	}


	tempfile mild_none
	save `mild_none',replace 
}
	append using `severe_moderate'

	gen agegrp=.
	gen sex=.

	replace agegrp=1 if ag1==1
	replace agegrp=2 if ag2==1
	replace agegrp=3 if ag3==1
	replace sex=1 if s1==1
	replace sex=2 if s2==1

	drop ag1 ag2 ag3 s1 s2 
	order agegrp sex sev

save "`output'/split_age_sex_sev_prop",replace 

