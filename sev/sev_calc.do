set more off
** temp debug settings:
*set trace on
*set tracedepth 1
clear all
pause on

set maxvar 32000
set seed 309221
if c(os) == "Unix" {
	global j "/home/j"
	set odbcmgr unixodbc
}

** set useful globals
global functions_dir = "$j/WORK/10_gbd/00_library/functions"
global sev_calc_dir = "/homes/strUser/sev_calculator"
global experimental_dir = "$j/WORK/05_risk/central/code" 
global base_dir = "/ihme/centralcomp/sev"
global tmp_dir = "$base_dir/temp"

** restrict locations for shorter run times (otherwise takes > 3 hr, usually 4)
global testing = "0"

** load functions we'll need 
adopath + "$sev_calc_dir/core"
adopath + "$sev_calc_dir/core/readers"
adopath + "$functions_dir"

** parse args from qsub
global risk_id = "`1'"
global paf_version_id = "`2'" // used to find where paf draws are stored
global continuous = "`3'" // boolean {1,0} indicating if risk is continuous

**logging
cap set rmsg on
cap log close
local log_dir = "$base_dir/$paf_version_id/logs"
cap mkdir "$base_dir/$paf_version_id"
cap mkdir `log_dir'
log using "`log_dir'/log_$risk_id.txt", replace

get_demographic_variables
local location_ids = r(location_ids)
local year_ids = r(year_ids)
local age_group_ids = r(age_group_ids)

** categorical sevs don't use exposures as inputs, only continuous
if $continuous {
    prep_exposure_draws, location_ids(`location_ids') year_ids(`year_ids') ///
        age_group_ids(`age_group_ids')
    local prepped_exposures = r(file_path)
    calc_percentiles `prepped_exposures'
    local exposure_percentiles = r(file_path)
}

** both categoricals and continuous risks use RRs as input
prep_rrs, location_ids(`location_ids') age_group_ids(`age_group_ids') year_ids(`year_ids')
local RRs = r(file_path)

** only continuous actually use tmrel. Categorical risks just need RR/pafs
if $continuous {
    prep_tmrels, rr_file(`RRs') exp_file(`exposure_percentiles') location_ids(`location_ids') ///
        year_ids(`year_ids') age_group_ids(`age_group_ids')
    local tmrels = r(file_path)
    local risks_w_tmrel_draws = r(risks_w_tmrel_draws)
}

** pull pafs
if $continuous {
    prep_pafs_continuous `tmrels' "`risks_w_tmrel_draws'"
}
else {
    prep_pafs_categorical, rrs(`RRs')  location_ids(`location_ids') age_group_ids(`age_group_ids')
}

** actually calculate sevs
calc_scalars
local results = r(file_path)

** add age/sex/location aggregates
clear
use `results'
add_both_sex
local both_sex_results = r(both_sex_file_path)

clear
use `results'
append using `both_sex_results'
add_loc_hierarchy, location_ids(`location_ids') year_ids(`year_ids')
local loc_results = r(loc_file_path)

clear
use `loc_results'
add_age_std 
local asr_results = r(asr_file_path)


clear
use `loc_results'
add_all_age
local all_age_results = r(all_age_file_path)

use `loc_results'
append using `asr_results'
append using `all_age_results'

** Save draws and summaries
local draw_dir = "$base_dir/$paf_version_id/draws"
local summary_dir = "$base_dir/$paf_version_id/summary"
cap mkdir "`draw_dir'"
cap mkdir "`summary_dir'"
cap mkdir "`summary_dir'/to_upload"
save "`draw_dir'/$risk_id.dta", replace

fastpctile sev*, pct(2.5 97.5) names(lower_sev upper_sev)
fastrowmean sev*, mean_var_name(mean_sev)
drop sev*
save "`summary_dir'/$risk_id.dta", replace

// save csv to upload to dabtabase
gen measure_id = 29
gen metric_id = 3
rename (mean_sev lower_sev upper_sev risk_id) (val lower upper rei_id)
sort year_id location_id sex_id age_group_id rei_id metric_id
order measure_id year_id location_id sex_id age_group_id rei_id metric_id val upper lower
keep measure_id year_id location_id sex_id age_group_id rei_id metric_id val upper lower
export delimited "`summary_dir'/to_upload/$risk_id.csv", replace

log close
