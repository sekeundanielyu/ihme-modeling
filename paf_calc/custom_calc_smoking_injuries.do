** Calculate injuries from smoking

qui {

local risk = "`1'"
local rei_id = "`2'"
local location_id = "`3'"
local year_id = "`4'"
local sex_id = "`5'"
local epi = "`6'"
local cod = "`7'"

noi di c(current_time) + ": begin"
noi di "risk = `risk'"
noi di "rei_id = `rei_id'"
noi di "location_id = `location_id'"
noi di "year_id = `year_id'"
noi di "sex_id = `sex_id'"
noi di "COMO = `epi'"
noi di "COD = `cod'"

local epi_dir "/ihme/centralcomp/como/`epi'/draws/cause/total_csvs"
local cod_dir "/share/central_comp/codcorrect/`cod'/draws"

insheet using /ihme/epi/risk/paf/smoking_direct_prev_interm/paf_yld_`location_id'_`year_id'_`sex_id'.csv, clear
** keep the injuries parts
keep if inlist(cause_id,878,923)
gen acause=""
replace acause="hip" if cause_id==878
replace acause="non-hip" if cause_id==923

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
joinby age_group_id healthstate inj year_id sex_id using `m'
joinby age_group_id acause using `P'

gen matrix = 1
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

	** calculate PAF
	replace draw_`i' = (paf_`i' * prop_`i')
	drop total
}

keep if matrix==1
fastcollapse draw*, type(sum) by(cause_id age_group_id year_id sex_id)
gen risk = "smoking_direct_prev"
tempfile r
save `r', replace
append using `EPI'
keep year_id sex_id cause_id age_group_id risk draw*
gen denominator = .
replace denominator = (risk == "")
duplicates drop
fastfraction draw*, by(year_id sex_id cause_id age_group_id) denominator(denominator) prefix(paf_) 
keep if risk=="smoking_direct_prev"
keep year_id sex_id cause_id age_group_id risk paf*
renpfix paf_draw_ paf_
cap gen modelable_entity_id=.
cap gen rei_id = `rei_id'
cap gen location_id = `location_id'

tempfile y
save `y', replace

insheet using /ihme/epi/risk/paf/smoking_direct_prev_interm/paf_yld_`location_id'_`year_id'_`sex_id'.csv, clear
drop if inlist(cause_id,878,923)
append using `y'

outsheet age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id paf* using "/ihme/epi/risk/paf/`risk'_interm/paf_yld_`location_id'_`year_id'_`sex_id'.csv", comma replace

noi di c(current_time) + ": YLD PAFs saved: /ihme/epi/risk/paf/`risk'_interm/paf_yld_`location_id'_`year_id'_`sex_id'.csv"

** prep YLLs
insheet using /ihme/epi/risk/paf/smoking_direct_prev_interm/paf_yll_`location_id'_`year_id'_`sex_id'.csv, clear
** keep the injuries parts
keep if inlist(cause_id,878,923)
gen acause=""
replace acause="hip" if cause_id==878
replace acause="non-hip" if cause_id==923

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
duplicates drop
fastfraction draw*, by(year_id sex_id cause_id age_group_id) denominator(denominator) prefix(paf_) 
keep if risk=="smoking_direct_prev"
keep year_id sex_id cause_id age_group_id risk paf*
renpfix paf_draw_ paf_
cap gen modelable_entity_id=.
cap drop rei_id
cap drop location_id
cap drop year_id
gen rei_id = `rei_id'
gen location_id = `location_id'
gen year_id = `year_id'

tempfile yll
save `yll', replace

insheet using /ihme/epi/risk/paf/smoking_direct_prev_interm/paf_yll_`location_id'_`year_id'_`sex_id'.csv, clear
drop if inlist(cause_id,878,923)
append using `yll'

outsheet age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id paf* using "/ihme/epi/risk/paf/`risk'_interm/paf_yll_`location_id'_`year_id'_`sex_id'.csv", comma replace

noi di c(current_time) + ": YLL PAFs saved: /ihme/epi/risk/paf/`risk'_interm/paf_yll_`location_id'_`year_id'_`sex_id'.csv"

} // end quiet loop
