//// File Name: gen_prev_newcat.do
// File Purpose: combine output from gpr models to create exposure inputs to PAF

// Additional Comments: 

//Set directories
	if c(os) == "Unix" {
		global j "/home/j"
		set more off
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j "J:"
	}


//Housekeeping
clear all 
set more off
set maxvar 20000

//Set relevant locals
local functions			"$j/WORK/10_gbd/00_library/functions"
local get_demo			"`functions'/get_demographics.ado"
local get_location		"`functions'/get_location_metadata.ado"
local input_folder		"/share/epi/risk/temp/wash_sanitation/run1"
local output_folder		"/share/epi/risk/temp/wash_sanitation/run1"
local graphloc			"$j/temp/wgodwin/save_results/wash_sanitation/rough_output"

local date "04102016"

// Prep dataset
**Sanitation**
import delimited "`input_folder'/imp_v1", clear
keep location_id year_id age_group_id draw_*
forvalues n = 0/999 {
	rename draw_`n' isanitation_`n'
	gen iunimp_`n' = 1 - isanitation_`n'
		}
tempfile sanitation
save `sanitation', replace


**Sewer** // Convert from proportion to prevalence
import delimited "`input_folder'/piped_v1", clear
keep location_id year_id age_group_id draw_*
forvalues n = 0/999 {
	rename draw_`n' isewer_prop`n'
		}

tempfile sewer
save `sewer', replace

// Merge on with improved sanitation
merge 1:1 location_id year_id using `sanitation', keep(1 3) nogen

**generate estimate for prevalence of improved facilities without sewer connection
forvalues n = 0/999 {
	gen isewer_`n' = isewer_prop`n' * isanitation_`n'
	gen iimproved_`n' = isanitation_`n' - isewer_`n'
	}
drop isewer_prop*

****replace negative prevalence numbers
local cats "improved sewer unimp" 
foreach cat of local cats {
	forvalues n = 0/999 {
	replace i`cat'_`n' = 0.0001 if i`cat'_`n'<0
		}
}

**rescale draws from all three categories to make sure they add up to 1
forvalues n = 0/999 {

	replace iimproved_`n' = (iimproved_`n'/(iimproved_`n'+isewer_`n'+iunimp_`n'))
	replace isewer_`n' = (isewer_`n'/(iimproved_`n'+isewer_`n'+iunimp_`n'))
	replace iunimp_`n' = (iunimp_`n'/(iimproved_`n'+isewer_`n'+iunimp_`n'))
	
	gen total_`n' = (iimproved_`n'+isewer_`n'+iunimp_`n')
		}
drop total* isanitation*

tempfile san_cats
save `san_cats', replace

// Prepare to merge on superregion and region variables
	run "`get_location'"
	get_location_metadata, location_set_id(9) clear
	keep if level >= 3
	keep location_id super_region_id super_region_name region_name
	tempfile country_info
	save `country_info', replace

// Merge on location info in order to bin all high income countries
	use `san_cats', clear
	merge m:1 location_id using `country_info', nogen keep(1 3)
	
// Bin all high income countries into TMRED
forvalues n = 0/999 {
	replace iunimp_`n' = 0 if super_region_id==64 & region_name!="Southern Latin America"
	replace iimproved_`n' = 0 if super_region_id==64 & region_name!="Southern Latin America"
	replace isewer_`n' = 1 if super_region_id==64 & region_name!="Southern Latin America"
	}

foreach exp in unimp improved sewer {
	preserve
	keep age_group_id location_id year_id i`exp'_*
	save "`output_folder'/`exp'_final_v1", replace
	restore
	}
**save data**
save "`graphloc'/allcat_prev_san_v1", replace

******************************************************************************************************************************
/*
**Calculate PAF**
gen paf_num = ((isewer_mean*1) + (iimproved_mean*2.71) + (iunimproved_mean*3.23)) - (1*1)
gen paf_denom =  ((isewer_mean*1) + (iimproved_mean*2.71) + (iunimproved_mean*3.23)) 
gen paf = paf_num/paf_denom
tempfile paf
save `paf', replace

**Collapse to gen global/regional estimates**
***Population data***
use "C:/Users/asthak/Documents/Covariates/Water and Sanitation/smoothing/spacetime input/pop_data.dta", clear
tempfile all_pop
sort iso3 
save `all_pop', replace

use `paf', clear
merge m:1 iso3 year using `all_pop'

collapse (mean) paf, by(region_name year)
collapse (mean) paf, by(year)

br if year==1990 | year == 1995 | year == 2000 | year==2005 | year == 2010 | year == 2013

//Graph to see if this works
local iso3s ECU PER SLV KEN MAR BGD
	foreach iso3 of local iso3s {
	twoway (line step2_prev year) || (line prev_piped_t year) || (line prev_piped_t2 year) || (line prev_piped_untr year) if iso3=="BGD", title("BGD") ///
	xlabel(1980(5)2013)
	graph export "`graphloc'/`iso3'_03182014.pdf", replace
}