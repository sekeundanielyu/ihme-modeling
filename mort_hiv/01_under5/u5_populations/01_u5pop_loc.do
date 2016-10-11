***********************************************************************************
*** under-5 envelope estimation based on qx values from child mortality process ***
*** updated with population estimates ***
***********************************************************************************

clear 
set more off
set seed 1234567
set memory 3000m


di "`1'"
di "`2'"

	if (c(os)=="Unix") {
		global j "StrPath"
		set odbcmgr unixodbc
		global ctmp "StrPath"
		local ihme_loc_id = "`1'"
		local code_dir "`2'"
		qui do "StrPath/get_locations.ado"
	} 
	if (c(os)=="Windows") { 
		global j "StrPath"
		qui do "StrPath/get_locations.ado"
		local ihme_loc_id = "AFG"
	}

	get_locations, level(estimate)
	keep if level_all == 1
	keep ihme_loc_id
	tempfile codes
	save `codes', replace

use "StrPath/population_gbd2015.dta", clear
keep if ihme_loc_id == "`ihme_loc_id'"
keep if inlist(age_group_id,2,3,4,5)
keep ihme_loc_id year sex age_group_id pop
replace year = year + .5
tempfile envpop
save `envpop', replace


tempfile malelts femalelts hmdlts
*** males ***
global working "StrPath/mltper_1x1"
local sfiles: dir "$working" files "*.txt", respectcase
foreach file of local sfiles {
	cd "$working"
    infix year 1-10 str age 11-22 lx 47-55 using `file', clear
	drop if year==.
	gen iso3=reverse(substr(reverse("`file'"),16,.))
	cap append using `malelts'
	save `malelts', replace
}
gen sex="male"
save `malelts', replace

*** females ***
global working "StrPath/fltper_1x1"
local sfiles: dir "$working" files "*.txt", respectcase
foreach file of local sfiles {
	cd "$working"
    infix year 1-10 str age 11-22 lx 47-55 using `file', clear
	drop if year==.
	gen iso3=reverse(substr(reverse("`file'"),16,.))
	cap append using `femalelts'
	save `femalelts', replace
}
gen sex="female"
append using `malelts'
destring age, ignore("+") replace
sort iso3 sex year age
bysort iso3 sex year: gen qx=1-lx[_n+1]/lx
gen agefive=0 if age==0
replace agefive=1 if age>=1 & age<=4
forvalues j=5(5)105 {
	replace agefive=`j' if age>=`j' & age<=`j'+4
}
replace agefive=110 if age==110
sort iso3 sex year agefive age
save `hmdlts'
keep iso3 sex year age agefive lx
keep if age==agefive
keep if year>1949
replace lx=lx/100000
sort iso3 sex year age
bysort iso3 sex year: gen qxfive=1-lx[_n+1]/lx
keep iso3 sex year agefive qxfive
sort iso3 sex year agefive
merge iso3 sex year agefive using `hmdlts'
keep if _merge==3
drop _merge
drop if age>4
tempfile pars
gen lnqx=ln(qx)
gen lnfive=ln(qxfive)
keep if year>1950

sort iso3 sex year age
bysort iso3 sex year: gen qinf=qx[1]
gen lnqinf=ln(qinf)

forvalues j=1/4 {
    preserve
	reg lnqx lnfive if sex=="male" & age==`j'
	clear
	set obs 1
	gen sex="male"
	gen par_lnfive=_b[lnfive]
	gen par_cons=_b[_cons]
	gen age=`j'
	cap append using `pars'
	save `pars',replace
	restore
	preserve
	reg lnqx lnfive if sex=="female" & age==`j'
	clear
	set obs 1
	gen sex="female"
	gen par_lnfive=_b[lnfive]
	gen par_cons=_b[_cons]
	gen age=`j'
	cap append using `pars'
	save `pars',replace
	restore
}


use "StrPath/births_gbd2015.dta", clear
drop if sex=="both"
keep ihme_loc_id sex year births

merge m:1 ihme_loc_id using `codes'
keep if _merge==3
drop _merge
	
