qui {

clear all
set maxvar 32767, perm
pause on
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

if "`1'" == "" {
	local location_id = 97
	local year_id = 1990
	local risk_version = 177
	local epi = 94

	local to_calc = "50198;50201;50210;50360;50468;50486;50720;50732;50735;50744;50762;50765;50768;50792;50816;50825;51149;77895;78218;78274;83866;84056;84302;85097;85098;85113;86208;86214;86215;86844;86898;87353;87365;87372;88741;88744;88745;88746;88747;88748;88750;88751;88752;88753;88754;88755;88756;88757;88758;88778;89040;89260;89261;89437;89438;89439;89440;89527;89529;90293;90294;90640;92724;93369;93370;93371;93372;93373;93374;93375;93393;93394;93395;93396;93751;93752;93761;93762;93763;93764;93765;93766;93767;93769;93770"

}

else if "`1'" !="" {
	local location_id = "`1'"
	local year_id = "`2'"
	local risk_version = "`3'"
	local to_calc = "`4'"
	local epi = "`5'"
}
adopath + "$j/WORK/10_gbd/00_library/functions"
local username = c(username)

local epi_dir "/ihme/centralcomp/como/`epi'/draws/cause/total_csvs"

local models_query = subinstr("`to_calc'",";",",",.)
local models = subinstr("`to_calc'",";"," ",.)

noi di "location_id = `location_id'"
noi di "year_id = `year_id'"
noi di "risk_version = `risk_version'"

cap mkdir "/share/central_comp/pafs/`risk_version'"

odbc load, exec("SELECT DISTINCT rei_set_version_id AS best_rei_version FROM shared.rei_hierarchy_history WHERE rei_set_version_id = shared.active_rei_set_version(2, 3)") `shared_string' clear
	levelsof best_rei_version, local(best_rei_version) c

** pull reis that correspond to each model
noi di "`models_query'"
odbc load, exec("SELECT model_version_id as my_model_id, rei_id, rei, rei_name from model_version left join modelable_entity_rei using (modelable_entity_id) left join shared.rei using (rei_id) where model_version_id in (`models_query')") `conn_string' clear
tempfile match
save `match', replace

clear
odbc load, exec("SELECT acause, cause_id FROM cause") `shared_string'
tempfile causes
save `causes', replace

clear
odbc load, exec("SELECT rei, rei_id FROM rei") `shared_string'
tempfile risks
save `risks', replace

clear
odbc load, exec("SELECT age_group_id, age_group_name FROM age_group") `shared_string'
tempfile ages
save `ages', replace

** build risk hierarchy
odbc load, exec("SELECT rhh.level AS level,rhh.rei_id,rhh.rei_name,rhh.parent_id,rhh.most_detailed,(SELECT GROUP_CONCAT(rei_id) FROM shared.rei_hierarchy_history WHERE rei_set_version_id = `best_rei_version' and parent_id = rhh.rei_id) AS children FROM shared.rei_hierarchy_history rhh WHERE rhh.rei_set_version_id = `best_rei_version' GROUP BY rhh.rei_id, rhh.rei_name, rhh.parent_id, rhh.most_detailed ORDER BY rhh.sort_order") `conn_string' clear
destring rei_id, replace
drop if children==""
replace children=subinstr(children,"169,","",.) if rei_id==169 

** all, metabolic, behavioral have mediation so we need the most detailed children to merge with the mediation matrix (metabolic fine)
tempfile h_orig
save `h_orig', replace
drop if rei_id==203 // behav
drop if rei_id==169 // all
tempfile h
save `h', replace

** behav
odbc load, exec("SELECT 203 as rei_id, 'Behavioral risks' as rei_name , GROUP_CONCAT(rei_id) as all_my_most_detailed_children FROM shared.rei_hierarchy_history WHERE rei_set_version_id = `best_rei_version' and LEFT(path_to_top_parent, LENGTH('169,203,') ) = '169,203,' and most_detailed = 1") `conn_string' clear
destring rei_id, replace
** we dropped diet high in calcium
replace all_my_most_detailed_children=subinstr(all_my_most_detailed_children,"146,147","120",.)
tempfile behav_h
save `behav_h', replace

** environmental
odbc load, exec("SELECT 202 as rei_id, 'Environmental risks' as rei_name , GROUP_CONCAT(rei_id) as all_my_most_detailed_children FROM shared.rei_hierarchy_history WHERE rei_set_version_id = `best_rei_version' and LEFT(path_to_top_parent, LENGTH('169,202,') ) = '169,202,' and most_detailed = 1") `conn_string' clear
destring rei_id, replace
tempfile env_h
save `env_h', replace

** all
odbc load, exec("SELECT 169 as rei_id, 'All risks' as rei_name , GROUP_CONCAT(rei_id) as all_my_most_detailed_children FROM shared.rei_hierarchy_history WHERE rei_set_version_id = `best_rei_version' and most_detailed = 1") `conn_string' clear
destring rei_id, replace
replace all_my_most_detailed_children=subinstr(all_my_most_detailed_children,"146,147","120",.)
replace all_my_most_detailed_children=subinstr(all_my_most_detailed_children,"141,142","105",.)
replace all_my_most_detailed_children=subinstr(all_my_most_detailed_children,"244,245","134",.)

tempfile all_h
save `all_h', replace

use `h', clear
qui summ level
local max `r(max)'
qui summ level
local min `r(min)'

qui do "$j/WORK/10_gbd/00_library/functions/get_demographics.ado"
qui do "$j/WORK/10_gbd/00_library/functions/fastcollapse.ado"
get_demographics, gbd_team("epi") 

local n = 0
foreach model of local models {
		** some risks might be one sex or just YLDs so capture
		foreach mort in yll yld {
			foreach sex of global sex_ids {
				cap import delimited using "/ihme/epi/risk/paf/`model'/draws/paf_`mort'_`location_id'_`year_id'_`sex'.csv", asdouble varname(1) clear
				if _rc continue
				else if _rc==0 noi di c(current_time) + ": model `model' read - `mort' `sex'"

				forvalues i = 0/1000 {
					cap rename draw_`i' paf_`i'
					cap rename paf_draw_`i' paf_`i'
					cap rename draw_yll_`i' paf_`i'
					cap rename paf_yll_`i' paf_`i'
					cap rename draw_yld_`i' paf_`i'
					cap rename paf_yld_`i' paf_`i'
					cap rename paf_yll_draw_`i' paf_`i'
					cap rename paf_yld_draw_`i' paf_`i'
				}

				cap confirm var paf_1000
					if _rc==0 rename paf_1000 paf_0

				keep age_group_id cause_id paf*
				gen mort_type = "`mort'"
				gen my_model_id = `model'
				
				gen location_id = `location_id'
				gen year_id = `year_id'
				gen sex_id = `sex'
					

					foreach var of varlist paf* {
						cap destring `var', replace force
						replace `var'=0 if `var'==.
						replace `var' = 1 if `var'>1
						replace `var' = -.999999 if `var'<-1
					}

				cap drop modelable_entity_id
				gen modelable_entity_id = .
				order location_id year_id sex_id age_group_id mort_type my_model_id cause_id
				duplicates drop
				local n = `n' + 1
				tempfile `n'
				save ``n'', replace
			}
		}

}

	clear
	forvalues i = 1/`n' {
		append using ``i''
	}

duplicates drop
merge m:1 my_model_id using `match', assert(3) keep(3) nogen

foreach var of varlist paf* {
	replace `var' = 0 if `var'<0 & !inlist(rei_id,108,102) & regexm(rei,"eti_")==0
}

preserve
drop if rei_id==109
rename cause_id ancestor_cause
joinby ancestor_cause using "$j/temp/`username'/GBD_2015/risks/cause_expand.dta", unmatched(master)
replace ancestor_cause = descendant_cause if ancestor_cause!=descendant_cause & descendant_cause!=. // if we have a no match for a sequelae
drop descendant_cause _merge
rename ancestor_cause cause_id
tempfile expanded
save `expanded', replace
restore
keep if rei_id==109
append using `expanded'
fastrowmean paf*, mean_var_name(paf_MEAN)
drop if paf_MEAN==1
drop paf_MEAN
drop if rei_id==138 & inlist(cause_id,298,300,299)
drop if inlist(rei_id,108,118) & inlist(cause_id,507,500,502,503,499)
drop if inlist(rei_id,136,241,94,240,239) & inlist(cause_id,329,328)
drop if sex_id==1 & regexm(rei,"female")
drop if sex_id==2 & (regexm(rei,"male")==1 & regexm(rei,"female")==0)

keep age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mort_type paf*

tempfile data
save `data', replace

noi di c(current_time) + ": prep osteo PAFs"
gen tag = .
replace tag = 1 if inlist(cause_id,2141,2145)
preserve
keep if tag==1
drop tag
tempfile 1
save `1', replace

clear
set obs 6
gen cause_id = 2141
gen sequela_id = 546
replace sequela_id=547 in 2
replace sequela_id=548 in 3

replace cause_id = 2145 in 4
replace cause_id = 2145 in 5
replace cause_id = 2145 in 6
replace sequela_id=549 in 4
replace sequela_id=550 in 5
replace sequela_id=551 in 6

joinby cause_id using `1'

replace cause_id = sequela_id if sequela_id!=.
drop sequela_id

rename cause_id sequela_id
tempfile s
save `s', replace
odbc load, exec("SELECT sequela_id, cause_id FROM epi.sequela") dsn(epi) clear
merge 1:m sequela_id using `s', keep(3) nogen
duplicates drop
keep age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id sequela_id mort_type paf*
tempfile osteo
save `osteo', replace

** read in seqeula and scale to COMO
levelsof sequela_id, local(ss) c
	local x = 0
		foreach s of local ss {

		local attempt = 0
			while `attempt'<5 {
				cap get_draws, location_ids(`location_id') year_ids(`year_id') status(best) source(como) gbd_id(`s') gbd_id_field(sequela_id) measure_ids(3) clear
				if _rc local attempt = `attempt'+1
				else local attempt=6
			}

			local x = `x' + 1
			tempfile `x'
			save ``x'', replace
		}

		clear
		forvalues n = 1/`x' {
			append using ``n''
		}

		renpfix draw_ seq_
		gen cause_id = 628 // osteoarthritis
		tempfile s
		save `s', replace


