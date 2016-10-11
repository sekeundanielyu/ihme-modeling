clear all
set more off
set graphics off
set maxvar 32000


/*  //////////////////////////////////////////////
		WORKING DIRECTORY
////////////////////////////////////////////// */ 

		//root dir
	if c(os) == "Windows" {
		local j "J:"
		// Load the PDF appending application
		quietly do "`j'/Usable/Tools/ADO/pdfmaker_acrobat11.do"
	}
	if c(os) == "Unix" {
		local j "/home/j"
		ssc install estout, replace 
		ssc install metan, replace
	} 
	
	adopath + "`j'/Usable/Tools/ADO"
	adopath + "`j'/WORK/01_covariates/common/lib"
	di in red "J drive is `j'"

local working_dir = "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/regression_results/hemo/01_rh_disease"

local rhogam_dir = "`working_dir'/birth_prev/B_rhogam_adjustment/rhogam_temp.csv"
local rh_count_dir = "`working_dir'/birth_prev/D_final_birthprev/rh_disease_count_summary_stats.dta"
local rh_prev_dir = "`working_dir'/birth_prev/A_rh_prev/rh_minus_summary_stats.dta"

local birth_dir = "`working_dir'/birth_prev/A_rh_prev/correct_births.dta"

insheet using "`rhogam_dir'", comma clear 
destring rhesusnegative, percent replace

identify_locations, locname_var(location_name)
merge 1:m iso3 using "`rh_count_dir'" , keep(3) nogen

keep if year==2010 & sex=="Both"

merge 1:1 iso3 year using "`rh_prev_dir'", keep(3) nogen

merge 1:1 iso3 year sex using "`birth_dir'", keep(3) nogen

keep if year==2010 & sex=="Both"
sort iso3
//br iso3 rhdisease rh_disease_count* if rhdisease < rh_disease_count_lower | rhdisease > rh_disease_count_upper


//br iso3 rhesusnegative rh_prev* if rhesusnegative < rh_prev_lower | rhesusnegative > rh_prev_upper

gen births_diff = totalbirths - births 
gen rh_disease_diff = rhdisease - rh_disease_count
 
br iso3 totalbirths births births_diff rhdisease rh_disease_count rh_disease_diff


