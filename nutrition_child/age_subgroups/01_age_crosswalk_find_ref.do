// Match the data points taht do not have standard age range with references from DHS or MICS 
/*
(1) find exact match for country-year
(2) find approximate match in the same location
Subnational will use national reference
Run CHNS in seperate code 
*/
// set up
clear all
set more off 
set maxvar 10000
cap log close 
// Set directories
	if c(os) == "Windows" {
		global j "J:"
		set mem 1g
	}
	if c(os) == "Unix" {
		global j "/home/j"
		set mem 2g
		set odbcmgr unixodbc
	}

************************************
	**Set up
	local maltype "heightforage"
	local exposure "stunting"
************************************
	local curr_date = subinstr(c(current_date), " ", "", .)
	local age_xwalk_folder 	"$j/WORK/05_risk/risks/nutrition_`exposure'/01_exposure/02_analysis/02_data/02_maln_age_xwalk"
	local database 			"$j/WORK/05_risk/risks/nutrition_underweight/01_exposure/01_data audit/02_data/Complete Maln Database ALL datasources/Complete Dataset ALL datasources `curr_date'.dta"
	local varlist_dhs_file 		"$j/WORK/05_risk/risks/nutrition_underweight/01_exposure/01_data audit/02_data/01_DHS_prep/varlist_final_dhs_3Jul2016.dta"
	local varlist_mics_file		"$j/WORK/05_risk/risks/nutrition_underweight/01_exposure/01_data audit/02_data/02_MICS_prep/varlist_final_mics_6Jul2016.dta"

******************************************************************************************
		****Make a list of reference from DHS and MICS microdata at country level****
******************************************************************************************
// Bring in the GBD 2015 complete database 
	use "`database'",clear
	gen ref=0
	// identify the references from complete database 
	keep if reference=="DHS" | reference=="MICS"
	drop if regexm(ihme_loc_id,"_") // only use national data
	keep if regexm(filepath,"DTA") | regexm(filepath,"dta") 
	keep if agerep==1 & natlrep==1 // only use 0-59 mo microdata and national representative database
	replace ref=1 // indicate this is a reference 

	gen reference_ref=reference // reference for the "reference"
	gen year_id=avgyear // year_id for merge 
	gen year_id_ref=avgyear // year_id for the "reference"
	gen ihme_loc_id_ref=ihme_loc_id 

	keep ihme_loc_id* year_id* reference* ref samplesizen
	// There are duplications in terms of year_id and ihme_loc_id, choose the one with largest sample size 
	gsort ihme_loc_id year_id -samplesizen // sort descedingly by samplesize 
	bysort ihme_loc_id year_id: egen num = seq()
	drop if num >1 // only keep the largest sample size 
	drop num 

// merge with final varlist to eliminate surveys in odd ball (have estimate but cannot calculate prevalence in a batch)
	*DHS
	preserve 
	use "`varlist_dhs_file'",clear 
	rename (iso3) (ihme_loc_id_ref)	
	gen reference_ref="DHS"
	destring endyear,replace 
	egen year_id_ref=rowmean(startyear endyear)
	replace year_id_ref=int(year_id_ref)
	tempfile varlist_dhs 
	save `varlist_dhs',replace 
	restore 
	*MICS
	preserve 
	use "`varlist_mics_file'",clear 
	rename (iso3) (ihme_loc_id_ref)	
	drop if subntl !=""
	gen reference_ref="MICS"
	destring startyear,replace 
	destring endyear,replace 
	egen year_id_ref=rowmean(startyear endyear)
	replace year_id_ref=int(year_id_ref)
	append using `varlist_dhs' 
	tempfile varlist
	save `varlist',replace 
	restore 
	merge m:1 year_id_ref ihme_loc_id_ref reference_ref using `varlist', keep(3) nogen // drop 10 data points that were done in odd-ball
	keep samplesizen reference ihme_loc_id ref reference_ref year_id year_id_ref ihme_loc_id_ref
	tempfile ref
	save `ref',replace  /*272 references*/
/*In each country, there is only one reference for each year which is the largest sample size */

******************************************************************************************
		****Make a list of data points that need age crosswalk****
******************************************************************************************
// bring in the data need age crosswalk
use "`age_xwalk_folder'/age_crosswalk_`maltype'_`curr_date'.dta",clear 
keep if agerep==0 // data points that need age crosswalk
drop if regexm(ihme_loc_id,"CHN") // China uses CHNS as reference instead of DHS and MICS
keep year_id reference nid ihme_loc_id agestring startage endage
gen ref=0 // indicate it is not a reference 

// make a copy of original loc_id for subnational
gen ihme_loc_id_orig=ihme_loc_id 
split ihme_loc_id, parse("_")
replace ihme_loc_id=ihme_loc_id1
drop ihme_loc_id1 ihme_loc_id2

