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
	

** blood lead
if "`2'"=="" {
	local risk = "envir_lead_blood"
	local rei_id = 242
	local location_id = 47
	local year_id = 1990
	local sex_id = 2
	local model_version_id = 78324
}

else if "`2'" !="" {
	local risk = "`1'"
	local rei_id = "`2'"
	local location_id = "`3'"
	local year_id = "`4'"
	local sex_id = "`5'"
	local model_version_id = "`6'"
}
local username = c(username)
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
qui do "$j/WORK/2013/05_risk/03_outputs/01_code/02_paf_calculator/functions_expand.ado"

** pull blood lead exposure
get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') year_ids(`year_id') sex_ids(`sex_id') location_ids(`location_id') status(best) kwargs(draw_type:exposure) source(risk) clear
drop if parameter=="cat2"
renpfix draw_ exp_
cap drop modelable_entity_id
noi di c(current_time) + ": exposure draws read"
tempfile exp
save `exp', replace

** pull blood lead RRs
insheet using /share/gbd/WORK/05_risk/02_models/02_results/envir_lead_blood/rr/1/rr_G.csv, clear
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

** Reshape wide on the three lead parameters.
replace parameter="low" if parameter=="shift:<8"
replace parameter="med" if parameter=="shift:8-18"
replace parameter="high" if parameter=="shift:>18"
	
rename sex sex_id
keep parameter age_group_id sex_id rr*
reshape wide rr_*, i(age_group_id sex_id) j(parameter) string
	
forvalues i = 0/999 {
	rename rr_`i'high high_`i'
	rename rr_`i'med med_`i'
	rename rr_`i'low low_`i'
}
	
keep age_group_id sex_id high* med* low*
compress
tempfile rr
save `rr'

merge m:1 age_group_id sex_id using `exp', keep(3) nogen

** Calculate total shift 
	forvalues k=0/999 {
		gen shift_`k'=.
		replace shift_`k' =	(low_`k' * exp_`k')	if exp_`k'<8
		replace shift_`k' =	(low_`k' * 8) +	(exp_`k' * (exp_`k' - 8)) if exp_`k'>=8 & exp_`k'<=18
		replace shift_`k' =	(low_`k' * 8) +	(med_`k' * 10) + (high_`k' * (exp_`k' - 18)) if exp_`k'>18
		drop low_`k' med_`k' high_`k' exp_`k'
	}
	
	tempfile iqshift
	save `iqshift', replace

** Read in intellectual disability
local x = 0
** select * from sequela left join healthstate using (healthstate_id) where sequela_name like '%idiopathic%'
foreach s in 450 488 489 490 491 {
	get_draws, location_ids(`location_id') year_ids(`year_id') status(best) source(como) gbd_id(`s') gbd_id_field(sequela_id) measure_ids(3) clear
	gen severity = ""
	replace severity = "borderline" if `s'==450
	replace severity = "mild" if `s'==488
	replace severity = "moderate" if `s'==489
	replace severity = "severe" if `s'==490
	replace severity = "profound" if `s'==491
	local x = `x' + 1
	tempfile `x'
	save ``x'', replace
	}
	
	clear
	forvalues i = 1/`x' {
		append using ``i''
	}

keep age_group_id sex_id severity draw*
reshape wide draw_*, i(age_group_id sex_id) j(severity) string

forvalues i = 0/999 {
	rename draw_`i'borderline borderline_`i'
	rename draw_`i'mild mild_`i'
	rename draw_`i'moderate moderate_`i'
	rename draw_`i'severe severe_`i'
	rename draw_`i'profound profound_`i'
}

tempfile intellectual_dis
save `intellectual_dis', replace

merge 1:1 sex_id age_group_id using `iqshift', keep(3) nogen

	forvalues x = 0 / 999 { 
		gen double profound_cum`x' = profound_`x'
		gen double severe_cum`x' =  severe_`x' + profound_`x'
		gen double moderate_cum`x' = moderate_`x' + severe_`x' + profound_`x'
		gen double mild_cum`x' = mild_`x' + moderate_`x' + severe_`x' + profound_`x'
		gen double borderline_cum`x' = borderline_`x' + mild_`x' + moderate_`x' + severe_`x' + profound_`x'
	}

		rename borderline_* draw*_borderline
		rename mild_* draw*_mild
		rename moderate_* draw*_moderate
		rename severe_* draw*_severe
		rename profound_* draw*_profound

		global numbers = ""
		forvalues x = 0 / 999 {
			global numbers = "${numbers} draw`x'_  drawcum`x'_"
			
		}

		reshape long $numbers, i(age_group_id sex_id) j(severity) string
		
	gen IQ_cutoff = .
		replace IQ_cutoff = 85 if severity == "borderline"
		replace IQ_cutoff = 70 if severity == "mild"
		replace IQ_cutoff = 50 if severity == "moderate"
		replace IQ_cutoff = 35 if severity == "severe"
		replace IQ_cutoff = 20 if severity == "profound"

	local assumed_mean = 100
		
forvalues x = 0/999 {		

	di in red `x'
	
	gen sd_`x' = (IQ_cutoff - `assumed_mean') / invnorm(drawcum`x'_)
	bysort sex_id age_group_id: egen sd_max_`x' = mean(sd_`x')
	gen drawcum`x'_shifted = normal((IQ_cutoff - (`assumed_mean' + shift_`x'))/sd_max_`x')
	gen drawcum`x'_unshifted = normal((IQ_cutoff - `assumed_mean')/sd_max_`x')
	gen paf_`x' =(drawcum`x'_unshifted - drawcum`x'_shifted)/drawcum`x'_unshifted

}
	
forvalues x = 0/999 {		
	bysort age_group_id sex_id: egen total_prev_`x' = total(draw`x'_)
	gen weighted_paf_`x' = (paf_`x' * draw`x'_) / total_prev_`x'
	gen diff_paf_`x' = paf_`x' -  weighted_paf_`x'
}

fastcollapse weighted_paf*, type(sum) by(age_group_id sex_id)

cap mkdir /ihme/epi/risk/paf/`risk'_interm/

renpfix weighted_paf_ paf_
keep sex_id age_group_id paf*
gen rei_id = `rei_id'
gen location_id = `location_id'
gen year_id = `year_id'

gen cause_id = 582 // intellectual disability

order age_group_id rei_id location_id sex_id year_id cause_id

outsheet age_group_id rei_id location_id sex_id year_id cause_id paf* using "/ihme/epi/risk/paf/`risk'_interm/paf_yld_`location_id'_`year_id'_`sex_id'.csv", comma replace

no di "saved: /ihme/epi/risk/paf/`risk'_interm/paf_yld_`location_id'_`year_id'_`sex_id'.csv"





