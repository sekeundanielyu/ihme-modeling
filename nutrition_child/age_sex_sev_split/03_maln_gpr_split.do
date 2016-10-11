// Apply the age sex sev split prop to the gpr result, set the gpr result for developed area to 0
/* Update in 6/14/2016: only include Austrlasia, High-income Asia Pacific, High-income North America and Western Europe */


clear all
set more off
cap log off
set maxvar 8000

//Set directories
	if c(os) == "Unix" {
		global j "/home/j"
		set more off
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j "J:"
	}

********************************* 
local maltype "heightforage" 
local malnutrition "stunting"
local famine_adj 0
local run_id 137
local version 4
*********************************
if `famine_adj'==0{
local gpr	"$j/WORK/05_risk/risks/nutrition_`malnutrition'/01_exposure/02_analysis/02_data/03_gpr_output/draws_run`run_id'.dta" 
}
if `famine_adj'==1 {
local gpr	"$j/WORK/05_risk/risks/nutrition_`malnutrition'/01_exposure/02_analysis/02_data/03_gpr_output/draws_run`run_id'_adj.dta" 	
}

local proportion 	"$j/WORK/05_risk/risks/nutrition_`malnutrition'/01_exposure/02_analysis/02_data/04_split_age_sex_sev/split_age_sex_sev_prop.dta"
local output 	"$j/WORK/05_risk/risks/nutrition_`malnutrition'/01_exposure/03_output/`version'"

// get location information
include "$j/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
get_location_metadata, location_set_id(9)
keep location_id location_ascii_name ihme_loc_id developed region_name
tempfile loc
save `loc',replace 

// Bring in GPR
use `gpr',clear 	

// modifiy draw names from 0-999 to 1-1000
forvalues i=0(1)999 {
	local p=`i'+1
	rename draw_`i' draw_`p'_gpr
		}

// split gpr result by age_group_id sex severity
	// sex
	gen sex=1
	expand 2, gen(exp)
	replace sex=2 if exp==1 
	drop exp sex_id
	// age_group_id
	expand 2, gen(exp)
	replace age_group_id=2 if exp==1
	replace age_group_id=3 if exp==0
	drop exp
	expand 2 if age_group_id==2, gen(exp) 
	replace age_group_id=4 if exp==1
	drop exp
	expand 2 if age_group_id==4, gen(exp) 
	replace age_group_id=5 if exp==1
	drop exp

	// agegrp
	gen agegrp=.
	replace agegrp=1 if age_group_id==2 | age_group_id==3
	replace agegrp=2 if age_group_id==4
	replace agegrp=3 if age_group_id==5

	// severity 
	gen str sev="3"
	expand 2, gen(exp)
	replace sev="2_3" if exp==1 
	drop exp
	expand 2 if sev=="2_3", gen(exp)
	replace sev="1_2/over2" if exp==1 
	drop exp
	expand 2 if sev=="1_2/over2", gen(exp)
	replace sev="over1/over2" if exp==1
	drop exp

	// replace the gpr result =1-draw for sev=over1/over2 to get the prevalence of over2 instead of <2sd 
	forvalues i=1(1)1000{
		replace draw_`i'_gpr=1-draw_`i'_gpr if sev=="over1/over2" | sev=="1_2/over2"
	}
	// merge GPR results with the prop
	merge m:1 agegrp sex sev using `proportion', keep(3) nogen

	// multiple the gpr draws with prop
	forvalues i=1(1)1000{
	gen draw_`i'_split=draw_`i'_gpr*draw_`i'_prop
	}
	drop draw*gpr draw*prop agegrp
	// rename draws
	forvalues i=1(1)1000{
		local p=`i'-1
		rename draw_`i'_split draw_`p'
	}

	replace sev="over1" if sev=="over1/over2"
	replace sev="1_2" if sev=="1_2/over2"
// gen variable parameter to indicate different  cat
	gen str parameter=""
	replace parameter="cat1" if sev=="3"
	replace parameter="cat2" if sev=="2_3"
	replace parameter="cat3" if sev=="1_2"
	replace parameter="cat4" if sev=="over1"
	
	
// set all high income areas to zero prevalence of malnutriton
merge m:1 location_id using `loc', keep(3) nogen
gen highincome=developed
/*IND,KEN,SAU subnational locations do not have developed variable, but they suppose to be 0*/
// set Taiwan Hong Kong Macao developed area 
replace highincome="1" if ihme_loc_id=="TWN" | ihme_loc_id=="CHN_354"|ihme_loc_id=="CHN_361"
// set Central, Eastern and Caribean not high income 
replace highincome="0" if region_name=="Caribbean" | region_name=="Central Europe"| region_name=="Eastern Europe"

// replace all prevalence of malnutrition in developed area to 0
preserve 
keep if highincome=="1" & sev !="over1"
forvalues i=0(1)999{
replace draw_`i'=0
}
tempfile setzero
save `setzero',replace 
restore 

preserve 
keep if highincome=="1" & sev=="over1"
forvalues i=0(1)999{
replace draw_`i'=1
}
tempfile setone
save `setone',replace 
restore 

drop if highincome=="1"
append using `setzero'
append using `setone'

// save the long split result
save "`output'/nutrition_`malnutrition'_splitted",replace 
