** Central PAF calculator for GBD 2015
** Parallelized by location/year/sex
qui {

clear all
pause on
cap set maxvar 32767, perm
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

	local risk = "diet_procmeat"
	local rei_id = 117
	local location_id = 101
	local year_id = 2015
	local sex_id = 1
	local model_version_id = 84182

}

else if "`2'" !="" {
	local risk = "`1'"
	local rei_id = "`2'"
	local location_id = "`3'"
	local year_id = "`4'"
	local sex_id = "`5'"
	local model_version_id = "`6'"
	local epi = "`7'"
	local cod = "`8'"
}

noi di c(current_time) + ": begin"

noi di "risk = `risk'"
noi di "rei_id = `rei_id'"
noi di "location_id = `location_id'"
noi di "year_id = `year_id'"
noi di "sex_id = `sex_id'"
noi di "model_version_id = `model_version_id'"

cap mkdir /ihme/epi/risk/paf/`risk'_interm

** check that moremata is installed
mata: a = 5
cap mata: a = mm_cond(a=5,0,a)
if _rc ssc install moremata

** install Rsource
cap ssc install rsource

adopath + "$j/WORK/10_gbd/00_library/functions"
qui do $j/WORK/05_risk/central/code/risk_utils/risk_info.ado
** load categorical PAF function
local username = c(username)
run $j/temp/`username'/GBD_2015/risks/paf_calc_categ.do
cap get_demographics, gbd_team("epi") make_template clear
if _rc insheet using $j/temp/`username'/GBD_2015/risks/location.csv, clear
keep location_id location_name *region*
duplicates drop

tempfile LOC
save `LOC', replace

** maybe add as locals in master script
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

