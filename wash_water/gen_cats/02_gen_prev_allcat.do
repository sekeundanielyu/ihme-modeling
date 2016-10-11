// File Name: gen_prev_newcat.do
// File Purpose: combine output from proportion models to split each source type group by HWT use 


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
set maxvar 30000

//Set relevant locals
local functions			"$j/WORK/10_gbd/00_library/functions"
local get_demo			"`functions'/get_demographics.ado"
local get_location		"`functions'/get_location_metadata.ado"
local input_folder		"/share/epi/risk/temp/wash_water/run1"
local output_folder		"/share/epi/risk/temp/wash_water/run1"
local graphloc			"$j/temp/wgodwin/save_results/wash_water/rough_output"


// Prep GPR draws of exposure by access to piped or improved water sources

	// improved water
	import delimited "`input_folder'/imp_v1", clear
	keep location_id year_id age_group_id draw_*
	forvalues n = 0/999 {
		rename draw_`n' iwater_mean`n'
		gen iunimp_mean`n' = 1 - iwater_mean`n'
		}
	tempfile imp_water
	save `imp_water', replace
	
	// piped water
	import delimited "`input_folder'/piped_v2", clear
	keep location_id year_id draw_*
	merge 1:1 location_id year_id using `imp_water', keep(1 3) nogen
	forvalues n = 0/999 {
		rename draw_`n' ipiped_prop`n'
		gen ipiped_mean`n' = ipiped_prop`n' * iwater_mean`n'
		gen iimp_mean`n' = iwater_mean`n' - ipiped_mean`n'
		}
	tempfile water_cats
	save `water_cats', replace



// Household water treatment exposures prep
local models "itreat_imp itreat_piped itreat_unimp tr_imp tr_piped tr_unimp"
foreach model of local models {
	import delimited "`input_folder'/`model'_v1", clear
	sort location_id year_id
	keep location_id year_id draw_*
	
		forvalues n = 0/999 {
			rename draw_`n' prop_`model'`n'
			}
	
	tempfile `model'
	save ``model'', replace
} 

// merge all draws
use `water_cats', clear
local sources imp unimp piped
	foreach source of local sources {
	merge m:1 location_id year using `itreat_`source'' , keepusing(prop_itreat_`source'*) nogen keep(1 3)
	merge m:1 location_id year using `tr_`source'', keepusing(prop_tr_`source'*) nogen keep(1 3)

		forvalues d = 0/999 {
			gen prop_untr_`source'`d' = 1 - (prop_tr_`source'`d')
			rename prop_tr_`source'`d' prop_any_treat_`source'`d'
			gen prop_treat2_`source'`d' = prop_any_treat_`source'`d' - prop_itreat_`source'`d'
		}
	}

tempfile compiled_draws
save `compiled_draws', replace
	
**********************************************
*******Generate estimates for final categories**********
**********************************************
use `compiled_draws', clear
local sources imp unimp piped
foreach source of local sources {
	
	forvalues n = 0/999 {
	
	gen prev_`source'_t_`n' = prop_itreat_`source'`n' * i`source'_mean`n'
	gen prev_`source'_t2_`n' = prop_treat2_`source'`n'* i`source'_mean`n'
	gen prev_`source'_untr_`n' = prop_untr_`source'`n'* i`source'_mean`n'
	
		}
	}

keep location_id year_id prev_*
tempfile all_prev
save `all_prev', replace

// Prep the country codes file
	run "`get_location'"
	get_location_metadata, location_set_id(9) clear
	keep if level >= 3
	keep location_id location_name super_region_id super_region_name region_name
	tempfile country_info
	save `country_info', replace

// Merge on location info in order to bin all high income countries
	use `all_prev', clear
	merge m:1 location_id using `country_info', nogen keep(1 3)


// Bin all high income countries into TMRED except Southern Latin America - this includes subnational GBR and HK and Macao
forvalues n = 0/999	 {

	replace prev_piped_untr_`n' = 0 if super_region_id==64 & region_name!="Southern Latin America"
	replace prev_piped_t2_`n' = 0 if super_region_id==64 & region_name!="Southern Latin America"
	replace prev_imp_t_`n' = 0 if super_region_id==64 & region_name!="Southern Latin America"
	replace prev_imp_t2_`n' = 0 if super_region_id==64 & region_name!="Southern Latin America"
	replace prev_imp_untr_`n' = 0 if super_region_id==64 & region_name!="Southern Latin America"
	replace prev_unimp_t_`n' = 0 if super_region_id==64 & region_name!="Southern Latin America"
	replace prev_unimp_t2_`n' = 0 if super_region_id==64 & region_name!="Southern Latin America"
	replace prev_unimp_untr_`n' = 0 if super_region_id==64 & region_name!="Southern Latin America"
	replace prev_piped_t_`n' = 1 if super_region_id==64 & region_name!="Southern Latin America" 

	replace prev_piped_untr_`n' = 0 if location_id==354 | location_id==361
	replace prev_piped_t2_`n' = 0 if location_id==354 | location_id==361
	replace prev_imp_t2_`n' = 0 if location_id==354 | location_id==361
	replace prev_imp_untr_`n' = 0 if location_id==354 | location_id==361
	replace prev_unimp_t_`n' = 0 if location_id==354 | location_id==361
	replace prev_unimp_t2_`n' = 0 if location_id==354 | location_id==361
	replace prev_unimp_untr_`n' = 0 if location_id==354 | location_id==361
	replace prev_piped_t_`n' = 1 if location_id==354 | location_id==361
	
	}
	
