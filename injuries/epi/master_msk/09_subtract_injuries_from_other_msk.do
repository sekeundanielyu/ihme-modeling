
// Subtract injuries (fractures, dislocations) from Other MSK and save to reupload to Epi

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

if "`1'" == "" {
	local 1 /share/code/injuries/ngraetz/inj/gbd2015
	local 2 89
	local 3 2015
	local 4 1
}

local repo `1'
local location_id `2'
local year_id `3'
local sex_id `4'

local msk_id 2161

adopath + "/share/code/injuries/ngraetz/inj/gbd2015/ado"
adopath + "$prefix/WORK/10_gbd/00_library/functions"

get_demographics, gbd_team("epi")

// Aggregate the injuries prevalence files we are subtracting for this iso3/year/sex
insheet using "$prefix/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/02_inputs/parameters/ncodes_dislocations_fractures.csv", comma names clear
keep n_code
tempfile fracture_ncodes
save `fracture_ncodes', replace
insheet using "`repo'/como_inj_me_to_ncode.csv", comma names clear
keep if longterm == 1
merge m:1 n_code using `fracture_ncodes', keep(3) nogen
levelsof modelable_entity_id, l(mes)
clear
tempfile inj_prev
save `inj_prev', emptyok
foreach me_id of local mes {
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(`me_id') location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') age_group_ids($age_group_ids) status(latest) source(dismod) clear
	append using `inj_prev'
	save `inj_prev', replace
}
fastcollapse draw_*, type(sum) by(age_group_id)
rename draw_* inj_draw_*
save `inj_prev', replace

// Bring in MSK Other prevalence (FILES LABELED "INCIDENCE" RATHER THAN "PREVALENCE" - apparently this is true for prevalence-only dismod models, no one knows why.  Classic.) for this iso3/year/sex, merge on aggregates injury draws, and subtract without letting any draw go below 20% of it's current value
// Get best model id for Other MSK
get_ids, table(measure) clear
keep if measure_name == "Prevalence"
local prev_id = measure_id 
get_draws, gbd_id_field(modelable_entity_id) gbd_id(`msk_id') location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') age_group_ids($age_group_ids) status(latest) source(dismod) clear
keep if measure_id == `prev_id'
merge 1:1 age_group_id using `inj_prev', keep(3) nogen
gen threshold_draws_necessary = 0
forvalues i = 0/999 {
	gen threshold_draw = draw_`i' * .2
	replace draw_`i' = draw_`i' - inj_draw_`i'
	replace threshold_draws_necessary = threshold_draws_necessary + 1 if draw_`i' < threshold_draw
	replace draw_`i' = threshold_draw if draw_`i' < threshold_draw
	drop threshold_draw
}
drop inj_draw_*

// Save new draws in parent MSK Other folder
keep age_group_id draw_*
outsheet using "/share/injuries/04_COMO_input/msk_other_adj/`prev_id'_`location_id'_`year_id'_`sex_id'.csv", comma names replace

// Save diagnostic file of draws needing to be capped at 80% reduction
keep age threshold_draws_necessary
//save "$prefix/WORK/04_epi/01_database/02_data/_inj/05_diagnostics/gbd2015/msk/diagnostics_`location_id'_`year_id'_`sex_id'.dta", replace

di "DONE"
