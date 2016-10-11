** Rescale u5 iteration numbers to nationals


clear all
set more off
set memory 6000m
cap restore, not

	if (c(os)=="Unix") {
		global root "StrPath"
		set odbcmgr unixodbc
		qui do "StrPath/get_locations.ado"
	} 
	if (c(os)=="Windows") { 
		global root "J:"
		qui do "StrPath/get_locations.ado"
	}

get_locations, level("all")
tempfile locs
save `locs', replace

use "StrPath\u5_pop_iteration.dta", clear
keep if year >= 1975
keep year sex ihme_loc_id pys_enn pys_lnn pys_pnn pys_1 pys_2 pys_3 pys_4 
reshape long pys_, i(year sex ihme_loc_id) j(age, string)
merge m:1 ihme_loc_id using `locs'
keep if _m == 3
drop _m

preserve
keep ihme_loc_id
duplicates drop
assert _N == 561
restore

rename pys_ pop

preserve
keep if parent_id == 6
collapse (sum) pop, by(year sex age)
gen ihme_loc_id = "CHN"
merge m:1 ihme_loc_id using `locs', keep(3) nogen
tempfile chn
save `chn', replace
restore
append using `chn'

preserve
keep if parent_id == 4749
collapse (sum) pop, by(year sex age)
gen ihme_loc_id = "GBR_4749"
merge m:1 ihme_loc_id using `locs', keep(3) nogen
tempfile eng
save `eng', replace
restore
append using `eng'


preserve
keep ihme_loc_id
duplicates drop
assert _N == 563
restore


keep ihme_loc_id year sex pop location_id location_name age parent_id level

sum level
tempfile master_unscaled
save `master_unscaled'

local max_level = `r(max)'
forvalues i = 4/`max_level' {
				local iminus = `i' - 1 
				
				if `i' == 4 use `master_unscaled', clear
				else use `temp_`iminus'', clear
				keep if level == `iminus'
				keep location_id year sex age pop
				rename (location_id pop) (parent_id pop_parent)
				tempfile temp_save
				save `temp_save'
				

				use `master_unscaled', clear
				keep if level == `i'
				merge m:1 parent_id year sex age using `temp_save', keep(3) nogen
				bysort year sex age parent_id: egen summed_pop = sum(pop)
				gen scale_factor = pop_parent / summed_pop
				replace pop = scale_factor * pop
				drop scale_factor summed_pop parent_id pop_parent
				tempfile temp_`i'
				save `temp_`i''
}

use `master_unscaled', clear
keep if level == 3
forvalues i = 4/`max_level' {
				append using `temp_`i''
}
	
