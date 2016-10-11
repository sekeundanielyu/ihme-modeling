
******************
** Set up Stata **
******************


cap program drop compile_45q15pop
program define compile_45q15pop

clear 
set mem 500m
set more off

*******************
** Define syntax **
*******************

syntax, iso3(string) saveas(string) 

************************
** Define directories **
************************

global rawdataDir = "J:/project/mortality/GBD Envelopes/00. Input data/00. Format all age data/Raw Data/Population"

global iso3_to_countryDir = "J:/project/mortality/Tools"
global iso3_to_countryFile = "countrytoiso3_master.dta"

global unDir = "J:\Usable\Estimates\UNPOP World Population Prospects 2008"
global unFile = "USABLE_EST_UNPOP_GLOBAL_1950-2010_vPOPULATIONMEDIUMVARIANT.csv"

global popDir = "J:/project/mortality/GBD Envelopes/00. Input data/00. Format all age data"
global popFile = "01. POPULATION_FORMATTED.dta"

global srsindDir = "J:/project/mortality/GBD Envelopes/00. Input data/00. Format all age data/Raw Data/Population/SRS LIBRARY/INDIA 1997-2000-2006"
global srsindFile = "USABLE_SRSPOP_IND_1997-2000-2006.dta"

global chndsp2004Dir = "J:/project/mortality/GBD Envelopes/00. Input data/00. Format all age data/Raw Data/Population/CHINA DSP"
global chndsp2004File = "USABLE_DSPPOP_CHN_2004.dta"

global chndsp1995Dir = "J:/project/mortality/GBD Envelopes/00. Input data/00. Format all age data/Raw Data/Population/CHINA DSP" 
global chndsp1995File = "USABLE_DSPPOP_CHN_1995.dta"

global chndsp9600Dir = "J:/project/mortality/GBD Envelopes/00. Input data/00. Format all age data/Raw Data/Population/CHINA DSP"
global chndsp9600File = "USABLE_DSPPOP_CHN_1996-2000.dta"

global censuspopforchnDir = "J:/project/mortality/GBD Envelopes/00. Input data/00. Format all age data"
global censuspopforchnFile = "00. POPULATION.dta"

global chnmohDir = "J:/project/mortality/GBD Envelopes/00. Input data/00. Format all age data/Raw Data/Population/WHO CHINA SAMPLE"
global chnmohFile = "USABLE_CENSUS_WHO_CHN_1950-2007.dta"

global chnmohrecentDir = "J:/project/mortality/GBD Envelopes/00. Input data/00. Format all age data/Raw Data/Population/WHO CHINA SAMPLE"
global chnmohrecentFile = "USABLE_CENSUS_WHO_CHN_2003-2007.dta"

global chn1survey95Dir = "J:/project/mortality/GBD Envelopes/00. Input data/00. Format all age data/Raw Data/Population/CHINA 1 percent"
global chn1survey95File = "USABLE_INT_GOV_CHN_1995_vPop.dta"

global chn1survey05Dir = "J:/project/mortality/GBD Envelopes/00. Input data/00. Format all age data/Raw Data/Population/CHINA 1 percent"
global chn1survey05File = "USABLE_INT_GOV_CHN_2005_vPop.dta"

global twnhmdDir = "J:/project/mortality/GBD Envelopes/00. Input data/00. Format all age data/Raw Data/Population/HMD"
global twnhmdFile = "USABLE_CENSUS_HMD_TWN_1970-2008_vallyears.dta"


**global saveasDir "J:/project/mortality/GBD Envelopes/00. Input data/00. Format all age data"
**global saveasFile "09. POPULATION_For45q15s.dta"

******************************
** Set up files for merging **
******************************

use "$iso3_to_countryDir/$iso3_to_countryFile", clear
sort country
save, replace

*************
** UN Data **
*************

noisily: display in green "UN data"

insheet using "$unDir/$unFile", clear names

g openend = .
forvalues j = 0/99 {
	local jplus = `j'+1
	replace openend = `jplus' if openend == . & pop_age`jplus' == .
}
replace openend = 100 if openend == .

