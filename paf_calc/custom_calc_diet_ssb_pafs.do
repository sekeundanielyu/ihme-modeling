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

	local risk = "diet_ssb"
	local rei_id = 118
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
set seed 370566
local username = c(username)

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

merge 1:1 age_group_id using `1', keep(3) nogen
merge 1:1 age_group_id using `2', keep(3) nogen
merge 1:1 age_group_id using `m', keep(3) nogen

noi di c(current_time) + ": begin prevalence of obesity calc"
forvalues i = 0/999 {
	qui gen pr_`i' =  1 - ibeta(shape1_`i', shape2_`i',((25-mm_`i')/scale_`i'))
	qui drop shape1_`i' shape2_`i' mm_`i' scale_`i'
}
noi di c(current_time) + ": prevalence of obesity calc done"
preserve
egen mean = rowmean(pr_*)
keep location_id year_id sex_id age_group_id mean
order location_id year_id sex_id age_group_id mean
tempfile ob_prev
save `ob_prev'
restore
cap drop risk
gen risk = "`risk'"
tempfile bmi_beta
save `bmi_beta', replace
** insheet mediated shift
** BMI less than 25 and greater than 25 that apply to all demographics (ie 2 rows in this file)
insheet using "/share/gbd/WORK/05_risk/02_models/02_results/diet_ssb_mediated/rr/2/rr_G.csv", clear 
cap drop risk
gen risk = "`risk'"
gen group = "_1" if parameter == "less:25"
replace group = "_2" if parameter == "more:25"
keep group rr* risk
reshape wide rr_* , i(risk) j(group) string

joinby risk using `bmi_beta'

forvalues i = 0 / 999 {
	gen shft_`i' = pr_`i' * rr_`i'_2  + (1 - pr_`i') * rr_`i'_1
	drop rr_`i'_*
}

tempfile shift
save `shift',replace

** pull BMI RRs
noi di c(current_time) + ": pull BMI RRs"
get_draws, gbd_id_field(rei_id) gbd_id(108) location_ids(`location_id') status(best) kwargs(draw_type:rr) source(risk) clear

noi di c(current_time) + ": shift RRs"
joinby age_group_id sex_id year_id using `shift'
		forvalues i = 0 /999 {
		replace rr_`i' = rr_`i'^(shft_`i'/5)
}
cap drop risk
gen risk="`risk'"
cap mkdir /ihme/epi/risk/rr/`risk'_interm
drop pr* shft*

keep if year_id == `year_id'
keep if sex_id == `sex_id'
duplicates drop
outsheet using /ihme/epi/risk/rr/`risk'_interm/rr_`location_id'_`year_id'_`sex_id'.csv, comma replace

noi di c(current_time) + ": saved /ihme/epi/risk/rr/`risk'_interm/rr_`location_id'_`year_id'_`sex_id'.csv"

tempfile rr
save `rr', replace

/*
******************************************************************************************************************************************************************************************************************************************
PAF CALCULATION
******************************************************************************************************************************************************************************************************************************************
*/

cap get_demographics, gbd_team("epi") make_template clear
if _rc insheet using $j/temp/`username'/GBD_2015/risks/location.csv, clear
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
CONTINUOUS CALCULATION
******************************************************************************************************************************************************************************************************************************************
*/

			** pre-crosswalked data to use for diet
			use $j/WORK/05_risk/risks/diet_general/data/exp/compiler/diet_exp_optimized_xwalks_studycov_only.dta, clear
			rename mean meas_value
			encode(ihme_risk), gen(risk_enc)
			levelsof risk_enc if ihme_risk=="`risk'", local(REnc) c
			** drop if data is from FAO
			cap drop if cv_fao==1
			gen tag = .
				replace tag = 1 if diet_2==1
				replace tag = 1 if ihme_risk=="diet_salt" & (urine_2==1 | urine_2==2 | urine_2==3)
			keep if tag==1

			gen std_dev = standard_error * sqrt(sample_size)
			gen log_std_dev = log(std_dev)
			gen log_meas_value = log(meas_value)
			gen outlier = (std_dev / meas_value > 2) | (std_dev / meas_value < .1)
			drop if outlier==1
			merge m:1 location_id using `LOC', keep(3) nogen

		noi di c(current_time) + ": begin regression"
			noi regress log_std_dev log_meas_value i.risk_enc if age_start>=25

			local intercept = _b[_cons]
			matrix b = e(b)
			matrix V = e(V)
			local bL = colsof(b)

		noi di c(current_time) + ": regression complete"

		** get exposure draws
		noi di c(current_time) + ": get exposure draws"

		get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') year_ids(`year_id') sex_ids(`sex_id') location_ids(`location_id') status(best) kwargs(draw_type:exposure) source(risk) clear

		cap drop modelable_entity_id

		noi di c(current_time) + ": exposure draws read"

		renpfix draw_ exp_
		fastrowmean exp*, mean_var_name(exp_mean)
		gen risk_enc = `REnc'
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
		keep coeff_ b`REnc' b`bL'
		gen n=_n
		replace n=n-1 // for draws labeled 0...999
		rename b`REnc' b`REnc'_
		rename b`bL' intercept_
		gen risk_enc = `REnc'
		reshape wide b`REnc'_ coeff_ intercept_, i(risk_enc) j(n)

		joinby risk_enc using `E'

		forvalues i = 0/999 {
			gen exp_sd_`i' = exp(intercept_`i' + coeff_`i' * ln(exp_mean) + b`REnc'_`i') // y_hat = intercept_`i' + risk_slope_`i'*(mean of 1000 draws) + FE_risk_`i'
			rename exp_`i' exp_mean_`i'
			drop coeff_`i' b`REnc'_`i' intercept_`i'
		}

		save /ihme/epi/risk/paf/`risk'_interm/exp_`location_id'_`year_id'_`sex_id'.dta, replace
		tempfile exp
		save `exp', replace

		merge 1:m age_group_id using `rr', keep(3) nogen

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

		** maxrr
		gen maxrr=.
			replace maxrr=`cap' if `inv_exp'==0
			replace maxrr = `minval' if maxrr==. & `inv_exp'==1

			cap drop rei_id 
			gen rei_id = `rei_id'
			merge m:1 rei_id using /ihme/epi/risk/paf/`risk'_sampled/global_sampled_200_mean.dta, keep(3) nogen
			forvalues i=0/999 {
				gen cap_`i' = .
					** min value
					replace cap_`i' = min_1_val_mean if cap_`i'==. & `inv_exp'==1

					** max vlaue
					replace cap_`i' = max_99_val_mean if cap_`i'==. & `inv_exp'!=1
			}

			local FILE = "/ihme/epi/risk/paf/`risk'_interm/FILE_`location_id'_`year_id'_`sex_id'"
			outsheet using `FILE'.csv, comma replace

			noi di c(current_time) + ": begin PAF calc"


			noi rsource using $j/temp/`username'/GBD_2015/risks/PAF_R_run_this_for_Rsource.R, rpath("/usr/local/bin/R") roptions(`" --vanilla --args "`minval'" "`maxval'" "`rr_scalar'" "`f_dist'" "`FILE'" "`inv_exp'" "')

			noi di c(current_time) + ": PAF calc complete"

			import delimited using `FILE'_OUT.csv, asdouble varname(1) clear

			** clean up the tempfiles
			erase `FILE'_OUT.csv
			erase `FILE'.csv

			forvalues i = 0/1000 {
				cap rename V`i' v`i'
				cap rename v`i' paf_`i'
			}
			cap rename paf_1000 paf_0

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