rename pop pys_	
reshape wide pys_, i(year sex ihme_loc_id) j(age, string)
keep ihme_loc_id year sex pys*
order ihme_loc_id year sex pys*
gen pys_1_4 = pys_1 + pys_2 + pys_3 + pys_4
tempfile scaled
save `scaled', replace


adopath + "StrPath"
get_locations, level(all)
keep ihme_loc_id local_id_2013 parent_id
rename local_id_2013 iso3
drop if iso3 == ""
tempfile loc_map
save `loc_map'


	use `scaled', clear
	
	drop if year < 1975 
	
	gen pys_0 = pys_enn + pys_lnn + pys_pnn
	rename pys_* PY_*
	
	tempfile data
	save `data', replace

	keep ihme_loc_id sex year PY_1 PY_2 PY_3 PY_4 PY_pnn PY_lnn PY_enn
	
	foreach var of varlist PY_* {
		rename `var' `var'_
	}
	
	reshape wide PY_*, i(ihme_loc_id sex) j(year) 

	gen delta_4 = ln(PY_4_1975/PY_4_1980)/(1980-1975)
	gen delta_3 = ln(PY_3_1975/PY_3_1980)/(1980-1975)
	gen delta_2 = ln(PY_2_1975/PY_2_1980)/(1980-1975)
	gen delta_1 = ln(PY_1_1975/PY_1_1980)/(1980-1975)
	gen delta_pnn = ln(PY_pnn_1975/PY_pnn_1980)/(1980-1975)
	gen delta_lnn = ln(PY_lnn_1975/PY_lnn_1980)/(1980-1975)
	gen delta_enn = ln(PY_enn_1975/PY_enn_1980)/(1980-1975)

	gen PY_4_1974 = PY_4_1975*exp((1975-1974)*delta_4)
	gen PY_4_1973 = PY_4_1975*exp((1975-1973)*delta_4)
	gen PY_4_1972 = PY_4_1975*exp((1975-1972)*delta_4)
	gen PY_4_1971 = PY_4_1975*exp((1975-1971)*delta_4)
	gen PY_4_1970 = PY_4_1975*exp((1975-1970)*delta_4)

	gen PY_3_1974 = PY_3_1975*exp((1975-1974)*delta_3)
	gen PY_3_1973 = PY_3_1975*exp((1975-1973)*delta_3)
	gen PY_3_1972 = PY_3_1975*exp((1975-1972)*delta_3)
	gen PY_3_1971 = PY_3_1975*exp((1975-1971)*delta_3)
	gen PY_3_1970 = PY_3_1975*exp((1975-1970)*delta_3)

	gen PY_2_1974 = PY_2_1975*exp((1975-1974)*delta_2)
	gen PY_2_1973 = PY_2_1975*exp((1975-1973)*delta_2)
	gen PY_2_1972 = PY_2_1975*exp((1975-1972)*delta_2)
	gen PY_2_1971 = PY_2_1975*exp((1975-1971)*delta_2)
	gen PY_2_1970 = PY_2_1975*exp((1975-1970)*delta_2)

	gen PY_1_1974 = PY_1_1975*exp((1975-1974)*delta_1)
	gen PY_1_1973 = PY_1_1975*exp((1975-1973)*delta_1)
	gen PY_1_1972 = PY_1_1975*exp((1975-1972)*delta_1)
	gen PY_1_1971 = PY_1_1975*exp((1975-1971)*delta_1)
	gen PY_1_1970 = PY_1_1975*exp((1975-1970)*delta_1)

	gen PY_pnn_1974 = PY_pnn_1975*exp((1975-1974)*delta_pnn)
	gen PY_pnn_1973 = PY_pnn_1975*exp((1975-1973)*delta_pnn)
	gen PY_pnn_1972 = PY_pnn_1975*exp((1975-1972)*delta_pnn)
	gen PY_pnn_1971 = PY_pnn_1975*exp((1975-1971)*delta_pnn)
	gen PY_pnn_1970 = PY_pnn_1975*exp((1975-1970)*delta_pnn)

	gen PY_lnn_1974 = PY_lnn_1975*exp((1975-1974)*delta_lnn)
	gen PY_lnn_1973 = PY_lnn_1975*exp((1975-1973)*delta_lnn)
	gen PY_lnn_1972 = PY_lnn_1975*exp((1975-1972)*delta_lnn)
	gen PY_lnn_1971 = PY_lnn_1975*exp((1975-1971)*delta_lnn)
	gen PY_lnn_1970 = PY_lnn_1975*exp((1975-1970)*delta_lnn)

	gen PY_enn_1974 = PY_enn_1975*exp((1975-1974)*delta_enn)
	gen PY_enn_1973 = PY_enn_1975*exp((1975-1973)*delta_enn)
	gen PY_enn_1972 = PY_enn_1975*exp((1975-1972)*delta_enn)
	gen PY_enn_1971 = PY_enn_1975*exp((1975-1971)*delta_enn)
	gen PY_enn_1970 = PY_enn_1975*exp((1975-1970)*delta_enn)
	drop delta*

	reshape long PY_4_ PY_3_ PY_2_ PY_1_ PY_pnn_ PY_lnn_ PY_enn_, i(ihme_loc_id sex) j(year)

	tempfile backcast 
	save `backcast', replace 
	
	use `data', clear
	merge 1:1 ihme_loc_id sex year using `backcast', keep(2 3) nogen 

	foreach var of varlist  PY_1 PY_2 PY_3 PY_4 PY_pnn PY_lnn PY_enn {
		replace `var' = `var'_ if year <= 1974		
	}

	replace PY_0 = PY_enn + PY_lnn + PY_pnn if year < 1975 
	replace PY_1_4 = PY_1 + PY_2 + PY_3 + PY_4 if year < 1975
	keep ihme_loc_id year sex PY_0 PY_1_4 PY_enn PY_lnn PY_pnn
	
	rename PY_* new_pop_*
	
	tempfile pop_1970
	save `pop_1970'
	
	
use "StrPath/under5_pop_updated_data_iteration_final.dta", clear

rename pys PY_
reshape wide PY_, i(iso3 sex year) j(age, string)

gen new_pop_enn = PY_enn
gen new_pop_lnn = PY_lnn
gen new_pop_pnn = PY_pnn
gen new_pop_0 = PY_enn + PY_lnn + PY_pnn
gen new_pop_1_4 = PY_1 + PY_2 + PY_3 + PY_4

tempfile data
save `data', replace

