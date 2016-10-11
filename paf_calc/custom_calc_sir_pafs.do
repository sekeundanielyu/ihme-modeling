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

set seed 370566

if "`2'" == "" {

	local risk = "smoking_direct_sir"
	local rei_id = 165
	local location_id = 4663
	local year_id = 2015
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
cap mkdir /share/epi/risk/paf/`risk'
cap mkdir /share/epi/risk/paf/`risk'/before_paf
adopath + "$j/WORK/10_gbd/00_library/functions/"
** categorical PAF function
local username = c(username)
qui do $j/temp/`username'/GBD_2015/risks/paf_calc_categ.do

** SIR = (C-N) / (S-N*)
	** C = lung cancer mortality rate by country in current pop
	** N = lung cancer mortality rate of never-smokers in current pop  (use CPS II for all, except China & Asia Pacific high income)
	** S = lung cancer mortality rate of life-long smokers in reference pop
	** N*= lung cancer mortality rate for never-smokers in reference pop 

** lung cancer is cause_id 426
noi di c(current_time) + ": pulling pop"

use $j/temp/`username'/GBD_2015/risks/best_pop.dta, clear

tempfile pop
save `pop', replace

** best CodCorrect
odbc load, exec("SELECT MAX(output_version_id) AS output_version_id FROM output_version") `conn_string' clear	
levelsof output_version_id, local(cod_correct) c

** Calculate death rate
noi di c(current_time) + ": pulling lung cancer deaths"
** As of 3/21/16, CoDCorrect doesn't produce rows if there are 0 deaths
** For example, Djibouti deaths are 0 in females:
** use if cause_id==426 & sex_id==2 using /share/central_comp/codcorrect/31/draws/death_173_1990.dta, clear
** count = 0
use if cause_id==426 & sex_id==`sex_id' using /share/central_comp/codcorrect/`cod_correct'/draws/death_`location_id'_`year_id'.dta, clear
count
if `r(N)'==0 {
	clear
	set obs 14
	gen location_id = `location_id' 
	gen year_id = `year_id'
	gen sex_id = `sex_id'
	gen age_group_id = _n
	gen cause_id = 426
	forvalues i = 0/999 {
		gen draw_`i' = 0
	}
}

cap renpfix death draw
merge 1:1 location_id year_id age_group_id sex_id using `pop', assert(2 3) keep(3) nogen
			
forvalues i = 0/999 {
	gen double c_`i' = draw_`i' / pop * 100000
	drop draw_`i'
}
tempfile c_deaths
save `c_deaths'
		
** Bring in smoker deaths (s)
clear
odbc load, exec("select age_group_id, age_data as age from age_groups where age_data is not NULL") `new_halem'
tostring age, replace force format(%12.3f)
destring age, replace force
tempfile ages
save `ages', replace

noi di c(current_time) + ": pull in S"
use "$j/WORK/05_risk/risks/smoking_direct_sir/data/exp/me_id/input_data/prepped/impact_ratio_s.dta", clear
rename gbd_age_start age
drop gbd_age_end
merge m:1 age using `ages', assert(2 3) keep(3) nogen
rename sex sex_id

tempfile s_deaths
save `s_deaths'
			
** Bring in background (non-smoking) deaths (n and n*)
noi di c(current_time) + ": pull in N"
use "$j/WORK/05_risk/risks/smoking_direct_sir/data/exp/me_id/input_data/prepped/impact_ratio_n_revised.dta", clear
rename gbd_age_start age
drop gbd_age_end
merge m:1 age using `ages', assert(2 3) keep(3) nogen
rename sex sex_id
** China is location_id (6) subnationals: children
** 354,361,491,492,493,494,495,496,497,498,499,500,501,502,503,504,505,506,507,508,509,510,511,512,513,514,515,516,517,518,519,520,521

if inlist(`location_id',354,361,491,492,493,494,495,496) | inlist(`location_id',497,498,499,500,501,502,503,504,505) | inlist(`location_id',506,507,508,509,510,511,512,513,514) | inlist(`location_id',515,516,517,518,519,520,521) {
	keep if whereami_id=="CHN"
	gen location_id = `location_id'
}

** R1 is High-Income Asia Pacific
** locations 66,67,68,69
** Japan (67) subnationals: children
** 35424,35425,35426,35427,35428,35429,35430,35431,35432,35433,35434,35435,35436,35437,35438,35439,35440,35441,35442,35443,35444,35445,35446,35447,35448,35449,35450,35451,35452,35453,35454,35455,35456,35457,35458,35459,35460,35461,35462,35463,35464,35465,35466,35467,35468,35469,35470

else if inlist(`location_id',66,68,69) | inlist(`location_id',35424,35425,35426,35427,35428,35429,35430) | inlist(`location_id',35431,35432,35433,35434,35435,35436,35437,35438) | inlist(`location_id',35439,35440,35441,35442,35443,35444,35445) | inlist(`location_id',35446,35447,35448,35449,35450,35451,35452) | inlist(`location_id',35453,35454,35455,35456,35457,35458,35459) | inlist(`location_id',35460,35461,35462,35463,35464,35465) | inlist(`location_id',35466,35467,35468,35469,35470) {
	keep if whereami_id=="R1"
	gen location_id = `location_id'
}
				
else {
	keep if whereami_id=="G"
	gen location_id = `location_id'
}

tempfile n_deaths
save `n_deaths'
		
** Merge together and calculate impact ratio
noi di c(current_time) + ": calculate impact ratio"
clear
use `c_deaths'
merge m:1 age_group_id sex_id using `s_deaths', keep(3) nogen // applies to all years
merge m:1 age_group_id sex_id using `n_deaths', keep(3) nogen // applies to all years

forvalues draw = 0 / 999 {
	gen double exp_`draw' = ((c_`draw' - n_`draw') / (s_`draw' - nstar_`draw')) * (nstar_`draw' / n_`draw')
	replace exp_`draw' = 0 if exp_`draw' < 0
	replace exp_`draw' = 1 if exp_`draw' > 1
}
		
	
** calculate PAFs
cap drop risk
gen risk = "`risk'"
expand 2, gen(dup)
gen parameter = "cat1" if dup == 0
replace parameter = "cat2" if dup == 1
forvalues i = 0/999 {
	replace exp_`i' = 1 - exp_`i' if dup == 1
}
drop dup

tempfile exp
save `exp', replace

** error with get draws

		noi di c(current_time) + ": get relative risk draws"
		get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') location_ids(`location_id') status(best) kwargs(draw_type:rr) source(risk) clear
		levelsof cause_id, local(C) sep(,)
		no di "causes: `C'"
		noi di c(current_time) + ": relative risk draws read"
		keep if year_id == `year_id'
		keep if sex_id == `sex_id'
		merge m:1 age_group_id parameter year_id using `exp', keep(3) nogen

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

		outsheet using /share/epi/risk/paf/`risk'/before_paf/before_paf_`location_id'_`year_id'_`sex_id'.csv, comma replace
		
		calc_paf_categ exp_ rr_ tmrel_ paf_, by(age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mortality morbidity)

		noi di c(current_time) + ": PAF calc complete"
		cap drop modelable_entity_id
		gen modelable_entity_id = .
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

noi di c(current_time) + ": DONE!"

} // end quiet loop


