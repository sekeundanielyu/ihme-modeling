*** MALNUTRITION ANALYSIS DO FILE
** Do file to call within microdata loops - DHS, MICS, RHS, etc.
** This way, when change the way I'm analyzing microdata, can just make the changes once, and then call this do file in all the microdata do files

******************************************************************************************************************************************

// drop ridiculous heights and wights and if there is missingness
drop if (height_cm>900 | height_cm==. | height_cm<=0)
drop if (weight_kg>90 | weight_kg==. | weight_kg<=0)
drop if sex==.
drop if (age_mo>=60 | age_mo<0 | age_mo==.)
rename age_mo month
// add in 2015
gen samplesizen=_N

*** if survey is over more than one year, just keep first year
capture confirm variable year
if _rc==0 {
	summarize year
	replace year = r(min)
}
** because of weird rounding issues with the height variable, must do this to get it back to correct number of decimal places
tostring height_cm, gen(height2) force 
destring height2, replace  // to make the type of  variable into "double" 
replace height2=height_cm
replace height2 = round(height2,.1)
rename height_cm height_orig
rename height2 height_cm

***************************************************************************************
*** WASTING - WEIGHT FOR HEIGHT
***************************************************************************************
// Merge with WHO srandard, sperate by two age groups (0-24mo and 24-59 mo according to the standard)
* 0-24 mo
*** NOTE that the weight for height/length file has all the way out to 4SD cutoffs
preserve
keep if month<24
merge m:1 sex height_cm using "J:/Usable/Tools/Child Growth Standards/WHO Child Growth Standards 2006/weight-for-length_expanded_0-2yrs_zscores_bothsexes.dta"
* the range for height_cm in the standard is [45,110], so would not merge with those with height <45 cm and > 110 cm aged 0-24 mo
drop if _merge==2
tempfile data0_2
save `data0_2', replace
restore

* 24-59 mo
keep if month>=24
merge m:1 sex height_cm using "J:/Usable/Tools/Child Growth Standards/WHO Child Growth Standards 2006/weight-for-height_expanded_2-5yrs_zscores_bothsexes.dta"
append using `data0_2'
*** just drop if _merge==2, (ie not if _merge==1 - meaning that we will keep the one child who did not merge to the standard)
drop if _merge==2
** don't drop _merge so that can make sure that unmerged observations don't contribute to the maln estimates (see below)

// Generating dummy indicators for whether each individual is above/below each standard
*** now generate the wasting variables - note that weightforheight goes all the way out to 4sd and 4sdneg (unlike the rest of the indicators, that just go out to -3sd and 3sd)
*** make a local "below" that is for the *negative* standards - calculate for weights below this
local below 4sdneg 3sdneg 2sdneg 1sdneg
foreach b of local below {
	gen weightforheight_`b' = (weight_kg < std_weightforheight_`b')
}
*** make a local "above" for the standards that are for overweight - the cutoff is if the weight is above these *positive* weightforheight cutoffs
local above 1sd 2sd 3sd 4sd
foreach a of local above {
	gen weightforheight_`a' = (weight_kg > std_weightforheight_`a')
}
*** must do MEDIAN separately because need 2 vars - one for abovemedian and one for belowmedian
gen weightforheight_blwmed = (weight_kg < std_weightforheight_median)
gen weightforheight_abvmed = (weight_kg > std_weightforheight_median)