tempfile births
save `births'


insheet using "StrPath/env_`ihme_loc_id'.csv", clear
rename year_id year
rename sex_id sex
replace year = year + .5
gen ihme_loc_id = "`ihme_loc_id'"
keep if inlist(age_group_id,2,3,4,5)
tostring sex, replace
replace sex = "male" if sex == "1"
replace sex = "female" if sex == "2"
replace sex = "both" if sex == "3"
merge 1:1 year sex age_group_id ihme_loc_id using `envpop'
drop if _m == 2
assert pop != .
drop _m
tostring age_group_id, gen(age)
replace age = "enn" if age == "2"
replace age = "lnn" if age == "3" 
replace age = "pnn" if age == "4" 
replace age = "ch" if age == "5"
forvalues i = 0/999 {
	replace draw_`i' = draw_`i'/pop
	replace draw_`i' = 1 - exp(-7/365*draw_`i') if age == "enn"
	replace draw_`i' = 1 - exp(-21/365*draw_`i') if age == "lnn"
	replace draw_`i' = 1 - exp(-1*(365-21-7)/365*draw_`i') if age == "pnn"
	replace draw_`i' = 1 - exp(-4*draw_`i') if age == "ch"
}
drop pop

reshape long draw_, i(age_group_id age sex year ihme_loc_id) j(simulation)
rename draw_ q_
drop age_group_id
reshape wide q_, i(sex year ihme_loc_id simulation) j(age, string)
tempfile qxs
save `qxs', replace

insheet using "StrPath/lt_`ihme_loc_id'.csv", clear
keep if inlist(age_group_id,28,5)
keep age_group_id year_id sex_id qx draw 
rename year_id year
rename sex_id sex
tostring sex, replace
replace sex = "male" if sex == "1"
replace sex = "female" if sex == "2"
replace sex = "both" if sex == "3"
rename age_group_id age
tostring age, replace
replace age = "under_1" if age == "28"
replace age = "1_4" if age == "5"
rename draw simulation
rename qx q_
reshape wide q_, i(year sex simulation) j(age, string)
gen ihme_loc_id = "`ihme_loc_id'"
replace year = year + .5

merge 1:1 ihme_loc_id sex year simulation using `qxs', assert(3) nogen
replace q_ch = q_1_4

	gen prob_enn = q_enn/q_under_1					
	gen prob_lnn = (1-q_enn)*q_lnn/q_under_1 			
	gen prob_pnn = (1-q_enn)*(1-q_lnn)*q_pnn/q_under_1					

	gen scale = (prob_enn + prob_lnn + prob_pnn) / 1
	foreach age in enn lnn pnn { 
		replace prob_`age' = prob_`age' / scale
	} 
	drop scale 
	
	replace q_enn = (q_under_1 * prob_enn)
	replace q_lnn = (q_under_1 * prob_lnn) / ((1-q_enn))
	replace q_pnn = (q_under_1 * prob_pnn) / ((1-q_enn)*(1-q_lnn))
	drop prob*

drop q_1_4 q_under_1
gen q_u5 = 1 - (1-q_enn)*(1-q_lnn)*(1-q_pnn)*(1-q_ch)
gen q_nn = 1 - (1-q_enn)*(1-q_lnn)
gen q_inf = 1 - (1-q_nn)*(1-q_pnn)
save "StrPath/u5_agessex_`ihme_loc_id'.dta", replace

preserve
	sort ihme_loc_id sex year simulation 
	isid ihme_loc_id sex year simulation 
	
	foreach q in enn lnn nn pnn inf ch u5 { 	
		noisily: di "`q'"
		by ihme_loc_id sex year: egen q_`q'_med = mean(q_`q')
		by ihme_loc_id sex year: egen q_`q'_lower = pctile(q_`q'), p(2.5)
		by ihme_loc_id sex year: egen q_`q'_upper = pctile(q_`q'), p(97.5)
		drop q_`q'
	}	
	
	drop simulation
	order ihme_loc_id sex year q* 
	duplicates drop
	isid ihme_loc_id sex year
	
	gen prob_enn_med = q_enn_med/q_u5_med				
	gen prob_lnn_med = (1-q_enn_med)*q_lnn_med/q_u5_med				
	gen prob_pnn_med = (1-q_enn_med)*(1-q_lnn_med)*q_pnn_med/q_u5_med		
	gen prob_ch_med = (1-q_enn_med)*(1-q_lnn_med)*(1-q_pnn_med)*q_ch_med/q_u5_med
	
	
	gen scale = (prob_enn_med + prob_lnn_med + prob_pnn_med + prob_ch_med) / 1
	foreach age in enn lnn pnn ch { 
		replace prob_`age'_med = prob_`age'_med / scale
	} 
	drop scale 

	replace q_enn_med = (q_u5_med * prob_enn_med)
	replace q_lnn_med = (q_u5_med * prob_lnn_med) / ((1-q_enn_med))
	replace q_pnn_med = (q_u5_med * prob_pnn_med) / ((1-q_enn_med)*(1-q_lnn_med))
	replace q_ch_med = (q_u5_med * prob_ch_med)/((1-q_enn_med)*(1-q_lnn_med)*(1-q_pnn_med))
	replace q_nn_med = 1 - ((1-q_enn_med)*(1-q_lnn_med))
	replace q_inf_med = 1- ((1-q_enn_med)*(1-q_lnn_med)*(1-q_pnn_med))
	
	drop prob*
	