local df = 0
foreach sex_id in 1 2 {
import delimited using "`epi_dir'/3_`location_id'_`year_id'_`sex_id'.csv", asdouble varname(1) clear
keep if cause_id == 628
renpfix draw_ yld_
local df = `df'+1
tempfile `df'
save ``df'', replace
}

clear
forvalues i = 1/`df' {
	append using ``i''
}

tempfile c_osteo
save `c_osteo', replace

joinby location_id year_id sex_id age_group_id cause_id using `s'

forvalues i = 0/999 {
	qui bysort age_group_id location_id sex_id year_id: egen total = total(seq_`i')
	qui replace seq_`i' = (seq_`i' * yld_`i')/total
	drop total
}
drop yld*
joinby location_id year_id sex_id age_group_id sequela_id using `osteo'

forvalues i = 0/999 {
	qui gen double yld_`i' = seq_`i' * paf_`i'
}

fastcollapse yld_*, type(sum) by(age_group_id location_id sex_id year_id cause_id rei_id)
append using `c_osteo'

gen denominator = .
replace denominator = (rei_id == .)
fastfraction yld*, by(location_id year_id sex_id cause_id age_group_id) denominator(denominator) prefix(paf_) 
keep if rei_id!=.
keep rei_id year_id sex_id cause_id age_group_id paf*
renpfix paf_yld_ paf_
gen location_id = `location_id'
gen mort_type="yld"
tempfile osteo_pafs
save `osteo_pafs', replace
drop if paf_0 == . // osteoarthritis starts at age 30+
restore
drop if tag==1
drop tag
append using `osteo_pafs'

drop if cause_id==297 & inlist(rei_id,142,141,105)
drop if rei_id==105
drop if inlist(rei_id,120,146,147) & cause_id==438

rename paf_* paf__*
unab vars : paf__*
local vars : subinstr local vars "__" "_@_", all
duplicates drop
reshape wide `vars', i(age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id) j(mort_type) string

