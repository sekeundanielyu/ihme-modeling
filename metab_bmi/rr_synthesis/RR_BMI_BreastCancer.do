// *********************************************************************************************************************************************************************
// Project:		RISK
// Purpose:		Update RR's for BMI and Breast Cancer based on Region and Menopausal status

** **************************************************************************
** RUNTIME CONFIGURATION
** **************************************************************************
// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		macro drop _all
		set maxvar 32000
	// Set to run all selected code without pausing
		set more off
	// Set to enable export of large excel files
		set excelxlsxlargefile on
	// Set graph output color scheme
		set scheme s1color
	// Remove previous restores
		cap restore, not
		

** Set directories
	if c(os) == "Windows" {
		global j "J:"
		set mem 1g
	}
	if c(os) == "Unix" {
		global j "/home/j"
		set mem 2g
		set odbcmgr unixodbc
	}

** **************************************************************************
** Meta-analysis of pre-menopausal risk
** **************************************************************************
use "J:/WORK/05_risk/02_models/metab_bmi/01_rr/data/raw/RRupdate_premeno2.dta", clear

// generate logRR and standard error of logRR 

	gen logRR = log(rr_premeno)
	gen log_seRR =(log(upperci) - log(lowerci))/(1.96*2)

// Meta-analysis of pre-menopausal risk 

	metan logRR log_seRR, eform random label(namevar=study_name, yearvar=year) rcols(region) boxsca(60) b2title(RR for 5 kg/m2 increase in BMI) title("BMI and Breast Cancer in Pre-Menopausal Women", size(small)) 
	
		graph export "J:/WORK/05_risk/temp/lalexan1/bmi_temp/graphs/pre_meno/Forestplot_premeno.png", height(800) width(1200) replace 
	
		// Fixed Effects

		metan logRR log_seRR, eform label(namevar=study_name, yearvar=year) rcols(region) boxsca(60) b2title(RR for 5 kg/m2 increase in BMI) title("BMI and Breast Cancer in Pre-Menopausal Women", size(small)) 
	

// Disagreggated by region (Asian-Pacific vs. other)

	metan logRR log_seRR, eform random label(namevar=study_name, yearvar=year) rcols(region) boxsca(40) b2title(RR for 5 kg/m2 increase in BMI) by(regioncombined) title("BMI and Breast Cancer in Pre-Menopausal Women by Region", size(small)) 
	
		graph export "J:/WORK/05_risk/02_models/metab_bmi/01_rr/graphs/Forestplot_premeno_byregion.png", height(800) width(1200) replace 
	
	metan logRR log_seRR if regioncombined == "Asia-Pacific", random nograph
	
		return list
		local RR_Asia_Premeno = r(ES)
		local RR_upper_Asia_Premeno = r(ci_upp)
		local RR_lower_Asia_Premeno = r(ci_low)
	
	 metan logRR log_seRR if regioncombined != "Asia-Pacific", random nograph
	 
		return list 
		local RR_NonAsia_Premeno = r(ES) 
		local RR_upper_NonAsia_Premeno = r(ci_upp)
		local RR_lower_NonAsia_Premeno = r(ci_low)
	
		// Fixed Effects
		
		metan logRR log_seRR, eform label(namevar=study_name, yearvar=year) rcols(region) boxsca(40) b2title(RR for 5 kg/m2 increase in BMI) by(regioncombined) title("BMI and Breast Cancer in Pre-Menopausal Women by Region", size(small)) 
		
	 
// Funnel plot 

	metafunnel logRR log_seRR, eform xtitle(Log Relative Risk) ytitle(Standard error of log RR) subtitle(Funnel Plot of BMI-Breast Cancer Studies) 
		
		graph export "J:/WORK/05_risk/02_models/metab_bmi/01_rr/graphs/Funnelplot_premeno.png", height(800) width(1200) replace 
	
	metafunnel logRR log_seRR if regioncombined == "Asia-Pacific", eform xtitle(Log Relative Risk) ytitle(Standard error of log RR) subtitle(Funnel Plot of BMI-Breast Cancer Studies, Asia-pacific) 
	
		graph export "J:/WORK/05_risk/02_models/metab_bmi/01_rr/graphs/Funnelplot_premeno_Asia.png", height(800) width(1200) replace 
		
	metafunnel logRR log_seRR if regioncombined != "Asia-Pacific", eform xtitle(Log Relative Risk) ytitle(Standard error of log RR) subtitle(Funnel Plot of BMI-Breast Cancer Studies, Non Asia-pacific countries) 

		graph export "J:/WORK/05_risk/02_models/metab_bmi/01_rr/graphs/Funnelplot_premeno_NonAsia.png", height(800) width(1200) replace 