replace pop_age80plus = . if openend == 100
rename pop_age80plus DATUM80plus
rename pop_age100 DATUM100plus 

rename pop_age0 DATUM0to0
egen DATUM1to4 = rowtotal(pop_age1-pop_age4)

forvalues j = 5(5)95 {
	local jplus = `j'+4
	egen DATUM`j'to`jplus' = rowtotal(pop_age`j'-pop_age`jplus')
}


egen DATUMTOT = rowtotal(DATUM*)
g DATUMUNK = .

drop pop_age* variant notes countrycode

rename sex SEX
rename year YEAR

preserve 
collapse (sum) DATUM*, by(country YEAR openend)
g SEX = 0
tempfile both
save `both', replace
restore

append using `both'

forvalues j = 80(5)95 {
	local jplus = `j'+4
	replace DATUM`j'to`jplus' = . if openend == 80
}
replace DATUM80plus = . if openend == 100
replace DATUM100plus = . if openend == 80

drop openend

sort country 
merge country using "$iso3_to_countryDir/$iso3_to_countryFile"
tab _merge
keep if _merge == 3
drop _merge

drop country
rename iso3 COUNTRY

rename DATUM0to0 c1_0to0
rename DATUM1to4 c1_1to4
rename DATUM80plus c1_80plus
rename DATUM100plus c1_100plus

forvalues j = 5(5)95 {
	local jplus = `j'+4
	rename DATUM`j'to`jplus' c1_`j'to`jplus'
}

g c1_0to4 = .
g c1_85plus = .

forvalues j = 5(5)95 {
	local jplus = `j'+4
	replace c1_`j'to`jplus' = c1_`j'to`jplus'*1000
}

replace c1_0to0 = c1_0to0*1000
replace c1_1to4 = c1_1to4*1000
replace c1_80plus = c1_80plus*1000
replace c1_100plus = c1_100plus*1000

replace c1_0to4 = c1_0to0 + c1_1to4

drop DATUMTOT DATUMUNK

preserve
keep CO YEAR SEX
keep if CO == "CHN"
replace CO = "CHN_"
tempfile chndata_
save `chndata_', replace
restore

append using `chndata_'
replace CO = "CHNDYB" if CO == "CHN_"
append using `chndata_'
replace CO = "CHNWHO" if CO == "CHN_"
append using `chndata_'
replace CO = "CHNDSP" if CO == "CHN_" 
append using `chndata_'
replace CO = "CHNDC" if CO == "CHN_" 

sort CO YEAR SEX
tempfile main
save `main', replace

*****************
** Census Data **
*****************

noisily: display in green "Census data"

preserve
use "$popDir/$popFile", clear
drop if agegroup2 ~= 2 & agegroup2 ~= 5 
g c1_0to0 = pop0 if agegroup2 == 2
egen c1_1to4 = rowtotal(pop1-pop4) if agegroup2 == 2
egen c1_0to4 = rowtotal(pop0-pop4)

g openend = .
forvalues j =  0/99 {
	local jplus = `j'+1
	replace openend = agegroup`j' if openend == . & agegroup`jplus' == .
}

forvalues j = 5(5)95 {
	local jplus = `j'+4
	egen c1_`j'to`jplus' = rowtotal(pop`j'-pop`jplus') if `j' < openend
}

forvalues j = 5/100 { 
	egen c1_`j'plus = rowtotal(pop`j'-pop100) if openend == `j'
	levelsof c1_`j'plus, local(dropit)
	if("`dropit'" == "") {
		drop c1_`j'plus
	}	
}

rename iso3 COUNTRY
rename year YEAR

g SEX = 0 if sex == "both"
replace SEX = 1 if sex == "male"
replace SEX = 2 if sex == "female"

drop sex

keep CO YEAR SEX c1_*

sort CO YEAR SEX

merge CO using `main'
keep if _merge == 1
drop _merge

sort CO YEAR SEX

tempfile censusdata
save `censusdata', replace
restore

append using `censusdata'


********************
** India SRS Data **
********************

noisily: display in green "India SRS data"

preserve
*use "J:\Project\Mortality\Death distribution methods\Data\GBD\CENSUS\SRS LIBRARY\INDIA 1997-2000-2006\USABLE_SRSPOP_IND_1997-2000-2006.dta", clear
use "$srsindDir/$srsindFile", clear

sort CO YEAR SEX
tempfile newdata
save `newdata', replace
restore

sort CO YEAR SEX
merge CO YEAR SEX using `newdata', keep(DATUM*)

replace c1_0to0 = . if _merge == 3
replace c1_1to4 = . if _merge == 3
replace c1_0to4 = DATUM0to4 if _merge == 3

forvalues j = 5(5)80 {
	local jplus = `j'+4
	replace c1_`j'to`jplus' = DATUM`j'to`jplus' if _merge == 3
}
replace c1_85plus = DATUM85plus if _merge == 3

drop DATUM* _merge

********************
** China DSP Data **
********************

noisily: display in green "China DSP data"

preserve
use "$chndsp2004Dir/$chndsp2004File", clear
append using "$chndsp1995Dir/$chndsp1995File"
append using "$chndsp9600Dir/$chndsp9600File"
*use "J:\Project\Mortality\Death distribution methods\Data\GBD\CENSUS\CHINA DSP\USABLE_DSPPOP_CHN_2004.dta", clear
*append using "J:\Project\Mortality\Death distribution methods\Data\GBD\CENSUS\CHINA DSP\USABLE_DSPPOP_CHN_1995.dta"
*append using "J:\Project\Mortality\Death distribution methods\Data\GBD\CENSUS\CHINA DSP\USABLE_DSPPOP_CHN_1996-2000.dta"

replace CO = "CHNDSP"
sort CO YEAR SEX
tempfile newdata
save `newdata', replace
restore

sort CO YEAR SEX
merge CO YEAR SEX using `newdata', keep(DATUM*)

replace c1_0to0 = DATUM0to0 if _merge == 3
replace c1_1to4 = DATUM1to4 if _merge == 3
replace c1_0to4 = c1_0to0 + c1_0to4 if _merge == 3
forvalues j = 5(5)80 {
	local jplus = `j'+4
	replace c1_`j'to`jplus' = DATUM`j'to`jplus' if _merge == 3
}
replace c1_85plus = DATUM85plus if _merge == 3

drop DATUM* _merge

***********************
** China census Data **
***********************

noisily: display in green "China census data"

preserve
use "$censuspopforchnDir/$censuspopforchnFile", clear
*use "J:\Project\Mortality\Death distribution methods\Data\GBD\CENSUS\USABLE_CENSUS_MULTIPLE_GLOBAL.dta", clear

rename iso3 COUNTRY
rename year YEAR
rename pop_source CENSUS_SOURCE

g SEX = 0 if sex == "both"
replace SEX = 1 if sex == "male"
replace SEX = 2 if sex == "female"

drop sex


keep if CO == "CHN" 
replace CO = "CHNDYB"
keep if strpos(CENSUS_SOURCE,"DYB") ~= 0
keep if YEAR == 1982 | YEAR == 1990 | YEAR == 2000
replace YEAR = YEAR - 1 if YEAR == 1990 | YEAR == 2000
sort DATUM0to0
duplicates drop CO YEAR SEX, force

sort CO YEAR SEX
tempfile newdata
save `newdata', replace
restore

sort CO YEAR SEX
merge CO YEAR SEX using `newdata', keep(DATUM*)
tab _merge

replace c1_0to0 = DATUM0to0 if _merge == 3
replace c1_1to4 = DATUM1to4 if _merge == 3
replace c1_0to4 = c1_0to0 + c1_0to4 if _merge == 3
forvalues j = 5(5)95 {
	local jplus = `j'+4
	replace c1_`j'to`jplus' = DATUM`j'to`jplus' if _merge == 3
}
replace c1_100plus = DATUM100plus if _merge == 3

drop DATUM* _merge

********************
** China MoH Data **
********************

noisily: display in green "China MoH data"

preserve
use "$chnmohDir/$chnmohFile", clear
append using "$chnmohrecentDir/$chnmohrecentFile"
*use "J:\Project\Mortality\Death distribution methods\Data\GBD\CENSUS\WHO CHINA SAMPLE\USABLE_CENSUS_WHO_CHN_1950-2007.dta", clear
*append using "J:\Project\Mortality\Death distribution methods\Data\GBD\CENSUS\WHO CHINA SAMPLE\USABLE_CENSUS_WHO_CHN_2003-2007.dta"
replace CO = "CHNWHO"
sort CO YEAR SEX
tempfile newdata
save `newdata', replace
restore

sort CO YEAR SEX
merge CO YEAR SEX using `newdata', keep(DATUM*)

replace c1_0to0 = DATUM0to0 if _merge == 3
replace c1_1to4 = DATUM1to4 if _merge == 3
replace c1_0to4 = c1_0to0 + c1_0to4 if _merge == 3
forvalues j = 5(5)80 {
	local jplus = `j'+4
	replace c1_`j'to`jplus' = DATUM`j'to`jplus' if _merge == 3
}
replace c1_85plus = DATUM85plus if _merge == 3

drop DATUM* _merge 

replace c1_0to4 = c1_0to0 + c1_1to4 if c1_0to4 == .

**************************
** China 1% Survey Data **
**************************

noisily: display in green "China 1% survey data"

preserve
use "$chn1survey95Dir/$chn1survey95File", clear
append using "$chn1survey05Dir/$chn1survey05File"
*use "J:\project\mortality\Death distribution methods\Data\GBD\CENSUS\CHINA 1 percent\USABLE_INT_GOV_CHN_1995_vPop.dta", clear
*append using "J:\project\mortality\Death distribution methods\Data\GBD\CENSUS\CHINA 1 percent\USABLE_INT_GOV_CHN_2005_vPop.dta"
replace CO = "CHNDC"
sort CO YEAR SEX
tempfile newdata
save `newdata', replace
restore

sort CO YEAR SEX
merge CO YEAR SEX using `newdata', keep(DATUM*)
tab _merge

replace c1_0to0 = DATUM0to0 if _merge == 3
replace c1_1to4 = DATUM1to4 if _merge == 3
replace c1_0to4 = c1_0to0 + c1_0to4 if _merge == 3
forvalues j = 5(5)95 {
	local jplus = `j'+4
	replace c1_`j'to`jplus' = DATUM`j'to`jplus' if _merge == 3
}
replace c1_100plus = DATUM100plus if _merge == 3

drop DATUM* _merge 

*********************
** Taiwan HMD data **
*********************

noisily: display in green "Taiwan HMD data"

sort CO YEAR SEX
*merge CO YEAR SEX using "J:\Project\Mortality\Death distribution methods\Data\GBD\CENSUS\HMD\USABLE_CENSUS_HMD_TWN_1970-2008_vallyears.dta", keep(DATUM*)
merge CO YEAR SEX using "$twnhmdDir/$twnhmdFile", keep(DATUM*)
tab _merge

replace c1_0to0 = DATUM0to0 if _merge == 3 | _merge == 2
replace c1_1to4 = DATUM1to4 if _merge == 3 | _merge == 2
replace c1_0to4 = c1_0to0 + c1_0to4 if _merge == 3 | _merge == 2
forvalues j = 5(5)95 {
	local jplus = `j'+4
	replace c1_`j'to`jplus' = DATUM`j'to`jplus' if _merge == 3 | _merge == 2
}
replace c1_100plus = DATUM100to104 + DATUM105to109 + DATUM110plus if _merge == 3 | _merge == 2

drop DATUM* _merge 


replace c1_0to4 = c1_0to0 + c1_1to4 if c1_0to4 == .



** Should only be 7 points dropped
duplicates drop CO YEAR SEX, force

rename COUNTRY iso3
rename YEAR year
g sex = "both" if SEX == 0
replace sex = "male" if SEX == 1
replace sex = "female" if SEX == 2
drop SEX

*save "$saveasDir/$saveasFile", replace

if("`iso3'" ~= "all" & "`iso3'" ~= "") {
	keep if strpos(iso3,"`iso3'") ~= 0
}

save "`saveas'", replace



end
