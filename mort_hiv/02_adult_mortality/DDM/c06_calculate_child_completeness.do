********************************************************
** Description:
**
********************************************************

** **********************
** Set up Stata 
** **********************

	clear all
	capture cleartmp 
	set mem 500m
	set more off

** **********************
** Filepaths 
** **********************

	if (c(os)=="Unix") global root "/home/j"	
	if (c(os)=="Windows") global root "J:"
	global u5_raw_file = "strPath/raw.5q0.unadjusted.txt"
	global u5_est_file = "strPath/estimated_5q0_noshocks.txt"
	global save_file = "strPath/d06_child_completeness.dta"


** **********************
** Calculate child comp 
** **********************	
// Grab locations for merging on later
	adopath + "$root/Project/Mortality/shared/functions"
	get_locations, level(estimate)
	keep if level_all == 1 // Drop England and India states
	keep ihme_loc_id
	tempfile codes
	save `codes'

** Format estimates 
	insheet using "$u5_est_file", clear
	rename med u5_est
	rename lower u5_est_lower
	rename upper u5_est_upper

	tempfile est
	save `est', replace 

** Format raw data 
	insheet using "$u5_raw_file", clear
	replace source = "DSP" if regexm(source, "DSP") == 1 
	replace source = "SRS" if regexm(source, "SRS") == 1 
	replace source = "SSPC-DC" if source == "1% Intra-Census Survey" 
	replace source = "SSPC-DC" if source == "1 per 1000 Survey on Pop Change" 
    replace source = "RapidMortality" if regexm(source,"Rapid") & regexm(source,"Mortality") & ihme_loc_id == "ZAF"
	replace source = "VR" if regexm(source, "VR") == 1
	rename q5 u5_obs
	replace year = floor(year) + .5
        
    // Exclude marked shocks and outliers, along with discretionary 5q0 points
        drop if regexm(indirect, "indirect") == 1 
        drop if shock == 1	
        drop if outlier == 1
        drop if ihme_loc_id == "IRN" & year > 2003
        drop if ihme_loc_id == "SAU" & inlist(year,2009.5,2012.5) & source == "VR" // Two very high child completeness points
        
	rename sourcedate data_year
	keep if inlist(source, "VR", "SRS", "DSP", "CENSUS", "SURVEY", "UNKNOWN", "SSPC-DC","SUSENAS")
    keep ihme_loc_id year u5_obs source data_year 
	
** Merge estimates and raw data 
	merge m:1 ihme_loc_id year using `est'
	drop if _m == 2
	drop _m 
	
** Calculate comp 
** You use the est lower bounds to calculate the comp upper bounds because 
** when you divide something by a smaller number, it gives you a bigger number
	g comp = u5_obs/u5_est
	g comp_upper = u5_obs/u5_est_lower
	g comp_lower = u5_obs/u5_est_upper
	drop if comp < .1
	
** Merge on ihme_loc_id
	merge m:1 ihme_loc_id using `codes', keep(3) nogen

** save
	keep ihme_loc_id year comp* source
	gen comp_type = "u5"
	rename source source_type
	compress
	save "$save_file", replace
