clear all
set maxvar 32767, perm
set more off, perm
pause on
	if c(os) == "Windows" {
		global j "J:"
		set mem 1g
	}
	if c(os) == "Unix" {
		global j "/home/j"
		set mem 2g
		set odbcmgr unixodbc
	}
	if c(os) == "MacOSX" {
		global j "/Volumes/snfs"
	}
	local username = c(username)

qui {
adopath + "$j/WORK/10_gbd/00_library/functions"

local exp_dir = "/ihme/gbd/WORK/05_risk/02_models/02_results/nutrition_iron/exp/6"
local tmrel_dir = "/ihme/gbd/WORK/05_risk/02_models/02_results/nutrition_iron/tmred/9"

if "`2'" == "" {

	local risk = "nutrition_iron"
	local rei_id = 95
	local location_id = 198
	local year_id = 1990
	local sex_id = 2

}

else if "`2'" !="" {
	local risk = "`1'"
	local rei_id = "`2'"
	local location_id = "`3'"
	local year_id = "`4'"
	local sex_id = "`5'"
}

cap mkdir /ihme/epi/risk/paf/`risk'_interm

local username = c(username)

import excel using $j/temp/`username'/GBD_2015/risks/risk_variables.xlsx, firstrow clear

keep if risk=="`risk'"
levelsof maxval, local(maxval) c
levelsof minval, local(minval) c
levelsof inv_exp, local(inv_exp) c
levelsof rr_scalar, local(rr_scalar) c
levelsof calc_type, local(f_dist) c
levelsof tmred_para1, local(tmred_1) c
levelsof tmred_para2, local(tmred_2) c
levelsof calc_type, local(f_dist) c
levelsof maxrr, local(cap) c

** RR
noi di c(current_time) + ": get relative risk draws"
get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') location_ids(`location_id') status(best) kwargs(draw_type:rr) source(risk) clear
noi di c(current_time) + ": relative risk draws read"
cap destring year_id, replace
cap destring sex_id, replace
cap destring age_group_id, replace
cap destring location_id, replace
keep if year_id == `year_id'
keep if sex_id == `sex_id'
tempfile rr
save `rr', replace

** exp 
noi di c(current_time) + ": read exp"
insheet using `exp_dir'/exp_`location_id'.csv, clear
rename gbd_age_start age_group_id
cap drop location_id
gen location_id = `location_id'
keep if year_id == `year_id'
keep if sex_id == `sex_id'
keep location_id year_id age_group_id sex_id parameter exp*
reshape wide exp_*, i(location_id year_id age_group_id sex_id) j(parameter) string
rename (exp_*mean exp_*sd) (exp_mean_* exp_sd_*)
tempfile exp
save `exp', replace

** tmrel
noi di c(current_time) + ": read TMREL"
insheet using `tmrel_dir'/tmred_`location_id'.csv, clear
rename gbd_age_start age_group_id
keep if parameter=="mean"
cap drop location_id
gen location_id = `location_id'
keep if year_id == `year_id'
keep if sex_id == `sex_id'
keep location_id year_id age_group_id sex_id tmred*
renpfix tmred_ tmred_mean_
merge 1:1 location_id year_id age_group_id sex_id using `exp', keep(3) nogen
merge 1:m age_group_id using `rr', keep(3) nogen

local FILE = "/ihme/epi/risk/paf/`risk'_interm/FILE_`location_id'_`year_id'_`sex_id'"
outsheet using `FILE'.csv, comma replace
noi di c(current_time) + ": begin PAF calc"

rsource using $j/temp/`username'/GBD_2015/risks/PAF_R_run_this_for_Rsource.R, rpath("/usr/local/bin/R") roptions(`" --vanilla --args "`minval'" "`maxval'" "`rr_scalar'" "`f_dist'" "`FILE'" "`inv_exp'" "') noloutput

noi di c(current_time) + ": PAF calc complete"
import delimited using `FILE'_OUT.csv, asdouble varname(1) clear
			
** clean up the tempfiles
erase `FILE'_OUT.csv
erase `FILE'.csv

cap drop rei_id
gen rei_id = `rei_id'

keep age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mortality morbidity paf*

rename cause_id ancestor_cause
joinby ancestor_cause using "$j/temp/`username'/GBD_2015/risks/cause_expand.dta", unmatched(master)
replace ancestor_cause = descendant_cause if ancestor_cause!=descendant_cause & descendant_cause!=. // if we have a no match for a sequelae
drop descendant_cause _merge
rename ancestor_cause cause_id

expand 2 if mortality == 1 & morbidity == 1, gen(dup)
replace morbidity = 0 if mortality == 1 & morbidity == 1 & dup == 0
replace mortality = 0 if mortality == 1 & morbidity == 1 & dup == 1
drop dup

levelsof mortality, local(morts)

noi di c(current_time) + ": saving PAFs"

cap drop modelable_entity_id
gen modelable_entity_id = .

	foreach mmm of local morts {
		if `mmm' == 1 local mmm_string = "yll"
		else local mmm_string = "yld"
					
		outsheet age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id paf* using "/share/epi/risk/paf/`risk'_interm/paf_`mmm_string'_`location_id'_`year_id'_`sex_id'.csv" if year_id == `year_id' & sex_id == `sex_id' & mortality == `mmm', comma replace

		no di "saved: /share/epi/risk/paf/`risk'_interm/paf_`mmm_string'_`location_id'_`year_id'_`sex_id'.csv"
	}

noi di c(current_time) + ": DONE!"

} // end quiet loop


