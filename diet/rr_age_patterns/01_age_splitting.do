// Compile FAO age trend results and apply them
clear all
macro drop _all
set maxvar 32000
// Set to run all selected code without pausing
set more off
// Remove previous restores
cap restore, not
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
if c(os) == "Unix" {
	global j "/home/j"
	set odbcmgr unixodbc
}
else if c(os) == "Windows" {
	global j "J:"
}

local population 	"`pop_dir'/pops_fao_as.dta"
local raw_data		"J:/WORK/05_risk/risks/diet_general/data/rr/2015/data/Literature Review/Updated RRs/Diet_RR_07152016_PS.xlsx"

**when the source files of metabolic RRs need to be re-pulled from the database if they are changed!!

**************************************************************************************
********************* BMI - DM PREP **************************************************
**************************************************************************************
use "bmi_dm_rr.dta", clear
egen rr_mean = rowmean(rr_*)
rename rr_mean pred
replace pred = log(pred)
drop rr_*
keep if year_id == 2015 & sex_id == 1
gen risk = "."

keep age_group_id pred risk
sort age_group_id

reshape wide pred, i(risk) j(age_group_id)

rename pred* pred_*

**prepare a separate trend for each of the different age at events needed for IHD
local event_ages 60 55
foreach age of local event_ages {
preserve
if `age' == 60 {
**prep this for being centered at 60 to correpsond to age at event = 60
	gen perc_21 = ((pred_21 - pred_17) / pred_17) + 1
	gen perc_20 = ((pred_20 - pred_17) / pred_17) + 1
	gen perc_19 = ((pred_19 - pred_17) / pred_17) + 1
	gen perc_18 = ((pred_18 - pred_17) / pred_17) + 1
	gen perc_17 = ((pred_17 - pred_17) / pred_17) + 1
	gen perc_16 = ((pred_16 - pred_17) / pred_17) + 1
	gen perc_15 = ((pred_15 - pred_17) / pred_17) + 1
	gen perc_14 = ((pred_14 - pred_17) / pred_17) + 1
	gen perc_13 = ((pred_13 - pred_17) / pred_17) + 1
	gen perc_12 = ((pred_12 - pred_17) / pred_17) + 1
	gen perc_11 = ((pred_11 - pred_17) / pred_17) + 1
	gen perc_10 = ((pred_10 - pred_17) / pred_17) + 1
}
if `age' == 55 {
**prep this for being centered at 55 to correpsond to age at event = 55
	gen perc_21 = ((pred_21 - pred_16) / pred_16) + 1
	gen perc_20 = ((pred_20 - pred_16) / pred_16) + 1
	gen perc_19 = ((pred_19 - pred_16) / pred_16) + 1
	gen perc_18 = ((pred_18 - pred_16) / pred_16) + 1
	gen perc_17 = ((pred_17 - pred_16) / pred_16) + 1
	gen perc_16 = ((pred_16 - pred_16) / pred_16) + 1
	gen perc_15 = ((pred_15 - pred_16) / pred_16) + 1
	gen perc_14 = ((pred_14 - pred_16) / pred_16) + 1
	gen perc_13 = ((pred_13 - pred_16) / pred_16) + 1
	gen perc_12 = ((pred_12 - pred_16) / pred_16) + 1
	gen perc_11 = ((pred_11 - pred_16) / pred_16) + 1
	gen perc_10 = ((pred_10 - pred_16) / pred_16) + 1
}


drop pred*

reshape long perc_, i(risk) 

rename _j age_group_id
rename perc_ percentage_change_bmi

//save the data
tempfile bmi_dm_`age'
save `bmi_dm_`age'', replace
restore
}
**************************************************************************************
**************************************************************************************
**************************************************************************************

**************************************************************************************
********************* BMI - IHD PREP *************************************************
**************************************************************************************
use "bmi_ihd_rr.dta", clear
egen rr_mean = rowmean(rr_*)
rename rr_mean pred
replace pred = log(pred)
drop rr_*
keep if year_id == 2015 & sex_id == 1
gen risk = "."

keep age_group_id pred risk
sort age_group_id

reshape wide pred, i(risk) j(age_group_id)

rename pred* pred_*

**prepare a separate trend for each of the different age at events needed for IHD
local event_ages 60 55 65 50
foreach age of local event_ages {
preserve

if `age' == 60 {
**prep this for being centered at 60 to correpsond to age at event = 60
	gen perc_21 = ((pred_21 - pred_17) / pred_17) + 1
	gen perc_20 = ((pred_20 - pred_17) / pred_17) + 1
	gen perc_19 = ((pred_19 - pred_17) / pred_17) + 1
	gen perc_18 = ((pred_18 - pred_17) / pred_17) + 1
	gen perc_17 = ((pred_17 - pred_17) / pred_17) + 1
	gen perc_16 = ((pred_16 - pred_17) / pred_17) + 1
	gen perc_15 = ((pred_15 - pred_17) / pred_17) + 1
	gen perc_14 = ((pred_14 - pred_17) / pred_17) + 1
	gen perc_13 = ((pred_13 - pred_17) / pred_17) + 1
	gen perc_12 = ((pred_12 - pred_17) / pred_17) + 1
	gen perc_11 = ((pred_11 - pred_17) / pred_17) + 1
	gen perc_10 = ((pred_10 - pred_17) / pred_17) + 1
}
if `age' == 55 {
**prep this for being centered at 55 to correpsond to age at event = 55
	gen perc_21 = ((pred_21 - pred_16) / pred_16) + 1
	gen perc_20 = ((pred_20 - pred_16) / pred_16) + 1
	gen perc_19 = ((pred_19 - pred_16) / pred_16) + 1
	gen perc_18 = ((pred_18 - pred_16) / pred_16) + 1
	gen perc_17 = ((pred_17 - pred_16) / pred_16) + 1
	gen perc_16 = ((pred_16 - pred_16) / pred_16) + 1
	gen perc_15 = ((pred_15 - pred_16) / pred_16) + 1
	gen perc_14 = ((pred_14 - pred_16) / pred_16) + 1
	gen perc_13 = ((pred_13 - pred_16) / pred_16) + 1
	gen perc_12 = ((pred_12 - pred_16) / pred_16) + 1
	gen perc_11 = ((pred_11 - pred_16) / pred_16) + 1
	gen perc_10 = ((pred_10 - pred_16) / pred_16) + 1
}
if `age' == 65 {
**prep this for being centered at 65 to correpsond to age at event = 65
	gen perc_21 = ((pred_21 - pred_18) / pred_18) + 1
	gen perc_20 = ((pred_20 - pred_18) / pred_18) + 1
	gen perc_19 = ((pred_19 - pred_18) / pred_18) + 1
	gen perc_18 = ((pred_18 - pred_18) / pred_18) + 1
	gen perc_17 = ((pred_17 - pred_18) / pred_18) + 1
	gen perc_16 = ((pred_16 - pred_18) / pred_18) + 1
	gen perc_15 = ((pred_15 - pred_18) / pred_18) + 1
	gen perc_14 = ((pred_14 - pred_18) / pred_18) + 1
	gen perc_13 = ((pred_13 - pred_18) / pred_18) + 1
	gen perc_12 = ((pred_12 - pred_18) / pred_18) + 1
	gen perc_11 = ((pred_11 - pred_18) / pred_18) + 1
	gen perc_10 = ((pred_10 - pred_18) / pred_18) + 1
}
if `age' == 50 {
**prep this for being centered at 50 to correpsond to age at event = 50
	gen perc_21 = ((pred_21 - pred_15) / pred_15) + 1
	gen perc_20 = ((pred_20 - pred_15) / pred_15) + 1
	gen perc_19 = ((pred_19 - pred_15) / pred_15) + 1
	gen perc_18 = ((pred_18 - pred_15) / pred_15) + 1
	gen perc_17 = ((pred_17 - pred_15) / pred_15) + 1
	gen perc_16 = ((pred_16 - pred_15) / pred_15) + 1
	gen perc_15 = ((pred_15 - pred_15) / pred_15) + 1
	gen perc_14 = ((pred_14 - pred_15) / pred_15) + 1
	gen perc_13 = ((pred_13 - pred_15) / pred_15) + 1
	gen perc_12 = ((pred_12 - pred_15) / pred_15) + 1
	gen perc_11 = ((pred_11 - pred_15) / pred_15) + 1
	gen perc_10 = ((pred_10 - pred_15) / pred_15) + 1
}


drop pred*

reshape long perc_, i(risk) 

rename _j age_group_id
rename perc_ percentage_change_bmi

//save the data
tempfile bmi_ihd_`age'
save `bmi_ihd_`age'', replace
restore
}
**************************************************************************************
**************************************************************************************
**************************************************************************************