keep iso3 sex year PY_1 PY_2 PY_3 PY_4 PY_pnn PY_lnn PY_enn
foreach var of varlist PY* {
	rename `var' `var'_
}

reshape wide PY*, i(iso3 sex) j(year)

gen delta_4 = ln(PY_4_1955/PY_4_1960)/(1960-1955)
gen delta_3 = ln(PY_3_1955/PY_3_1960)/(1960-1955)
gen delta_2 = ln(PY_2_1955/PY_2_1960)/(1960-1955)
gen delta_1 = ln(PY_1_1955/PY_1_1960)/(1960-1955)
gen delta_pnn = ln(PY_pnn_1955/PY_pnn_1960)/(1960-1955)
gen delta_lnn = ln(PY_lnn_1955/PY_lnn_1960)/(1960-1955)
gen delta_enn = ln(PY_enn_1955/PY_enn_1960)/(1960-1955)

gen PY_4_1954 = PY_4_1955*exp((1955-1954)*delta_4)
gen PY_4_1953 = PY_4_1955*exp((1955-1953)*delta_4)
gen PY_4_1952 = PY_4_1955*exp((1955-1952)*delta_4)
gen PY_4_1951 = PY_4_1955*exp((1955-1951)*delta_4)
gen PY_4_1950 = PY_4_1955*exp((1955-1950)*delta_4)

gen PY_3_1954 = PY_3_1955*exp((1955-1954)*delta_3)
gen PY_3_1953 = PY_3_1955*exp((1955-1953)*delta_3)
gen PY_3_1952 = PY_3_1955*exp((1955-1952)*delta_3)
gen PY_3_1951 = PY_3_1955*exp((1955-1951)*delta_3)
gen PY_3_1950 = PY_3_1955*exp((1955-1950)*delta_3)

gen PY_2_1954 = PY_2_1955*exp((1955-1954)*delta_2)
gen PY_2_1953 = PY_2_1955*exp((1955-1953)*delta_2)
gen PY_2_1952 = PY_2_1955*exp((1955-1952)*delta_2)
gen PY_2_1951 = PY_2_1955*exp((1955-1951)*delta_2)
gen PY_2_1950 = PY_2_1955*exp((1955-1950)*delta_2)

gen PY_1_1954 = PY_1_1955*exp((1955-1954)*delta_1)
gen PY_1_1953 = PY_1_1955*exp((1955-1953)*delta_1)
gen PY_1_1952 = PY_1_1955*exp((1955-1952)*delta_1)
gen PY_1_1951 = PY_1_1955*exp((1955-1951)*delta_1)
gen PY_1_1950 = PY_1_1955*exp((1955-1950)*delta_1)

gen PY_pnn_1954 = PY_pnn_1955*exp((1955-1954)*delta_pnn)
gen PY_pnn_1953 = PY_pnn_1955*exp((1955-1953)*delta_pnn)
gen PY_pnn_1952 = PY_pnn_1955*exp((1955-1952)*delta_pnn)
gen PY_pnn_1951 = PY_pnn_1955*exp((1955-1951)*delta_pnn)
gen PY_pnn_1950 = PY_pnn_1955*exp((1955-1950)*delta_pnn)

gen PY_lnn_1954 = PY_lnn_1955*exp((1955-1954)*delta_lnn)
gen PY_lnn_1953 = PY_lnn_1955*exp((1955-1953)*delta_lnn)
gen PY_lnn_1952 = PY_lnn_1955*exp((1955-1952)*delta_lnn)
gen PY_lnn_1951 = PY_lnn_1955*exp((1955-1951)*delta_lnn)
gen PY_lnn_1950 = PY_lnn_1955*exp((1955-1950)*delta_lnn)

gen PY_enn_1954 = PY_enn_1955*exp((1955-1954)*delta_enn)
gen PY_enn_1953 = PY_enn_1955*exp((1955-1953)*delta_enn)
gen PY_enn_1952 = PY_enn_1955*exp((1955-1952)*delta_enn)
gen PY_enn_1951 = PY_enn_1955*exp((1955-1951)*delta_enn)
gen PY_enn_1950 = PY_enn_1955*exp((1955-1950)*delta_enn)

reshape long PY_4_ PY_3_ PY_2_ PY_1_ PY_pnn_ PY_lnn_ PY_enn_, i(iso3 sex) j(year)

tempfile backcast 
save `backcast', replace 

use "`data'", replace

