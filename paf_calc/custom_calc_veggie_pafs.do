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
	local rei_id 112
	local model_version_id "88734;88740" // legumes and veggies
	local location_id = 101
	local year_id = 2015
	local sex_id = 1
}

else if "`2'" !="" {
	local rei_id = "`1'"
	local model_version_id = "`2'"
	local location_id = "`3'"
	local year_id = "`4'"
	local sex_id = "`5'"
}

qui {
noi di c(current_time) + ": begin"

local risk = "diet_veg"
noi di "risk = `risk'"
noi di "rei_id = `rei_id'"
noi di "model_version_id = `model_version_id'"
noi di "location_id = `location_id'"
noi di "year_id = `year_id'"
noi di "sex_id = `sex_id'"

** check that moremata is installed
mata: a = 5
cap mata: a = mm_cond(a=5,0,a)
if _rc ssc install moremata

** Rsource
cap ssc install rsource
local username = c(username)
adopath + "$j/WORK/10_gbd/00_library/functions"
cap get_demographics, gbd_team("epi") make_template clear
if _rc insheet using $j/temp/`username'/GBD_2015/risks/location.csv, clear
keep location_id location_name *region*
duplicates drop

tempfile LOC
save `LOC', replace

import excel using $j/temp/`username'/GBD_2015/risks/risk_variables.xlsx, firstrow clear

keep if risk=="diet_veg"
levelsof maxval, local(maxval) c
levelsof minval, local(minval) c
levelsof inv_exp, local(inv_exp) c
levelsof rr_scalar, local(rr_scalar) c
levelsof calc_type, local(f_dist) c
levelsof tmred_para1, local(tmred_1) c
levelsof tmred_para2, local(tmred_2) c
levelsof calc_type, local(f_dist) c
levelsof maxrr, local(cap) c

		** pre-crosswalked data to use for diet
			use $j/WORK/05_risk/risks/diet_general/data/exp/compiler/diet_exp_optimized_xwalks_studycov_only.dta, clear
			rename mean meas_value
			encode(ihme_risk), gen(risk_enc)
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

			** 2442 = veggies
			** 2432 = legumes
			levelsof risk_enc if ihme_risk=="diet_veg", local(REnc2442) c
			levelsof risk_enc if ihme_risk=="diet_legumes", local(REnc2432) c			

			local intercept = _b[_cons]
			matrix b = e(b)
			matrix V = e(V)
			local bL = colsof(b)

	noi di c(current_time) + ": regression complete"

** get exposure draws
noi di c(current_time) + ": pull exposures for veggies and legumes"

local n = 0
** MEs for veggie and legumes
foreach me in 2442 2432 {
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(`me') location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') status(best) source(epi) clear
		renpfix draw_ exp_
		fastrowmean exp*, mean_var_name(exp_mean)

		gen risk_enc = `REnc`me''
		tempfile E
		save `E', replace

		drawnorm b1-b`bL', double n(1000) means(b) cov(V) clear
		** shift from matrix column names to values
		forvalues i = 1/`bL' {
			local x = `i' - 1
			rename b`i' b`x'
		}
		local bLshift = `bL' - 1
		rename b0 coeff_
		keep coeff_ b`REnc`me'' b`bLshift'
		gen n=_n
		replace n=n-1 // for draws labeled 0...999
		rename b`REnc`me'' b`REnc`me''_
		rename b`bLshift' intercept_
		gen risk_enc = `REnc`me''
		reshape wide b`REnc`me''_ coeff_ intercept_, i(risk_enc) j(n)

		joinby risk_enc using `E'

		forvalues i = 0/999 {
			gen exp_sd_`i' = exp(intercept_`i' + coeff_`i' * ln(exp_mean) + b`REnc`me''_`i') // y_hat = intercept_`i' + risk_slope_`i'*(mean of 1000 draws) + FE_risk_`i'
			rename exp_`i' exp_mean_`i'
			drop coeff_`i' b`REnc`me''_`i' intercept_`i'
		}


	local n = `n' + 1
	tempfile `n'
	save ``n'', replace
}

clear
forvalues i = 1/`n' {
	append using ``i''
}

** SD to variance to sum legumes + veggies
forvalues i = 0/999 {
	replace exp_sd_`i' = (exp_sd_`i')^2
}
		
fastcollapse exp*, type(sum) by(location_id year_id age_group_id sex_id)
	
** Variance to SDs
forvalues i = 0/999 {
	replace exp_sd_`i' = sqrt(exp_sd_`i')
}

save /ihme/epi/risk/paf/`risk'_interm/exp_`location_id'_`year_id'_`sex_id'.dta, replace

tempfile exp
save `exp', replace

** get RRs
noi di c(current_time) + ": get relative risk draws"
get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') location_ids(`location_id') status(best) kwargs(draw_type:rr) source(risk) clear
noi di c(current_time) + ": relative risk draws read"

keep if year_id == `year_id'
keep if sex_id == `sex_id'
merge m:1 age_group_id using `exp', keep(3) nogen

** maxrr
gen maxrr=`minval'
cap drop rei_id 
gen rei_id = `rei_id'

			merge m:1 rei_id using /ihme/epi/risk/paf/`risk'_sampled/global_sampled_200_mean.dta, keep(3) nogen
			forvalues i=0/999 {
				gen cap_`i' = .
					** min value
					replace cap_`i' = min_1_val_mean if `inv_exp'==1

			}

** generate TMREL
sort age_group_id cause_id modelable_entity_id mortality morbidity
forvalues i = 0/999 {
	qui gen double tmred_mean_`i' = ((`tmred_2'-`tmred_1')*runiform() + `tmred_1')
}

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

			rsource using $j/temp/`username'/GBD_2015/risks/PAF_R_run_this_for_Rsource.R, rpath("/usr/local/bin/R") roptions(`" --vanilla --args "`minval'" "`maxval'" "`rr_scalar'" "`f_dist'" "`FILE'" "`inv_exp'" "') noloutput

			noi di c(current_time) + ": PAF calc complete"

			import delimited using `FILE'_OUT.csv, asdouble varname(1) clear
			
			** clean up the tempfiles
			erase `FILE'_OUT.csv
			erase `FILE'.csv

** save PAFs
cap drop rei_id
gen rei_id = `rei_id'

keep age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mortality morbidity paf*

** expand mortliaty and morbidity
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
					
		outsheet age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id paf* using "/share/epi/risk/paf/diet_veg_interm/paf_`mmm_string'_`location_id'_`year_id'_`sex_id'.csv" if year_id == `year_id' & sex_id == `sex_id' & mortality == `mmm', comma replace

		no di "saved: /share/epi/risk/paf/diet_veg_interm/paf_`mmm_string'_`location_id'_`year_id'_`sex_id'.csv"
	}

noi di c(current_time) + ": DONE!"


} // end quite loop






