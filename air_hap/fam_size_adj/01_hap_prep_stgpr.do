// prepare HAP exposure dataset for ST-GPR 
// Crosswalk for family size: update on 6/30/2016


// set up 
clear all
set more off

//Set directories
	if c(os) == "Unix" {
		global j "/home/j"
		set more off
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j "J:"
	}

local curr_date = 		subinstr(c(current_date), " ", "", .)	
local input_file		"$j/WORK/05_risk/risks/air_hap/01_exposure/01_data audit/02_data/Complete Maln Database ALL datasources/database_2015_complete_`curr_date'.dta"
local output 			"$j/WORK/05_risk/risks/air_hap/01_exposure/02_analysis/02_data/01_hap_stgpr_input" // ST-GPR input 


local dhs_adj_file 		"J:/WORK/05_risk/risks/air_hap/01_exposure/01_data audit/adj_family_size/02_data/microdata/DHS/prev_dhs_hap_11Jul2016_adj_fs.dta"
local mics_adj_file 	"J:/WORK/05_risk/risks/air_hap/01_exposure/01_data audit/adj_family_size/02_data/microdata/MICS/prev_mics_hap_11Jul2016_adj_fs.dta"
local dhsdir 			"J:/WORK/05_risk/risks/air_hap/01_exposure/01_data audit/02_data/01_DHS_results"
local micsdir 			"J:/WORK/05_risk/risks/air_hap/01_exposure/01_data audit/02_data/02_MICS_results"


// get location
include "J:/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
get_location_metadata, location_set_id(9) clear 
keep location_id region_id super_region_id ihme_loc_id
tempfile loc 
save `loc',replace 

**********************************************************
***Generate Multiplier (coef) for family size crosswalk***
 **********************************************************

// Adjusted microdata 
use "`dhs_adj_file'",clear 
append using "`mics_adj_file'" /*275*/
replace filepath=lower(filepath)
// set a minimal value since will logit-transform later 
replace mean=0.0001 if mean==0
gen ind=0 // reference group 
tempfile adjusted 
save `adjusted',replace 

// Undajusted data, data originally extracted without adjusting for family size 
local dirs dhs mics
	foreach d of local dirs {
		clear
		cd "``d'dir'"
		local fullfilenames: dir "``d'dir'" files "*_*.dta", respectcase
		foreach f of local fullfilenames {
			append using "``d'dir'/`f'"
		}
		tempfile `d'
		save ``d'', replace
	}
	
	use "`dhs'",clear 
	append using `mics'
	replace filepath=lower(filepath)
	replace mean=0.0001 if mean==0
	gen ind=1 // need reference 
	tempfile unadjusted 
	save `unadjusted',replace 

// make a list of surveys that would be included in the mixed effect model
	// matched surveys with and without family size adjustment
	use `adjusted',clear
	rename mean mean_adj 
	merge 1:1 filepath using `unadjusted', keep(3) nogen
	keep iso3 startyear endyear mean_adj reference filepath mean
	
	// drop the data point identified since they are not at the expected direction 	
	/* in these surveys, either family size is negatively associated with solid fuel use or no assocation OR the mean is extremely small */
	drop if mean_adj<mean 
	keep filepath

	tempfile matchfile /*232*/
	save `matchfile',replace 

// reduce the adjusted and undajusted datasets to the matched files 
use `adjusted',clear 
merge 1:1 filepath using `matchfile', keep(3) nogen
rename iso3 ihme_loc_id
save `adjusted',replace 

use `unadjusted',clear 
merge 1:1 filepath using `matchfile', keep(3) nogen
rename iso3 ihme_loc_id
save `unadjusted', replace 

// Calculate multiplier
	// make a database consists of matched adjusted and unadjusted data points and run mixed effect model
	append using `adjusted'
	// get location and clean the database 
	merge m:1 ihme_loc_id using `loc', keep(3) nogen
	keep ihme_loc_id startyear endyear mean se reference ind filepath location_id region_id super_region_id

	// Run mixed effect model to generate a multiplier for shifting 
	gen logit_mean = logit(mean)

	mixed logit_mean ind || super_region_id: ind || region_id: ind || location_id:ind || filepath:ind
	predict re*, reffect
	gen coef=_b[ind]
	rename (re1 re3) (re_sregion re_region)
	keep region_id super_region_id re_sregion re_region coef

	preserve 
	duplicates drop region_id, force 
	tempfile reffect_region
	save `reffect_region',replace // region random effect
	restore 
	duplicates drop super_region_id, force 
	tempfile reffect_sregion
	save `reffect_sregion',replace // super region random effect 

*********************************************************************************
// Cross walk for family size 
*********************************************************************************
use "`input_file'",clear
duplicates drop ihme_loc_id year_start underlying_nid filepath reference, force // kenya has a dup for unknown reason 
replace mean=0.0001 if mean==0
replace mean=0.9999 if mean==1
gen logit_mean=logit(mean)
rename mean mean_orig
rename se se_orig
replace filepath=lower(filepath)

