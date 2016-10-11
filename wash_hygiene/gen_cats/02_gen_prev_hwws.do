// Purpose: Generate final prevalence of handwashing with soap risk by combining lit and survey data

//Set directories
	if c(os) == "Unix" {
		global j "/home/j"
		set more off
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j "J:"
	}

// Additional Comments: 
clear all
set more off
capture log close
capture restore, not
set maxvar 20000

//Set relevant locals
local input_folder		"/share/epi/risk/temp/wash_hwws5"
local output_folder		"/share/epi/risk/temp/wash_hwws5"
local merge_2013		"$j/WORK/01_covariates/02_inputs/water_sanitation/hygiene/data/gpr/gpr output"
adopath + "$j/WORK/10_gbd/00_library/functions"

local date "04152016"


// Prep dataset
**Lit data**
import delimited "`input_folder'/lit_v2", clear
keep location_id year_id age_group_id draw_* measure_id
forvalues n = 0/999 {
	rename draw_`n' hwws_lit_`n'
		}
tempfile lit
save `lit', replace

**Merge on region info in order to apply region specific DHS values b/c we assume 100% availability in high-income superregion**
get_location_metadata, location_set_id(9) clear
keep location_id ihme_loc_id super_region_name region_name
tempfile loc_id
save `loc_id', replace

**DHS/MICS data**
import delimited "`input_folder'/dhs_v1", clear
keep location_id year_id age_group_id draw_* measure id
forvalues n = 0/999 {
	rename draw_`n' hwws_dhs_`n'
		}
merge m:1 location_id using `loc_id', nogen keep(1 3)

// Assume 100% availability for high-income superregion
forvalues n = 0/999 {
	replace hwws_dhs_`n' = 1 if super_region_name == "High-income"
}
tempfile dhs
save `dhs', replace

// Merge on with literature draws
merge 1:1 location_id year_id using `lit', keep(1 3) nogen

// Generate final prevalenceby multiplying H2O + soap availability (from surveys) with country practices (from literature)
forvalues n = 0/999 {
	gen hwws_final_`n' = hwws_lit_`n' * hwws_dhs_`n'
	}

// Prep for save_results
preserve
keep age_group_id location_id year_id hwws_final_*
	forvalues n = 0/999 {
		rename hwws_final_`n' hwws_final2_`n'
		gen hwws_final_`n' = 1 - hwws_final2_`n'
	}
drop hwws_final2_*
save "`output_folder'/hwws_final_v3", replace
restore

// Prep for Kelly's gpr viz tool
	keep age_group_id location_id year_id hwws_final_*
	// Calculate mean of 1000 draws
		fastrowmean hwws_final_*, mean_var_name(gpr_mean)
	// Calculate lower and upper bounds of draws
		fastpctile hwws_final_*, pct(2.5 97.5) names(gpr_lower gpr_upper)
	drop hwws_final_*

// Merge on 2013 hwws data
preserve
	get_location_metadata, location_set_id(9) clear
	keep location_id ihme_loc_id
	tempfile loc_id
	save `loc_id', replace
restore
	merge m:1 location_id using `loc_id', nogen keep(1 3)
	merge m:1 ihme_loc_id year_id using "`merge_2013'/hwws_mean", keep(1 3) nogen
	gen sex_id = 3
	gen me_name = "wash_hwws"
	gen st = .
	gen prior = .
	gen data = . 

export delimited "`output_folder'/hwws_viz_`date'", replace