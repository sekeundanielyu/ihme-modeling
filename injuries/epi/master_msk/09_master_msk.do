// Nick Graetz
// MASTER - Subtract injuries (fractures, dislocations) from Other MSK and save to reupload to Epi
// 10/7/14

clear all
set more off
set mem 2g
set maxvar 32000
if c(os) == "Unix" {
global prefix "/home/j"
set odbcmgr unixodbc
}
else if c(os) == "Windows" {
global prefix "J:"
}

local subtract = 1
local epi_upload = 0
	local target_me = 3136

local repo "/share/code/injuries/ngraetz/inj/gbd2015"
adopath + "`repo'/ado"
adopath + "$prefix/WORK/10_gbd/00_library/functions"
load_params
get_demographics, gbd_team("epi")

cap mkdir "/share/injuries/04_COMO_input/msk_other_adj"

if `subtract' == 1 {
	foreach location_id of global location_ids {
		foreach year of global year_ids {
			foreach sex of global sex_ids {
				! qsub -P proj_injuries -N inj_msk_`location_id'_`year'_`sex' -pe multi_slot 4 -l mem_free=8 "`repo'/stata_shell.sh" "`repo'/master_msk/09_subtract_injuries_from_other_msk.do" "`repo' `location_id' `year' `sex'"
			}
		}
	}
}

// Upload new results to MSK Other parent - sequeal id 3136
if `epi_upload' == 1 {
do /home/j/WORK/10_gbd/00_library/functions/save_results.do
save_results, modelable_entity_id(`target_me') description("Prevalence for COMO submission") in_dir("/share/injuries/04_COMO_input/msk_other_adj") metrics(5) mark_best("yes")
}

di "DONE"