// for now - replace -ve draws
local sources imp unimp piped
foreach source of local sources {

	local trx untr t t2
	foreach t of local trx {
	
	forvalues n = 0/999 {

		replace prev_`source'_`t'_`n' = 0.0001 if prev_`source'_`t'_`n' < 0
		
				}
			}
		}
	
//Squeeze in categories to make sure they add up to 1
forvalues n = 0/999 {
	egen prev_total_`n' = rowtotal(*prev*_`n')
	replace prev_piped_untr_`n' = prev_piped_untr_`n' / prev_total_`n'
	replace prev_piped_t2_`n' = prev_piped_t2_`n'/ prev_total_`n'
	replace prev_imp_t_`n' = prev_imp_t_`n' / prev_total_`n'
	replace prev_imp_t2_`n' = prev_imp_t2_`n' / prev_total_`n'
	replace prev_imp_untr_`n' = prev_imp_untr_`n' / prev_total_`n'
	replace prev_unimp_t_`n' = prev_unimp_t_`n' / prev_total_`n'
	replace prev_unimp_t2_`n' = prev_unimp_t2_`n' / prev_total_`n'
	replace prev_unimp_untr_`n' = prev_unimp_untr_`n' / prev_total_`n'
	replace prev_piped_t_`n' = prev_piped_t_`n' / prev_total_`n'
	}
	
	drop *total*
	tempfile check
	save `check', replace

// Generate high quality piped categories for Southern Latin America and Eastern Europe ***CHECK ON HK and MACAO WITH MEHRDAD
local treatments t t2 untr
foreach hwt of local treatments {
	forvalues n = 0/999 {
		gen prev_piped_`hwt'_hq_`n' = 0
		replace prev_piped_`hwt'_hq_`n' = prev_piped_`hwt'_`n' if region_name == "Eastern Europe" | region_name == "Southern Latin America"
		replace prev_piped_`hwt'_`n' = 0 if prev_piped_`hwt'_hq_`n' != 0
	}
}

**save data**
save "`graphloc'/allcat_prev_water_v2.dta", replace
// Save each category separately in prep for save_results
local exposures imp_t imp_t2 imp_untr unimp_t unimp_t2 unimp_untr piped_t2 piped_untr piped_untr_hq piped_t2_hq
	foreach exposure of local exposures {
		preserve
			keep location_id year_id prev_`exposure'_*
			if "`exposure'" == "piped_t2" {
				drop prev_piped_t2_hq_*
			}
			if "`exposure'" == "piped_untr" {
				drop prev_piped_untr_hq_*
			}
			gen age_group_id = 22
			save "`output_folder'/`exposure'_v2", replace
		restore
	}
//End of Code//
