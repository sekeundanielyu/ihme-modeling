// *********************************************************************************************************************************************************************	
// Project:		RISK
// Purpose:		Update RR's for BMI and other cancers

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
		global j "$j"
		set mem 1g
	}
	if c(os) == "Unix" {
		global j "/home/j"
		set mem 2g
		set odbcmgr unixodbc
	}

	local data_dir "$j/WORK/05_risk/02_models/metab_bmi/01_rr/data/raw"
	local graph_dir "$j/WORK/05_risk/02_models/metab_bmi/01_rr/graphs"
	local version 6 // increase by 1 everytime something changes 
	local cd "$prefix/WORK/05_risk/02_models/02_results/metab_bmi/rr"
	local out_dir "$prefix/WORK/05_risk/02_models/02_results/metab_bmi/rr/`version'"
	cap mkdir "`out_dir'"
	local clustertmpdir "/snfs3/WORK/05_risk/02_models/02_results/metab_bmi/rr/`version'"
	cap mkdir "`clustertmpdir'"

** **************************************************************************
** Meta-Analysis of Cancers and BMI
** **************************************************************************

insheet using "`data_dir'/RR_BMI_cancers2.csv", clear 

// generate logRR and standard error of logRR 

	gen logRR = log(rr_mean)
	gen log_seRR =(log(rr_upper) - log(rr_lower))/(1.96*2)

	tempfile all
	save `all', replace
	
// Loop through cancers (men & women)

	levelsof cancer_type if sex == 1, local(cancers_M)
	
	foreach cancer of local cancers_M {
		use `all', clear
		keep if cancer_type == "`cancer'"
		di "`cancer'"
		
		metan logRR log_seRR if sex == 1, eform random label(namevar=study_name, yearvar=year) boxsca(60) b2title(RR for 5 kg/m2 increase in BMI) title(BMI and `cancer' Cancer in Men, size(small)) 
			
			return list 
			local RR_`cancer'_men = r(ES)
			local RRupper_`cancer'_men = r(ci_upp)
			local RRlower_`cancer'_men = r(ci_low)
			
			graph export "`graph_dir'/Forestplot_`cancer'_men.png", height(800) width(1200) replace 
				
	}
	
	clear all
	insheet using "`data_dir'/RR_BMI_cancers2.csv", clear 
	
	levelsof cancer_type if sex == 2, local(cancers_W)	
	
		foreach cancer of local cancers_W {
		use `all', clear
		keep if cancer_type == "`cancer'"
		di "`cancer'"
		
		metan logRR log_seRR if sex == 2, eform random label(namevar=study_name, yearvar=year) boxsca(60) b2title(RR for 5 kg/m2 increase in BMI) title(BMI and `cancer' Cancer in Women, size(small)) 
	
			return list 
			local RR_`cancer'_women = r(ES)
			local RRupper_`cancer'_women = r(ci_upp)
			local RRlower_`cancer'_women = r(ci_low)
			
			graph export "`graph_dir'/Forestplot_`cancer'_women.png", height(800) width(1200) replace 
	
		}

// Populate table with values 

insheet using "`data_dir'/cancerfile.csv", clear 

foreach cancer of local cancers_W {	
	replace logrr_mean = `RR_`cancer'_women' if sex == 2 & acause == "neo_`cancer'"
	replace logrr_lower = `RRlower_`cancer'_women' if sex == 2 & acause == "neo_`cancer'"
	replace logrr_upper = `RRupper_`cancer'_women' if sex == 2 & acause == "neo_`cancer'" 
	
	}

foreach cancer of local cancers_M {
	replace logrr_mean = `RR_`cancer'_men' if sex == 1 & acause == "neo_`cancer'"
	replace logrr_lower = `RRlower_`cancer'_men' if sex == 1 & acause == "neo_`cancer'"
	replace logrr_upper = `RRupper_`cancer'_men' if sex == 1 & acause == "neo_`cancer'" 
	
	}

	
// Weighted average for colorectal cancer

replace logrr_mean = (`RR_colon_men')*(0.65) + (`RR_rectum_men')*(0.35) if acause == "neo_colon" & sex == 1
replace logrr_lower = (`RRlower_colon_men')*(0.65) + (`RRlower_rectum_men')*(0.35) if acause == "neo_colon" & sex == 1
replace logrr_upper = (`RRupper_colon_men')*(0.65) + (`RRupper_rectum_men')*(0.35) if acause == "neo_colon" & sex == 1

replace logrr_mean = (`RR_colon_women')*(0.65) + (`RR_rectum_women')*(0.35) if acause == "neo_colon" & sex == 2
replace logrr_lower = (`RRlower_colon_women')*(0.65) + (`RRlower_rectum_women')*(0.35) if acause == "neo_colon" & sex == 2
replace logrr_upper = (`RRupper_colon_women')*(0.65) + (`RRupper_rectum_women')*(0.35) if acause == "neo_colon" & sex == 2

replace acause = "neo_colorectal" if acause == "neo_colon"
replace acause = "neo_uterine" if acause == "neo_uterus"
drop if acause == "neo_rectum"

	gen rr_mean = exp(logrr_mean)
	gen rr_upper = exp(logrr_upper)
	gen rr_lower = exp(logrr_lower)
	
gen gbd_age_start = 25 
gen gbd_age_end = 80 

drop if acause == "neo_cervix"

** Generate draws (Always generate draws in ln space for RRs)
	gen sd = ((logrr_upper) - (logrr_lower)) / (2*invnormal(.975))
	forvalues draw = 0/999 {
		gen draw_`draw' = exp(rnormal(logrr_mean), sd)
	}
	drop logrr_mean logrr_lower logrr_upper 
	


tempfile updatedRR
save `updatedRR', replace

export excel using "`data_dir'/updatedRRs.csv", firstrow(var) replace


// Bring in the most recent version of RRs so we can append other RRs for BMI to updated RRs for cancers

clear 
local old = `version' - 1
insheet using "`cd'/`old'/rr_G.csv", clear
drop if regexm(acause, "^neo")
tempfile bigfile 
// drop mean upper lower updated draw_*
save `bigfile', replace 

append using `updatedRR'


outsheet using "`clustertmpdir'/rr_G.csv", comma names replace
drop draw_*
outsheet using "`out_dir'/rr_G.csv", comma names replace






	
	
	
	