**************************************************************************************
********************* BMI - ISCH_STROKE PREP *****************************************
**************************************************************************************
use "bmi_isch_stroke_rr.dta", clear
egen rr_mean = rowmean(rr_*)
rename rr_mean pred
replace pred = log(pred)
drop rr_*
keep if year_id == 2015 & sex_id == 1
gen risk = "."

keep age_group_id pred risk
sort age_group_id

reshape wide pred, i(risk) j(age_group_id)

rename pred* pred_*

**prepare a separate trend for each of the different age at events needed for IHD
local event_ages 60 65
foreach age of local event_ages {
preserve

if `age' == 60 {
**prep this for being centered at 60 to correpsond to age at event = 60
	gen perc_21 = ((pred_21 - pred_17) / pred_17) + 1
	gen perc_20 = ((pred_20 - pred_17) / pred_17) + 1
	gen perc_19 = ((pred_19 - pred_17) / pred_17) + 1
	gen perc_18 = ((pred_18 - pred_17) / pred_17) + 1
	gen perc_17 = ((pred_17 - pred_17) / pred_17) + 1
	gen perc_16 = ((pred_16 - pred_17) / pred_17) + 1
	gen perc_15 = ((pred_15 - pred_17) / pred_17) + 1
	gen perc_14 = ((pred_14 - pred_17) / pred_17) + 1
	gen perc_13 = ((pred_13 - pred_17) / pred_17) + 1
	gen perc_12 = ((pred_12 - pred_17) / pred_17) + 1
	gen perc_11 = ((pred_11 - pred_17) / pred_17) + 1
	gen perc_10 = ((pred_10 - pred_17) / pred_17) + 1
}
if `age' == 65 {
**prep this for being centered at 65 to correpsond to age at event = 65
	gen perc_21 = ((pred_21 - pred_18) / pred_18) + 1
	gen perc_20 = ((pred_20 - pred_18) / pred_18) + 1
	gen perc_19 = ((pred_19 - pred_18) / pred_18) + 1
	gen perc_18 = ((pred_18 - pred_18) / pred_18) + 1
	gen perc_17 = ((pred_17 - pred_18) / pred_18) + 1
	gen perc_16 = ((pred_16 - pred_18) / pred_18) + 1
	gen perc_15 = ((pred_15 - pred_18) / pred_18) + 1
	gen perc_14 = ((pred_14 - pred_18) / pred_18) + 1
	gen perc_13 = ((pred_13 - pred_18) / pred_18) + 1
	gen perc_12 = ((pred_12 - pred_18) / pred_18) + 1
	gen perc_11 = ((pred_11 - pred_18) / pred_18) + 1
	gen perc_10 = ((pred_10 - pred_18) / pred_18) + 1
}


drop pred*

reshape long perc_, i(risk) 

rename _j age_group_id
rename perc_ percentage_change_bmi

//save the data
tempfile bmi_isch_stroke_`age'
save `bmi_isch_stroke_`age'', replace
restore
}
**************************************************************************************
**************************************************************************************
**************************************************************************************

**************************************************************************************
********************* BMI - HEM_STROKE PREP ******************************************
**************************************************************************************
use "bmi_hem_stroke_rr.dta", clear
egen rr_mean = rowmean(rr_*)
rename rr_mean pred
replace pred = log(pred)
drop rr_*
keep if year_id == 2015 & sex_id == 1
gen risk = "."

keep age_group_id pred risk
sort age_group_id

reshape wide pred, i(risk) j(age_group_id)

rename pred* pred_*

**prepare a separate trend for each of the different age at events needed for IHD
local event_ages 60 65
foreach age of local event_ages {
preserve

if `age' == 60 {
**prep this for being centered at 60 to correpsond to age at event = 60
	gen perc_21 = ((pred_21 - pred_17) / pred_17) + 1
	gen perc_20 = ((pred_20 - pred_17) / pred_17) + 1
	gen perc_19 = ((pred_19 - pred_17) / pred_17) + 1
	gen perc_18 = ((pred_18 - pred_17) / pred_17) + 1
	gen perc_17 = ((pred_17 - pred_17) / pred_17) + 1
	gen perc_16 = ((pred_16 - pred_17) / pred_17) + 1
	gen perc_15 = ((pred_15 - pred_17) / pred_17) + 1
	gen perc_14 = ((pred_14 - pred_17) / pred_17) + 1
	gen perc_13 = ((pred_13 - pred_17) / pred_17) + 1
	gen perc_12 = ((pred_12 - pred_17) / pred_17) + 1
	gen perc_11 = ((pred_11 - pred_17) / pred_17) + 1
	gen perc_10 = ((pred_10 - pred_17) / pred_17) + 1
}
if `age' == 65 {
**prep this for being centered at 65 to correpsond to age at event = 65
	gen perc_21 = ((pred_21 - pred_18) / pred_18) + 1
	gen perc_20 = ((pred_20 - pred_18) / pred_18) + 1
	gen perc_19 = ((pred_19 - pred_18) / pred_18) + 1
	gen perc_18 = ((pred_18 - pred_18) / pred_18) + 1
	gen perc_17 = ((pred_17 - pred_18) / pred_18) + 1
	gen perc_16 = ((pred_16 - pred_18) / pred_18) + 1
	gen perc_15 = ((pred_15 - pred_18) / pred_18) + 1
	gen perc_14 = ((pred_14 - pred_18) / pred_18) + 1
	gen perc_13 = ((pred_13 - pred_18) / pred_18) + 1
	gen perc_12 = ((pred_12 - pred_18) / pred_18) + 1
	gen perc_11 = ((pred_11 - pred_18) / pred_18) + 1
	gen perc_10 = ((pred_10 - pred_18) / pred_18) + 1
}


drop pred*

reshape long perc_, i(risk) 

rename _j age_group_id
rename perc_ percentage_change_bmi

//save the data
tempfile bmi_hem_stroke_`age'
save `bmi_hem_stroke_`age'', replace
restore
}
**************************************************************************************
**************************************************************************************
**************************************************************************************