** save summary file
save "StrPath/u5_agessex_`ihme_loc_id'.dta", replace
restore

keep ihme_loc_id year simulation sex q_u5 q_enn q_lnn q_pnn q_ch
rename q_u5 q5
rename simulation sim
tempfile data
save `data'

keep ihme_loc_id sim sex year q_ch
expand 4
sort ihme_loc_id sim sex year
bysort ihme_loc_id sim sex year: gen age=_n
merge m:1 sex age using `pars'
keep if _merge==3
drop _merge
gen lnqch=ln(q_ch)
gen pqx=exp(par_lnfive*lnqch+par_cons)
keep ihme_loc_id sim sex year age pqx q_ch
rename pqx qx
reshape wide qx, i(ihme_loc_id sim sex year) j(age)

gen pv4q1=1-(1-qx1)*(1-qx2)*(1-qx3)*(1-qx4)
egen id=group(ihme_loc_id sim sex year)
cap sum id
local nid=r(max)
tempfile singles adjs
save `singles'

keep if pv4q1<q_ch
local cnum = 10
local citer = 20
local ccat=1
gen crmax = 2 
gen crmin = 0.0000000000000001 
gen cadj = .
gen adj4q1_min = .
gen r_min = .
gen diffc_min = .
while `ccat'<=`citer' {
	local cq=0
	while `cq'<=`cnum' {
		cap: gen y`cq' = .
		replace y`cq' = crmin + `cq'*((crmax-crmin)/`cnum')
		local cqq=`cq'+1
		cap: gen r`cqq' = .
		replace r`cqq'=y`cq'
		local cq=`cq'+1 
		
		cap: gen adj4q1`cqq' = .
		replace adj4q1`cqq' = 1-(1-qx1*(1+r`cqq'))*(1-qx2*(1+r`cqq'))*(1-qx3*(1+r`cqq'))*(1-qx4*(1+r`cqq'))
			
		cap: gen diffc`cqq' = .
		replace diffc`cqq'=abs(adj4q1`cqq'-q_ch) if adj4q1`cqq' != 0
	}	
	
	cap: drop diffc_min
	egen diffc_min = rowmin(adj4q11-adj4q111) 
	
	replace r_min = .
	forvalues cqq = 1/11 {
			replace r_min = r`cqq' if diffc`cqq' == diffc_min 
	}

	count if r_min == .
	if(`r(N)' != 0) {
		noisily: di "`ccat'"
		pause
	}
	
	replace cadj=abs(crmax-crmin)/10
	replace crmax=r_min+2*cadj
	replace crmin=r_min-2*cadj
	replace crmin=0.000000001 if crmin < 0 
		
	local ccat=`ccat'+1
}
forvalues j=1/4 {
	replace qx`j'=qx`j'*(1+r_min) 
}
tempfile qx_less
save `qx_less', replace
********************************************************
use `singles', clear
keep if pv4q1>q_ch
local cnum = 10
local citer = 20
local ccat=1

gen crmin = -2 
gen crmax = -0.0000000000000001 
gen cadj = .
gen adj4q1_min = .
gen r_min = .
gen diffc_min = .

