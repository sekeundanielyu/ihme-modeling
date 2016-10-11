* July 13, 2016
* Create population file  from WPP2010 numbers 

clear all
set mem 700m
set maxvar 32000
set more off
set trace off
cap restore, not

local popdata = "J:\Project\Mortality\Population\UN Pop estimates\Data\01. formatted UN pop.dta"
local storedata = "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\output\POPULATION"

// open population dataset
use "`popdata'"

// only keep relevant variables
keep if sex=="female"
keep if year>=1980 & year<=2015
keep /* gbd_country */ iso3 region_name year sex pop_15_19 pop_20_24 pop_25_29 pop_30_34 pop_35_39 pop_40_44 pop_45_49

// rename vars
	rename pop_15_19 pop_15
	rename pop_20_24 pop_20
	rename pop_25_29 pop_25
	rename pop_30_34 pop_30
	rename pop_35_39 pop_35
	rename pop_40_44 pop_40
	rename pop_45_49 pop_45

// reshape wide to long
reshape long pop_, i(iso3 year) j(agegroup)

// make sure you know that population is in 1000s
label var pop_ "Population in 1000s"

// somehow verify that these are from the WPP (UN estimates)
gen source = "WPP2010"


save "`storedata'/population.dta", replace