** Squeeze and calculate activity PAFs

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
	local location_id = 522
	local year_id = 1995
	local sex_id = 1
}

else if "`2'" !="" {
	local location_id = "`1'"
	local year_id = "`2'"
	local sex_id = "`3'"
}

qui {
adopath + "$j/WORK/10_gbd/00_library/functions"	
local username = c(username)
run $j/temp/`username'/GBD_2015/risks/paf_calc_categ.do

noi di c(current_time) + ": pull exposure categories"

** these are the MEs for all activity DisMod models
local n = 0
foreach me in 9356 9357 9358 9359 9360 9361 {
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(`me') location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') status(best) source(epi)clear
	local n = `n' + 1
	tempfile `n'
	save ``n'', replace
}

clear
forvalues i = 1/`n' {
	append using ``i''
}

forvalues i = 0/999 {
	rename draw_`i' exp_`i'_
}

gen type = ""
replace type = "activity_inactive" if modelable_entity_id==9356
replace type = "activity_lowmodhigh" if modelable_entity_id==9360
replace type = "activity_low" if modelable_entity_id==9357
replace type = "activity_modhigh" if modelable_entity_id==9361
replace type = "activity_mod" if modelable_entity_id==9358
replace type = "activity_high" if modelable_entity_id==9359

keep location_id year_id age_group_id sex_id type exp* 

reshape wide exp_*, i(location_id year_id age_group_id sex_id) j(type) string
		
		** Rescale models to come up with exhaustive - non-over lapping categories
		
		forvalues draw = 0/999 {
			// Step1: Rescale inactive model and low+moderate+high model so that the sum is equal to 1
				gen sum = exp_`draw'_activity_inactive + exp_`draw'_activity_lowmodhigh
				gen scaler1 = 1 / sum
				gen exp_`draw'_cat1 = exp_`draw'_activity_inactive * scaler1
				replace exp_`draw'_activity_lowmodhigh = exp_`draw'_activity_lowmodhigh * scaler1
			
			// Step2: Rescale low activity exposure and moderate+high exposure so that sum is equal to [rescaled version of] low+moderate+high exposure
				gen sum_lowmodhigh = exp_`draw'_activity_low + exp_`draw'_activity_modhigh
				gen scaler2 = exp_`draw'_activity_lowmodhigh / sum_lowmodhigh
				gen exp_`draw'_cat2 = exp_`draw'_activity_low * scaler2
				replace exp_`draw'_activity_modhigh = exp_`draw'_activity_modhigh * scaler2	
				
			// Step3: Rescale moderate activity exposure and high activity exposure so that sum is equal to [rescaled version of] moderate+high exposure
				gen sum_modhigh = exp_`draw'_activity_mod + exp_`draw'_activity_high
				gen scaler3 = exp_`draw'_activity_modhigh / sum_modhigh
				gen exp_`draw'_cat3 = exp_`draw'_activity_mod * scaler3
				gen exp_`draw'_cat4 = exp_`draw'_activity_high * scaler3
				
			drop sum* scaler*

		}
		drop exp_*activity*

		unab vars : exp_*_cat1
		local vars : subinstr local vars "cat1" "@", all
		reshape long `vars', i(location_id year_id age_group_id sex_id) j(parameter) string
		rename exp*_ exp*
		
		order location_id year_id age_group_id sex_id parameter exp*
		sort location_id year_id age_group_id sex_id parameter exp*
				
** Calculate PAFs
tempfile exp
save `exp', replace

** get RRs
noi di c(current_time) + ": get relative risk draws"
get_draws, gbd_id_field(rei_id) gbd_id(125) location_ids(`location_id') status(best) kwargs(draw_type:rr) source(risk) clear
merge m:1 age_group_id parameter using `exp', keep(3) nogen

** generate tmrel
forvalues i = 0/999 {
	qui gen tmrel_`i' = 0
	replace tmrel_`i' = 1 if parameter=="cat4"
}

noi di c(current_time) + ": calc PAFs"

calc_paf_categ exp_ rr_ tmrel_ paf_, by(age_group_id year_id sex_id cause_id mortality morbidity)

** expand mortliaty and morbidity
expand 2 if mortality == 1 & morbidity == 1, gen(dup)
replace morbidity = 0 if mortality == 1 & morbidity == 1 & dup == 0
replace mortality = 0 if mortality == 1 & morbidity == 1 & dup == 1
drop dup

levelsof mortality, local(morts)

noi di c(current_time) + ": saving PAFs"

** rei_id for activity
gen rei_id = 125
gen location_id = `location_id'
gen modelable_entity_id = .

	foreach mmm of local morts {
		if `mmm' == 1 local mmm_string = "yll"
		else local mmm_string = "yld"
					
		outsheet age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id paf* using "/share/epi/risk/paf/activity_interm/paf_`mmm_string'_`location_id'_`year_id'_`sex_id'.csv" if year_id == `year_id' & sex_id == `sex_id' & mortality == `mmm', comma replace
				
	}

} // end quiet loop