tempfile CATZ
save `CATZ', replace

** apply direct DisMod --> PAFs
noi di c(current_time) + ": prep direct PAFs for HIV"
odbc load, exec("SELECT rei_id FROM shared.rei WHERE rei_name = 'Unsafe sex'") `shared_string' clear
levelsof rei_id, local(my_rei) c

odbc load, exec("SELECT DISTINCT cause_set_version_id AS best_cause_version FROM shared.cause_hierarchy_history WHERE cause_set_version_id = shared.active_cause_set_version(2, 3)") `shared_string' clear
	levelsof best_cause_version, local(best_cause_version) c
				
odbc load, exec("SELECT cause_id FROM shared.cause_hierarchy_history WHERE acause like ('hiv_%') AND cause_set_version_id=`best_cause_version' AND level=4") `shared_string' clear
gen n = 1
tempfile HIV
save `HIV', replace

odbc load, exec("SELECT modelable_entity_id, modelable_entity_name FROM modelable_entity WHERE modelable_entity_name IN ('Proportion HIV due to intravenous drug use','Proportion HIV due to other','Proportion HIV due to sex')") `conn_string' clear
levelsof modelable_entity_id, local(MEs) c
levelsof modelable_entity_id if modelable_entity_name=="Proportion HIV due to sex", local(sex) c
levelsof modelable_entity_id if modelable_entity_name=="Proportion HIV due to intravenous drug use", local(IV) c


