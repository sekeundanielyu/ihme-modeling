// Date: June 2016
// Purpose: Create scatter plots of prevalence calculated in 2010 vs prevalence calculated in June 2016

 *********** 
 ** DHS** 
 ***********

use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\output\MASTER PREVALENCE FILES\master_modern_contra_unmet_need_prevalence.dta", clear
duplicates drop

sort iso3
replace survey = "MICS" if survey == "UNICEF_MICS" 
replace survey = "DHS" if survey == "MACRO_DHS"
rename modall_prev modall_prev_2016
rename modcurrmarr_prev modcurrmarr_prev_2016
rename modevermarr_prev modevermarr_prev_2016
rename modnomarr_prev modnomarr_prev_2016
rename modcurrmarr_var modcurrmarr_var_2016
rename modevermarr_var modevermarr_var_2016
rename modnomarr_var modnomarr_var_2016

** collapse modall_prev_2016 modcurrmarr_prev_2016 modevermarr_prev_2016 modcurrmarr_var_2016 modevermarr_var_2016 modnomarr_var_2016 modnomarr_prev_2016 unmet_needall_prev unmet_needall_var, by(iso3 agegroup)

tempfile 2016
save `2016', replace

use "J:\Project\Coverage\Contraceptives\Prevalence estimates\datasets\Age, Time, Space Smoothing\prevalence\DHS-xs prev.dta", clear
duplicates drop

replace survey = "DHS" if regexm(survey, "DHS")
keep if survey == "MICS" | survey == "DHS"
rename modall_prev modall_prev_2010
rename modcurrmarr_prev modcurrmarr_prev_2010
rename modevermarr_prev modevermarr_prev_2010
rename modnomarr_prev modnomarr_prev_2010
rename modcurrmarr_var modcurrmarr_var_2010
rename modevermarr_var modevermarr_var_2010
rename modnomarr_var modnomarr_var_2010

** collapse modall_prev_2010 modcurrmarr_prev_2010 modevermarr_prev_2010 modcurrmarr_var_2010 modevermarr_var_2010 modnomarr_var_2010 modnomarr_prev_2010, by(iso3 agegroup)

tempfile 2010
save `2010', replace

merge 1:m  filename agegroup using `2016', keep(3)

order iso3 survey year agegroup modall_prev_2010 modall_prev_2016 modcurrmarr_prev_2010 modcurrmarr_prev_2016 modcurrmarr_var_2010 modcurrmarr_var_2016 modevermarr_prev_2010 modevermarr_prev_2016 modevermarr_var_2010 modevermarr_var_2016 modnomarr_prev_2010 modnomarr_prev_2016 modnomarr_var_2010 modnomarr_var_2016


// graph it out
do "J:\Usable\Tools\ADO\pdfmaker_Acrobat11.do"  
pdfstart using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\data_quality_scatterplots\modern_prevalence_scatterplots_dhs.pdf"
levelsof iso3, local(countries)
foreach country of local countries {
	twoway (scatter modall_prev_2010 modall_prev_2016 if iso3 == "`country'", ytitle(2010) xtitle(2016) title("Modern Contraceptive Use Prevalence in `country' -- DHS")) || function y = x
	pdfappend
	}

pdffinish


 *********** 
 ** MICS** 
 ***********
 
 
 
 use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\output\MASTER PREVALENCE FILES\master_modern_contra_unmet_need_prevalence.dta", clear
duplicates drop

sort iso3
replace survey = "MICS" if survey == "UNICEF_MICS" 
keep if survey == "MICS"
rename modall_prev modall_prev_2016
rename modcurrmarr_prev modcurrmarr_prev_2016
rename modevermarr_prev modevermarr_prev_2016
rename modnomarr_prev modnomarr_prev_2016
rename modcurrmarr_var modcurrmarr_var_2016
rename modevermarr_var modevermarr_var_2016
rename modnomarr_var modnomarr_var_2016

tempfile 2016
save `2016', replace


use "J:\Project\Coverage\Contraceptives\Prevalence estimates\datasets\Age, Time, Space Smoothing\prevalence\MICS2 prev.dta", clear
duplicates drop

destring year, replace
replace survey = "MICS" if survey == "MICS 2"
replace filename = "AGO_MICS2_2001_WN_Y2008M09D23.DTA" if filename == "crude_int_mics2_ago_2001_wm"
replace filename = "ALB_MICS2_2000_WN_Y2008M09D23.DTA" if filename == "crude_int_mics2_alb_2000_wm"
replace filename = "AZE_MICS2_2000_WN_Y2008M09D23.DTA" if filename == "crude_int_mics2_aze_2000_wm"
rename modcurrmarr_prev modcurrmarr_prev_2010
rename modcurrmarr_var modcurrmarr_var_2010

tempfile 2010
save `2010', replace