** now for those observations that didn't merge with the wfh files, make sure that they don't get 1s or 0s above bcs they shouldn't contribute to the maln estimates if they didn't merge correctly
local measures weightforheight_4sdneg weightforheight_3sdneg weightforheight_2sdneg weightforheight_1sdneg weightforheight_blwmed ///
weightforheight_abvmed weightforheight_1sd weightforheight_2sd weightforheight_3sd weightforheight_4sd
foreach m of local measures {
	replace `m' = . if _merge==1
}
** now drop _merge
drop _merge

************************************************************************************************************
**Merge with standard other than (height for weight)
************************************************************************************************************
***  merge in heightforage file
merge m:1 month sex using "J:\Usable\Tools\Child Growth Standards\WHO Child Growth Standards 2006\heightforage_0-5yrs_zscores_bothsexes.dta"
drop if _merge==2
** _merge==1 should ALWAYS have zero obs bcs we are merging on month and sex, which should ALWAYS be in the master dataset. so it's ok to drop _merge
drop _merge
***  merge in weightforage file
merge m:1 month sex using "J:\Usable\Tools\Child Growth Standards\WHO Child Growth Standards 2006\weightforage_0-5yrs_zscores_bothsexes.dta"
drop if _merge==2
** _merge==1 should ALWAYS have zero obs bcs we are merging on month and sex, which should ALWAYS be in the master dataset. so it's ok to drop _merge
drop _merge

************************************************************************************************************
*** Stunting- HEIGHT FOR AGE 
************************************************************************************************************
** generating dummy indicators for whether each individual is above/below each standard
gen heightforage_3sdneg = (height_cm < std_heightforage_3sdneg)
gen heightforage_2sdneg = (height_cm < std_heightforage_2sdneg)
gen heightforage_1sdneg = (height_cm < std_heightforage_1sdneg)
gen heightforage_belowmedian = (height_cm < std_heightforage_median)
gen heightforage_abovemedian = (height_cm > std_heightforage_median)
gen heightforage_1sd = (height_cm > std_heightforage_1sd)
gen heightforage_2sd = (height_cm > std_heightforage_2sd)
gen heightforage_3sd = (height_cm > std_heightforage_3sd)

************************************************************************************************************
*** Underweight-WEIGHT FOR AGE
************************************************************************************************************
** generating dummy indicators for whether each individual is above/below each standard
gen weightforage_3sdneg = (weight_kg < std_weightforage_3sdneg)
gen weightforage_2sdneg = (weight_kg < std_weightforage_2sdneg)
gen weightforage_1sdneg = (weight_kg < std_weightforage_1sdneg)
gen weightforage_belowmedian = (weight_kg < std_weightforage_median)
gen weightforage_abovemedian = (weight_kg > std_weightforage_median)
gen weightforage_1sd = (weight_kg > std_weightforage_1sd)
gen weightforage_2sd = (weight_kg > std_weightforage_2sd)
gen weightforage_3sd = (weight_kg > std_weightforage_3sd)


************************************************************************************************************
*** SURVEY WEIGHTING THE MEANS AND STANDARD ERRORS	--calculate the prevalence based on the sample design
************************************************************************************************************	
svyset cluster_num [pweight=sample_weight]
local means heightforage_3sdneg heightforage_2sdneg heightforage_1sdneg heightforage_belowmedian heightforage_abovemedian ///
heightforage_1sd heightforage_2sd heightforage_3sd weightforage_3sdneg weightforage_2sdneg weightforage_1sdneg ///
weightforage_belowmedian weightforage_abovemedian weightforage_1sd weightforage_2sd weightforage_3sd ///
weightforheight_4sdneg weightforheight_3sdneg weightforheight_2sdneg weightforheight_1sdneg weightforheight_blwmed ///
weightforheight_abvmed weightforheight_1sd weightforheight_2sd weightforheight_3sd weightforheight_4sd
foreach m of local means {
	di "`m'"
	svy: mean `m'
	ereturn list
	matrix variance_matrix = e(V)
	matrix mean_matrix = e(b)
	gen mean_`m'=.
	di "`m'"
	gen semean_`m'=.
	*** below is overkill but will allow for easy substitution when separating this out for m and f malnutrition prevalence, if desired
	forvalues x = 1(1)1 {
		local mean = mean_matrix[1,`x']
		di `mean'
		** replace mean_`m' = `mean'*100
		replace mean_`m' = `mean'
		local se = sqrt(variance_matrix[1,`x'])
		di `se'
		** replace semean_`m' = `se'*100
		replace semean_`m' = `se'
	}
}
		
*** make upper and lower CIs using means local above
foreach m of local means {
	gen upperci_`m' = mean_`m' + 1.96*semean_`m'
	gen lowerci_`m' = mean_`m' - 1.96*semean_`m'
}

*** gen startage and endage vars 
summarize month
local startage = r(min)
local endage = r(max)
gen startage = `startage'
gen endage = `endage'

// do the below for surveys other than DHS where year is a variable---for longitudinal surveys?
capture confirm variable year
if _rc==0 {
	collapse year mean_* semean_* upperci_* lowerci_* startage endage samplesizen
	*** fix years so that they are 4 digits rather than 2 (when applicable)
	replace year = 1900+year if year>10 & year<100
	replace year = 2000+year if year<10
	summarize year
	local startyear = r(min)
}

capture confirm variable year
if _rc!=0 {
*** collapse to just get one mean and se per survey
	collapse mean_* semean_* upperci_* lowerci_* startage endage samplesizen
}

*** rename to get rid of "mean" in front of all the variables
foreach m of local means {
	rename mean_`m' `m'
}

// This File Contains: % prevalence of height for age, weight for height, weight for age at all possible levels, and their standard errors of the mean, and the upper & lower CIs


******************************************************************************************************************************************