while `ccat'<=`citer' {
	local cq=0
	while `cq'<=`cnum' {
		cap: gen y`cq' = .
		replace y`cq' = crmin + `cq'*((crmax-crmin)/`cnum')
		local cqq=`cq'+1
		cap: gen r`cqq' = .
		replace r`cqq'=y`cq'
		local cq=`cq'+1 
		
		cap: gen adj4q1`cqq' = .
		replace adj4q1`cqq' = 1-(1-qx1*(1+r`cqq'))*(1-qx2*(1+r`cqq'))*(1-qx3*(1+r`cqq'))*(1-qx4*(1+r`cqq'))
		
		cap: gen diffc`cqq' = .
		replace diffc`cqq'=abs(adj4q1`cqq'-q_ch) if adj4q1`cqq' != 0
	}	
	
	cap: drop diffc_min
	egen diffc_min = rowmin(adj4q11-adj4q111)
	
	replace r_min = .
	forvalues cqq = 1/11 {
		replace r_min = r`cqq' if abs(diffc`cqq' == diffc_min) < .00001 & diffc`cqq' != .
	}
		replace cadj=abs(crmax-crmin)/10
	replace crmax=r_min+2*cadj
	replace crmin=r_min-2*cadj
	replace crmax=-0.000000001 if crmax > 0
	
	local ccat=`ccat'+1
}
	forvalues j=1/4 {
	replace qx`j'=qx`j'*(1+r_min)
}
tempfile qx_more
save `qx_more', replace
********************************************************
use `singles', clear
keep if pv4q1 == q_ch
append using `qx_less'
append using `qx_more'
keep ihme_loc_id sex sim year qx*
tempfile adjs
save `adjs'

use `data', clear
keep ihme_loc_id sim sex year sim q_*
rename q_enn qxenn
rename q_lnn qxlnn
rename q_pnn qxpnn
merge 1:1 ihme_loc_id sim sex year using `adjs'

keep if _merge==3
drop _merge
replace year=floor(year)

save `adjs',replace

gen dqxenn=1-(1-qxenn)^(1/7)
gen dqxlnn=1-(1-qxlnn)^(1/21)
gen dqxpnn=1-(1-qxpnn)^(1/337)
gen dqx1=1-(1-qx1)^(1/365)
gen dqx2=1-(1-qx2)^(1/365)
gen dqx3=1-(1-qx3)^(1/365)
gen dqx4=1-(1-qx4)^(1/365)
save `adjs',replace

use `births',clear
keep if ihme_loc_id == "`ihme_loc_id'"
expand 1000
bysort ihme_loc_id year sex: gen sim = _n-1

replace births=births/52
expand 52
sort ihme_loc_id sim sex year
bysort ihme_loc_id sim sex year: gen double btime=year+(1/52)*(_n-0.5)
tempfile weeks

gen double length_enn=7/365
gen double length_lnn=21/365
gen double length_pnn=337/365
forvalues j=1/4 {
   gen double length_`j'=1
}
gen double start_time_enn=btime
gen double start_time_lnn=btime+length_enn
gen double start_time_pnn=btime+length_enn+length_lnn
forvalues j=1/4 {
   gen start_time_`j'=btime+`j'
}
local vars="enn lnn pnn 1 2 3 4"
foreach v of local vars {
	gen end_time_`v'=start_time_`v'+length_`v'
}