odbc load, exec("SELECT rei_id FROM rei where rei_name = 'Unsafe sex'") `shared_string' clear
levelsof rei_id, local(unsafe_sex) c

odbc load, exec("SELECT rei_id FROM rei where rei_name = 'Drug use dependence and blood borne viruses'") `shared_string' clear
levelsof rei_id, local(drug_use) c

local x=0
foreach me of local MEs { 
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(`me') location_ids(`location_id') year_ids(`year_id') status(best) source(epi) clear
	local x = `x' + 1
	tempfile `x'
	save ``x'', replace	
}

clear
forvalues i = 1/`x' {
	append using ``i''
}

cap drop rei_id
** re-scale
	forvalues draw = 0/999 {
		bysort location_id year_id age_group_id sex_id: egen scalar = total(draw_`draw')
		replace draw_`draw' = draw_`draw' / scalar
		rename draw_`draw' paf_yll_`draw'
		gen double paf_yld_`draw' = paf_yll_`draw'
		drop scalar
	}

gen n = 1

preserve
keep if modelable_entity_id == `sex'
gen rei_id = `unsafe_sex'
cap drop modelable_entity_id
gen modelable_entity_id = .

joinby n using `HIV'

tempfile HIV
save `HIV', replace

restore
keep if modelable_entity_id == `IV'
gen rei_id = `drug_use'

cap drop modelable_entity_id
gen modelable_entity_id = .

joinby n using `HIV'

tempfile IV
save `IV', replace

** Fraction of homicide against females due to IPV
noi di c(current_time) + ": prep intimate partner violence and homicide"
odbc load, exec("SELECT rei_id FROM shared.rei WHERE rei_name = 'Intimate partner violence (direct PAF approach)'") `shared_string' clear
levelsof rei_id, local(my_rei) c

odbc load, exec("SELECT cause_id FROM shared.cause_hierarchy_history WHERE acause like ('inj_homicide_%') AND cause_set_version_id=`best_cause_version' AND level=4") `shared_string' clear
gen n = 1
tempfile INJ
save `INJ', replace


odbc load, exec("SELECT modelable_entity_id FROM modelable_entity WHERE modelable_entity_name IN ('Fraction of homicide against females due to IPV')") `conn_string' clear
levelsof modelable_entity_id, local(MEs) c

get_draws, gbd_id_field(modelable_entity_id) gbd_id(`MEs') location_ids(`location_id') year_ids(`year_id') sex_ids(2) status(best) source(epi) clear

cap drop modelable_entity_id
gen modelable_entity_id = .

forvalues i = 0/999 {
	rename draw_`i' paf_yll_`i'
	gen double paf_yld_`i' = paf_yll_`i'
}

gen n = 1
joinby n using `INJ'
gen rei_id = `my_rei'

