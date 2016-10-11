/*******************************************
Description: This is the second lower-level script submitted by 
06_save_results.do, and the first submitted by 06_save_results_parallel.do. 
06_save_results_parallel_parallel formats mild_imp prevalence data and runs 
save_results. We do not run a second DisMod model for mild impairment because 
we assume no excess mortality associated with mild impairment. Therefore there 
is no need to stream out in DisMod to get our final results. 

*******************************************/

clear all 
set more off
set maxvar 30000
version 13.0

// priming the working environment
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

// arguments
local acause `1'
local me_id `2'

// test arguments
/*local acause "neonatal_enceph"
local me_id 2525
*/

// directories
local in_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/temp_outputs/`acause'/`me_id'/parallel_no_sub"
local out_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/temp_outputs/`acause'/`me_id'/draws"

// functions
run "`j'/WORK/10_gbd/00_library/functions/save_results.do"
run "`j'/WORK/10_gbd/00_library/functions/get_location_metadata.ado"

************************************************************************************

di "getting gest age, target_me_id"
	if `me_id' == 1557 {
		local gest_age "ga1_"
		local target_me_id 8618
	}
	if `me_id' == 1558 {
		local gest_age "ga2_"
		local target_me_id 8619
	}
	if `me_id' == 1559 {
		local gest_age "ga3_"
		local target_me_id 8620
	}
	if `me_id' == 2525 {
		local gest_age ""
		local target_me_id 8652
	}
	if `me_id' == 9793 {
		local gest_age ""
		local target_me_id 8673
	}


di "Me_id is `me_id' and target_me_id is `target_me_id'"
import delimited "`in_dir'/mild_prev_final_prev.csv", clear

gen measure_id = 5
gen garbage = 1
generate modelable_entity_id = `target_me_id'
rename year year_id
rename sex sex_id

di "dropping for all but the most granular locations"
drop if draw_0 == .

tempfile data
save `data'

clear
set obs 20 
gen garbage = 1
gen age_group_id = _n + 1

joinby garbage using `data'
drop garbage
cap drop _merge
save `data', replace

levelsof location_id, local(location_ids)
levelsof year_id, local(year_ids)
levelsof sex_id, local(sex_ids)

foreach location_id of local location_ids {
	foreach year_id of local year_ids {
		foreach sex_id of local sex_ids {
			keep if location_id == `location_id' & year_id == `year_id' & sex_id == `sex_id'
			export delimited "`out_dir'/mild/5_`location_id'_`year_id'_`sex_id'.csv", replace
			use `data', clear
		}
	}
}

// save_results
save_results, modelable_entity_id(`target_me_id') description(Bprev mild impairment`me_id') in_dir(`out_dir'/mild/) metrics(prevalence) mark_best(yes)


