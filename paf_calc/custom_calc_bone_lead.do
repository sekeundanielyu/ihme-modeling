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

if "`2'" == "" {

	local risk = "envir_lead_bone"
	local rei_id = 243
	local location_id = 20 // 20 = Vietnam
	local year_id = 1990
	local sex_id = 1

}

else if "`2'" !="" {
	local risk = "`1'"
	local rei_id = "`2'"
	local location_id = "`3'"
	local year_id = "`4'"
	local sex_id = "`5'"
}

set seed 370566

adopath + "$j/WORK/10_gbd/00_library/functions"
local username = c(username)

** pull SBP RRs
noi di c(current_time) + ": pull SBP RRs"
get_draws, gbd_id_field(rei_id) gbd_id(107) location_ids(`location_id') status(best) kwargs(draw_type:rr) source(risk) clear
keep if year_id == `year_id'
keep if sex_id == `sex_id'
duplicates drop
noi di c(current_time) + ": shift RRs"

forvalues i = 0/999 {
	replace rr_`i' = rr_`i'^(.61/10)
}

tempfile rr
save `rr', replace


cap get_demographics, gbd_team("epi") make_template clear
if _rc insheet using $j/temp/strUser/GBD_2015/risks/location.csv, clear
keep location_id location_name *region*
duplicates drop

tempfile LOC
save `LOC', replace

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
	levelsof maxrr, local(cap) c

/*
******************************************************************************************************************************************************************************************************************************************
PAF CALCULATION
******************************************************************************************************************************************************************************************************************************************
*/

noi di c(current_time) + ": begin SD regression"

insheet using $j/WORK/05_risk/risks/envir_lead_blood/data/exp/prepped/data.csv, clear
drop if data==.
rename data meas_value
gen std_dev = standard_error * sqrt(sample_size)
gen log_std_dev = log(std_dev)
gen log_meas_value = log(meas_value)
gen outlier = (std_dev / meas_value > 2) | (std_dev / meas_value < .1)
drop if outlier==1

noi regress log_std_dev log_meas_value if age_group_id>=10
local intercept = _b[_cons]
matrix b = e(b)
matrix V = e(V)
local bL = colsof(b)

noi di c(current_time) + ": regression complete"

		** get exposure draws
		noi di c(current_time) + ": get exposure draws for `risk'"

		get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') year_ids(`year_id') sex_ids(`sex_id') location_ids(`location_id') status(best) kwargs(draw_type:exposure) source(risk) clear

		cap drop modelable_entity_id

		noi di c(current_time) + ": exposure draws read"

		renpfix draw_ exp_
		fastrowmean exp*, mean_var_name(exp_mean)
		gen risk = "`risk'"
		tempfile E
		save `E', replace

		drawnorm b1-b`bL', double n(1000) means(b) cov(V) clear
		** shift from matrix column names to values
		forvalues i = 1/`bL' {
			local x = `i' - 1
			rename b`i' b`x'
		}
		local bL = `bL' - 1
		rename b0 coeff_
		keep coeff_ b`bL'
		gen n=_n
		replace n=n-1 // for draws labeled 0...999
		rename b`bL' intercept_
		gen risk = "`risk'"
		reshape wide coeff_ intercept_, i(risk) j(n)

		joinby risk using `E'

		forvalues i = 0/999 {
			gen exp_sd_`i' = exp(intercept_`i' + coeff_`i' * ln(exp_mean)) // y_hat = intercept_`i' + risk_slope_`i'*(mean of 1000 draws)
			rename exp_`i' exp_mean_`i'
			drop coeff_`i' intercept_`i'
		}

		save /ihme/epi/risk/paf/`risk'_interm/exp_`location_id'_`year_id'_`sex_id'.dta, replace
		tempfile exp
		save `exp', replace

		merge 1:m age_group_id using `rr', keep(3) nogen

		** maxrr
		gen maxrr=`cap'

			cap drop rei_id
			gen rei_id = `rei_id'
			merge m:1 rei_id using /ihme/epi/risk/paf/`risk'_sampled/global_sampled_200_mean.dta, keep(3) nogen
			forvalues i=0/999 {
				gen cap_`i' = .
					** maxvlaue
					replace cap_`i' = max_99_val_mean if cap_`i'==.
					replace cap_`i' = maxrr if maxrr<cap_`i'
			}
		
		** generate TMREL
		sort age_group_id cause_id modelable_entity_id mortality morbidity
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

			local FILE = "/ihme/epi/risk/paf/`risk'_interm/FILE_`location_id'_`year_id'_`sex_id'"
			outsheet using `FILE'.csv, comma replace

			noi di c(current_time) + ": begin PAF calc"

			noi di "minval: `minval'"
			noi di "maxval: `maxval'"
			noi di "rr_scalar: `rr_scalar'"
			noi di "exp dist: `f_dist'"
			noi di "inv exp: `inv_exp'"
			noi di "cap: `cap'"

			rsource using $j/temp/`username'/GBD_2015/risks/PAF_R_run_this_for_Rsource.R, rpath("/usr/local/bin/R") roptions(`" --vanilla --args "`minval'" "`maxval'" "`rr_scalar'" "`f_dist'" "`FILE'" "`inv_exp'" "') noloutput

			noi di c(current_time) + ": PAF calc complete"

			import delimited using `FILE'_OUT.csv, asdouble varname(1) clear

			** clean up the tempfiles
			erase `FILE'_OUT.csv
			erase `FILE'.csv

		cap drop rei_id
		gen rei_id = `rei_id'
		duplicates drop
		keep age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mortality morbidity paf*

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

} // end quiet loop