tempfile IPV
save `IPV', replace

** diabetes prevalence and FPG - we want to pull the dismod results
noi di c(current_time) + ": prep diabetes - TB"
qui do $j/temp/`username'/GBD_2015/risks/paf_calc_categ.do
get_draws, gbd_id_field(modelable_entity_id) gbd_id(2005) location_ids(`location_id') year_ids(`year_id') status(best) source(epi) clear
keep if measure_id==5 // prevalence
cap drop modelable_entity_id
gen modelable_entity_id = .
gen parameter = "cat1"
expand 2, gen(dup)
replace parameter = "cat2" if dup==1

forvalues i = 0/999 {
	replace draw_`i' = 1 - draw_`i' if dup == 1
}
drop dup

renpfix draw_ exp_
tempfile exp
save `exp', replace

local k = 0
foreach s in 1 2 {
		get_draws, gbd_id_field(rei_id) gbd_id(142) location_ids(`location_id') year_ids(`year_id') sex_ids(`s') status(best) kwargs(draw_type:rr) source(risk) clear
		cap destring year_id, replace
		cap destring sex_id, replace
		local k = `k' + 1
		tempfile `k'
		save ``k'', replace
	}
clear
forvalues i = 1/`k' {
	append using ``i''
}

		merge m:1 age_group_id parameter year_id sex_id using `exp', keep(3) nogen

		** generate TMREL
		levelsof parameter, c
		local L : word count `r(levels)'

		forvalues i = 0/999 {
			qui gen tmrel_`i' = 0
			replace tmrel_`i' = 1 if parameter=="cat`L'"
		}

		cap drop rei_id
		gen rei_id = 142 // FPG categorical
		duplicates drop
		calc_paf_categ exp_ rr_ tmrel_ paf_, by(age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mortality morbidity)
		keep age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mortality morbidity paf*

		expand 2 if mortality == 1 & morbidity == 1, gen(dup)
		replace morbidity = 0 if mortality == 1 & morbidity == 1 & dup == 0
		replace mortality = 0 if mortality == 1 & morbidity == 1 & dup == 1
		drop dup

		rename paf_* paf__*
		unab vars : paf__*
		local vars : subinstr local vars "__" "_@_", all
		duplicates drop
		gen mort_type = ""
			replace mort_type="yll" if mortality==1 & morbidity==0
			replace mort_type="yld" if mortality==0 & morbidity==1

		cap drop location_id 
		cap drop year_id
		gen location_id = `location_id'
		gen year_id = `year_id'
		keep age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id mort_type paf*
		reshape wide `vars', i(age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id) j(mort_type) string

append using `HIV'
append using `IV'
append using `IPV'
append using `CATZ'

keep age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id paf*
order age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id
keep if age_group_id<=21

tempfile data
save `data', replace

preserve

keep if rei_id==100
tempfile shs
save `shs', replace

restore
** aggregate smoking to adjust SHS
keep if inlist(rei_id,165,166)
foreach var of varlist paf* {
	replace `var' = log(1 - `var')
}

fastcollapse paf*, type(sum) by(age_group_id location_id sex_id year_id cause_id modelable_entity_id)
foreach var of varlist paf* {
	replace `var' = 1 - exp(`var')
	replace `var' = 1 if `var' == . 
}