merge 1:m  filename agegroup using `2016', keep(3)


// graph it out
do "J:\Usable\Tools\ADO\pdfmaker_Acrobat11.do"  
pdfstart using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\data_quality_scatterplots\modern_prevalence_scatterplots_mics.pdf"
levelsof iso3, local(countries)
foreach country of local countries {
	twoway (scatter modcurrmarr_prev_2010 modcurrmarr_prev_2016 if iso3 == "`country'", ytitle(2010) xtitle(2016) title("Modern Contraceptive Use Prevalence amongst Married Women in `country' -- MICS")) || function y = x
	pdfappend
	}

pdffinish


 *********** 
 ** ALL SURVEYS** 
 ***********
 

use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\output\MASTER PREVALENCE FILES\master_modern_contra_unmet_need_prevalence_with_year.dta", clear
duplicates drop
replace survey = "DHS" if survey == "MACRO_DHS"
replace survey = "MICS" if survey == "UNICEF_MICS"
replace survey = "PMA2020" if survey == "GBD"
collapse unmet_needall_prev unmet_needcurr_prev modall_prev modcurrmarr_prev, by(iso3 survey ihme_start_year)
gen outlier = 1 if iso3 == "MNG" & survey == "MICS" & ihme_start_year == 2000
gen survey_name = iso3 + " " + survey 

// scatter modern prevalence between all and married women
do "J:\Usable\Tools\ADO\pdfmaker_Acrobat11.do"  
pdfstart using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\data_quality_scatterplots\modall_prev_modcurrmarr_prev_scatter.pdf"

twoway (scatter modall_prev modcurrmarr_prev), ylabel(0(.1)1) || (scatter modall_prev modcurrmarr_prev if outlier== 1, mlabel(survey_name))

pdfappend


pdffinish


// scatter unmet need between all and married women
do "J:\Usable\Tools\ADO\pdfmaker_Acrobat11.do"  
pdfstart using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\data_quality_scatterplots\unmet_needall_currmarr_scatter.pdf"

twoway (scatter unmet_needall_prev unmet_needcurr_prev), ylabel(0(.1).6) xlabel(0(.1).6)

pdfappend


pdffinish






***************** 
** TIME SERIES PLOTS ** 
***************** 


use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\output\MASTER PREVALENCE FILES\master_modern_contra_unmet_need_prevalence_with_year.dta", clear
duplicates drop
replace survey = "PMA2020" if survey == "GBD"
replace survey = "DHS" if survey == "MACRO_DHS"
replace survey = "MICS" if survey == "UNICEF_MICS"

collapse unmet_needall_prev unmet_needcurr_prev modall_prev modcurrmarr_prev, by(iso3 survey ihme_start_year)

// unmet need for all women by country over time
do "J:\Usable\Tools\ADO\pdfmaker_Acrobat11.do"  
pdfstart using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\data_quality_scatterplots\unmet_need_all_country_plots.pdf"
levelsof iso3, local(countries)
foreach country of local countries {
	twoway (scatter unmet_needall_prev ihme_start_year, msymbol(lgx) mlabposition(10) mlabel(survey)) if iso3 == "`country'", ylabel(0(.1)1) title(Unmet Need for All Women in "`country'")

	pdfappend
	}

pdffinish

// unmet need for currently married women by country over time

do "J:\Usable\Tools\ADO\pdfmaker_Acrobat11.do"  
pdfstart using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\data_quality_scatterplots\unmet_need_curr_country_plots.pdf"
levelsof iso3, local(countries)
foreach country of local countries {
	twoway (scatter unmet_needcurr_prev ihme_start_year, msymbol(lgx) mlabposition(10) mlabel(survey)) if iso3 == "`country'",ylabel(0(.1)1) title(Unmet Need for Currently Married Women in "`country'")

	pdfappend
	}

pdffinish


// modern contraceptive use prevalence for all women
do "J:\Usable\Tools\ADO\pdfmaker_Acrobat11.do"  
pdfstart using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\data_quality_scatterplots\mod_all_country_plots.pdf"
levelsof iso3, local(countries)
foreach country of local countries {
	twoway (scatter modall_prev ihme_start_year, msymbol(lgx) mlabposition(10) mlabel(survey)) if iso3 == "`country'", ylabel(0(.1)1) title(Mod. Contraception for All Women in "`country'")

	pdfappend
	}

pdffinish