**************************************************************************************
********************* SBP - IHD PREP *************************************************
**************************************************************************************
use "sbp_ihd_rr.dta", clear
egen rr_mean = rowmean(rr_*)
rename rr_mean pred
replace pred = log(pred)
drop rr_*
keep if year_id == 2015 & sex_id == 1
gen risk = "."

keep age_group_id pred risk
sort age_group_id

reshape wide pred, i(risk) j(age_group_id)

rename pred* pred_*

**prepare a separate trend for each of the different age at events needed for IHD
local event_ages 60 55 65 50
foreach age of local event_ages {
preserve

if `age' == 60 {
**prep this for being centered at 60 to correpsond to age at event = 60
	gen perc_21 = ((pred_21 - pred_17) / pred_17) + 1
	gen perc_20 = ((pred_20 - pred_17) / pred_17) + 1
	gen perc_19 = ((pred_19 - pred_17) / pred_17) + 1
	gen perc_18 = ((pred_18 - pred_17) / pred_17) + 1
	gen perc_17 = ((pred_17 - pred_17) / pred_17) + 1
	gen perc_16 = ((pred_16 - pred_17) / pred_17) + 1
	gen perc_15 = ((pred_15 - pred_17) / pred_17) + 1
	gen perc_14 = ((pred_14 - pred_17) / pred_17) + 1
	gen perc_13 = ((pred_13 - pred_17) / pred_17) + 1
	gen perc_12 = ((pred_12 - pred_17) / pred_17) + 1
	gen perc_11 = ((pred_11 - pred_17) / pred_17) + 1
	gen perc_10 = ((pred_10 - pred_17) / pred_17) + 1
}
if `age' == 55 {
**prep this for being centered at 55 to correpsond to age at event = 55
	gen perc_21 = ((pred_21 - pred_16) / pred_16) + 1
	gen perc_20 = ((pred_20 - pred_16) / pred_16) + 1
	gen perc_19 = ((pred_19 - pred_16) / pred_16) + 1
	gen perc_18 = ((pred_18 - pred_16) / pred_16) + 1
	gen perc_17 = ((pred_17 - pred_16) / pred_16) + 1
	gen perc_16 = ((pred_16 - pred_16) / pred_16) + 1
	gen perc_15 = ((pred_15 - pred_16) / pred_16) + 1
	gen perc_14 = ((pred_14 - pred_16) / pred_16) + 1
	gen perc_13 = ((pred_13 - pred_16) / pred_16) + 1
	gen perc_12 = ((pred_12 - pred_16) / pred_16) + 1
	gen perc_11 = ((pred_11 - pred_16) / pred_16) + 1
	gen perc_10 = ((pred_10 - pred_16) / pred_16) + 1
}
if `age' == 65 {
**prep this for being centered at 65 to correpsond to age at event = 65
	gen perc_21 = ((pred_21 - pred_18) / pred_18) + 1
	gen perc_20 = ((pred_20 - pred_18) / pred_18) + 1
	gen perc_19 = ((pred_19 - pred_18) / pred_18) + 1
	gen perc_18 = ((pred_18 - pred_18) / pred_18) + 1
	gen perc_17 = ((pred_17 - pred_18) / pred_18) + 1
	gen perc_16 = ((pred_16 - pred_18) / pred_18) + 1
	gen perc_15 = ((pred_15 - pred_18) / pred_18) + 1
	gen perc_14 = ((pred_14 - pred_18) / pred_18) + 1
	gen perc_13 = ((pred_13 - pred_18) / pred_18) + 1
	gen perc_12 = ((pred_12 - pred_18) / pred_18) + 1
	gen perc_11 = ((pred_11 - pred_18) / pred_18) + 1
	gen perc_10 = ((pred_10 - pred_18) / pred_18) + 1
}
if `age' == 50 {
**prep this for being centered at 50 to correpsond to age at event = 50
	gen perc_21 = ((pred_21 - pred_15) / pred_15) + 1
	gen perc_20 = ((pred_20 - pred_15) / pred_15) + 1
	gen perc_19 = ((pred_19 - pred_15) / pred_15) + 1
	gen perc_18 = ((pred_18 - pred_15) / pred_15) + 1
	gen perc_17 = ((pred_17 - pred_15) / pred_15) + 1
	gen perc_16 = ((pred_16 - pred_15) / pred_15) + 1
	gen perc_15 = ((pred_15 - pred_15) / pred_15) + 1
	gen perc_14 = ((pred_14 - pred_15) / pred_15) + 1
	gen perc_13 = ((pred_13 - pred_15) / pred_15) + 1
	gen perc_12 = ((pred_12 - pred_15) / pred_15) + 1
	gen perc_11 = ((pred_11 - pred_15) / pred_15) + 1
	gen perc_10 = ((pred_10 - pred_15) / pred_15) + 1
}


drop pred*

reshape long perc_, i(risk) 

rename _j age_group_id
rename perc_ percentage_change_sbp

