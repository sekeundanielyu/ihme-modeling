clear all
cap set maxvar 32767, perm
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

** Random.org set seed for consistent TMRELs
set seed 370566

if "`2'" == "" {

	local risk = "metab_bmd"
	local rei_id = 109
	local location_id = 44545
	local year_id = 2015
	local sex_id = 2
	local model_version_id = 60677
	local epi = 94
	local cod = 41

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

qui {

noi di c(current_time) + ": begin"
noi di "risk = `risk'"
noi di "rei_id = `rei_id'"
noi di "location_id = `location_id'"
noi di "year_id = `year_id'"
noi di "sex_id = `sex_id'"
noi di "model_version_id = `model_version_id'"
noi di "COMO = `epi'"
noi di "COD = `cod'"

local epi_dir "/ihme/centralcomp/como/`epi'/draws/cause/total_csvs"
local cod_dir "/share/central_comp/codcorrect/`cod'/draws"

cap mkdir /ihme/epi/risk/paf/`risk'_interm

** check that moremata is installed
mata: a = 5
cap mata: a = mm_cond(a=5,0,a)
if _rc ssc install moremata

local username = c(username)

** install Rsource
cap ssc install rsource

adopath + "$j/WORK/10_gbd/00_library/functions"
run $j/WORK/10_gbd/00_library/functions/get_draws.ado
qui do $j/WORK/05_risk/central/code/risk_utils/risk_info.ado
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

		** pul exposure
		noi di c(current_time) + ": get exposure draws"

		get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') year_ids(`year_id') sex_ids(`sex_id') location_ids(`location_id') status(best) kwargs(draw_type:exposure) source(risk) clear

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

		** get RRs
		noi di c(current_time) + ": get relative risk draws"
		qui do "$j/WORK/2013/05_risk/03_outputs/01_code/02_paf_calculator/functions_expand.ado"

		insheet using /share/gbd/WORK/05_risk/02_models/02_results/metab_bmd/rr/3/rr_G.csv, comma double clear

		sex_expand sex
		age_expand gbd_age_start gbd_age_end, gen(age)	
		tostring age, replace force format(%12.3f)
		destring age, replace force
		tempfile r
		save `r', replace

		clear
		cap odbc load, exec("select age_group_id, age_data as age from age_groups where age_data is not NULL") `new_halem'
		if _rc insheet using $j/temp/`username'/GBD_2015/risks/age_group_id_merge.csv, clear
		tostring age, replace force format(%12.3f)
		destring age, replace force
		tempfile ages
		save `ages', replace
		merge 1:m age using `r', keep(3) nogen
		rename sex sex_id
		rename year year_id
		keep if sex_id == `sex_id'
		merge m:1 age_group_id using `exp', keep(3) nogen

		tempfile 1
		save `1', replace

		** merge TMREL
		insheet using /share/gbd/WORK/05_risk/02_models/02_results/metab_bmd/tmred/4/tmred_G.csv, comma double clear
		sex_expand sex
		age_expand gbd_age_start gbd_age_end, gen(age)	
		tostring age, replace force format(%12.3f)
		destring age, replace force
		merge m:1 age using `ages', keep(3) nogen
		rename sex sex_id
		rename year year_id
		keep if sex_id == `sex_id'
		duplicates drop
		cap drop if parameter=="sd"
		cap drop parameter
		merge 1:m age_group_id year_id sex_id using `1', keep(3) nogen

		renpfix tmred_ tmred_mean_

		** maxrr
		gen maxrr=`cap'

			cap merge m:1 rei_id using /ihme/epi/risk/paf/`risk'_sampled/global_sampled_200.dta, keep(3) nogen
			if _rc cap merge m:1 rei_id using /ihme/epi/risk/paf/`risk'_sampled/global_sampled_200_mean.dta, keep(3) nogen
			forvalues i=0/999 {
				gen cap_`i' = .
					** min value
					cap replace cap_`i' = min_1_val_draw_`i' if `inv_exp'==1
					cap replace cap_`i' = min_1_val_mean if cap_`i'==. & `inv_exp'==1
					replace cap_`i' = `minval' if cap_`i'==. & `inv_exp'==1

					** maxvlaue
					cap replace cap_`i' = max_99_val_draw_`i' if `inv_exp'!=1
					cap replace cap_`i' = max_99_val_mean if cap_`i'==. & `inv_exp'!=1
					replace cap_`i' = maxrr if maxrr<cap_`i' & `inv_exp'!=1
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

		keep age_group_id rei_id location_id sex_id year_id acause mortality morbidity paf*
		order age_group_id rei_id location_id sex_id year_id acause mortality morbidity
		save /ihme/epi/risk/paf/`risk'_interm/paf_`location_id'_`year_id'_`sex_id'.dta, replace
		tempfile P
		save `P', replace

** apply fractions
import excel using $j/WORK/2013/05_risk/02_models/02_results/metab_bmd/Matrix.xlsx, firstrow clear sheet("Matrix for YLD")
keep if inlist(acause,"inj_trans_road_pedest","inj_trans_road_pedal","inj_trans_road_2wheel","inj_trans_road_4wheel","inj_trans_road_other","inj_trans_other","inj_falls") | inlist(acause,"inj_mech_other","inj_animal_nonven","inj_homicide_other","inj_disaster")

reshape long N, i(acause) j(healthstate) string
rename acause inj
replace healthstate = "N" + healthstate
rename N acause
replace acause="hip" if acause=="Hip PAF"
replace acause="non-hip" if acause=="non-hip PAF"
gen morbidity=1
levelsof healthstate, local(H)
levelsof inj, local(acause) c
tempfile yld
save `yld', replace

local x = 0
foreach a of local acause {
	odbc load, exec("SELECT cause_id, acause as inj FROM shared.cause WHERE acause LIKE '`a''") dsn(epi) clear
	local x = `x' + 1
	tempfile `x'
	save ``x'', replace
}

clear
forvalues i = 1/`x' {
	append using ``i''
}

joinby inj using `yld'
tempfile yld
save `yld', replace

levelsof cause_id, local(C) c
levelsof cause_id, local(CAUSES) c sep(,)

keep cause_id acause
duplicates drop
tempfile C
save `C', replace

import delimited using "`epi_dir'/3_`location_id'_`year_id'_`sex_id'.csv", asdouble varname(1) clear

** some draws are strings
forvalues i = 0/999 {
	qui cap replace draw_`i' = "0" if draw_`i'=="NA"
	qui cap replace draw_`i' = "0" if draw_`i'=="."
	qui cap destring draw_`i', force replace
}

tempfile epi
save `epi', replace
keep if inlist(cause_id,`CAUSES')
tempfile EPI
save `EPI', replace

joinby cause_id using `yld'

tempfile m
save `m', replace

insheet using /share/injuries/04_COMO_input/01_NE_matrix/NEmatrix_`location_id'_`year_id'_`sex_id'.csv, clear
if "`sex_id'"=="1" gen sex_id=1
else if "`sex_id'"=="2" gen sex_id=2
gen year_id = `year_id'
rename ncode healthstate
rename ecode inj
renpfix draw_ matrix_
tempfile ne
save `ne', replace

renpfix matrix_ prop_

** merge on COMO YLDs and YLD matrix (inj is inj_falls etc, healthstate is N code)
joinby age_group_id healthstate inj year_id sex_id using `m'

** merge PAF
joinby age_group_id acause using `P'

gen matrix = 1

** merge on total matrix to re-scale proportions to COMO output
joinby age_group_id healthstate inj year_id sex_id using `ne', unmatched(using)

forvalues i = 0/999 {
	cap replace draw_`i' = "0" if draw_`i'=="NA"
	cap replace paf_`i' = "0" if paf_`i'=="NA"
	cap replace prop_`i' = "0" if prop_`i'=="NA"
	cap replace matrix_`i' = "0" if matrix_`i'=="NA"
	cap destring draw_`i', force replace
	cap destring paf_`i', force replace
	cap destring prop_`i', force replace
	cap destring matrix_`i', force replace
	replace draw_`i' = 0 if draw_`i'==.
	replace paf_`i' = 0 if paf_`i'==.
	replace prop_`i' = 0 if prop_`i'==.
	replace matrix_`i' = 0 if matrix_`i'==.
	** carryforward draw
	bysort age_group_id sex_id inj: egen total = max(draw_`i')
	replace draw_`i' = total
	drop total
	** re-scale matrix inputs
	bysort age_group_id sex_id inj: egen total = total(matrix_`i')
	replace prop_`i' = (matrix_`i' * draw_`i')/total
	replace draw_`i' = (paf_`i' * prop_`i')
	drop total
}

keep if matrix==1

fastcollapse draw*, type(sum) by(cause_id age_group_id year_id sex_id)

gen risk = "metab_bmd"
tempfile r
save `r', replace

append using `EPI'

keep year_id sex_id cause_id age_group_id risk draw*
gen denominator = .
replace denominator = (risk == "")
fastfraction draw*, by(year_id sex_id cause_id age_group_id) denominator(denominator) prefix(paf_) 
keep if risk=="metab_bmd"
keep year_id sex_id cause_id age_group_id risk paf*
renpfix paf_draw_ paf_

cap gen modelable_entity_id=.
cap gen rei_id = `rei_id'
cap gen location_id = `location_id'

outsheet age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id paf* using "/ihme/epi/risk/paf/`risk'_interm/paf_yld_`location_id'_`year_id'_`sex_id'.csv", comma replace

noi di c(current_time) + ": YLD PAFs saved: /ihme/epi/risk/paf/`risk'_interm/paf_yld_`location_id'_`year_id'_`sex_id'.csv"

** prep YLLs
use `P', clear
joinby age_group_id sex_id acause using $j/WORK/05_risk/risks/metab_bmd/gbd2015_proportions_of_hospital_deaths.dta

keep if inlist(inj,"inj_trans_road_pedest","inj_trans_road_pedal","inj_trans_road_2wheel","inj_trans_road_4wheel","inj_trans_road_other","inj_trans_other","inj_falls") | inlist(inj,"inj_mech_other","inj_animal_nonven","inj_homicide_other","inj_disaster")
duplicates drop
tempfile f
save `f', replace

clear
odbc load, exec("SELECT acause as inj, cause_id FROM cause") `shared_string'
tempfile causes
save `causes', replace

use "`cod_dir'/death_`location_id'_`year_id'.dta", clear
keep if sex_id==`sex_id'
keep if inlist(cause_id,`CAUSES')

cap renpfix death draw
keep age_group_id sex_id cause_id draw*
gen location_id = `location_id'
gen year_id = `year_id'

foreach var of varlist draw* {
qui replace `var' = 0 if `var' == .
}

merge m:1 cause_id using `causes', keep(3) nogen
tempfile cod
save `cod', replace

joinby inj age_group_id sex_id using `f'

forvalues i = 0/999 {
	replace draw_`i' = (paf_`i' * draw_`i' * fraction)
}

fastcollapse draw*, type(sum) by(cause_id age_group_id year_id sex_id)
cap gen modelable_entity_id=.
gen risk = "`risk'"
append using `cod'

keep year_id sex_id cause_id age_group_id risk draw*
gen denominator = .
replace denominator = (risk == "")
fastfraction draw*, by(year_id sex_id cause_id age_group_id) denominator(denominator) prefix(paf_) 
keep if risk=="metab_bmd"
keep year_id sex_id cause_id age_group_id risk paf*
renpfix paf_draw_ paf_
cap gen modelable_entity_id=.
cap drop rei_id
cap drop location_id
cap drop year_id
gen rei_id = `rei_id'
gen location_id = `location_id'
gen year_id = `year_id'

outsheet age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id paf* using "/ihme/epi/risk/paf/`risk'_interm/paf_yll_`location_id'_`year_id'_`sex_id'.csv", comma replace

noi di c(current_time) + ": YLL PAFs saved: /ihme/epi/risk/paf/`risk'_interm/paf_yll_`location_id'_`year_id'_`sex_id'.csv"

} // end quiet loop
