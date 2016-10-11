* July 14, 2010
* Create Template File onto which Prev, Fraction Married, and Population can be merged


clear all
set mem 700m
set more off
set trace off
set maxvar 30000
cap log close

// store locals
	local countrycodes "J:\Usable\Common Indicators\Country Codes\countrycodes_official.dta"


// create template from country code dataset; merge with population
	use iso3 ihme_country countryname countryname_ihme  wb_income_group_short gbd_developing ///
		gbd_region gbd_super_region using "`countrycodes'", clear
	keep if countryname==countryname_ihme & ihme_country==1 
	drop if iso3==""
	drop countryname

	gen agegroup=.
	gen year=.

// create agegroup categories
	gen rep=7
	expand rep
	bysort iso3: egen tmp=seq()

	scalar x=1
	scalar z=15

	forvalues i=1(1)7 {
		bysort iso3: replace agegroup=z if tmp==x
		
		scalar z=z+5
		scalar x=x+1
	}
	drop tmp rep

// create year categories
	sort iso3 agegroup
	gen rep=36
	expand rep
	bysort iso3 agegroup: egen tmp=seq()

	scalar x=1
	scalar z=1980

	forvalues i=1(1)36{
		bysort iso3 agegroup: replace year=z if tmp==x
		
		scalar z=z+1
		scalar x=x+1
	}
	drop tmp rep

	order iso3 year agegroup countryname_ihme
	sort iso3 year agegroup
	
// save new dataset
	save "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\template.dta", replace