//save the data
tempfile sbp_ihd_`age'
save `sbp_ihd_`age'', replace
restore
}
**************************************************************************************
**************************************************************************************
**************************************************************************************

**************************************************************************************
********************* SBP - ISCH_STROKE PREP *****************************************
**************************************************************************************
use "sbp_isch_stroke_rr.dta", clear
egen rr_mean = rowmean(rr_*)
rename rr_mean pred
replace pred = log(pred)
drop rr_*
keep if year_id == 2015 & sex_id == 1
gen risk = "."

keep age_group_id pred risk
sort age_group_id

reshape wide pred, i(risk) j(age_group_id)

rename pred* pred_*

**prepare a separate trend for each of the different age at events needed for IHD
local event_ages 60 65
foreach age of local event_ages {
preserve

if `age' == 60 {
**prep this for being centered at 60 to correpsond to age at event = 60
	gen perc_21 = ((pred_21 - pred_17) / pred_17) + 1
	gen perc_20 = ((pred_20 - pred_17) / pred_17) + 1
	gen perc_19 = ((pred_19 - pred_17) / pred_17) + 1
	gen perc_18 = ((pred_18 - pred_17) / pred_17) + 1
	gen perc_17 = ((pred_17 - pred_17) / pred_17) + 1
	gen perc_16 = ((pred_16 - pred_17) / pred_17) + 1
	gen perc_15 = ((pred_15 - pred_17) / pred_17) + 1
	gen perc_14 = ((pred_14 - pred_17) / pred_17) + 1
	gen perc_13 = ((pred_13 - pred_17) / pred_17) + 1
	gen perc_12 = ((pred_12 - pred_17) / pred_17) + 1
	gen perc_11 = ((pred_11 - pred_17) / pred_17) + 1
	gen perc_10 = ((pred_10 - pred_17) / pred_17) + 1
}
if `age' == 65 {
**prep this for being centered at 65 to correpsond to age at event = 65
	gen perc_21 = ((pred_21 - pred_18) / pred_18) + 1
	gen perc_20 = ((pred_20 - pred_18) / pred_18) + 1
	gen perc_19 = ((pred_19 - pred_18) / pred_18) + 1
	gen perc_18 = ((pred_18 - pred_18) / pred_18) + 1
	gen perc_17 = ((pred_17 - pred_18) / pred_18) + 1
	gen perc_16 = ((pred_16 - pred_18) / pred_18) + 1
	gen perc_15 = ((pred_15 - pred_18) / pred_18) + 1
	gen perc_14 = ((pred_14 - pred_18) / pred_18) + 1
	gen perc_13 = ((pred_13 - pred_18) / pred_18) + 1
	gen perc_12 = ((pred_12 - pred_18) / pred_18) + 1
	gen perc_11 = ((pred_11 - pred_18) / pred_18) + 1
	gen perc_10 = ((pred_10 - pred_18) / pred_18) + 1
}


drop pred*

reshape long perc_, i(risk) 

rename _j age_group_id
rename perc_ percentage_change_sbp

//save the data
tempfile sbp_isch_stroke_`age'
save `sbp_isch_stroke_`age'', replace
restore
}
**************************************************************************************
**************************************************************************************
**************************************************************************************

**************************************************************************************
********************* SBP - HEM_STROKE PREP ******************************************
**************************************************************************************
use "sbp_hem_stroke_rr.dta", clear
egen rr_mean = rowmean(rr_*)
rename rr_mean pred
replace pred = log(pred)
drop rr_*
keep if year_id == 2015 & sex_id == 1
gen risk = "."

keep age_group_id pred risk
sort age_group_id

reshape wide pred, i(risk) j(age_group_id)

rename pred* pred_*

**prepare a separate trend for each of the different age at events needed for IHD
local event_ages 60 65
foreach age of local event_ages {
preserve

if `age' == 60 {
**prep this for being centered at 60 to correpsond to age at event = 60
	gen perc_21 = ((pred_21 - pred_17) / pred_17) + 1
	gen perc_20 = ((pred_20 - pred_17) / pred_17) + 1
	gen perc_19 = ((pred_19 - pred_17) / pred_17) + 1
	gen perc_18 = ((pred_18 - pred_17) / pred_17) + 1
	gen perc_17 = ((pred_17 - pred_17) / pred_17) + 1
	gen perc_16 = ((pred_16 - pred_17) / pred_17) + 1
	gen perc_15 = ((pred_15 - pred_17) / pred_17) + 1
	gen perc_14 = ((pred_14 - pred_17) / pred_17) + 1
	gen perc_13 = ((pred_13 - pred_17) / pred_17) + 1
	gen perc_12 = ((pred_12 - pred_17) / pred_17) + 1
	gen perc_11 = ((pred_11 - pred_17) / pred_17) + 1
	gen perc_10 = ((pred_10 - pred_17) / pred_17) + 1
}
if `age' == 65 {
**prep this for being centered at 65 to correpsond to age at event = 65
	gen perc_21 = ((pred_21 - pred_18) / pred_18) + 1
	gen perc_20 = ((pred_20 - pred_18) / pred_18) + 1
	gen perc_19 = ((pred_19 - pred_18) / pred_18) + 1
	gen perc_18 = ((pred_18 - pred_18) / pred_18) + 1
	gen perc_17 = ((pred_17 - pred_18) / pred_18) + 1
	gen perc_16 = ((pred_16 - pred_18) / pred_18) + 1
	gen perc_15 = ((pred_15 - pred_18) / pred_18) + 1
	gen perc_14 = ((pred_14 - pred_18) / pred_18) + 1
	gen perc_13 = ((pred_13 - pred_18) / pred_18) + 1
	gen perc_12 = ((pred_12 - pred_18) / pred_18) + 1
	gen perc_11 = ((pred_11 - pred_18) / pred_18) + 1
	gen perc_10 = ((pred_10 - pred_18) / pred_18) + 1
}


drop pred*

reshape long perc_, i(risk) 

rename _j age_group_id
rename perc_ percentage_change_sbp