foreach v of local vars {
	gen start_year_`v'=floor(start_time_`v')
	gen end_year_`v'=floor(end_time_`v')
}
gen start_size_enn=births
save `weeks'


qui foreach v of local vars {
	use `adjs',clear
	keep ihme_loc_id sim sex year dqx`v'
	rename year start_year_`v'
	rename dqx`v' dqx`v'_sy
	merge 1:m ihme_loc_id sim sex start_year_`v' using `weeks'
	drop if _merge==1
	drop _merge
	save `weeks',replace
	use `adjs',clear
	keep ihme_loc_id sim sex year dqx`v'
	rename year end_year_`v'
	rename dqx`v' dqx`v'_ey
	merge 1:m ihme_loc_id sim sex end_year_`v' using `weeks'
	drop if _merge==1
	drop _merge
	

	gen days_`v'_sy=round(length_`v'*365,1) if start_year_`v'==end_year_`v'
	replace days_`v'_sy=round((1-(start_time_`v'-start_year_`v'))*365, 1) if start_year_`v'<end_year_`v' 
	gen days_`v'_ey=round(length_`v'*365,1)-days_`v'_sy if start_year_`v'<end_year_`v'
	replace days_`v'_ey=0 if start_year_`v'==end_year_`v'
	gen deaths_sy_`v'=(1-(1-dqx`v'_sy)^days_`v'_sy)*start_size_`v'
	gen mid_size_`v'=((1-dqx`v'_sy)^days_`v'_sy)*start_size_`v'
	gen deaths_ey_`v'=(1-(1-dqx`v'_ey)^days_`v'_ey)*mid_size_`v'
	gen end_size_`v'=((1-dqx`v'_ey)^days_`v'_ey)*mid_size_`v'
	gen PY_sy_`v'=(1-(1-dqx`v'_sy)^days_`v'_sy)*start_size_`v'*(days_`v'_sy/2)/365+((1-dqx`v'_sy)^days_`v'_sy)*start_size_`v'*days_`v'_sy/365
	gen PY_ey_`v'=(1-(1-dqx`v'_ey)^days_`v'_ey)*mid_size_`v'*(days_`v'_ey/2)/365+((1-dqx`v'_ey)^days_`v'_ey)*mid_size_`v'*days_`v'_ey/365
	
	if "`v'"=="enn" {
		gen start_size_lnn=end_size_enn
	}
	if "`v'"=="lnn" {
		gen start_size_pnn=end_size_lnn
	}
	if "`v'"=="pnn" {
		gen start_size_1=end_size_pnn
	}
	if "`v'"=="1" {
		gen start_size_2=end_size_1
	}
	if "`v'"=="2" {
		gen start_size_3=end_size_2
	}	
	if "`v'"=="3" {
		gen start_size_4=end_size_3
	}
	save `weeks',replace
}
local vars="enn lnn pnn 1 2 3 4"
foreach v of local vars {
	egen sum_deaths_sy_`v'=sum( deaths_sy_`v'), by(ihme_loc_id sim sex start_year_`v')
	egen sum_deaths_ey_`v'=sum( deaths_ey_`v'), by(ihme_loc_id sim sex end_year_`v')
	egen sum_PY_sy_`v'=sum( PY_sy_`v'), by(ihme_loc_id sim sex start_year_`v')
	egen sum_PY_ey_`v'=sum( PY_ey_`v'), by(ihme_loc_id sim sex end_year_`v')
}
keep ihme_loc_id sim sex start_year* end_year* sum_deaths* sum_PY*
duplicates drop ihme_loc_id sim sex start_year_enn end_year_enn, force
tempfile raw
save `raw'
tempfile deaths
foreach v of local vars {
	use `raw',clear
	keep ihme_loc_id sim sex sum_deaths_sy_`v' start_year_`v' sum_PY_sy_`v'
	rename start_year year
	duplicates drop ihme_loc_id sim sex year, force
	collapse (sum) sum_deaths_sy_`v' sum_PY_sy_`v', by(ihme_loc_id sim sex year)
	rename sum_deaths deaths
	rename sum_PY pys
    gen age="`v'"
	cap append using `deaths'
	save `deaths',replace
	use `raw',clear
	keep ihme_loc_id sim sex sum_deaths_ey_`v' sum_PY_ey_`v' end_year_`v'
	rename end_year year
	duplicates drop ihme_loc_id sim sex year, force
	collapse (sum) sum_deaths_ey_`v' sum_PY_ey_`v', by(ihme_loc_id sim sex year)
	rename sum_deaths deaths
	rename sum_PY pys
	gen age="`v'"
	append using `deaths'
    save `deaths',replace
}
collapse (sum) deaths pys, by(ihme_loc_id sim sex year age)


keep ihme_loc_id sim sex year age pys
keep if year>1949 & year<2016

saveold "StrPath/shock_u5_pop_sims_`ihme_loc_id'.dta", replace
collapse (mean) pys, by(ihme_loc_id sex year age)
rename pys pys_
reshape wide pys_, i(ihme_loc_id year sex) j(age, string)
gen pys_1_4 = pys_1 + pys_2 + pys_3 + pys_4

saveold "StrPath/shock_u5_pop_mean_`ihme_loc_id'.dta", replace

exit,clear