if "`risk_type'" == "2" {
		cap import delimited using /share/epi/panda_cascade/prod/`model_version_id'/full/data.csv, asdouble varname(1) clear
		if _rc==0 local dismod = 1
		else local dismod = 0

	if `dismod'== 1 {
	if regexm("`risk'","diet")==0 {
			** drop if data is from FAO
			cap drop if cv_fao==1

		cap destring a_data_id, replace

		rename meas_stdev standard_error
		preserve
			levelsof a_data_id, local(data_ids) sep(,) clean
			clear
			odbc load, exec("SELECT sample_size, input_data_key AS a_data_id FROM input_data_audit WHERE input_data_key IN (`data_ids')") dsn(epi) clear
			cap destring a_data_id, replace
			tempfile sample_size
			save `sample_size', replace
		restore
			merge 1:1 a_data_id using `sample_size', assert(3) nogen

	}

	else if `dismod'==1 & regexm("`risk'","diet")==1 {
			** pre-crosswalked data to use for diet
			use $j/WORK/05_risk/risks/diet_general/data/exp/compiler/diet_exp_optimized_xwalks_studycov_only.dta, clear
			rename mean meas_value
			** keep if ihme_risk=="`risk'"
			encode(ihme_risk), gen(risk_enc)
			levelsof risk_enc if ihme_risk=="`risk'", local(REnc) c
			** drop if data is from FAO
			cap drop if cv_fao==1

			** study level CV to keep for regression
			gen tag = .
				replace tag = 1 if diet_2==1
				replace tag = 1 if ihme_risk=="diet_salt" & (urine_2==1 | urine_2==2 | urine_2==3)
			keep if tag==1

	}
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
	} // end if dismod loop

	** now metabolic
	if `dismod'!=1 & regexm("`risk'","metab_")==1 {
	local p = 0
	noi di c(current_time) + ": begin regression"
	foreach risky in metab_fpg_cont metab_cholesterol metab_sbp {
	clear

	if "`risky'"=="metab_fpg_cont" local risky "metab_fpg"

			clear
			set obs 100
			gen file = ""
			local fs : dir "/share/covariates/ubcov/04_model/`risky'/_data" files "*dta", respectcase
			local row = 0
			foreach f of local fs {
				local row = `row' + 1
				replace file = "`f'" in `row'
			}
			drop if file==""
			replace file = subinstr(file,".dta","",.)
			destring file, replace
			gsort -file
			levelsof file in 1, local(my_file) c
			use /share/covariates/ubcov/04_model/`risky'/_data/`my_file'.dta, clear
			cap drop risk
			gen risk = "`risky'"
			replace risk = "metab_fpg_cont" if risk=="metab_fpg"

	local p = `p'+1
	tempfile `p'
	save ``p'', replace
	}

	clear
	forvalues i = 1/`p' {
		append using ``i''
	}

			rename data meas_value
			rename standard_deviation std_dev
			drop if std_dev==.

			gen log_std_dev = log(std_dev)
			gen log_meas_value = log(meas_value)
			gen outlier = (std_dev / meas_value > 2) | (std_dev / meas_value < .1)
			drop if outlier==1

	tempfile most
	save `most', replace

	** BMD
	odbc load, exec("SELECT model_version_id FROM model_version LEFT JOIN modelable_entity USING (modelable_entity_id) WHERE modelable_entity_name='Low bone mineral density mean' AND is_best=1") dsn(epi) clear
	levelsof model_version_id, local(BoneM) c
	import delimited using /share/epi/panda_cascade/prod/`BoneM'/full/data.csv, asdouble varname(1) clear
	cap drop risk
	gen risk = "metab_bmd"
		cap destring a_data_id, replace

		rename meas_stdev standard_error
		preserve
			levelsof a_data_id, local(data_ids) sep(,) clean
			clear
			odbc load, exec("SELECT effective_sample_size as sample_size, input_data_key AS a_data_id FROM input_data_audit WHERE input_data_key IN (`data_ids')") dsn(epi) clear
			cap destring a_data_id, replace
			tempfile sample_size
			save `sample_size', replace
		restore
			merge 1:1 a_data_id using `sample_size', assert(3) nogen

			gen std_dev = standard_error * sqrt(sample_size)
			gen log_std_dev = log(std_dev)
			gen log_meas_value = log(meas_value)
			gen outlier = (std_dev / meas_value > 2) | (std_dev / meas_value < .1)
			drop if outlier==1

		append using `most'
		rename risk ihme_risk

		encode(ihme_risk), gen(risk_enc)

			levelsof risk_enc if ihme_risk=="`risk'", local(REnc) c
			noi regress log_std_dev log_meas_value i.risk_enc if age_start>=25
			local intercept = _b[_cons]
			matrix b = e(b)
			matrix V = e(V)
			local bL = colsof(b)

	} // now end non dismod continuous loop; mostly metabolics loop

	** begin if diet calcium loop
	if "`risk'" == "diet_calcium" {
		noi di c(current_time) + ": get exposure draws"
		get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') year_ids(`year_id') sex_ids(`sex_id') location_ids(`location_id') status(best) kwargs(draw_type:exposure) source(risk) clear

		** make sure the exposure ME is dropped if pulled since when we merge on relative risks, some have YLD specific MEs
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

		** save exposure with SD for SEV
		save /ihme/epi/risk/paf/`risk'_interm/exp_`location_id'_`year_id'_`sex_id'.dta, replace
		tempfile exp
		save `exp', replace

		** get RRs & calculate PAFs for diet low in calcium and high in calcium
		foreach child in diet_calcium_low diet_calcium_high {
		** pull meta-data
				import excel using $j/temp/`username'/GBD_2015/risks/risk_variables.xlsx, firstrow clear

				keep if risk=="`child'"
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

			** pull rei for respective low and high
			risk_info, risk(`child') clear
			levelsof risk_id, local(R) c

			noi di c(current_time) + ": get relative risk draws for `child'"
			get_draws, gbd_id_field(rei_id) gbd_id(`R') location_ids(`location_id') status(best) kwargs(draw_type:rr) source(risk) clear

			gen maxrr = .
				replace maxrr = 2.25 if cause_id==438 & "`child'"=="diet_calcium_high" // max from paper
				replace maxrr = `cap' if maxrr==. & `inv_exp'!=1
				replace maxrr = `minval' if maxrr==. & `inv_exp'==1

			cap drop rei_id 
			gen rei_id = `rei_id'
			merge m:1 rei_id using /ihme/epi/risk/paf/`risk'_sampled/global_sampled_200_mean.dta, keep(3) nogen
			forvalues i=0/999 {
				gen cap_`i' = .
					** min value
					replace cap_`i' = min_1_val_mean if `inv_exp'==1
					** max value
					replace cap_`i' = max_99_val_mean if `inv_exp'!=1
					replace cap_`i' = maxrr if maxrr<cap_`i' & `inv_exp'!=1
			}

			noi di c(current_time) + ": relative risk draws read for `child'"
			cap destring year_id, replace
			cap destring sex_id, replace
			cap destring age_group_id, replace
			cap destring location_id, replace
			keep if year_id == `year_id'
			keep if sex_id == `sex_id'
			merge m:1 age_group_id using `exp', keep(3) nogen

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

			local FILE = "/ihme/epi/risk/paf/`risk'_interm/FILE_`child'_`location_id'_`year_id'_`sex_id'"

			outsheet using `FILE'.csv, comma replace

			noi di c(current_time) + ": begin PAF calc for `child'"

			rsource using $j/temp/`username'/GBD_2015/risks/PAF_R_run_this_for_Rsource.R, rpath("/usr/local/bin/R") roptions(`" --vanilla --args "`minval'" "`maxval'" "`rr_scalar'" "`f_dist'" "`FILE'" "`inv_exp'" "') noloutput

			noi di c(current_time) + ": PAF calc complete for `child'"

		} // end both calcium child calculations

	} // end of diet calcium loop

	** begin if PUFA loop to calculate custom TMREL
	** bring in PUFA and saturated fat models and combine

	if "`risk'"=="diet_pufa" {
			noi di c(current_time) + ": prep TMREL PUFA"

			** get draws pulls both the saturated and polyunsaturated fat models if source type is risk....
			** 2436 is the ME for PUFA
			get_draws, gbd_id_field(modelable_entity_id) gbd_id(2436) location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') status(best) source(epi) clear
			tempfile PUFA
			save `PUFA', replace

			get_draws, gbd_id_field(modelable_entity_id) gbd_id(2439) location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') status(best) source(epi) clear
			
			forvalues i = 0/999 {
				gen shift_`i' = draw_`i' - .07
				drop draw_`i'
			}

			merge 1:1 age_group_id using `PUFA', keep(3) nogen

			forvalues i = 0/999 {
				replace draw_`i' = .12 - shift_`i' if shift_`i'>=0 & shift_`i'!=.
				rename draw_`i' tmred_mean_`i'
			}
			drop shift*
			tempfile tmrel_pufa
			save `tmrel_pufa', replace

		use `PUFA', clear
		cap drop modelable_entity_id

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

		** get RRs
		noi di c(current_time) + ": get relative risk draws"

		get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') location_ids(`location_id') status(best) kwargs(draw_type:rr) source(risk) clear
		noi di c(current_time) + ": relative risk draws read"
		cap destring year_id, replace
		cap destring sex_id, replace
		cap destring age_group_id, replace
		cap destring location_id, replace
		keep if year_id == `year_id'
		keep if sex_id == `sex_id'

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
					replace cap_`i' = min_1_val_mean if `inv_exp'==1
					** max value
					replace cap_`i' = max_99_val_mean if `inv_exp'!=1
					replace cap_`i' = maxrr if maxrr<cap_`i' & `inv_exp'!=1
			}

		merge m:1 age_group_id using `exp', keep(3) nogen

		** merge on TMREL
		merge m:1 age_group_id using `tmrel_pufa', keep(3) nogen

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


	} // end of diet PUFA loop

	if "`risk'"!="diet_calcium" & "`risk'"!="diet_pufa" {

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


		** convert omega 3s from grams to milligrams
		if "`risk'"=="diet_fish" {
			forvalues i = 0/999 {
				replace exp_mean_`i' = exp_mean_`i' * 1000
				replace exp_sd_`i' = exp_sd_`i' * 1000
			}
		}

		if "`risk'"=="metab_sbp" {
			merge 1:1 age_group_id using $j/temp/`username'/sbp_correction.dta, keep(3) nogen
			forvalues i = 0/999 {
				replace exp_sd_`i' = exp_sd_`i' * ratio
			}

			drop ratio age	
		}

		save /ihme/epi/risk/paf/`risk'_interm/exp_`location_id'_`year_id'_`sex_id'.dta, replace
		tempfile exp
		save `exp', replace

		** get RRs
		noi di c(current_time) + ": get relative risk draws"
		get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') location_ids(`location_id') status(best) kwargs(draw_type:rr) source(risk) clear
		noi di c(current_time) + ": relative risk draws read"
		cap destring year_id, replace
		cap destring sex_id, replace
		cap destring age_group_id, replace
		cap destring location_id, replace
		keep if year_id == `year_id'
		keep if sex_id == `sex_id'

		** rr cap - some values from studies
		gen maxrr = .
			replace maxrr = 100 if cause_id==587 & "`risk'"=="diet_redmeat"
			replace maxrr = 174 if cause_id==441 & "`risk'"=="diet_redmeat"
			replace maxrr = 50 if cause_id==441 & "`risk'"=="diet_procmeat"
			replace maxrr = 54 if cause_id==587 & "`risk'"=="diet_procmeat"
			replace maxrr = 17 if cause_id==493 & "`risk'"=="diet_procmeat"
			replace maxrr = .03 if cause_id==493 & "`risk'"=="diet_transfat"
			replace maxrr = `cap' if maxrr==. & `inv_exp'==0
			replace maxrr = `minval' if maxrr==. & `inv_exp'==1

			cap drop rei_id 
			gen rei_id = `rei_id'
			merge m:1 rei_id using /ihme/epi/risk/paf/`risk'_sampled/global_sampled_200_mean.dta, keep(3) nogen
			forvalues i=0/999 {
				gen cap_`i' = .
					** min value
					replace cap_`i' = min_1_val_mean if `inv_exp'==1
					** max value
					replace cap_`i' = max_99_val_mean if `inv_exp'!=1
					replace cap_`i' = maxrr if maxrr<cap_`i' & `inv_exp'!=1
			}

		merge m:1 age_group_id using `exp', keep(3) nogen

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


	} // end if not diet_calcium or PUFA now continue to saving PAFs

	if "`risk'"=="diet_calcium" {
		local x = 0
		foreach child in diet_calcium_low diet_calcium_high {
				import delimited using /share/epi/risk/paf/diet_calcium_interm/FILE_`child'_`location_id'_`year_id'_`sex_id'_OUT.csv, asdouble varname(1) clear
				local x = `x' + 1
				tempfile `x'
				save ``x'', replace
				
				cap erase /share/epi/risk/paf/diet_calcium_interm/FILE_`child'_`location_id'_`year_id'_`sex_id'_OUT.csv
				cap erase /share/epi/risk/paf/diet_calcium_interm/FILE_`child'_`location_id'_`year_id'_`sex_id'.csv
	
		}
		clear
		forvalues i = 1/`x' {
			append using ``i''
		}
		cap drop rei_id
		gen rei_id = `rei_id'
	}

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

noi di c(current_time) + ": DONE!"
} // end continuous loop

/*
******************************************************************************************************************************************************************************************************************************************
CATEGORICAL CALCULATION
******************************************************************************************************************************************************************************************************************************************
*/
if "`risk_type'"=="1" {
		noi di c(current_time) + ": get exposure draws"
		** smoking is five year lagged
		if "`risk'"=="smoking_direct_prev" local year_id = `year_id' - 5

		get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') year_ids(`year_id') sex_ids(`sex_id') location_ids(`location_id') status(best) kwargs(draw_type:exposure) source(risk) clear

		if "`risk'"=="smoking_shs" {

			if "`sex_id'"=="1" {
				** male model - drop child estimate
				get_draws, gbd_id_field(modelable_entity_id) gbd_id(2512) location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') status(best) source(epi)clear
				gen parameter="cat1"
				drop if age_group_id<=7
				tempfile male
				save `male', replace
			
				** append male child results from female model
				get_draws, gbd_id_field(modelable_entity_id) gbd_id(9419) location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') status(best) source(epi)clear
				gen parameter="cat1"
				keep if age_group_id<=7
				append using `male'
			}
				** female model for all ages
				else if "`sex_id'"=="2" {
				get_draws, gbd_id_field(modelable_entity_id) gbd_id(9419) location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') status(best) source(epi)clear
				gen parameter="cat1"
				}

			fastcollapse draw*, type(sum) by(location_id year_id age_group_id sex_id) append flag(dup)
			replace parameter = "cat2" if dup == 1
			forvalues i = 0/999 {
				replace draw_`i' = 1 - draw_`i' if dup == 1
			}
			drop dup

		}

		if "`risk'"=="smoking_direct_prev" {
			** smoking prevalence is 5 year lagged
			local year_id = `year_id' + 5
			replace year_id = year_id + 5
			replace age_group_id = age_group_id + 1
		}

		** make sure the exposure ME is dropped if pulled since when we merge on relative risks, some have YLD specific MEs
		renpfix draw_ exp_
		cap drop modelable_entity_id

		noi di c(current_time) + ": exposure draws read"

		tempfile exp
		save `exp', replace

		** get RRs
		noi di c(current_time) + ": get relative risk draws"
		get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') location_ids(`location_id') status(best) kwargs(draw_type:rr) source(risk) clear
		duplicates drop
		** expand mortliaty and morbidity
		expand 2 if mortality == 1 & morbidity == 1, gen(dup)
		replace morbidity = 0 if mortality == 1 & morbidity == 1 & dup == 0
		replace mortality = 0 if mortality == 1 & morbidity == 1 & dup == 1
		drop dup
		duplicates drop
		noi di c(current_time) + ": relative risk draws read"
		cap destring year_id, replace
		cap destring sex_id, replace
		cap destring age_group_id, replace
		cap destring location_id, replace
		keep if year_id == `year_id'
		keep if sex_id == `sex_id'
		if "`risk'"=="abuse_ipv_exp" {
			tempfile R
			save `R', replace
		}
		merge m:1 age_group_id parameter year_id using `exp', keep(3) assert(2 3) nogen

		** apply proportion of victims of lifetime physical or sexual IPV that have experienced IPV in the last 12 months, by age to abuse_ipv_exp for maternal abortion
		if "`risk'"=="abuse_ipv_exp" {
				joinby age_group_id using $j/temp/`username'/abuse_ipv_exp_proportion_current.dta, unmatched(master)
				cap drop _merge
				keep if cause_id==371
				forvalues i = 0/999 {
					qui replace exp_`i' = exp_`i' * fraction_`i' if fraction_`i'!=.
				}
				drop if parameter=="cat2"
				drop fraction*
				drop cause_id mortality morbidity
				duplicates drop
				expand 2, gen(dup)
				replace parameter = "cat2" if dup == 1
					forvalues i = 0/999 {
						replace exp_`i' = 1 - exp_`i' if dup == 1
					}
				drop dup
				gen cause_id = 371
				gen mortality=1
				gen morbidity=1
				tempfile ab
				save `ab', replace
			}
		if "`risk'"=="abuse_ipv_exp" {
			use `R', clear
			merge m:1 age_group_id parameter year_id using `exp', keep(3) assert(2 3) nogen
			drop if cause_id==371
			append using `ab'
		}

		** generate TMREL
		levelsof parameter, c
		local L : word count `r(levels)'

		forvalues i = 0/999 {
			qui gen tmrel_`i' = 0
			replace tmrel_`i' = 1 if parameter=="cat`L'"
		}

		noi di c(current_time) + ": calc PAFs"
		cap drop rei_id
		gen rei_id = `rei_id'

		calc_paf_categ exp_ rr_ tmrel_ paf_, by(age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mortality morbidity)

		noi di c(current_time) + ": PAF calc complete"

		** save PAFs
		** these go into an intermediate directory
		** then they go through save results and are moved
		keep age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mortality morbidity paf*

		** make sure we expand causes to the most detailed level
		rename cause_id ancestor_cause
		joinby ancestor_cause using "$j/temp/`username'/GBD_2015/risks/cause_expand.dta", unmatched(master)
		replace ancestor_cause = descendant_cause if ancestor_cause!=descendant_cause & descendant_cause!=. // if we have a no match for a sequelae
		drop descendant_cause _merge
		rename ancestor_cause cause_id

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

		** smoking injuries adjustment
		if "`risk'"=="smoking_direct_prev" {
			noi di c(current_time) + ": begin smoking injuries comp"
			noi do $j/temp/`username'/GBD_2015/risks/custom_calc_smoking_injuries.do `risk' `rei_id' `location_id' `year_id' `sex_id' `epi' `cod'
			noi di c(current_time) + ": smoking injury calc done"
		}

noi di c(current_time) + ": DONE!"

} // end categorical loop

} // end quite loop