//save the data
tempfile sbp_hem_stroke_`age'
save `sbp_hem_stroke_`age'', replace
restore
}
**************************************************************************************
**************************************************************************************
**************************************************************************************

**************************************************************************************
********************* FPG - IHD PREP *************************************************
**************************************************************************************
use "fpg_ihd_rr.dta", clear
egen rr_mean = rowmean(rr_*)
rename rr_mean pred
replace pred = log(pred)
drop rr_*
keep if year_id == 2015 & sex_id == 1
gen risk = "."

keep age_group_id pred risk
sort age_group_id

reshape wide pred, i(risk) j(age_group_id)

rename pred* pred_*

**prepare a separate trend for each of the different age at events needed for IHD
local event_ages 60 55 65 50
foreach age of local event_ages {
preserve

if `age' == 60 {
**prep this for being centered at 60 to correpsond to age at event = 60
	gen perc_21 = ((pred_21 - pred_17) / pred_17) + 1
	gen perc_20 = ((pred_20 - pred_17) / pred_17) + 1
	gen perc_19 = ((pred_19 - pred_17) / pred_17) + 1
	gen perc_18 = ((pred_18 - pred_17) / pred_17) + 1
	gen perc_17 = ((pred_17 - pred_17) / pred_17) + 1
	gen perc_16 = ((pred_16 - pred_17) / pred_17) + 1
	gen perc_15 = ((pred_15 - pred_17) / pred_17) + 1
	gen perc_14 = ((pred_14 - pred_17) / pred_17) + 1
	gen perc_13 = ((pred_13 - pred_17) / pred_17) + 1
	gen perc_12 = ((pred_12 - pred_17) / pred_17) + 1
	gen perc_11 = ((pred_11 - pred_17) / pred_17) + 1
	gen perc_10 = ((pred_10 - pred_17) / pred_17) + 1
}
if `age' == 55 {
**prep this for being centered at 55 to correpsond to age at event = 55
	gen perc_21 = ((pred_21 - pred_16) / pred_16) + 1
	gen perc_20 = ((pred_20 - pred_16) / pred_16) + 1
	gen perc_19 = ((pred_19 - pred_16) / pred_16) + 1
	gen perc_18 = ((pred_18 - pred_16) / pred_16) + 1
	gen perc_17 = ((pred_17 - pred_16) / pred_16) + 1
	gen perc_16 = ((pred_16 - pred_16) / pred_16) + 1
	gen perc_15 = ((pred_15 - pred_16) / pred_16) + 1
	gen perc_14 = ((pred_14 - pred_16) / pred_16) + 1
	gen perc_13 = ((pred_13 - pred_16) / pred_16) + 1
	gen perc_12 = ((pred_12 - pred_16) / pred_16) + 1
	gen perc_11 = ((pred_11 - pred_16) / pred_16) + 1
	gen perc_10 = ((pred_10 - pred_16) / pred_16) + 1
}
if `age' == 65 {
**prep this for being centered at 65 to correpsond to age at event = 65
	gen perc_21 = ((pred_21 - pred_18) / pred_18) + 1
	gen perc_20 = ((pred_20 - pred_18) / pred_18) + 1
	gen perc_19 = ((pred_19 - pred_18) / pred_18) + 1
	gen perc_18 = ((pred_18 - pred_18) / pred_18) + 1
	gen perc_17 = ((pred_17 - pred_18) / pred_18) + 1
	gen perc_16 = ((pred_16 - pred_18) / pred_18) + 1
	gen perc_15 = ((pred_15 - pred_18) / pred_18) + 1
	gen perc_14 = ((pred_14 - pred_18) / pred_18) + 1
	gen perc_13 = ((pred_13 - pred_18) / pred_18) + 1
	gen perc_12 = ((pred_12 - pred_18) / pred_18) + 1
	gen perc_11 = ((pred_11 - pred_18) / pred_18) + 1
	gen perc_10 = ((pred_10 - pred_18) / pred_18) + 1
}
if `age' == 50 {
**prep this for being centered at 50 to correpsond to age at event = 50
	gen perc_21 = ((pred_21 - pred_15) / pred_15) + 1
	gen perc_20 = ((pred_20 - pred_15) / pred_15) + 1
	gen perc_19 = ((pred_19 - pred_15) / pred_15) + 1
	gen perc_18 = ((pred_18 - pred_15) / pred_15) + 1
	gen perc_17 = ((pred_17 - pred_15) / pred_15) + 1
	gen perc_16 = ((pred_16 - pred_15) / pred_15) + 1
	gen perc_15 = ((pred_15 - pred_15) / pred_15) + 1
	gen perc_14 = ((pred_14 - pred_15) / pred_15) + 1
	gen perc_13 = ((pred_13 - pred_15) / pred_15) + 1
	gen perc_12 = ((pred_12 - pred_15) / pred_15) + 1
	gen perc_11 = ((pred_11 - pred_15) / pred_15) + 1
	gen perc_10 = ((pred_10 - pred_15) / pred_15) + 1
}


drop pred*

reshape long perc_, i(risk) 

rename _j age_group_id
rename perc_ percentage_change_fpg

//save the data
tempfile fpg_ihd_`age'
save `fpg_ihd_`age'', replace
restore
}
**************************************************************************************
**************************************************************************************
**************************************************************************************

**************************************************************************************
********************* FPG - ISCH_STROKE PREP *****************************************
**************************************************************************************
use "fpg_isch_stroke_rr.dta", clear
egen rr_mean = rowmean(rr_*)
rename rr_mean pred
replace pred = log(pred)
drop rr_*
keep if year_id == 2015 & sex_id == 1
gen risk = "."

keep age_group_id pred risk
sort age_group_id

reshape wide pred, i(risk) j(age_group_id)

rename pred* pred_*

**prepare a separate trend for each of the different age at events needed for IHD
local event_ages 60 65
foreach age of local event_ages {
preserve

if `age' == 60 {
**prep this for being centered at 60 to correpsond to age at event = 60
	gen perc_21 = ((pred_21 - pred_17) / pred_17) + 1
	gen perc_20 = ((pred_20 - pred_17) / pred_17) + 1
	gen perc_19 = ((pred_19 - pred_17) / pred_17) + 1
	gen perc_18 = ((pred_18 - pred_17) / pred_17) + 1
	gen perc_17 = ((pred_17 - pred_17) / pred_17) + 1
	gen perc_16 = ((pred_16 - pred_17) / pred_17) + 1
	gen perc_15 = ((pred_15 - pred_17) / pred_17) + 1
	gen perc_14 = ((pred_14 - pred_17) / pred_17) + 1
	gen perc_13 = ((pred_13 - pred_17) / pred_17) + 1
	gen perc_12 = ((pred_12 - pred_17) / pred_17) + 1
	gen perc_11 = ((pred_11 - pred_17) / pred_17) + 1
	gen perc_10 = ((pred_10 - pred_17) / pred_17) + 1
}
if `age' == 65 {
**prep this for being centered at 65 to correpsond to age at event = 65
	gen perc_21 = ((pred_21 - pred_18) / pred_18) + 1
	gen perc_20 = ((pred_20 - pred_18) / pred_18) + 1
	gen perc_19 = ((pred_19 - pred_18) / pred_18) + 1
	gen perc_18 = ((pred_18 - pred_18) / pred_18) + 1
	gen perc_17 = ((pred_17 - pred_18) / pred_18) + 1
	gen perc_16 = ((pred_16 - pred_18) / pred_18) + 1
	gen perc_15 = ((pred_15 - pred_18) / pred_18) + 1
	gen perc_14 = ((pred_14 - pred_18) / pred_18) + 1
	gen perc_13 = ((pred_13 - pred_18) / pred_18) + 1
	gen perc_12 = ((pred_12 - pred_18) / pred_18) + 1
	gen perc_11 = ((pred_11 - pred_18) / pred_18) + 1
	gen perc_10 = ((pred_10 - pred_18) / pred_18) + 1
}


drop pred*

reshape long perc_, i(risk) 

rename _j age_group_id
rename perc_ percentage_change_fpg