tempfile smoking_direct
save `smoking_direct', replace

** adjust SHS PAF for smoking
	noi di c(current_time) + ": adjust SHS for smoking"
	** Smoking prevalence exposure
	odbc load, exec("SELECT modelable_entity_id FROM modelable_entity WHERE modelable_entity_name IN ('Smoking Prevalence')") `conn_string' clear
	levelsof modelable_entity_id, local(MEs) c

	noi di c(current_time) + ": pull smoking exposure"
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(`MEs') location_ids(`location_id') year_ids(`year_id') status(best) source(epi) clear
	renpfix draw_ smk_prev_
	tempfile smoking_prev
	save `smoking_prev', replace

	use `smoking_direct', clear
	renpfix paf_yll_ smk_paf_yll_
	renpfix paf_yld_ smk_paf_yld_

		merge 1:1 age_group_id cause_id year_id sex_id using `shs', keep(2 3) nogen
		merge m:1 age_group_id year_id sex_id using `smoking_prev', keep(2 3) nogen
		
		forvalues i = 0/999 {
			replace smk_paf_yll_`i' = 0 if smk_paf_yll_`i' == .
			replace smk_paf_yld_`i' = 0 if smk_paf_yld_`i' == .
			replace smk_prev_`i' = 0 if smk_prev_`i' == .
		}
		
	** Adjust PAF
		** SHS = SHS PAF among non-smokers * (non-smoker population) * (burden not attributble to smoking)
		forvalues i=0/999 {
			replace paf_yll_`i' = paf_yll_`i' * ((1 - smk_paf_yll_`i') * (1 - smk_prev_`i'))	
			replace paf_yld_`i' = paf_yld_`i' * ((1 - smk_paf_yld_`i') * (1 - smk_prev_`i'))
		}
		
		drop smk_paf_* smk_prev_*

	keep if rei_id==100 // keep just SHS
	cap levelsof age_group_id, local(ages) sep(,) c
	cap levelsof cause_id, local(causes) sep(,) c
	tempfile shs_adj
	save `shs_adj', replace

	use `data', clear
	cap drop if rei_id==100 & inlist(cause_id,`causes') & inlist(age_group_id,`ages') // drop unadjusted SHS PAF
	append using `shs_adj'

drop if inlist(rei_id,135,167,201,168) & sex_id==1

** Drop PAFs of 1 if they came through before joint calculation
duplicates drop
merge 1:1 rei_id age_group_id sex_id year_id cause_id using $j/temp/`username'/GBD_2015/risks/all_attrib_06_10_16.dta, keep(1) nogen

foreach x of varlist paf* {
  replace `x' = 0 if missing(`x') 
}

keep rei_id age_group_id location_id sex_id year_id cause_id paf*
tempfile data
save `data', replace

** Prep PAFs of 1
noi di c(current_time) + ": agg PAFs of 1"
use $j/temp/`username'/GBD_2015/risks/all_attrib_06_10_16.dta, clear
cap drop dup
expand 2 if rei_id==103 & cause_id==562, gen(dup)
replace cause_id=513 if dup==1
replace rei_id=129 if dup==1
drop dup

cap drop location_id
cap drop year_id
duplicates drop
gen year_id = `year_id'
gen location_id = `location_id'

tempfile A
save `A', replace

foreach x of numlist `max'(-1)0 {
use if level==`x' using `h_orig', clear
count
if `r(N)'==0 continue
	forvalues i=1/`r(N)' {
		use if level==`x' using `h_orig', clear
		levelsof children in `i', local(keep) c
		levelsof rei_id in `i', local(parent) c
		use if inlist(rei_id,`keep') using `A', clear

		count
		if `r(N)'==0 continue

		** aggregate
			foreach var of varlist paf_yll* paf_yld* {
				replace `var' = log(1 - `var')
			}

			fastcollapse paf_yld* paf_yll*, type(sum) by(age_group_id location_id sex_id year_id cause_id)
			** Exponentiate and complement.
			foreach var of varlist paf* {
				replace `var' = 1 - exp(`var')
				replace `var' = 1 if `var' == . 
			}

		gen rei_id=`parent'

		append using `A'
		save `A', replace
	}

}

forvalues i = 0/999 {
	replace paf_yld_`i' = 1
	replace paf_yll_`i' = 1
}

keep rei_id age_group_id location_id sex_id year_id cause_id paf*
duplicates drop
** overlaps of 1 too
expand 2 if inlist(rei_id,104,202), gen(dup) // metabolic, environmental
replace rei_id = 246 if dup==1
drop dup

expand 2 if inlist(rei_id,203,202), gen(dup) // b_e
replace rei_id = 247 if dup==1
drop dup

expand 2 if inlist(rei_id,104,203), gen(dup) // m_b
replace rei_id = 248 if dup==1
drop dup

expand 2 if inlist(rei_id,104,203,202), gen(dup) // b_e_m
replace rei_id = 249 if dup==1
drop dup

duplicates drop 

tempfile A
save `A', replace


noi di c(current_time) + ": begin joint PAF calculation"

** joint PAF calculation
** add mediation once finalized
foreach x of numlist `max'(-1)`min' {
use if level==`x' using `h', clear
count
if `r(N)'==0 continue
	forvalues i=1/`r(N)' {
		use if level==`x' using `h', clear
		levelsof children in `i', local(keep) c
		levelsof rei_id in `i', local(parent) c
		use if inlist(rei_id,`keep') using `data', clear

		count
		if `r(N)'==0 continue

		** mediate metabolic
		if `parent'==104 {
			merge m:1 rei_id cause_id using $j/WORK/05_risk/mediation/metab.dta, keep(1 3) assert(1 3)
		}

	cap confirm var mediate_0
	if _rc==0 {
		forvalues i = 0/999 {
			replace mediate_`i' = .99999999999999999 if mediate_`i'==1
			replace mediate_`i' = .00000000000000001 if mediate_`i'==0
			replace paf_yll_`i' = paf_yll_`i' * mediate_`i' if _merge==3
			replace paf_yld_`i' = paf_yld_`i' * mediate_`i' if _merge==3
		}
		drop _merge mediate*
	}
		** aggregate
			foreach var of varlist paf_yll* paf_yld* {
				replace `var' = log(1 - `var')
			}

			fastcollapse paf_yld* paf_yll*, type(sum) by(age_group_id location_id sex_id year_id cause_id)
			foreach var of varlist paf* {
				replace `var' = 1 - exp(`var')
				replace `var' = 1 if `var' == . 
			}

		gen rei_id=`parent'

		append using `data'
		save `data', replace
	}

}

** behav mediation calc
noi di c(current_time) + ": begin behavioral calculation"

use `behav_h', clear
replace all_my_most_detailed_children = subinstr(all_my_most_detailed_children,","," ",.)
levelsof all_my_most_detailed_children, local (risks) c
levelsof rei_id, local(PARENT) c

** need to append since inlist only takes 10 args total
local DF = 0
foreach risk of local risks {
	use if rei_id==`risk' using `data', clear
	local DF = `DF' + 1
	tempfile `DF'
	save ``DF'', replace

}

clear
forvalues i = 1/`DF' {
	append using ``i''
}

merge m:1 rei_id cause_id using $j/WORK/05_risk/mediation/_behav.dta, keep(1 3) assert(1 3)
forvalues i = 0/999 {
	replace mediate_`i' = .99999999999999999 if mediate_`i'==1
	replace mediate_`i' = .00000000000000001 if mediate_`i'==0
	replace paf_yll_`i' = paf_yll_`i' * mediate_`i' if _merge==3
	replace paf_yld_`i' = paf_yld_`i' * mediate_`i' if _merge==3
}

drop _merge mediate*
** aggregate
foreach var of varlist paf_yll* paf_yld* {
	replace `var' = log(1 - `var')
}

fastcollapse paf_yld* paf_yll*, type(sum) by(age_group_id location_id sex_id year_id cause_id)
foreach var of varlist paf* {
	replace `var' = 1 - exp(`var')
	replace `var' = 1 if `var' == . 
}

gen rei_id=`PARENT'
tempfile B
save `B', replace

** all calculation
use `all_h', clear
noi di c(current_time) + ": begin all calculation"

replace all_my_most_detailed_children = subinstr(all_my_most_detailed_children,","," ",.)
levelsof all_my_most_detailed_children, local (risks) c
levelsof rei_id, local(PARENT) c

** need to append since inlist only takes 10 args total
local DF = 0
foreach risk of local risks {
	use if rei_id==`risk' using `data', clear
	local DF = `DF' + 1
	tempfile `DF'
	save ``DF'', replace

}

