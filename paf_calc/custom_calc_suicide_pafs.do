qui {
clear all
pause on
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

set seed 745026

if "`2'" == "" {

	local risk = "drugs_illicit_suicide"
	local rei_id = 140
	local location_id = 101
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

adopath + "$j/WORK/10_gbd/00_library/functions"
local username = c(username)
run $j/temp/`username'/GBD_2015/risks/paf_calc_categ.do

cap mkdir /ihme/epi/risk/paf/`risk'_interm

local n = 0
foreach me in 1977 1978 1976 {

	** pull exposure
		get_draws, gbd_id_field(modelable_entity_id) gbd_id(`me') location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') status(best) source(epi) clear
		renpfix draw_ exp_
		** prevalence model is 5
		keep if measure_id==5

		gen parameter="cat1"
		expand 2, gen(dup)
		forvalues i = 0/999 {
			qui replace exp_`i' = 1-exp_`i' if dup==1
		}
		replace parameter="cat2" if dup==1
		drop dup
		tempfile exp
		save `exp', replace

	** prep RRs

	clear
	set obs 1
	gen cause_id = 719 in 1
	if `me' == 1967 {
		gen modelable_entity_id = `me'
		gen sd = ((ln(10.65)) - (ln(8.98))) / (2*invnormal(.975))
		forvalues i = 0/999 {
			gen double rr_`i' = exp(rnormal(ln(9.79), sd))
		}
	}

	if `me' == 1977 {
		gen modelable_entity_id = `me'
		gen sd = ((ln(16.94)) - (ln(3.93))) / (2*invnormal(.975))
		forvalues i = 0/999 {
			gen double rr_`i' = exp(rnormal(ln(8.16), sd))
		}
	}

	if `me' == 1978 {
		gen modelable_entity_id = `me'
		gen sd = ((ln(16.94)) - (ln(3.93))) / (2*invnormal(.975))
		forvalues i = 0/999 {
			gen double rr_`i' = exp(rnormal(ln(8.16), sd))
		}
	}

	if `me' == 1976 {
		gen modelable_entity_id = `me'
		gen sd = ((ln(10.53)) - (ln(4.49))) / (2*invnormal(.975))
		forvalues i = 0/999 {
			gen double rr_`i' = exp(rnormal(ln(6.85), sd))
		}
	}

	replace cause_id = 718

	gen parameter = "cat1"

	gen n = 1
	tempfile r
	save `r', replace

	clear
	set obs 50
	gen age_group_id = _n
	keep if age_group_id<=21
	drop if age_group_id==.
	gen n = 1
	joinby n using `r'
	keep cause_id age_group_id modelable_entity_id parameter rr*

	expand 2, gen(dup)
	forvalues i = 0/999 {
		replace rr_`i' = 1 if dup==1
	}
	replace parameter="cat2" if dup==1 
	drop dup
	gen mortality=1
	gen morbidity=1

	tempfile rr
	save `rr', replace

	merge m:1 age_group_id modelable_entity_id parameter using `exp', keep(3) nogen

		** generate TMREL
		bysort age_group_id year_id sex_id cause_id mortality morbidity: gen level = _N
		levelsof level, local(tmrel_param) c
		drop level

		forvalues i = 0/999 {
			qui gen tmrel_`i' = 0
			replace tmrel_`i' = 1 if parameter=="cat`tmrel_param'"
		}

		cap drop rei_id
		gen rei_id = `rei_id'
		calc_paf_categ exp_ rr_ tmrel_ paf_, by(age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mortality morbidity)

		local n = `n' + 1
		tempfile `n'
		save ``n'', replace

} // end me loop

** append PAFs and calculate joint for all drug use
		clear
		forvalues i = 1/`n' {
			append using ``i''
		}


	foreach var of varlist paf* {
		replace `var' = log(1 - `var')
	}

	fastcollapse paf*, type(sum) by(age_group_id location_id sex_id year_id cause_id rei_id)
	foreach var of varlist paf* {
		replace `var' = 1 - exp(`var')
		replace `var' = 1 if `var' == . 
	}

** apply cap
	local logit_mean = logit(.84488)
	local logit_sd = (logit(.896145) - logit(.785724)) / (2*invnormal(.975))

	forvalues i = 0/999 {
		gen paf_tot_cap_`i' = invlogit(rnormal(`logit_mean',`logit_sd')) if _n==1
		replace paf_tot_cap_`i' = paf_tot_cap_`i'[1]
		gen paf_tot_temp_`i' = min(paf_`i',paf_tot_cap_`i')
		replace paf_`i' = paf_`i' * (paf_tot_temp_`i' / paf_`i') if paf_tot_temp_`i'!=0
	}

	drop paf_tot_cap* paf_tot_temp*

		** expand mortliaty and morbidity
		gen mortality=1
		gen morbidity=1

		expand 2 if mortality == 1 & morbidity == 1, gen(dup)
		replace morbidity = 0 if mortality == 1 & morbidity == 1 & dup == 0
		replace mortality = 0 if mortality == 1 & morbidity == 1 & dup == 1
		drop dup

		levelsof mortality, local(morts)

		cap gen modelable_entity_id=.

		noi di c(current_time) + ": saving PAFs"

			foreach mmm of local morts {
				if `mmm' == 1 local mmm_string = "yll"
				else local mmm_string = "yld"
							
				outsheet age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id paf* using "/ihme/epi/risk/paf/`risk'_interm/paf_`mmm_string'_`location_id'_`year_id'_`sex_id'.csv" if year_id == `year_id' & sex_id == `sex_id' & mortality == `mmm', comma replace

				no di "saved: /ihme/epi/risk/paf/`risk'_interm/paf_`mmm_string'_`location_id'_`year_id'_`sex_id'.csv"
			}

} // end quiet loop


