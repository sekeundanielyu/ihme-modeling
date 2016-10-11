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
		set max_memory 8G
	}
	if c(os) == "MacOSX" {
		global j "/Volumes/snfs"
	}

** Random.org set seed for consistent TMRELs
set seed 370566

if "`2'" == "" {

	local risk = "wash_water"
	local rei_id = 83
	local location_id = 63
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

noi di c(current_time) + ": begin"

noi di "risk = `risk'"
noi di "rei_id = `rei_id'"
noi di "location_id = `location_id'"
noi di "year_id = `year_id'"
noi di "sex_id = `sex_id'"

cap mkdir /ihme/epi/risk/paf/`risk'_interm

** check that moremata is installed
mata: a = 5
cap mata: a = mm_cond(a=5,0,a)
if _rc ssc install moremata

adopath + "$j/WORK/10_gbd/00_library/functions"		
local username = c(username)
run $j/temp/`username'/GBD_2015/risks/paf_calc_categ.do

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

		tempfile rr
		save `rr', replace

		odbc load, exec("SELECT modelable_entity_id, modelable_entity_name FROM modelable_entity WHERE modelable_entity_name LIKE 'Unsafe water source exposure%' AND end_date IS NULL") `conn_string' clear
		levelsof modelable_entity_id, local(MEs) c
		tempfile M
		save `M', replace

		noi di c(current_time) + ": pull exposures"
		local x = 0
		foreach me of local MEs {
			get_draws, gbd_id_field(modelable_entity_id) gbd_id(`me') location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') status(best) source(epi) clear
			local x = `x' + 1
			tempfile `x'
			save ``x'', replace
			
		}

		clear
		forvalues i = 1/`x' {
			append using ``i''
		}

		merge m:1 modelable_entity_id using `M', keep(3) nogen
		gen parameter = ""
			replace parameter="cat1" if modelable_entity_name=="Unsafe water source exposure, Unimproved & untreated"
			replace parameter="cat2" if modelable_entity_name=="Unsafe water source exposure, Unimproved & chlorinated"
			replace parameter="cat3" if modelable_entity_name=="Unsafe water source exposure, Unimproved & filtered"
			replace parameter="cat4" if modelable_entity_name=="Unsafe water source exposure, Improved & untreated"
			replace parameter="cat5" if modelable_entity_name=="Unsafe water source exposure, Improved & chlorinated"
			replace parameter="cat6" if modelable_entity_name=="Unsafe water source exposure, Improved & filtered"
			replace parameter="cat7" if modelable_entity_name=="Unsafe water source exposure, Piped & untreated"
			replace parameter="cat8" if modelable_entity_name=="Unsafe water source exposure, Piped & chlorinated"
			replace parameter="cat9" if modelable_entity_name=="Unsafe water source exposure, High quality piped & untreated"
			replace parameter="cat10" if modelable_entity_name=="Unsafe water source exposure, High quality piped & chlorinated"

		noi di c(current_time) + ": exposure draws read"
		** merge on RRs just to get categories first then squeeze exposure
		merge 1:m age_group_id parameter year_id using `rr', keep(3) nogen
		drop cause_id rr* mortality morbidity
		duplicates drop

		levelsof parameter, c
		local L : word count `r(levels)'

		** drop TMREL category
		drop if parameter=="cat`L'"
		
		forvalues i = 0/999 {
			bysort location_id year_id age_group_id sex_id: egen scalar = total(draw_`i')
			replace draw_`i' = draw_`i' / scalar if scalar > 1
			drop scalar
		}

		bysort location_id age_group_id year_id sex_id: gen level = _N
		levelsof level, local(ref_cat) c
		local ref_cat = `ref_cat' + 1
		drop level

		fastcollapse draw*, type(sum) by(location_id year_id age_group_id sex_id) append flag(dup)
		replace parameter = "cat`ref_cat'" if dup == 1
		forvalues i = 0/999 {
			replace draw_`i' = 1 - draw_`i' if dup == 1
		}
		drop dup

		levelsof parameter, c
		local L : word count `r(levels)'

		forvalues i = 0/999 {
			qui gen tmrel_`i' = 0
			replace tmrel_`i' = 1 if parameter=="cat`L'"
		}

		renpfix draw_ exp_

		tempfile exp
		save `exp', replace

		** merge on RRs
		merge 1:m age_group_id parameter year_id sex_id using `rr', keep(3) nogen

		noi di c(current_time) + ": calc PAFs"
		cap drop rei_id
		gen rei_id = `rei_id'

		cap drop modelable_entity_id
		gen modelable_entity_id = .
		calc_paf_categ exp_ rr_ tmrel_ paf_, by(age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mortality morbidity)

		noi di c(current_time) + ": PAF calc complete"
		keep age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mortality morbidity paf*
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

} // end quiet loop


