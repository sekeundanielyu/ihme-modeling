//age_crosswalk_ratio_dhs
// gen a ratio from reference 

// set up
clear all
set more off
cap log close
set maxvar 10000

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

*************************************
local maltype "heightforage"
local exposure "stunting"
local calculate 1
*************************************
local curr_date = subinstr(c(current_date), " ", "", .)
local age_xwalk_folder "$j/WORK/05_risk/risks/nutrition_`exposure'/01_exposure/02_analysis/02_data/02_maln_age_xwalk"
local database 			"$j/WORK/05_risk/risks/nutrition_underweight/01_exposure/01_data audit/02_data/Complete Maln Database ALL datasources/Complete Dataset ALL datasources `curr_date'.dta"
************************************************************************************************
// Prepare for the reference value (0-59 mo)
*****************************************************************************
	use "`database'",clear 
	keep if reference=="DHS"
	keep if agerep==1 & natlrep==1
	drop if regexm(ihme_loc_id,"_") // only use national data
	keep if regexm(filepath,"DTA") | regexm(filepath,"dta") 
	keep ihme_loc_id startyear endyear `maltype'_2sdneg reference filepath
	egen avgyear = rowmean(startyear endyear)
	replace avgyear = int(avgyear)
	order avgyear, before(startyear)
	
	rename avgyear year_id_ref
	rename reference reference_ref
	rename ihme_loc_id ihme_loc_id_ref
	drop startyear endyear
	tempfile micro
	save `micro',replace 
	
	use "`age_xwalk_folder'/age_crosswalk_reflist_`maltype'_`curr_date'.dta", clear 
	merge m:1 year_id_ref ihme_loc_id_ref reference_ref using `micro', keep(3) nogen 
	rename `maltype'_2sdneg denominator 
	/*306 wfa*/
	tempfile denominator
	save `denominator',replace 

************************************************************************************************
// Prepare for the reference varnames (customized age groups)
*****************************************************************************
if `calculate'==1 {
	//Merge with the DHS codebook to get the varname for variables of interest
	preserve 
	use "$j/WORK/05_risk/risks/nutrition_underweight/01_exposure/01_data audit/02_data/01_DHS_prep/varlist_final_dhs_3Jul2016.dta", clear // confirm this is the latest version in the folder , need to update 
	rename filepath_full filepath
	tempfile varlist_dhs
	save `varlist_dhs', replace
	restore 
	// to get varnames
	merge m:1 filepath using `varlist_dhs', keep(3) nogen
	tempfile varlist_dhs_ref
	save `varlist_dhs_ref',replace 
	/* a list of data point- reference -varname(reference) that needs to calculate the prevalence of malnutriton in customized age groups */
	// generate a temp for appending
	preserve 
	clear 
	tempfile new
	save `new', emptyok
	restore 

	************************************************************************************************
	// Calculate prevalence in customized age groups
	*****************************************************************************
	// make the variable names just refer to hc1_ etc (rather than hc1_1) so that it will keep all weights/heights/ages/sex later
	foreach var of varlist height_cm-sex {
		if regexm(`var', "_") {
			capture split `var', parse("_")
			replace `var'=`var'1
			drop `var'1 `var'2
		}
	}
	tostring startyear, replace 
	tostring startage,replace 
	tostring endage,replace 
	local maxobs = _N

	forvalues filenum =1(1)`maxobs' {
		mata: womens=st_sdata(.,("location_name", "iso3", "startyear", "endyear", "cluster_num", "sample_weight", "height_cm", "weight_kg", "age_mo", "sex", "caseid", "startage", "endage", "filepath", "agestring"))
		// create locals with file-specific information, then display it	
		mata: st_local("location_name", womens[`filenum', 1])
		mata: st_local("iso3", womens[`filenum', 2])
		mata: st_local("startyear", womens[`filenum', 3])
		mata: st_local("endyear", womens[`filenum', 4])
		mata: st_local("cluster_num", womens[`filenum', 5])
		mata: st_local("sample_weight", womens[`filenum', 6])
		mata: st_local("height_cm", womens[`filenum', 7])
		mata: st_local("weight_kg", womens[`filenum', 8])
		mata: st_local("age_mo", womens[`filenum', 9])
		mata: st_local("sex", womens[`filenum', 10])
		mata: st_local("caseid", womens[`filenum', 11])
		mata: st_local("startage", womens[`filenum', 12])
		mata: st_local("endage", womens[`filenum', 13])
		mata: st_local("filepath", womens[`filenum', 14])
		mata: st_local("agestring", womens[`filenum', 15])
		
		display in red "location_name: `location_name'" 

		preserve 
		use `cluster_num' `sample_weight' `height_cm'_* `weight_kg'_* `age_mo'_* `sex'_* `caseid' using "`filepath'", clear
		// HEIGHT CM
			forvalues v=1(1)9 {
				capture rename `height_cm'_0`v' height_cm_`v'
			}
			forvalues v=10(1)20 {
				capture rename `height_cm'_`v' height_cm_`v'
			}
			forvalues v=1(1)9 {
				capture rename `height_cm'_`v' height_cm_`v'
			}
			
		// WEIGHT KG
			forvalues v=1(1)9 {
				capture rename `weight_kg'_0`v' weight_kg_`v'
			}
			forvalues v=10(1)20 {
				capture rename `weight_kg'_`v' weight_kg_`v'
			}
			forvalues v=1(1)9 {
				capture rename `weight_kg'_`v' weight_kg_`v'
			}

		// AGE MO
			forvalues v=1(1)9 {
				capture rename `age_mo'_0`v' age_mo_`v'
			}
			forvalues v=10(1)20 {
				capture rename `age_mo'_`v' age_mo_`v'
			}
			forvalues v=1(1)9 {
				capture rename `age_mo'_`v' age_mo_`v'
			}
			
		// SEX	
			forvalues v=1(1)9 {
				capture rename `sex'_0`v' sex_`v'
			}
			forvalues v=10(1)20 {
				capture rename `sex'_`v' sex_`v'
			}
			forvalues v=1(1)9 {
				capture rename `sex'_`v' sex_`v'
			}
		
		// CLUSTER_NUM, SAMPLE_WEIGHT, CASEID
		local varlist cluster_num sample_weight caseid
		foreach var of local varlist {
			capture	rename ``var'' `var'
		}
		duplicates drop caseid, force
		
		reshape long age_mo_ height_cm_ weight_kg_ sex_, i(caseid) j(child_id 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)
		
		rename age_mo_ age_mo
		rename weight_kg_ weight_kg
		rename height_cm_ height_cm
		rename sex_ sex
		
		// DHS has its weights & heights with 1 decimal place, so remove it
		replace weight_kg = weight_kg/10
		replace height_cm = height_cm/10
		
		gen startage_cus=`startage'
		gen endage_cus=`endage'
		
		// only keep age within the age groups!
		keep if age_mo>=startage_cus & age_mo<=endage_cus
	************************************************************************************************************************************
		*** Do microdata analysis do file
	do "$j/WORK/05_risk/risks/nutrition_underweight/01_exposure/01_data audit/01_code/22_CALCULATING MALN PREV/MALN MICRODATA ANALYSIS do file.do"
	***********************************************************************************************************************
		rename `maltype'_2sdneg numerator		
		gen agestring= "`agestring'"
		gen filepath="`filepath'"
		
		keep numerator agestring filepath
		append using `new'
		save `new',replace 
		restore
		}

	use `new', clear
	duplicates drop 
	save "`age_xwalk_folder'/xwalk_`maltype'_dhs_cust_prev",replace 
	}

// merge with the calculated dhs to see whether there is update and need to recalculate 
use "`age_xwalk_folder'/xwalk_`maltype'_dhs_cust_prev",clear
merge 1:m filepath agestring using `denominator'
/* if _m==2, then need to recalculate the DHS for cutomized age groups*/
gen ratio=numerator/denominator 

save "`age_xwalk_folder'/xwalk_ratio_`maltype'_dhs_`curr_date'",replace 