clear
forvalues i = 1/`DF' {
	append using ``i''
}

merge m:1 rei_id cause_id using $j/WORK/05_risk/mediation/_all.dta, keep(1 3) assert(1 3)
forvalues i = 0/999 {
	replace mediate_`i' = .99999999999999999 if mediate_`i'==1
	replace mediate_`i' = .00000000000000001 if mediate_`i'==0
	replace paf_yll_`i' = paf_yll_`i' * mediate_`i' if _merge==3
	replace paf_yld_`i' = paf_yld_`i' * mediate_`i' if _merge==3
}

drop _merge mediate*
** aggregate
foreach var of varlist paf* {
	replace `var' = log(1 - `var')
}

fastcollapse paf_yld* paf_yll*, type(sum) by(age_group_id location_id sex_id year_id cause_id)
foreach var of varlist paf* {
	replace `var' = 1 - exp(`var')
	replace `var' = 1 if `var' == . 
}

gen rei_id=`PARENT'
append using `B'
append using `data'
save `data', replace

** calc overlaps
** m_e
noi di c(current_time) + ": begin m_e calculation"
use `h', clear
keep if rei_id==104
rename children all_my_most_detailed_children
append using `env_h'
rename all_my_most_detailed_children children
replace children = subinstr(children,","," ",.)
levelsof children, local(risks) c

local DF = 0
foreach risk of local risks {
	use if rei_id==`risk' using `data', clear
	local DF = `DF' + 1
	tempfile `DF'
	save ``DF'', replace

}

clear
forvalues i = 1/`DF' {
	append using ``i''
}

merge m:1 rei_id cause_id using $j/WORK/05_risk/mediation/m_e.dta, keep(1 3) assert(1 3)

		forvalues i = 0/999 {
			replace mediate_`i' = .99999999999999999 if mediate_`i'==1
			replace mediate_`i' = .00000000000000001 if mediate_`i'==0
			replace paf_yll_`i' = paf_yll_`i' * mediate_`i' if _merge==3
			replace paf_yld_`i' = paf_yld_`i' * mediate_`i' if _merge==3
		}
		drop _merge mediate*