merge 1:1 iso3 sex year using `backcast'
drop _m 

foreach var of varlist  PY_1 PY_2 PY_3 PY_4 PY_pnn PY_lnn PY_enn {
	replace `var' = `var'_ if year <= 1954		
}


replace new_pop_0 = PY_enn + PY_lnn + PY_pnn if year < 1955 
replace new_pop_1_4 = PY_1 + PY_2 + PY_3 + PY_4 if year < 1955
replace new_pop_pnn = PY_pnn if year < 1955
replace new_pop_lnn = PY_lnn if year < 1955
replace new_pop_enn = PY_enn if year < 1955

keep iso3 year sex new*
merge m:1 iso3 using `loc_map'
replace ihme_loc_id = "CHN_44533" if iso3 == "CHN"
replace parent_id = 6 if ihme_loc_id == "CHN_44533"
keep if _m == 3
drop _m
drop iso3

preserve
keep if parent_id == 6
collapse (sum) new_pop*, by(year sex)
gen ihme_loc_id = "CHN"
merge m:1 ihme_loc_id using `locs', keep(3) nogen
tempfile chn
save `chn', replace
restore
append using `chn'

preserve
keep if parent_id == 4749
collapse (sum) new_pop*, by(year sex)
gen ihme_loc_id = "GBR_4749"
merge m:1 ihme_loc_id using `locs', keep(3) nogen
tempfile eng
save `eng', replace
restore
append using `eng'

keep if year < 1970
append using `pop_1970'

sort ihme_loc_id sex year
order ihme_loc_id sex year

rename new_pop_* pys_*

reshape long pys_, i(year sex ihme_loc_id) j(age, string)
merge m:1 ihme_loc_id using `locs', update replace
keep if _m == 3 | _m == 4
drop _m

rename pys_ pop


keep ihme_loc_id year sex pop location_id location_name age parent_id level

tempfile master_unscaled
save `master_unscaled'


sum level
local max_level = `r(max)'

forvalues i = 4/`max_level' {
				local iminus = `i' - 1 
				
				if `i' == 4 use `master_unscaled', clear
				else use `temp_`iminus'', clear
				keep if level == `iminus'
				keep location_id year sex age pop
				rename (location_id pop) (parent_id pop_parent)
				tempfile temp_save
				save `temp_save'
				

				use `master_unscaled', clear
				keep if level == `i'
				merge m:1 parent_id year sex age using `temp_save', keep(1 3) nogen
				bysort year sex age parent_id: egen summed_pop = sum(pop)
				gen scale_factor = pop_parent / summed_pop
				replace pop = scale_factor * pop if scale_factor != .
				drop scale_factor summed_pop parent_id pop_parent
				tempfile temp_`i'
				save `temp_`i''
}

use `master_unscaled', clear
keep if level == 3
forvalues i = 4/`max_level' {
				append using `temp_`i''
}
	
rename pop pys_	
reshape wide pys_, i(year sex ihme_loc_id) j(age, string)
keep ihme_loc_id year sex pys*
order ihme_loc_id year sex pys*
rename pys* new_pop*

merge m:1 ihme_loc_id using `locs'
assert _m != 1
keep if _m == 3
keep ihme_loc_id year sex new_pop*

summ year
local max_year = `r(max)'
local years = `max_year' - 1950 + 1

preserve
keep ihme_loc_id 
duplicates drop
expand `years'
bysort ihme_loc_id: gen year = _n + 1949
expand 2
bysort ihme_loc_id year: gen sex = "male" if _n == 1
by ihme_loc_id year: replace sex = "female" if _n == 2
tempfile square
save `square', replace
restore
merge 1:1 ihme_loc_id year sex using `square'
assert _m == 3 | (year < 1970 & (regexm(ihme_loc_id,"IND_") | regexm(ihme_loc_id,"JPN_") | regexm(ihme_loc_id,"USA_") | regexm(ihme_loc_id,"ASM") | regexm(ihme_loc_id,"BRA_") | regexm(ihme_loc_id,"GUM") | regexm(ihme_loc_id,"VIR") | regexm(ihme_loc_id,"ZAF_") | regexm(ihme_loc_id,"SWE_") | regexm(ihme_loc_id,"SAU_") | regexm(ihme_loc_id,"KEN_") | regexm(ihme_loc_id,"MNP") | regexm(ihme_loc_id,"GRL") | regexm(ihme_loc_id,"CHN_44533")))
keep if _m == 3
drop _m

save "StrPath\u5_pop_iteration_scaled.dta", replace
save "StrPath\u5_pop_iteration_scaled_$S_DATE.dta", replace