//save the data
tempfile fpg_isch_stroke_`age'
save `fpg_isch_stroke_`age'', replace
restore
}
**************************************************************************************
**************************************************************************************
**************************************************************************************

**************************************************************************************
********************* FPG - HEM_STROKE PREP ******************************************
**************************************************************************************
use "fpg_hem_stroke_rr.dta", clear
egen rr_mean = rowmean(rr_*)
rename rr_mean pred
replace pred = log(pred)
drop rr_*
keep if year_id == 2015 & sex_id == 1
gen risk = "."

keep age_group_id pred risk
sort age_group_id

reshape wide pred, i(risk) j(age_group_id)

rename pred* pred_*

**prepare a separate trend for each of the different age at events needed for IHD
local event_ages 60 65
foreach age of local event_ages {
preserve

if `age' == 60 {
**prep this for being centered at 60 to correpsond to age at event = 60
	gen perc_21 = ((pred_21 - pred_17) / pred_17) + 1
	gen perc_20 = ((pred_20 - pred_17) / pred_17) + 1
	gen perc_19 = ((pred_19 - pred_17) / pred_17) + 1
	gen perc_18 = ((pred_18 - pred_17) / pred_17) + 1
	gen perc_17 = ((pred_17 - pred_17) / pred_17) + 1
	gen perc_16 = ((pred_16 - pred_17) / pred_17) + 1
	gen perc_15 = ((pred_15 - pred_17) / pred_17) + 1
	gen perc_14 = ((pred_14 - pred_17) / pred_17) + 1
	gen perc_13 = ((pred_13 - pred_17) / pred_17) + 1
	gen perc_12 = ((pred_12 - pred_17) / pred_17) + 1
	gen perc_11 = ((pred_11 - pred_17) / pred_17) + 1
	gen perc_10 = ((pred_10 - pred_17) / pred_17) + 1
}
if `age' == 65 {
**prep this for being centered at 65 to correpsond to age at event = 65
	gen perc_21 = ((pred_21 - pred_18) / pred_18) + 1
	gen perc_20 = ((pred_20 - pred_18) / pred_18) + 1
	gen perc_19 = ((pred_19 - pred_18) / pred_18) + 1
	gen perc_18 = ((pred_18 - pred_18) / pred_18) + 1
	gen perc_17 = ((pred_17 - pred_18) / pred_18) + 1
	gen perc_16 = ((pred_16 - pred_18) / pred_18) + 1
	gen perc_15 = ((pred_15 - pred_18) / pred_18) + 1
	gen perc_14 = ((pred_14 - pred_18) / pred_18) + 1
	gen perc_13 = ((pred_13 - pred_18) / pred_18) + 1
	gen perc_12 = ((pred_12 - pred_18) / pred_18) + 1
	gen perc_11 = ((pred_11 - pred_18) / pred_18) + 1
	gen perc_10 = ((pred_10 - pred_18) / pred_18) + 1
}


drop pred*

reshape long perc_, i(risk) 

rename _j age_group_id
rename perc_ percentage_change_fpg

//save the data
tempfile fpg_hem_stroke_`age'
save `fpg_hem_stroke_`age'', replace
restore
}
**************************************************************************************
**************************************************************************************
**************************************************************************************

**************************************************************************************
********************* CHOLESTEROL - IHD PREP *****************************************
**************************************************************************************
use "cholesterol_ihd_rr.dta", clear
egen rr_mean = rowmean(rr_*)
rename rr_mean pred
replace pred = log(pred)
drop rr_*
keep if year_id == 2015 & sex_id == 1
gen risk = "."

keep age_group_id pred risk
sort age_group_id

reshape wide pred, i(risk) j(age_group_id)

rename pred* pred_*

**prepare a separate trend for each of the different age at events needed for IHD
local event_ages 60 55 65 50
foreach age of local event_ages {
preserve

if `age' == 60 {
**prep this for being centered at 60 to correpsond to age at event = 60
	gen perc_21 = ((pred_21 - pred_17) / pred_17) + 1
	gen perc_20 = ((pred_20 - pred_17) / pred_17) + 1
	gen perc_19 = ((pred_19 - pred_17) / pred_17) + 1
	gen perc_18 = ((pred_18 - pred_17) / pred_17) + 1
	gen perc_17 = ((pred_17 - pred_17) / pred_17) + 1
	gen perc_16 = ((pred_16 - pred_17) / pred_17) + 1
	gen perc_15 = ((pred_15 - pred_17) / pred_17) + 1
	gen perc_14 = ((pred_14 - pred_17) / pred_17) + 1
	gen perc_13 = ((pred_13 - pred_17) / pred_17) + 1
	gen perc_12 = ((pred_12 - pred_17) / pred_17) + 1
	gen perc_11 = ((pred_11 - pred_17) / pred_17) + 1
	gen perc_10 = ((pred_10 - pred_17) / pred_17) + 1
}
if `age' == 55 {
**prep this for being centered at 55 to correpsond to age at event = 55
	gen perc_21 = ((pred_21 - pred_16) / pred_16) + 1
	gen perc_20 = ((pred_20 - pred_16) / pred_16) + 1
	gen perc_19 = ((pred_19 - pred_16) / pred_16) + 1
	gen perc_18 = ((pred_18 - pred_16) / pred_16) + 1
	gen perc_17 = ((pred_17 - pred_16) / pred_16) + 1
	gen perc_16 = ((pred_16 - pred_16) / pred_16) + 1
	gen perc_15 = ((pred_15 - pred_16) / pred_16) + 1
	gen perc_14 = ((pred_14 - pred_16) / pred_16) + 1
	gen perc_13 = ((pred_13 - pred_16) / pred_16) + 1
	gen perc_12 = ((pred_12 - pred_16) / pred_16) + 1
	gen perc_11 = ((pred_11 - pred_16) / pred_16) + 1
	gen perc_10 = ((pred_10 - pred_16) / pred_16) + 1
}
if `age' == 65 {
**prep this for being centered at 65 to correpsond to age at event = 65
	gen perc_21 = ((pred_21 - pred_18) / pred_18) + 1
	gen perc_20 = ((pred_20 - pred_18) / pred_18) + 1
	gen perc_19 = ((pred_19 - pred_18) / pred_18) + 1
	gen perc_18 = ((pred_18 - pred_18) / pred_18) + 1
	gen perc_17 = ((pred_17 - pred_18) / pred_18) + 1
	gen perc_16 = ((pred_16 - pred_18) / pred_18) + 1
	gen perc_15 = ((pred_15 - pred_18) / pred_18) + 1
	gen perc_14 = ((pred_14 - pred_18) / pred_18) + 1
	gen perc_13 = ((pred_13 - pred_18) / pred_18) + 1
	gen perc_12 = ((pred_12 - pred_18) / pred_18) + 1
	gen perc_11 = ((pred_11 - pred_18) / pred_18) + 1
	gen perc_10 = ((pred_10 - pred_18) / pred_18) + 1
}
if `age' == 50 {
**prep this for being centered at 50 to correpsond to age at event = 50
	gen perc_21 = ((pred_21 - pred_15) / pred_15) + 1
	gen perc_20 = ((pred_20 - pred_15) / pred_15) + 1
	gen perc_19 = ((pred_19 - pred_15) / pred_15) + 1
	gen perc_18 = ((pred_18 - pred_15) / pred_15) + 1
	gen perc_17 = ((pred_17 - pred_15) / pred_15) + 1
	gen perc_16 = ((pred_16 - pred_15) / pred_15) + 1
	gen perc_15 = ((pred_15 - pred_15) / pred_15) + 1
	gen perc_14 = ((pred_14 - pred_15) / pred_15) + 1
	gen perc_13 = ((pred_13 - pred_15) / pred_15) + 1
	gen perc_12 = ((pred_12 - pred_15) / pred_15) + 1
	gen perc_11 = ((pred_11 - pred_15) / pred_15) + 1
	gen perc_10 = ((pred_10 - pred_15) / pred_15) + 1
}


