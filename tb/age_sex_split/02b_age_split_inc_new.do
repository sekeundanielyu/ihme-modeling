** Description: HIV-TB incidence calculations


// Settings
			// Clear memory and set memory and variable limits
				clear all
				set mem 5G
				set maxvar 32000

			// Set to run all selected code without pausing
				set more off

			// Set graph output color scheme
				set scheme s1color

			// Define J drive (data) for cluster (UNIX) and Windows (Windows)
				if c(os) == "Unix" {
					global prefix "/home/j"
					set odbcmgr unixodbc
				}
				else if c(os) == "Windows" {
					global prefix "J:"
				}
			
			// Close any open log file
				cap log close
				
			// local

				

** *************************************************************************************************************************************************
// locals
local acause hiv_tb
local custom_version dismod_90644_90646
local measure incidence
local measure_id 6

// Make folders on cluster
capture mkdir "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws"
capture mkdir "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`custom_version'"	

// define filepaths
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015//`custom_version'/"
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015//`custom_version'/results"
	
	local outdir "$prefix/WORK/04_epi/01_database/02_data//`acause'/GBD2015//`custom_version'/"
	local indir "$prefix/WORK/04_epi/01_database/02_data//`acause'/GBD2015/data"
	local tempdir "$prefix/WORK/04_epi/01_database/02_data/hiv_tb/GBD2015/temp"
	
** *********************************************************************************************************
   
    
// get HIV prev age pattern

use "$prefix/WORK/04_epi/01_database/02_data/hiv_tb/GBD2015/data/hiv_prev_age_pattern.dta", clear
drop model_version_id
drop if age_group_id>21
tempfile age_pattern
save `age_pattern', replace



// get population
	  
		clear all
		adopath + "$prefix/Project/Mortality/shared/functions"
		get_env_results
		tempfile pop_all
		save `pop_all', replace
		
		keep if age_group_id==22
        tempfile pop
		save `pop', replace

// run ado file for fast collapse

adopath+ "$prefix/WORK/10_gbd/00_library/functions"


** *****************************
// Generate TB-HIV prev numbers
** *****************************
use "/ihme/gbd/WORK/04_epi/01_database/02_data/tb/temp/hybrid_`custom_version'.dta" , clear
drop if age_group_id>21
keep if measure_id==6
tempfile inc
save `inc', replace


// collapse draws
// collapse(sum) draw_*, by (location_id year_id)
use `inc', clear
merge m:1 location_id year_id age_group_id sex_id using `pop_all', keepusing(mean_pop) keep(3)nogen
forvalues i=0/999 {
			di in red "draw `i'"
			replace draw_`i'=draw_`i'*mean_pop
			}

			tempfile inc_cases
save `inc_cases', replace

fastcollapse draw_*, type(sum) by(location_id year_id) 

** merge on the fraction data
merge 1:1 location_id year_id using "$prefix/WORK/04_epi/01_database/02_data/hiv_tb/GBD2015/data/Prop_tbhiv_mean_ui.dta", keepusing(mean_prop) keep(3)nogen
		
	** loop through draws and adjust them... 
		forvalues i=0/999 {
			di in red "draw `i'"
			gen tbhiv_d`i'=mean_prop*draw_`i'
			drop draw_`i' 
		}
tempfile hivtb
save `hivtb', replace
		

// prep pop
use `pop_all', clear
drop if year_id<1980
drop if location_id==1
drop if sex_id==3
tempfile tmp_pop
save `tmp_pop', replace


// age-sex split

use `hivtb', clear
merge 1:m location_id year_id using `tmp_pop', keep(1 3) nogen
merge m:1 location_id year_id age_group_id sex_id using `age_pattern', keep(3)nogen

rename mean_pop sub_pop
gen rate_sub_pop=rate*sub_pop

preserve
collapse (sum) rate_sub_pop, by(location_id year_id) fast
rename rate_sub_pop sum_rate_sub_pop
tempfile sum
save `sum', replace

restore
merge m:1 location_id year_id using `sum', keep(3)nogen

forvalues i=0/999 {
			di in red "draw `i'"
			gen draw_`i'=rate_sub_pop*(tbhiv_d`i'/sum_rate_sub_pop)
			drop tbhiv_d`i' 
		}

keep location_id year_id age_group_id sex_id draw_*

tempfile hivtb_cyas
save `hivtb_cyas', replace


** *****************************************************************************************************************************************
** Capping hivtb cases if hivtb/tb >90% of TB all forms
** *****************************************************************************************************************************************

// rename tb draws
use `inc_cases', clear
// rename draws
forvalues i = 0/999 {
			  rename draw_`i' tb_`i'
			}
tempfile tb
save `tb', replace


// merge the tb-all-forms and hivtb files
			use `tb', clear
			merge 1:1 location_id year_id age_group_id sex using `hivtb_cyas', keep(3) nogen 

// loop through draws and adjust them... 
		forvalues i=0/999 {
			gen frac_`i'=draw_`i'/tb_`i'
			replace draw_`i'=tb_`i'*0.9 if frac_`i'>0.9 & frac_`i' !=.
			replace draw_`i'=0 if draw_`i'==.
			}
drop tb_* frac_* modelable_entity_id measure_id
tempfile hivtb_capped
save `hivtb_capped', replace


** ******************************************************************************************************************

// merge on pop again to calculate incidence
merge m:1 location_id year_id age_group_id sex_id using `pop_all', keepusing(mean_pop) keep(3)nogen
forvalues i=0/999 {
			di in red "draw `i'"
			replace draw_`i'=draw_`i'/mean_pop
			}
// Locations where the prevalence of HIV is zero (location_ids 161 and 186 for 1990) have missing draws, so replace them with zero
foreach a of varlist draw_0-draw_999 {
	replace `a'=0 if `a'==.
	}
gen modelable_entity_id=1176
tempfile hivtb_cyas_capped
save `hivtb_cyas_capped', replace
save /ihme/gbd/WORK/04_epi/01_database/02_data/tb/temp/HIVTB_inc_cyas_`custom_version'_capped.dta, replace



// upload results

use `hivtb_cyas_capped', clear
drop mean_pop
// save results for hiv_tb

gen measure_id=6
	

	// prep for COMO
	levelsof(location_id), local(ids) clean
	levelsof(year_id), local(years) clean

global sex_id "1 2"

foreach location_id of local ids {
		foreach year_id of local years {
			foreach sex_id of global sex_id {
					qui outsheet if location_id==`location_id' & year_id==`year_id' & sex_id==`sex_id' using "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`custom_version'/`measure_id'_`location_id'_`year_id'_`sex_id'.csv", comma replace
				}
			}
		}
		
/*	
	// save results and upload
	
	do /home/j/WORK/10_gbd/00_library/functions/save_results.do
    save_results, modelable_entity_id(1176) description(`acause' `measure' `custom_version') mark_best(no) in_dir(/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`custom_version') metrics(`measure')

	
	