// make a list of DHS and MICS that have beed adjusted family size during extraction
preserve 
keep if reference =="DHS" | reference=="MICS"
merge 1:1 ihme_loc_id filepath using `adjusted', keep(3) nogen /*4 subnational dropped */
tempfile list 
save `list', replace 
restore 

merge 1:1 ihme_loc_id year_start mean_orig se_orig underlying_nid using `list', keep(1 3) keepusing (mean se ind) nogen // 228

// get region and super_region id 
merge m:1 location_id using `loc', keepusing(region_id super_region_id) keep(3) nogen
// get random effect at region level 
merge m:1 region_id using `reffect_region', keepusing (re_region) keep(1 3) nogen
// replace region random effect to zero for those regions do not have re_region
replace re_region=0 if re_region==.
// get random effect at super region level 
merge m:1 super_region_id using `reffect_sregion', keepusing (re_sregion coef) keep(1 3) nogen
// replace region random effect to zero for those regions do not have re_region
replace re_sregion=0 if re_sregion==.

replace ind=1 if ind !=0
// generate multiplier 
gen multiplier = re_sregion + re_region + coef * ind 

**************************************************
// Crosswalk
***************************************************
gen mean_adj=invlogit(logit_mean - multiplier)
replace mean=mean_adj if ind==1 
drop mean_adj re_region re_sregion coef multiplier

*****************************************
// clean up
*****************************************
//year_id
egen avgyear = rowmean(year_start year_end)
replace avgyear = int(avgyear)
order avgyear, before(year_start)
rename avgyear year_id

// representative- only keep nationally representative data
drop if natlrep==0 & subnatl_rep==0

// calculate a rough sample size for those data points do not have sample size nor se, then will use the sample size to calculate variance later 
egen pcile5_n = pctile(sample_size), p(5)
replace sample_size = pcile5_n if sample_size==.	
drop pcile

*********************************************
// Outliers ..2015
*********************************************
rename nid parent_nid
rename underlying_nid nid
drop if nid==5407 & ihme_loc_id=="IDN"
drop if nid==141558 & ihme_loc_id=="THA"
drop if nid==11410 & ihme_loc_id=="WSM"
drop if nid==797 & ihme_loc_id=="ARM"
drop if nid==811 & ihme_loc_id=="ARM"
drop if nid==21676 & ihme_loc_id=="KAZ"
drop if nid==189045 & ihme_loc_id=="MNG"
drop if nid==11214 & ihme_loc_id=="RUS"
drop if nid==11271 & ihme_loc_id=="RUS"
drop if nid==11299 & ihme_loc_id=="RUS"
drop if nid==7480 & ihme_loc_id=="KOR"
drop if nid==160478 & ihme_loc_id=="KOR"
drop if nid==7481 & ihme_loc_id=="KOR"
drop if nid==10371 & ihme_loc_id=="PRY"
drop if nid==141628 & ihme_loc_id=="PSE"
drop if nid==45777 & ihme_loc_id=="IND"
drop if nid==60942 & ihme_loc_id=="PAK"
drop if nid==154210 & ihme_loc_id=="AGO"
drop if nid==3736 & ihme_loc_id=="ETH"
drop if nid==208731 & ihme_loc_id=="NGA"
drop if nid==9492 & ihme_loc_id=="NGA"