drop pred*

reshape long perc_, i(risk) 

rename _j age_group_id
rename perc_ percentage_change_cholesterol

//save the data
tempfile cholesterol_ihd_`age'
save `cholesterol_ihd_`age'', replace
restore
}
**************************************************************************************
**************************************************************************************
**************************************************************************************

**************************************************************************************
********************* CHOLESTEROL - ISCH_STROKE PREP *********************************
**************************************************************************************
use "cholesterol_isch_stroke_rr.dta", clear
egen rr_mean = rowmean(rr_*)
rename rr_mean pred
replace pred = log(pred)
drop rr_*
keep if year_id == 2015 & sex_id == 1
gen risk = "."

keep age_group_id pred risk
sort age_group_id

reshape wide pred, i(risk) j(age_group_id)

rename pred* pred_*

**prepare a separate trend for each of the different age at events needed for IHD
local event_ages 60 65
foreach age of local event_ages {
preserve

if `age' == 60 {
**prep this for being centered at 60 to correpsond to age at event = 60
	gen perc_21 = ((pred_21 - pred_17) / pred_17) + 1
	gen perc_20 = ((pred_20 - pred_17) / pred_17) + 1
	gen perc_19 = ((pred_19 - pred_17) / pred_17) + 1
	gen perc_18 = ((pred_18 - pred_17) / pred_17) + 1
	gen perc_17 = ((pred_17 - pred_17) / pred_17) + 1
	gen perc_16 = ((pred_16 - pred_17) / pred_17) + 1
	gen perc_15 = ((pred_15 - pred_17) / pred_17) + 1
	gen perc_14 = ((pred_14 - pred_17) / pred_17) + 1
	gen perc_13 = ((pred_13 - pred_17) / pred_17) + 1
	gen perc_12 = ((pred_12 - pred_17) / pred_17) + 1
	gen perc_11 = ((pred_11 - pred_17) / pred_17) + 1
	gen perc_10 = ((pred_10 - pred_17) / pred_17) + 1
}
if `age' == 65 {
**prep this for being centered at 65 to correpsond to age at event = 65
	gen perc_21 = ((pred_21 - pred_18) / pred_18) + 1
	gen perc_20 = ((pred_20 - pred_18) / pred_18) + 1
	gen perc_19 = ((pred_19 - pred_18) / pred_18) + 1
	gen perc_18 = ((pred_18 - pred_18) / pred_18) + 1
	gen perc_17 = ((pred_17 - pred_18) / pred_18) + 1
	gen perc_16 = ((pred_16 - pred_18) / pred_18) + 1
	gen perc_15 = ((pred_15 - pred_18) / pred_18) + 1
	gen perc_14 = ((pred_14 - pred_18) / pred_18) + 1
	gen perc_13 = ((pred_13 - pred_18) / pred_18) + 1
	gen perc_12 = ((pred_12 - pred_18) / pred_18) + 1
	gen perc_11 = ((pred_11 - pred_18) / pred_18) + 1
	gen perc_10 = ((pred_10 - pred_18) / pred_18) + 1
}


drop pred*

reshape long perc_, i(risk) 

rename _j age_group_id
rename perc_ percentage_change_cholesterol

//save the data
tempfile cholesterol_isch_stroke_`age'
save `cholesterol_isch_stroke_`age'', replace
restore
}
**************************************************************************************
**************************************************************************************
**************************************************************************************




**************************************************************************************
********************* Prepare those that will be averaged ****************************
**************************************************************************************
**Averaging for fruit - ihd
use `sbp_ihd_60', clear
	merge 1:1 age_group_id using `bmi_ihd_60', nogen
	merge 1:1 age_group_id using `fpg_ihd_60', nogen
	merge 1:1 age_group_id using `cholesterol_ihd_60', nogen
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_fruit_cvd_ihd
		save `diet_fruit_cvd_ihd', replace

**Averaging for fruit - isch_stroke
use `bmi_isch_stroke_60', clear
	merge 1:1 age_group_id using `sbp_isch_stroke_60', nogen
	merge 1:1 age_group_id using `fpg_isch_stroke_60', nogen
	merge 1:1 age_group_id using `cholesterol_isch_stroke_60', nogen
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_fruit_cvd_stroke_isch
		save `diet_fruit_cvd_stroke_isch', replace

**Averaging for fruit - hem_stroke
use `sbp_hem_stroke_60', clear
	merge 1:1 age_group_id using `bmi_hem_stroke_60', nogen
	merge 1:1 age_group_id using `fpg_hem_stroke_60', nogen
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_fruit_cvd_stroke_cerhem
		save `diet_fruit_cvd_stroke_cerhem', replace

**Averaging for fruit - diabetes
use `bmi_dm_60', clear
	gen percentage_change = percentage_change_bmi
		keep risk age_group_id percentage_change
		tempfile diet_fruit_diabetes
		save `diet_fruit_diabetes', replace

**Averaging for veg - ihd
use `sbp_ihd_55', clear
	merge 1:1 age_group_id using `bmi_ihd_55', nogen
	merge 1:1 age_group_id using `fpg_ihd_55', nogen
	merge 1:1 age_group_id using `cholesterol_ihd_55', nogen
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_veg_cvd_ihd
		save `diet_veg_cvd_ihd', replace

**Averaging for veg - isch_stroke
use `sbp_isch_stroke_60', clear
	merge 1:1 age_group_id using `bmi_isch_stroke_60', nogen
	merge 1:1 age_group_id using `fpg_isch_stroke_60', nogen
	merge 1:1 age_group_id using `cholesterol_isch_stroke_60', nogen
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_veg_cvd_stroke_isch
		save `diet_veg_cvd_stroke_isch', replace

**Averaging for veg - hem_stroke
use `sbp_hem_stroke_60', clear
	merge 1:1 age_group_id using `bmi_hem_stroke_60', nogen
	merge 1:1 age_group_id using `fpg_hem_stroke_60', nogen
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_veg_cvd_stroke_cerhem
		save `diet_veg_cvd_stroke_cerhem', replace

**Averaging for nuts - ihd
use `cholesterol_ihd_55', clear
	merge 1:1 age_group_id using `fpg_ihd_55', nogen
	merge 1:1 age_group_id using `bmi_ihd_55', nogen
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_nuts_cvd_ihd
		save `diet_nuts_cvd_ihd', replace

**Averaging for nuts - diabetes
use `bmi_dm_60', clear
	gen percentage_change = percentage_change_bmi
		keep risk age_group_id percentage_change
		tempfile diet_nuts_diabetes
		save `diet_nuts_diabetes', replace

**Averaging for grains - ihd
use `bmi_ihd_65', clear
	merge 1:1 age_group_id using `fpg_ihd_65', nogen
	merge 1:1 age_group_id using `cholesterol_ihd_65', nogen
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_grains_cvd_ihd
		save `diet_grains_cvd_ihd', replace