// modern contraceptive use prevalence for currently married women
do "J:\Usable\Tools\ADO\pdfmaker_Acrobat11.do"  
pdfstart using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\data_quality_scatterplots\mod_currmarr_country_plots.pdf"
levelsof iso3, local(countries)
foreach country of local countries {
	twoway (scatter modcurrmarr_prev ihme_start_year, msymbol(lgx) mlabposition(10) mlabel(survey)) if iso3 == "`country'", ylabel(0(.1)1) title(Mod. Contraception for Currently Married Women in "`country'")

	pdfappend
	}

pdffinish



// country plots comparing 2010 and 2016 data
// currmarr
use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\data_quality_scatterplots\2010_2016_prev_dta\merged_2010_2016_prev_report_data_vcal_jul11.dta", clear
if report_data == 1 {
gen moddcurrmarr_2010_report = modcurrmarr_2010 
replace moddcurrmarr_2010_report = . if report_data == 0
replace modcurrmarr_2010 = . if report_data == 1
}
gen modcurrmarr_2010_vcal = modcurrmarr_2010
replace modcurrmarr_2010_vcal = . if survey != "DHS-vcal"
replace modcurrmarr_2010 = . if survey == "DHS-vcal"

lab var moddcurrmarr_2010_report "GBD 2010 report data"
lab var modcurrmarr_2010_vcal "GBD 2010 vcal data"
lab var modcurrmarr_2010 "GBD 2010 extracted data"
lab var modcurrmarr_2016 "2016 re-extracted data"
do "J:\Usable\Tools\ADO\pdfmaker_Acrobat11.do"  
pdfstart using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\data_quality_scatterplots\modcurrmarr_2010_v_2016_country_plots_jul_11.pdf"
levelsof iso3, local(countries)
foreach country of local countries {
	preserve
	keep if iso3 == "`country'"
	twoway (scatter modcurrmarr_2010 year, msymbol(lgx) mlabposition(10) mlabel(survey)), ylabel(0(.1)1) title(Mod. Contraception for Currently Married Women in "`country'")  || (scatter modcurrmarr_2016 year, msymbol(circle_hollow) mlabposition(12) mlabel(survey)) || (scatter moddcurrmarr_2010_report year, msymbol(smx) mlabel(survey) mlabsize(vsmall)) || (scatter modcurrmarr_2010_vcal year, msymbol(triangle) mlabel(survey) mlabsize(vsmall))
	restore
	pdfappend
	}

pdffinish

// all
use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\data_quality_scatterplots\2010_2016_prev_dta\merged_2010_2016_prev_report_data_vcal_jul11.dta", clear
if report_data == 1 {
gen modall_2010_report = modall_2010 
replace modall_2010_report = . if report_data == 0
replace modall_2010 = . if report_data == 1
}
gen modall_2010_vcal = modall_2010
replace modall_2010_vcal = . if survey != "DHS-vcal"
replace modall_2010 = . if survey == "DHS-vcal"

lab var modall_2010_report "GBD 2010 report data"
lab var modall_2010_vcal "GBD 2010 vcal data"
lab var modall_2010 "GBD 2010 extracted data"
lab var modall_2016 "2016 re-extracted data"
do "J:\Usable\Tools\ADO\pdfmaker_Acrobat11.do"  
pdfstart using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\data_quality_scatterplots\modall_2010_v_2016_country_plots_vcal_jul_11.pdf"
levelsof iso3, local(countries)
foreach country of local countries {
	preserve
	keep if iso3 == "`country'"
	twoway (scatter modall_2010 year, msymbol(lgx) mlabposition(10) mlabel(survey)), ylabel(0(.1)1) title(Mod. Contraception for All Women in "`country'")  || (scatter modall_2016 year, msymbol(circle_hollow) mlabposition(12) mlabel(survey)) || (scatter modall_2010_report year, msymbol(smx) mlabel(survey) mlabsize(vsmall)) || (scatter modall_2010_vcal year, msymbol(triangle) mlabel(survey) mlabsize(vsmall))
	restore
	pdfappend
	}

pdffinish

// unmet_need
use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\output\MASTER PREVALENCE FILES\master_modern_contra_unmet_need_prevalence_12jul2016.dta", clear

replace survey = "PMA2020" if survey == "GBD"
collapse unmet_needall_prev unmet_needcurr_prev, by(iso3 ihme_start_year survey)
do "J:\Usable\Tools\ADO\pdfmaker_Acrobat11.do"  
pdfstart using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\data_quality_scatterplots\unmet_needdall.pdf"
levelsof iso3, local(countries)
foreach country of local countries {
	preserve
	keep if iso3 == "`country'"
	twoway (scatter unmet_needall_prev ihme_start_year, msymbol(lgx) mlabposition(10) mlabel(survey)), ylabel(0(.1)1) title(Unmet Need for Contraception for All Women in "`country'")
	restore
	pdfappend
	}

pdffinish

