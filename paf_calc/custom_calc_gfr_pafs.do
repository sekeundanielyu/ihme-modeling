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

set seed 370566

if "`2'" == "" {

	local risk = "metab_gfr"
	local rei_id = 143
	local location_id = 101
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

qui {
adopath + "$j/WORK/10_gbd/00_library/functions/"
** categorical PAF function
local username = c(username)
qui do $j/temp/`username'/GBD_2015/risks/paf_calc_categ.do

** Pull stage 5 model
noi di c(current_time) + ": read in Stage V"
odbc load, exec("SELECT modelable_entity_id FROM modelable_entity WHERE modelable_entity_name IN ('Stage V chronic kidney disease untreated')") `conn_string' clear
levelsof modelable_entity_id, local(MEs) c

get_draws, gbd_id_field(modelable_entity_id) gbd_id(`MEs') location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') status(best) source(epi)clear
gen parameter = "cat1"
tempfile V
save `V', replace

** Pull stage 4 model
noi di c(current_time) + ": read in Stage IV"
odbc load, exec("SELECT modelable_entity_id FROM modelable_entity WHERE modelable_entity_name IN ('Stage IV chronic kidney disease')") `conn_string' clear
levelsof modelable_entity_id, local(MEs) c

get_draws, gbd_id_field(modelable_entity_id) gbd_id(`MEs') location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') status(best) source(epi)clear
gen parameter = "cat2"
tempfile IV
save `IV', replace

** Pull stage 3 model
noi di c(current_time) + ": read in Stage III"
odbc load, exec("SELECT modelable_entity_id FROM modelable_entity WHERE modelable_entity_name IN ('Stage III chronic kidney disease')") `conn_string' clear
levelsof modelable_entity_id, local(MEs) c

get_draws, gbd_id_field(modelable_entity_id) gbd_id(`MEs') location_ids(`location_id') year_ids(`year_id') sex_ids(`sex_id') status(best) source(epi)clear
gen parameter = "cat3"

append using `IV'
append using `V'

gen rei_id = `rei_id'
keep if measure_id==5

forvalues i = 0/999 {
	bysort location_id year_id age_group_id sex_id rei_id: egen scalar = total(draw_`i')
	replace draw_`i' = draw_`i' / scalar if scalar > 1
	drop scalar
}

bysort location_id age_group_id year_id sex_id rei_id: gen level = _N
levelsof level, local(ref_cat) c
local ref_cat = `ref_cat' + 1
drop level

fastcollapse draw*, type(sum) by(location_id year_id age_group_id sex_id rei_id) append flag(dup)
replace parameter = "cat`ref_cat'" if dup == 1
	forvalues i = 0/999 {
		replace draw_`i' = 1 - draw_`i' if dup == 1
	}
drop dup

** calculate PAFs
renpfix draw_ exp_
tempfile exp
save `exp', replace

		noi di c(current_time) + ": get relative risk draws"
		get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') location_ids(`location_id') status(best) kwargs(draw_type:rr) source(risk) clear
		noi di c(current_time) + ": relative risk draws read"

		keep if year_id == `year_id'
		keep if sex_id == `sex_id'
		merge m:1 age_group_id parameter year_id sex_id using `exp', keep(3) nogen

		** generate TMREL
		bysort age_group_id year_id sex_id cause_id mortality morbidity: gen level = _N
		levelsof level, local(tmrel_param) c
		drop level

		forvalues i = 0/999 {
			qui gen tmrel_`i' = 0
			replace tmrel_`i' = 1 if parameter=="cat`tmrel_param'"
		}

		noi di c(current_time) + ": calc PAFs"
		cap drop rei_id
		gen rei_id = `rei_id'
		calc_paf_categ exp_ rr_ tmrel_ paf_, by(age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mortality morbidity)

		noi di c(current_time) + ": PAF calc complete"

		** save PAFs
		cap drop modelable_entity_id
		gen modelable_entity_id = .
		keep age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mortality morbidity paf*

		** expand mortliaty and morbidity
		expand 2 if mortality == 1 & morbidity == 1, gen(dup)
		replace morbidity = 0 if mortality == 1 & morbidity == 1 & dup == 0
		replace mortality = 0 if mortality == 1 & morbidity == 1 & dup == 1
		drop dup

		** make sure we expand causes to the most detailed level
		rename cause_id ancestor_cause
		joinby ancestor_cause using "$j/temp/`username'/GBD_2015/risks/cause_expand.dta", unmatched(master)
		replace ancestor_cause = descendant_cause if ancestor_cause!=descendant_cause & descendant_cause!=. // if we have a no match for a sequelae
		drop descendant_cause _merge
		rename ancestor_cause cause_id

		levelsof mortality, local(morts)

		noi di c(current_time) + ": saving PAFs"
		cap mkdir /ihme/epi/risk/paf/`risk'_interm/

			foreach mmm of local morts {
				if `mmm' == 1 local mmm_string = "yll"
				else local mmm_string = "yld"
							
				outsheet age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id paf* using "/ihme/epi/risk/paf/`risk'_interm/paf_`mmm_string'_`location_id'_`year_id'_`sex_id'.csv" if year_id == `year_id' & sex_id == `sex_id' & mortality == `mmm', comma replace

				no di "saved: /ihme/epi/risk/paf/`risk'_interm/paf_`mmm_string'_`location_id'_`year_id'_`sex_id'.csv"
			}

noi di c(current_time) + ": DONE!"

} // end quiet loop