//3/17/2016
drop if nid==34012 & ihme_loc_id=="ARG" // IPUMS, the options for fuel only include GAS, which makes the prevalence 0
drop if nid==81044 & ihme_loc_id=="IND" // In the report, only urban, rural split for country level, drop for now if have time do urban/rural crosswalk
drop if nid==124072 // China subnational, I found the data from this survey generally lower than others, drop for now , ask Erica to get access to the data 
drop if nid==798 & ihme_loc_id=="ARM" // I did not see the 2002 data under the series folder and there is not much information on GHDx
drop if nid==794 & ihme_loc_id=="ARM" // I did not see the 2002 data under the series folder and there is not much information on GHDx
drop if nid==802 & ihme_loc_id=="ARM" // do not have fuel variable 
drop if nid==22790 & ihme_loc_id=="ARM" // do not have fuel variable 
drop if nid==22813 & ihme_loc_id=="ARM" // do not have fuel variable 
drop if nid==22817 & ihme_loc_id=="ARM" // do not have fuel variable 
drop if nid==22786 & ihme_loc_id=="ARM" // do not have fuel variable
drop if nid==142027 & ihme_loc_id=="ARM" // Data actually from Households Integrated Living Conditions Survey which I trust less and still need to investigate it 
drop if nid==22786 & ihme_loc_id=="ARM" // do not have fuel variable
drop if nid==154210 & ihme_loc_id=="SDN" // The report is more national level, instead of surveys, drop for now and look into it later 
drop if nid==23219 // India DHLS, the option of "other" in the fuel use may include solid fule other than wood. So the level is underestimate. drop for both national and subnational 
// 4/24/2016
drop if nid==141571 & ihme_loc_id=="SEN" // the percentage was only for firewood, potentially underestimated comparing with the adjascent years

tempfile database
save "`database'", replace 
*********************************************************************************
					// PREP square 
*********************************************************************************
// Store filepaths/values in macros
 local gbd_functions "$j/WORK/10_gbd/00_library/functions"
 
 // Function library            
include `gbd_functions'/get_demographics.ado
get_demographics, gbd_team("cov") make_template clear
keep location_id year_id age_group_id sex_id
tempfile square
save `square', replace

// Merge on ihme_loc_id
get_location_metadata, location_set_id(9) clear
keep location_id ihme_loc_id level region_id super_region_id
merge 1:m location_id using `square'

// Keep if national or subnational
keep if level >= 3
// Dropping GBR_4749 (from location_metadata)
drop if _merge == 1
// Setting China without Hong Kong and Macau (not in location metadata)
replace level = 4 if location_id == 44533
replace ihme_loc_id = "CHN_44533" if location_id == 44533

// make the square per location-year pair 
bysort location_id year_id: egen num = seq()
drop if num >1
replace age_group_id=22
replace sex_id=3

// Clean
drop _merge level num
sort location_id year_id age_group_id sex_id
save `square', replace

*****************************************************
	//Prep Covariates 
*****************************************************
preserve
include "$j/WORK/10_gbd/00_library/functions/get_covariate_estimates.ado"
/*
// LDI --> ln ldi           
	get_covariate_estimates, covariate_name_short(LDI_pc) clear
	rename mean_value ldi
	gen ln_ldi = ln(ldi)
	keep if year_id<=2015
	keep if year_id>=1980
	keep location_id location_name year_id sex_id ln_ldi
	tempfile ln_ldi
	save `ln_ldi', replace
	
	*/
// MATERNAL education covariate 
	get_covariate_estimates, covariate_name_short(maternal_educ_yrs_pc) clear
	rename mean_value meduc
	keep if year_id<=2015
	keep if year_id>=1980
	keep location_id location_name year_id sex_id meduc
	tempfile meduc
	save `meduc', replace

// prop_urban
	get_covariate_estimates, covariate_name_short(prop_urban) clear
	rename mean_value urban
	keep if year_id<=2015
	keep if year_id>=1980
	keep location_id location_name year_id sex_id urban
	tempfile urban
	save `urban', replace
	
	*merge 1:1 location_id year_id using `ln_ldi', keep(3) nogen
	merge 1:1 location_id year_id using `meduc', keep(3) nogen

	tempfile covs
	save `covs'
	restore 

merge m:1 location_id year_id using `covs', keep(3) nogen

merge 1:m location_id year_id using "`database'"
drop if _m==2
drop _m
// CRI? _me==2
// Organize
gen me_name = "air_hap"
gen data=mean
gen variance=se^2
replace variance=data*(1-data)/sample_size if variance ==. & data !=.
*temporaly, replace when a variance=0
replace variance=0.001 if variance==0
// BOL 1998 doesnot have variance and sample size
gen standard_deviation=se*sqrt(sample_size)
*temporaly, replace when a SD=0
replace standard_deviation=0.001 if standard_deviation==0

keep me_name location_id year_id sex_id age_group_id data variance sample_size standard_deviation nid ihme_loc_id meduc urban region_id super_region_id
order me_name location_id year_id sex_id age_group_id data variance sample_size standard_deviation nid ihme_loc_id meduc urban
drop if year_id<1980

save "`output'/hap_prepped_`curr_date'.dta",replace
