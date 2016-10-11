qui {
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

adopath + "$j/WORK/10_gbd/00_library/functions"
local username = c(username)

if "`2'" == "" {

	local risk = "occ_hearing"
	local rei_id = 130
	local location_id = 101 // Ukraine
	local year_id = 1990
	local sex_id = 1
	local epi = 87

}

else if "`2'" !="" {
	local risk = "`1'"
	local rei_id = "`2'"
	local location_id = "`3'"
	local year_id = "`4'"
	local sex_id = "`5'"
	local epi = "`6'"
}

noi di c(current_time) + ": begin"

noi di "risk = `risk'"
noi di "rei_id = `rei_id'"
noi di "location_id = `location_id'"
noi di "year_id = `year_id'"
noi di "sex_id = `sex_id'"

local epi_dir "/ihme/centralcomp/como/`epi'/draws/cause/total_csvs"

cap mkdir /ihme/epi/risk/paf/`risk'_interm

run $j/temp/`username'/GBD_2015/risks/paf_calc_categ.do

insheet using /share/epi/risk/rr/occ_hearing/2013/rr_1.csv, clear
	
gen sequela_id = ""
replace sequela_id = "40,63,86,109,582,631" if acause==" sense_hearing + _hearing + hearing_comp"
replace sequela_id = "30,53,76,99,576,621,972,1054" if acause==" sense_hearing + _hearing + hearing_mild"
replace sequela_id = "32,55,78,101,578,623,1102,1104" if acause==" sense_hearing + _hearing + hearing_mod"
replace sequela_id = "34,57,80,103,584,625" if acause==" sense_hearing + _hearing + hearing_modsev"
replace sequela_id = "38,61,84,107,586,629" if acause==" sense_hearing + _hearing + hearing_prof"
replace sequela_id = "41,64,87,110,583,632" if acause==" sense_hearing + _hearing + hearing_ring_comp"
replace sequela_id = "31,54,77,100,577,622,973,1055" if acause==" sense_hearing + _hearing + hearing_ring_mild"
replace sequela_id = "33,56,79,102,579,624,1103,1105" if acause==" sense_hearing + _hearing + hearing_ring_mod"
replace sequela_id = "35,58,81,104,585,626" if acause==" sense_hearing + _hearing + hearing_ring_modsev"
replace sequela_id = "39,62,85,108,587,630" if acause==" sense_hearing + _hearing + hearing_ring_prof"
replace sequela_id = "37,60,83,106,580,627" if acause==" sense_hearing + _hearing + hearing_ring_sev"
replace sequela_id = "36,59,82,105,581,628" if acause==" sense_hearing + _hearing + hearing_sev"
replace sequela_id = subinstr(sequela_id,","," ",.)

tempfile rr
save `rr', replace

** get exposure draws
noi di c(current_time) + ": get exposure draws"
get_draws, gbd_id_field(rei_id) gbd_id(`rei_id') year_ids(`year_id') sex_ids(`sex_id') location_ids(`location_id') status(best) kwargs(draw_type:exposure) source(risk) clear
renpfix draw_ exp_
cap drop modelable_entity_id
noi di c(current_time) + ": exposure draws read"
merge 1:m age_group_id parameter year_id using `rr', keep(3) nogen

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

calc_paf_categ exp_ rr_ tmrel_ paf_, by(age_group_id rei_id location_id sex_id year_id sequela_id)

noi di c(current_time) + ": PAF calc complete"

keep age_group_id rei_id location_id sex_id year_id sequela_id paf*

tempfile paf
save `paf', replace

noi di c(current_time) + ": read sequela"

keep sequela_id
duplicates drop
levelsof sequela_id, local(all) c
gen n = _n
local count = _N
tempfile s_list
save `s_list', replace

** read in seqeula for each row
local y = 5000

qui {
forvalues iii = 1/`count' {
	use if n==`iii' using `s_list', clear
	levelsof sequela_id, local(ss) c
	local x = 0
		foreach s of local ss {
			get_draws, location_ids(`location_id') year_ids(`year_id') status(best) source(como) gbd_id(`s') gbd_id_field(sequela_id) measure_ids(3) clear
			local x = `x' + 1
			tempfile `x'
			save ``x'', replace
		}

		clear
		forvalues n = 1/`x' {
			append using ``n''
		}

		renpfix draw_ yld_

		fastcollapse yld_*, type(sum) by(age_group_id location_id sex_id year_id)

		gen sequela_id = "`ss'"

		noi di "appended row `iii' sequela: `ss'"
		merge 1:m age_group_id sex_id location_id year_id sequela_id using `paf', keep(3) nogen
			forvalues i = 0/999 {
				qui replace yld_`i' = yld_`i' * paf_`i'
			}
		keep age_group_id rei_id location_id sex_id year_id sequela_id yld*

		local y = `y' + 1
		tempfile `y'
		save ``y'', replace
}
}

clear
forvalues w = 5001/`y' {
	append using ``w''
}

fastcollapse yld*, type(sum) by(age_group_id rei_id location_id sex_id year_id)
gen cause_id = 674 // hearing loss
tempfile ab
save `ab', replace


import delimited using "`epi_dir'/3_`location_id'_`year_id'_`sex_id'.csv", asdouble varname(1) clear
keep if cause_id == 674
renpfix draw_ yld_
append using `ab'

gen denominator = .
replace denominator = (rei_id == .)
fastfraction yld*, by(year_id sex_id cause_id age_group_id) denominator(denominator) prefix(paf_) 
keep if rei_id==`rei_id'
keep rei_id year_id sex_id cause_id age_group_id paf*
gen location_id = `location_id'
gen modelable_entity_id=.

renpfix paf_yld_ paf_
outsheet age_group_id rei_id location_id sex_id year_id cause_id modelable_entity_id paf* using "/ihme/epi/risk/paf/`risk'_interm/paf_yld_`location_id'_`year_id'_`sex_id'.csv" if year_id == `year_id' & sex_id == `sex_id', comma replace

} // end quiet loop