tempfile list_need_reference
save `list_need_reference', replace /*383 wfa, 388 wfh*/

******************************************************************************************
		//find exact match in terms of country-year
******************************************************************************************
// match with reference exactly
merge m:1 ihme_loc_id year_id using `ref'
preserve
keep if _m==3 
drop ref _m
tempfile mat_exact
save `mat_exact',replace /*162wfa, 161wfh*/
restore 

keep if _m==1 
drop _m
******************************************************************************************
		//Find approximate match in terms of year WITHIN THE COUNTRY
******************************************************************************************
drop reference_ref year_id_ref ihme_loc_id_ref /*221wfa, 227wfh */
duplicates report year_id agestring reference nid ihme_loc_id_orig
// match each data point with all reference 
merge m:m ihme_loc_id using `ref', keep(1 3) // _m==1, no country match, _m==3 country matches but need to select the closest year
preserve 
keep if _m==3
drop _m
duplicates tag year_id agestring reference nid ihme_loc_id_orig, gen(dup)
/* if dup=0, matched, the country only have one reference
if dup>0m need to find out the reference with the closest year*/
sort ihme_loc_id_orig year_id
gen year_diff=abs(year_id-year_id_ref)
// only keep the closest year 
sort year_id agestring reference nid ihme_loc_id_orig year_diff
bysort year_id agestring reference nid ihme_loc_id_orig: egen num = seq()
drop if num >1 // only keep the largest sample size 
drop num year_diff dup
/*192wfa, 195wfh*/
tempfile mat_country
save `mat_country',replace 
restore 
keep if _m==1 /*29wfa, 32 wfh*/
drop _m

*********************************************************************************************
// Within region, find reference 
*********************************************************************************************
// get location to get region_id
preserve
clear
include "J:/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
get_location_metadata, location_set_id(9)
gen ihme_loc_id_orig=ihme_loc_id
tempfile loc
save `loc',replace 
restore 

// Edit reference list to get: in each region, only one reference for one year which is the biggest sample size 
preserve 
use `ref', clear 
// merge to get region_id 
merge m:1 ihme_loc_id using `loc', keepusing(region_id) keep(1 3) nogen
gsort region_id year_id_ref -samplesizen // sort descedingly by samplesize 
bysort region_id year_id_ref: egen num = seq()
drop if num >1 // only keep the biggest sample size 
drop num
save `ref',replace  /*In each region, there is only one reference for each year which is the biggest sample size */
restore 

drop reference_ref year_id_ref ihme_loc_id_ref samplesizen 
// get region_id
merge m:1 ihme_loc_id_orig using `loc', keep(3) keepusing(region_id) nogen
duplicates report year_id agestring reference nid region_id // make sure each data point is unique at region level
merge m:m region_id using `ref', keep(1 3) // _m==1, no region match, _m==3 region matches but need to select the closest year
preserve 
keep if _m==3
drop _m
duplicates tag year_id agestring reference nid ihme_loc_id_orig, gen(dup)
/* if dup=0, matched, the country only have one reference
if dup>0m need to find out the reference with the closest year*/
sort ihme_loc_id_orig year_id
gen year_diff=abs(year_id-year_id_ref)
// only keep the closest year 
sort year_id agestring reference nid ihme_loc_id_orig year_diff
bysort year_id agestring reference nid ihme_loc_id_orig: egen num = seq()
drop if num >1 // only keep the largest sample size 
drop num year_diff dup
/*23wfa, 28wfh*/
tempfile mat_region
save `mat_region',replace 
restore 
keep if _m==1 /*6wfa, 4 wfh*/
drop _m

*********************************************************************************************
// Within the Superregion, find reference 
*********************************************************************************************
// get location to get super_region_id
preserve
clear
include "J:/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
get_location_metadata, location_set_id(9)
gen ihme_loc_id_orig=ihme_loc_id
tempfile loc
save `loc',replace 
restore 

// Edit reference list to get: in each super region, only one reference for each year which is the biggest sample size 
preserve 
use `ref', clear 
drop region_id
// merge to get region_id 
merge m:1 ihme_loc_id using `loc', keepusing(super_region_id) keep(1 3) nogen
gsort super_region_id year_id_ref -samplesizen // sort descedingly by samplesize 
bysort super_region_id year_id_ref: egen num = seq()
drop if num >1 // only keep the biggest sample size 
drop num
save `ref',replace  /*In each region, there is only one reference for each year which is the biggest sample size */
restore 

drop reference_ref year_id_ref ihme_loc_id_ref samplesizen /*6*/
// get super_region_id
merge m:1 ihme_loc_id_orig using `loc', keep(3) keepusing(super_region_id) nogen
duplicates report year_id agestring reference nid super_region // make sure each data point is unique at super_region level
merge m:m super_region_id using `ref', keep(1 3) // _m==1, no region match, _m==3 region matches but need to select the closest year

if ihme_loc_id!="ARG" & ihme_loc_id!="AUS" & ihme_loc_id!="CHL" & ihme_loc_id!="USA" { // these countries do not have microdata reference at super region level
preserve 
keep if _m==3
drop _m
duplicates tag year_id agestring reference nid ihme_loc_id_orig, gen(dup)
/* if dup=0, matched, the country only have one reference
if dup>0m need to find out the reference with the closest year*/
sort ihme_loc_id_orig year_id
gen year_diff=abs(year_id-year_id_ref)

// only keep the closest year 
sort year_id agestring reference nid ihme_loc_id_orig year_diff
bysort year_id agestring reference nid ihme_loc_id_orig: egen num = seq()
drop if num >1 // only keep the largest sample size 
drop num year_diff dup
tempfile mat_sregion
save `mat_sregion',replace 
restore 
}

if ihme_loc_id =="ARG" | ihme_loc_id=="AUS" | ihme_loc_id=="CHL" | ihme_loc_id=="USA" { // these countries do not have microdata reference at super region level
drop _m
tempfile mat_sregion
save `mat_sregion',replace 
}

// organize 
use `mat_exact',clear
append using `mat_country'
append using `mat_region'
append using `mat_sregion'
//check whether still have data points that need reference 
merge 1:1 year_id startage endage reference nid ihme_loc_id_orig using `list_need_reference'
drop _m

keep year_id startage endage reference nid ihme_loc_id agestring ihme_loc_id_orig reference_ref year_id_ref ihme_loc_id_ref region_id super_region_id
/* 6 data points for wfa/4 for wfh need reference, mostly high-income areas*/
save "`age_xwalk_folder'/age_crosswalk_reflist_`maltype'_`curr_date'.dta",replace

