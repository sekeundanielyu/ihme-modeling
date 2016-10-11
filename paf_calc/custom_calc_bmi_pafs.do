qui {

clear all
set maxvar 32767, perm
set more off, perm
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

** Random.org set seed for consistent TMRELs
set seed 370566

if "`2'" == "" {

	local risk = "metab_bmi"
	local rei_id = 108
	local location_id = 43872
	local year_id = 2010
	local sex_id = 1

}

else if "`2'" !="" {
	local risk = "`1'"
	local rei_id = "`2'"
	local location_id = "`3'"
	local year_id = "`4'"
	local sex_id = "`5'"
}

noi di c(current_time) + ": begin"

noi di "risk = `risk'"
noi di "rei_id = `rei_id'"
noi di "location_id = `location_id'"
noi di "year_id = `year_id'"
noi di "sex_id = `sex_id'"

cap mkdir /ihme/epi/risk/paf/`risk'_interm
local username = c(username)
** install Rsource
cap ssc install rsource

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
levelsof risk_type, local(risk_type) c

adopath + "$j/WORK/10_gbd/00_library/functions"

local bmi_dir "/share/covariates/ubcov/04_model/beta_parameters/8"

** shape1
insheet using "`bmi_dir'/bshape1/19_`location_id'_`year_id'_`sex_id'.csv", clear
renpfix draw_ shape1_
tempfile 1
save `1', replace

** shape2
insheet using "`bmi_dir'/bshape2/19_`location_id'_`year_id'_`sex_id'.csv", clear
renpfix draw_ shape2_
tempfile 2
save `2', replace

** mm
insheet using "`bmi_dir'/mm/19_`location_id'_`year_id'_`sex_id'.csv", clear
renpfix draw_ mm_
tempfile m
save `m', replace

** scale
insheet using "`bmi_dir'/scale/19_`location_id'_`year_id'_`sex_id'.csv", clear
renpfix draw_ scale_
tempfile s
save `s', replace

** RRs
get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') location_ids(`location_id') status(best) kwargs(draw_type:rr) source(risk) clear

** put RR into comparable unit space
forvalues i = 0/999 {
	qui replace rr_`i' = rr_`i'^(.2)
}

keep if year==`year_id'
keep if sex==`sex_id'

merge m:1 age_group_id using `1', keep(3) nogen
merge m:1 age_group_id using `2', keep(3) nogen
merge m:1 age_group_id using `m', keep(3) nogen
merge m:1 age_group_id using `s', keep(3) nogen

		** generate TMREL
		sort age_group_id cause_id mortality morbidity
		forvalues i = 0/999 {
			qui gen double tmred_mean_`i' = ((`tmred_2'-`tmred_1')*runiform() + `tmred_1')
		}

		** We want all TMREL draws to be the same across age/sex/cause so just carryforward from row 1
		qui count
		local n = `r(N)'
		forvalues x = 0/999 {
			qui levelsof tmred_mean_`x' in 1, local(t) c
				forvalues i = 1/`n' {
					qui replace tmred_mean_`x' = `t' in `i'
				}
		}

local minval = 0
local maxval = 1
local FILE = "/ihme/epi/risk/paf/`risk'_interm/FILE_`location_id'_`year_id'_`sex_id'"

outsheet using `FILE'.csv, comma replace

noi di c(current_time) + ": begin PAF calc"

rsource using $j/temp/`username'/GBD_2015/risks/PAF_R_run_this_for_Rsource_BMI.R, rpath("/usr/local/bin/R") roptions(`" --vanilla --args "`minval'" "`maxval'" "`FILE'" "')

noi di c(current_time) + ": PAF calc complete"

import delimited using `FILE'_OUT.csv, asdouble varname(1) clear


** clean up the tempfiles
cap erase `FILE'_OUT.csv
cap erase `FILE'.csv

foreach var of varlist paf* {
	cap replace `var' = "0" if `var'=="NA"
	cap destring `var', replace
}
		** save PAFs
		cap drop rei_id
		gen rei_id = `rei_id'
		keep age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mortality morbidity paf*
		duplicates drop // just in case - for some reason there were dups in household air pollution
		** expand mortliaty and morbidity
		expand 2 if mortality == 1 & morbidity == 1, gen(dup)
		replace morbidity = 0 if mortality == 1 & morbidity == 1 & dup == 0
		replace mortality = 0 if mortality == 1 & morbidity == 1 & dup == 1
		drop dup

		levelsof mortality, local(morts)

		noi di c(current_time) + ": saving PAFs"

			foreach mmm of local morts {
				if `mmm' == 1 local mmm_string = "yll"
				else local mmm_string = "yld"
							
				outsheet age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id paf* using "/ihme/epi/risk/paf/`risk'_interm/paf_`mmm_string'_`location_id'_`year_id'_`sex_id'.csv" if year_id == `year_id' & sex_id == `sex_id' & mortality == `mmm', comma replace

				no di "saved: /ihme/epi/risk/paf/`risk'_interm/paf_`mmm_string'_`location_id'_`year_id'_`sex_id'.csv"
			}


} // end quiet LOOP