foreach var of varlist paf_yll* paf_yld* {
replace `var' = log(1 - `var')
}
fastcollapse paf_yld* paf_yll*, type(sum) by(age_group_id location_id sex_id year_id cause_id)
foreach var of varlist paf* {
replace `var' = 1 - exp(`var')
replace `var' = 1 if `var' == . 
}

gen rei_id = 246
tempfile m_e
save `m_e', replace

** b_e
noi di c(current_time) + ": begin b_e calculation"
use `behav_h', clear
append using `env_h'
rename all_my_most_detailed_children children
replace children = subinstr(children,","," ",.)
levelsof children, local(risks) c

local DF = 0
foreach risk of local risks {
	use if rei_id==`risk' using `data', clear
	local DF = `DF' + 1
	tempfile `DF'
	save ``DF'', replace

}

clear
forvalues i = 1/`DF' {
	append using ``i''
}

merge m:1 rei_id cause_id using $j/WORK/05_risk/mediation/b_e.dta, keep(1 3) assert(1 3)

		forvalues i = 0/999 {
			replace mediate_`i' = .99999999999999999 if mediate_`i'==1
			replace mediate_`i' = .00000000000000001 if mediate_`i'==0
			replace paf_yll_`i' = paf_yll_`i' * mediate_`i' if _merge==3
			replace paf_yld_`i' = paf_yld_`i' * mediate_`i' if _merge==3
		}
		drop _merge mediate*

foreach var of varlist paf_yll* paf_yld* {
replace `var' = log(1 - `var')
}
fastcollapse paf_yld* paf_yll*, type(sum) by(age_group_id location_id sex_id year_id cause_id)
foreach var of varlist paf* {
replace `var' = 1 - exp(`var')
replace `var' = 1 if `var' == . 
}

gen rei_id = 247
tempfile b_e
save `b_e', replace

** m_b
noi di c(current_time) + ": begin m_b calculation"

use `h', clear
keep if rei_id==104
rename children all_my_most_detailed_children
append using `behav_h'
rename all_my_most_detailed_children children
replace children = subinstr(children,","," ",.)
levelsof children, local(risks) c

local DF = 0
foreach risk of local risks {
	use if rei_id==`risk' using `data', clear
	local DF = `DF' + 1
	tempfile `DF'
	save ``DF'', replace

}

clear
forvalues i = 1/`DF' {
	append using ``i''
}

merge m:1 rei_id cause_id using $j/WORK/05_risk/mediation/m_b.dta, keep(1 3)

		forvalues i = 0/999 {
			replace mediate_`i' = .99999999999999999 if mediate_`i'==1
			replace mediate_`i' = .00000000000000001 if mediate_`i'==0
			replace paf_yll_`i' = paf_yll_`i' * mediate_`i' if _merge==3
			replace paf_yld_`i' = paf_yld_`i' * mediate_`i' if _merge==3
		}
		drop _merge mediate*

foreach var of varlist paf_yll* paf_yld* {
replace `var' = log(1 - `var')
}
fastcollapse paf_yld* paf_yll*, type(sum) by(age_group_id location_id sex_id year_id cause_id)
foreach var of varlist paf* {
replace `var' = 1 - exp(`var')
replace `var' = 1 if `var' == . 
}

gen rei_id = 248
tempfile m_b
save `m_b', replace

append using `b_e'
append using `m_e'
append using `data'

noi di c(current_time) + ": joint PAF calculation complete"

noi di c(current_time) + ": append PAFs of 1"

** Make sure PAFs of 1 are also set for aggregates
merge 1:1 rei_id age_group_id sex_id year_id cause_id using `A', keep(1) nogen
append using `A'
keep rei_id age_group_id sex_id cause_id paf*
cap drop *draw*
duplicates drop
gen location_id = `location_id'
gen year_id = `year_id'
foreach var of varlist paf* {
	replace `var'=0 if `var'==.
	replace `var' = 1 if `var'>1
	replace `var' = -.999999 if `var'<-1
}

compress
save "/share/central_comp/pafs/`risk_version'/`location_id'_`year_id'.dta", replace

noi di c(current_time) + ": SAVED!"


} // end quiet loop