//  Analysis of publication bias 

	metatrim logRR log_seRR, graph funnel eform reffect idvar(study_name) print
	
		graph export "J:/WORK/05_risk/02_models/metab_bmi/01_rr/graphs/Trimmedplot_premeno.png", height(800) width(1200) replace 
	

** **************************************************************************
** Meta-analysis of post-menopausal risk
** **************************************************************************
use "J:/WORK/05_risk/02_models/metab_bmi/01_rr/data/raw/RRupdate_postmeno.dta", clear

// generate logRR and standard error of logRR (using Delta method for log of standard error)
	
	gen logRR = log(rr_postmeno)
	gen log_seRR =(log(upperci) - log(lowerci))/(1.96*2)
	
// Meta-analysis of post-menopausal risk

	metan logRR log_seRR, eform random label(namevar=study_name, yearvar=year) rcols(studylocation) boxsca(60) b2title(RR for 5 kg/m2 increase in BMI) title(BMI and Breast Cancer in Post-Menopausal Women, size(small)) 

		graph export "J:/WORK/05_risk/02_models/metab_bmi/01_rr/graphs/Forestplot_postmeno.png", height(800) width(1200) replace 
		
		
		// Fixed Effects
		
		metan logRR log_seRR, eform label(namevar=study_name, yearvar=year) rcols(studylocation) boxsca(60) b2title(RR for 5 kg/m2 increase in BMI) title(BMI and Breast Cancer in Post-Menopausal Women, size(small)) 

// Disaggregated by region (Asian-Pacific vs. other)

	metan logRR log_seRR, eform random label(namevar=study_name, yearvar=year) rcols(studylocation) boxsca(40) b2title(RR for 5 kg/m2 increase in BMI) by(regioncombined) title(BMI and Breast Cancer in Post-Menopausal Women by Region, size(small)) 
	
		graph export "J:/WORK/05_risk/02_models/metab_bmi/01_rr/graphs/Forestplot_postmeno_byregion.png", height(800) width(1200) replace 
		
	metan logRR log_seRR if regioncombined == "Asia-Pacific", random nograph
		
		return list
		local RR_Asia_Postmeno = r(ES)
		local RR_upper_Asia_Postmeno = r(ci_upp)
		local RR_lower_Asia_Postmeno = r(ci_low)
	
	 metan logRR log_seRR if regioncombined != "Asia-Pacific", random nograph
	 
		return list 
		local RR_NonAsia_Postmeno = r(ES) 
		local RR_upper_NonAsia_Postmeno = r(ci_upp)
		local RR_lower_NonAsia_Postmeno = r(ci_low)
		
		// Fixed Effects
		
		metan logRR log_seRR, eform label(namevar=study_name, yearvar=year) rcols(studylocation) boxsca(40) b2title(RR for 5 kg/m2 increase in BMI) by(regioncombined) title(BMI and Breast Cancer in Post-Menopausal Women by Region, size(small)) 

// Funnel plot 

	metafunnel logRR log_seRR, eform xtitle(Log Relative Risk) ytitle(Standard error of log RR) subtitle(Funnel Plot of BMI-Breast Cancer Studies) 
		
		graph export "J:/WORK/05_risk/02_models/metab_bmi/01_rr/graphs/Funnelplot_postmeno.png", height(800) width(1200) replace 
	
	metafunnel logRR log_seRR if regioncombined == "Asia-Pacific", eform xtitle(Log Relative Risk) ytitle(Standard error of log RR) subtitle(Funnel Plot of BMI-Breast Cancer Studies, Asia-Pacific) 

		graph export "J:/WORK/05_risk/02_models/metab_bmi/01_rr/graphs/Funnelplot_postmeno_Asia.png", height(800) width(1200) replace 
		
	metafunnel logRR log_seRR if regioncombined != "Asia-Pacific", eform xtitle(Log Relative Risk) ytitle(Standard error of log RR) subtitle(Funnel Plot of BMI-Breast Cancer Studies, Non Asia-Pacific countries) 

		graph export "J:/WORK/05_risk/02_models/metab_bmi/01_rr/graphs/Funnelplot_postmeno_NonAsia.png", height(800) width(1200) replace 
	