**Averaging for grains - isch_stroke
use `bmi_isch_stroke_65', clear
	merge 1:1 age_group_id using `fpg_isch_stroke_65', nogen
	merge 1:1 age_group_id using `cholesterol_isch_stroke_65', nogen
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_grains_cvd_stroke_isch
		save `diet_grains_cvd_stroke_isch', replace

**Averaging for grains - hem_stroke
use `bmi_hem_stroke_65', clear
	merge 1:1 age_group_id using `fpg_hem_stroke_65', nogen
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_grains_cvd_stroke_cerhem
		save `diet_grains_cvd_stroke_cerhem', replace

**Averaging for grains - diabetes
use `bmi_dm_60', clear
	gen percentage_change = percentage_change_bmi
		keep risk age_group_id percentage_change
		tempfile diet_grains_diabetes
		save `diet_grains_diabetes', replace

**Averaging for redmeat - diabetes
use `bmi_dm_60', clear
	gen percentage_change = percentage_change_bmi
		keep risk age_group_id percentage_change
		tempfile diet_redmeat_diabetes
		save `diet_redmeat_diabetes', replace

**Averaging for procmeat - ihd
use `bmi_ihd_60', clear
	merge 1:1 age_group_id using `sbp_ihd_60', nogen
	merge 1:1 age_group_id using `fpg_ihd_60', nogen
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_procmeat_cvd_ihd
		save `diet_procmeat_cvd_ihd', replace

**Averaging for procmeat - diabetes
use `bmi_dm_60', clear
	gen percentage_change = percentage_change_bmi
		keep risk age_group_id percentage_change
		tempfile diet_procmeat_diabetes
		save `diet_procmeat_diabetes', replace

**Averaging for pufa - ihd
use `cholesterol_ihd_50', clear
	merge 1:1 age_group_id using `fpg_ihd_50', nogen
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_pufa_cvd_ihd
		save `diet_pufa_cvd_ihd', replace

**Averaging for fish - ihd
use `bmi_ihd_60', clear
	merge 1:1 age_group_id using `sbp_ihd_60', nogen
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_fish_cvd_ihd
		save `diet_fish_cvd_ihd', replace

**Averaging for transfat - ihd
use `cholesterol_ihd_60', clear
	merge 1:1 age_group_id using `bmi_ihd_60', nogen
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_transfat_cvd_ihd
		save `diet_transfat_cvd_ihd', replace

**Averaging for fiber - ihd
use `cholesterol_ihd_50', clear
	egen percentage_change = rowmean(percentage_change*)
		keep risk age_group_id percentage_change
		tempfile diet_fiber_cvd_ihd
		save `diet_fiber_cvd_ihd', replace


**************************************************************************************
**************************************************************************************
**************************************************************************************


capture restore, not
import excel "`raw_data'", firstrow clear

drop if removing == 1 | morbidity == . | mortality == . | pending == 1 | outcome == "metab_bmi"

drop if risk == "diet_nuts" & outcome == "cvd_ihd"

drop if Reference == "WCRF"

levelsof risk, local(risks)
levelsof outcome, local(outcomes)

foreach risk of local risks {
foreach outcome of local outcomes {
preserve
**for testing purposes
keep if risk == "`risk'" & outcome == "`outcome'"

count
if `r(N)' != 0 {	

**drop unnecessary vars
drop new* removing pending parameter unit Reference

gen standard_error = (rr_upper - rr_lower)/(2*1.96)
gen location_id = 1

**rename grams_daily exp_mean
rename rr_mean exp_mean
forvalues n = 0/999 {
	gen rr_`n' = rnormal(exp_mean, standard_error)
	replace rr_`n' = log(rr_`n')
}

**associate the metabolic age trends where appropriate
	local risk = risk
	replace risk = "."
	cap joinby risk using ``risk'_`outcome''
	replace risk = "`risk'"

quietly {
forvalues n = 0/999 {
	capture replace rr_`n' = rr_`n' * percentage_change
	replace rr_`n' = exp(rr_`n')
}
}
cap drop percentage_change exp_mean rr_lower rr_upper standard_error location_id year_id

egen mean_rr = rowmean(rr_*)
cap mkdir "tests/`risk'/"
save "`risk'_`outcome'.dta", replace
}
restore
}
}




**take care of nuts - cvd_ihd separately 
import excel "`raw_data'", firstrow clear

**do this one separate since separate risks for morbidity versus mortality
keep if risk == "diet_nuts" & outcome == "cvd_ihd"

levelsof morbidity, local(levels)

foreach level of local levels{
	preserve
	keep if morbidity == `level'

**drop unnecessary vars
drop new* removing pending parameter unit Reference

gen standard_error = (rr_upper - rr_lower)/(2*1.96)
gen location_id = 1
gen year_id = 2015
**rename grams_daily exp_mean
rename rr_mean exp_mean
forvalues n = 0/999 {
	gen rr_`n' = rnormal(exp_mean, standard_error)
	replace rr_`n' = log(rr_`n')
}
**Redmeat and Diabetes
	local risk = risk
	replace risk = "."
	joinby risk using `diet_nuts_cvd_ihd'
	replace risk = "`risk'"

quietly {
forvalues n = 0/999 {
	replace rr_`n' = rr_`n' * percentage_change
	replace rr_`n' = exp(rr_`n')
}
}
drop percentage_change exp_mean rr_lower rr_upper standard_error location_id year_id

tempfile level_`level'
save `level_`level'', replace
restore
}
use `level_1', clear
	append using `level_0' 
	egen mean_rr = rowmean(rr_*)
cap mkdir "tests/diet_nuts"
save "tests/diet_nuts/diet_nuts_cvd_ihd.dta", replace




*********************************
**expand cancers separately
*********************************
capture restore, not
import excel "`raw_data'", firstrow clear
keep if Reference == "WCRF"

drop if risk == "diet_salt_direct"

**prepare locals of each pair
levelsof risk, local(risks)
levelsof outcome, local(outcomes)

foreach risk of local risks {
foreach outcome of local outcomes {
preserve
**for testing purposes
keep if risk == "`risk'" & outcome == "`outcome'"

count
if `r(N)' != 0 {	

**drop unnecessary vars
drop new* removing pending parameter unit Reference

gen standard_error = (rr_upper - rr_lower)/(2*1.96)
gen location_id = 1

forvalues n = 0/999 {
	gen rr_`n' = rnormal(rr_mean, standard_error)
}

expand 12
**create age_group_id var
gen obs = _n
replace obs = obs + 9
rename obs age_group_id

cap drop percentage_change rr_mean rr_lower rr_upper standard_error location_id year_id

egen mean_rr = rowmean(rr_*)
cap mkdir "tests/`risk'/"
save "tests/`risk'/`risk'_`outcome'.dta", replace
}
restore
}
}