//  Analysis of publication bias

	metatrim logRR log_seRR, graph funnel eform reffect

		graph export "J:/WORK/05_risk/02_models/metab_bmi/01_rr/graphs/Trimmedplot_postmeno.png", height(800) width(1200) replace 
		
	


** **************************************************************************
**  Assign Region and Age-Specific RRs to Countries
** **************************************************************************

use J:/DATA/IHME_COUNTRY_CODES/IHME_COUNTRY_CODES_Y2013M07D26.DTA, clear
drop if indic_epi != 1 | (gbd_country_iso3 == "ZAF" & iso3 != "ZAF")
keep if type == "admin0"

gen asia = 1 if regexm(gbd_analytical_superregion_name, "Southeast") == 1
replace asia = 1 if regexm(gbd_analytical_region_name, "Asia Pacific")
replace asia = 0 if asia == .
keep asia iso3 gbd_analytical_superregion_name gbd_analytical_region_name

gen menopause = "pre"
expand 2, gen(dup)
replace menopause = "post" if dup == 1

gen gbd_age_start = 25 if menopause == "pre" 
replace gbd_age_start = 50 if menopause == "post"
gen gbd_age_end = 50 if menopause == "pre"
replace gbd_age_end = 80 if menopause == "post"

gen risk = "metab_bmi" 
gen acause = "neo_breast"
gen sex = 2 
gen mortality = 1 
gen morbidity = 1 
gen parameter = "per unit" 
gen year = 0 
gen logmean_rr = . 
gen logupper_rr = . 
gen loglower_rr = .
drop dup 

levelsof iso3 if asia == 0, local(countriesNonAsia)

foreach country of local countriesNonAsia {

	replace logmean_rr = `RR_NonAsia_Postmeno' if asia == 0 & menopause == "post"
	replace logupper_rr = `RR_upper_NonAsia_Postmeno' if asia == 0 & menopause == "post"
	replace loglower_rr = `RR_lower_NonAsia_Postmeno' if asia == 0 & menopause == "post"
	
	replace logmean_rr = `RR_NonAsia_Premeno' if asia == 0 & menopause == "pre"
	replace logupper_rr = `RR_upper_NonAsia_Premeno' if asia == 0 & menopause == "pre"
	replace loglower_rr = `RR_lower_NonAsia_Premeno' if asia == 0 & menopause == "pre"
	
	}

	replace logmean_rr = `RR_Asia_Premeno' if asia == 1 & menopause == "pre"
	replace loglower_rr = `RR_lower_Asia_Premeno' if asia == 1 & menopause == "pre"
	replace logupper_rr = `RR_upper_Asia_Premeno' if asia == 1 & menopause == "pre"
	replace logmean_rr = `RR_Asia_Postmeno' if asia == 1 & menopause == "post" 
	replace logupper_rr = `RR_upper_Asia_Postmeno' if asia == 1 & menopause == "post"
	replace loglower_rr = `RR_lower_Asia_Premeno' if asia == 1 & menopause == "post"
	

drop menopause asia gbd_analytical_region_name gbd_analytical_superregion_name
gen rr_mean = exp(logmean_rr)
	gen rr_upper = exp(logupper_rr)
	gen rr_lower = exp(loglower_rr)
	order iso3 risk acause gbd_age_start gbd_age_end sex mortality morbidity parameter year rr_mean rr_lower rr_upper 
	
	tempfile all
	save `all', replace

** Generate draws (Always generate draws in ln space for RRs)
	gen sd = ((logupper_rr) - (loglower_rr)) / (2*invnormal(.975))
	forvalues draw = 0/999 {
		gen rr_`draw' = exp(rnormal(logmean_rr), sd)
	}
	drop sd logmean_rr logupper_rr loglower_rr
	

outsheet using "J:/WORK/05_risk/02_models/metab_bmi/01_rr/data/prepped/all_countries.csv", comma names replace



