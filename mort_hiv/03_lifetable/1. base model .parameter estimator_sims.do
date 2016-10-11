************************************
*** Model Life Table parameter estimation and preparation for standard selection process 
*** Haidong Wang
*** with simulated coefficients from base model and HIV models
*** 10/16/2011
*** updated to one-step model for HIV, EDU and GDP 8/17/2013
set more off
set seed 1234567

global datadir "j:/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data"

***** register tempfiles
tempfile dbase stands expands ratebase regs base g2index allmatched entry modelbase pars counter hiventry target isoid inbase allmatched pars stans adult

*** UNAIDS deaths file
tempfile kidunaids adultunaids
** use "J:\Project\Causes of Death\codem\models\A02\UNAIDS 2012\misc\data\UNAIDS_u5_mort_rt_extended_16Aug13.dta",clear
** use "J:\Project\Causes of Death\codem\models\A02\GBD 2013 HIV\UNAIDS 2013\UNAIDS' estimates\HIV mort & prev\prepped\UNAIDS2013_HIV_dth_rt_u5_9Dec13.dta",clear
insheet using "J:\Project\Mortality\GBD Envelopes\00. Input data\00. Format all age data\hiv_formatting\formatted_hiv_5q0.csv",clear
destring hiv, force replace
rename hiv kid_CDR
keep iso3 year kid_CDR
save `kidunaids'

** use "J:\Project\Causes of Death\codem\models\A02\GBD 2013 HIV\UNAIDS 2013\UNAIDS' estimates\HIV mort & prev\prepped\UNAIDS2013_HIV_dth_rt_1559_9Dec13.dta",clear
insheet using "J:\Project\Mortality\GBD Envelopes\00. Input data\00. Format all age data\hiv_formatting\formatted_hiv_45q15.csv",clear
tostring sex, force replace
replace sex="male" if sex=="1"
replace sex="female" if sex=="2"
rename death adult_CDR
save `adultunaids'

tempfile egh pop
use "J:\Project\Mortality\Population\USABLE_POPULATION_GLOBAL_1970-2013.dta",clear
reshape long pop, i(iso3 sex year) j(age) str
forvalue j=15(5)55 {
    local jj=`j'+4
	replace age="`j'" if age=="_`j'_`jj'"
}
destring age, force replace
drop if age==.
keep iso3 sex year age pop
save `pop'

*** covariates 
** use "J:\WORK\01_covariates\02_inputs\education\model\2013rerun_Education_IHME_1950-2015.dta",clear
use "J:\WORK\01_covariates\02_inputs\education\model\Education_IHME_1950-2020_Y2013M12Y16.dta",clear

rename sex sexid
gen sex="male"
replace sex="female" if sexid==2
drop sexid
rename age age
keep iso3 sex year mean age
drop if age==.
reshape wide mean_yrseduc,i(iso3 sex year) j(age)
gen  mean_yrseduc20= mean_yrseduc15
gen  mean_yrseduc30= mean_yrseduc25
gen  mean_yrseduc40= mean_yrseduc35
gen  mean_yrseduc50= mean_yrseduc45
gen  mean_yrseduc60= mean_yrseduc55
reshape long mean_yrseduc,i(iso3 sex year) j(age)
merge 1:1 iso3 sex year age using `pop'
keep if _merge==3
drop _merge

preserve
keep if sex=="female"
keep if age>=15 & age<=45
egen tpop=sum(pop),by(iso3 sex year)
gen maternal_edu=mean_yrs*pop/tpop
collapse (sum) maternal_edu,by(iso3 sex year) 
tempfile edu
save `edu'
restore

drop if age==65
egen tpop=sum(pop),by(iso3 sex year)
gen meanedu=mean_yrs*pop/tpop
collapse (sum) meanedu,by(iso3 sex year) 
merge m:1 iso3 year using `edu'
drop _merge

*** all covariates for mortality analysis
tempfile covars
merge m:1 iso3 year using "J:\WORK\01_covariates\02_inputs\LDI_pc\model\model_final.dta",force
** merge m:1 iso3 year using "J:\WORK\01_covariates\02_inputs\LDI_pc\model\LDI_id_pc_1950-2015_Y2013M08D15.dta"
keep if _merge==3
drop _merge
rename mean_value LDI_id
keep iso3 sex year meanedu maternal_edu LDI_id
merge 1:1 iso3 sex year using `adultunaids'
drop if _merge==2
drop _merge
replace adult=0 if adult==.
merge m:1 iso3 year using `kidunaids'
drop if _merge==2
drop _merge
replace kid_CDR=0 if kid_CDR==.
save `covars'


*** ******************************
*** adult HIV covariates estimation ***
*** ******************************

insheet using "J:\Project\Mortality\GBD Envelopes\03_adult_mortality\data\input_data\final\input_data.txt",clear
keep iso3 sex year mort type source
replace year=floor(year)
destring mort, force replace
drop if mort==.
gen v45m15=ln(1-mort)/-45
gen ln45m15=ln(v45m15)
merge m:1 iso3 sex year using `covars'
drop if _merge==2
drop _merge
gen lngdp=ln(LDI_id)
save `adult'

tempfile pars
use `adult',clear
keep if sex=="male"
reg ln45m15 meanedu lngdp
local bm=_b[meanedu]
local bg=_b[lngdp]
local bc=_b[_cons]
predict pln45m15
gen p45m15=exp(pln45m15)
xtmixed v45m15 p45m15 adult_CDR, noc|| iso3:p45m15,noc
local bh=_b[adult_CDR]
local c=0.1 
qui while `c'>=0.001 {
    gen lns45m15=ln(v45m15-`bh'*adult_CDR)
	reg lns45m15 meanedu lngdp
	local rd1=abs(_b[meanedu]/`bm'-1)
	local rd2=abs(_b[lngdp]/`bg'-1)
	local rd4=abs(_b[_cons]/`bc'-1)
	local bm=_b[meanedu]
	local bg=_b[lngdp]	
	local bc=_b[_cons]	
	cap drop pln45m15 p45m15 lns45m15
	predict pln45m15
	gen p45m15=exp(pln45m15)
	xtmixed v45m15 p45m15 adult_CDR, noc|| iso3:p45m15,noc
	
	preserve
	predict riso3, reffects
	keep iso3 sex riso3
	replace riso3=riso3+_b[p45m15]
	duplicates drop iso3 sex, force
	tempfile mre
	save `mre',replace
	restore
	
	local rd3=abs(_b[adult_CDR]/`bh'-1)
	local bh=_b[adult_CDR]	
	local c=max(`rd1',`rd2',`rd3')
	noisily dis `c'
}

clear
set obs 1
gen sex="male"
gen par_edu=`bm'
gen par_gdp=`bg'
gen par_hiv=`bh'
gen par_cons=`bc'
cap append using `pars'
save `pars',replace

use `adult',clear
keep if sex=="female"
reg ln45m15 meanedu lngdp
local bm=_b[meanedu]
local bg=_b[lngdp]
	local bc=_b[_cons]
predict pln45m15
gen p45m15=exp(pln45m15)
xtmixed v45m15 p45m15 adult_CDR, noc|| iso3:p45m15,noc
local bh=_b[adult_CDR]
local c=0.1 
qui 	while `c'>=0.0025 {
    gen lns45m15=ln(v45m15-`bh'*adult_CDR)
	reg lns45m15 meanedu lngdp
	local rd1=abs(_b[meanedu]/`bm'-1)
	local rd2=abs(_b[lngdp]/`bg'-1)
	local rd4=abs(_b[_cons]/`bc'-1)
	local bm=_b[meanedu]
	local bg=_b[lngdp]	
	local bc=_b[_cons]
	cap drop pln45m15 p45m15 lns45m15
	predict pln45m15
	gen p45m15=exp(pln45m15)
	xtmixed v45m15 p45m15 adult_CDR, noc|| iso3:p45m15,noc
	
	preserve
	predict riso3, reffects
	keep iso3 sex riso3
	replace riso3=riso3+_b[p45m15]
	duplicates drop iso3 sex, force
	tempfile fre
	save `fre',replace
	restore	
	
	
	local rd3=abs(_b[adult_CDR]/`bh'-1)
	local bh=_b[adult_CDR]	
	local c=max(`rd1',`rd2',`rd3')
	noisily dis `c'
}

clear
set obs 1
gen sex="female"
gen par_edu=`bm'
gen par_gdp=`bg'
gen par_hiv=`bh'
gen par_cons=`bc'
append using `pars'
save `pars',replace

use `pars',clear
rename par_hiv par_adult_hiv
keep sex par_adult
save "J:/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/hivratio_adult.dta",replace
save "J:/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/hivratio_adult_$S_DATE.dta",replace


use `mre',clear
append using `fre'
merge m:1 sex using `pars'
keep if _merge==3
drop _merge
tempfile preds
save `preds'

use `covars',clear
keep iso3 sex year adult_CDR meanedu LDI
merge m:1 iso3 sex using `preds'
drop _merge
merge m:1 iso3 using "J:\Project\Mortality\GBD Envelopes\04. Lifetables\02. MORTMatch\cluster\data\iso_reg.dta"
gen p45m15=exp(par_cons+par_edu*meanedu+par_gdp*ln(LDI))*riso3+par_hiv*adult_CDR
egen rgbd=mean(riso3),by(sex gbd_region)
local pars="par_cons par_edu par_gdp par_hiv"
foreach p of local pars {
    egen g_`p'=mean(`p'),by(sex gbd_region)
}
replace p45m15=exp(g_par_cons+g_par_edu*meanedu+g_par_gdp*ln(LDI))*rgbd+g_par_hiv*adult_CDR if riso3==. & p45m15==.
keep iso3 sex year p45m15 
save "$datadir/adult_45m15_prediction.dta",replace
save "$datadir/adult_45m15_prediction_$_S_DATE.dta",replace

*** get the HIV counterfactual ***
** insheet using "J:\Project\Mortality\GBD Envelopes\03_adult_mortality\results\estimated_45q15_noshocks.txt", clear
** keep iso3 sex year mort_med
** rename mort v45q15
** replace year=floor(year)
** tempfile v45s
** save `v45s'

** use `pars',clear
** keep sex par_hiv 
** merge 1:m sex using `v45s',nogen
** save `v45s',replace
** use `covars',clear
** keep iso3 sex year cdr_adult
** merge 1:1 iso3 sex year using `v45s'
** keep if _merge==3
** drop _merge
** merge 1:1 iso3 sex year using `preds'
** keep if _merge==3
** drop _merge
** gen adjcdr_adult=cdr_adult*(ln(1-v45q15)/-45)/p45m15
** gen counter45=1-exp(((ln(1-v45q15)/-45)-par_hiv*adjcdr_adult)*(-45))
** save `v45s',replace


*** *****************
*** child age groups ***
*** *****************
insheet using "J:\Project\Mortality\GBD Envelopes\00. Input data\03. Final input dataset for 5q0 child mortality\raw.5q0.unadjusted.txt", clear
keep iso3 year q5 source sourcedate outlier shock
rename q v5q0 
drop if outlier==1
drop if shock==1
replace year=floor(year)
tempfile v5s
save `v5s'

use `covars',clear
keep iso3 sex year maternal LDI kid_CDR
drop sex
duplicates drop iso3 year, force
merge 1:m iso3 year using `v5s'
keep if _merge==3
drop _merge
gen lngdp=ln(LDI)
gen v5m0=ln(1-v5q0)/-5
gen ln5m0=ln(v5m0)
tempfile kids
save `kids'

*** iterations to get the stablized coefficients ***
tempfile cpars
use `kids',clear
reg ln5m0 maternal lngdp
local bm=_b[maternal_edu]
local bg=_b[lngdp]
local bc=_b[_cons]
predict pln5m0
gen p5m0=exp(pln5m0)
xtmixed v5m0 p5m0 kid_CDR, noc|| iso3:p5m0,noc
local bh=_b[kid_CDR]

local c=0.1 
qui while `c'>=0.001 {
    gen lns5m0=ln(v5m0-`bh'*kid_CDR)
	reg lns5m0 maternal_edu lngdp
	local rd1=abs(_b[maternal_edu]/`bm'-1)
	local rd2=abs(_b[lngdp]/`bg'-1)
	local rd4=abs(_b[_cons]/`bc'-1)
	local bm=_b[maternal_edu]
	local bg=_b[lngdp]	
	local bc=_b[_cons]	
	cap drop pln5m0 p5m0 lns5m0
	predict pln5m0
	gen p5m0=exp(pln5m0)
	xtmixed v5m0 p5m0 kid_CDR, noc|| iso3:p5m0,noc
	
	preserve
	predict riso3, reffects
	keep iso3 riso3
	replace riso3=riso3+_b[p5m0]
	duplicates drop iso3, force
	tempfile cre
	save `cre',replace
	restore
	
	local rd3=abs(_b[kid_CDR]/`bh'-1)
	local bh=_b[kid_CDR]	
	local c=max(`rd1',`rd2',`rd3')
	noisily dis `c'
}

clear
set obs 1
gen par_edu=`bm'
gen par_gdp=`bg'
gen par_hiv=`bh'
gen par_cons=`bc'
gen sex="male"
save `cpars'

use `cre',clear
gen sex="male"
merge m:1 sex using `cpars'
keep if _merge==3
drop _merge
tempfile cpreds
save `cpreds'

use `covars',clear
keep iso3 sex year kid_CDR maternal LDI
merge m:1 iso3 sex using `cpreds'
keep if _merge==3
drop _merge
gen p5m0=exp(par_cons+par_edu*maternal+par_gdp*ln(LDI))*riso3+par_hiv*kid_CDR
keep iso3 year p5m0
save "$datadir/kid_5m0_prediction.dta",replace

use `cpars',clear
expand 2
replace sex="female" in 2
rename par_hiv par_kid_hiv
keep sex par_kid
save "J:/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/hivratio_kid.dta",replace
save "J:/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/hivratio_kid_$S_DATE.dta",replace



***************************************************************
*** 1. get the database for country-time specific standards ***
***************************************************************
use "$datadir/ltbase_final.dta",clear
** drop if hivprev>=0.001
drop if adult_CDR>=0.0001
drop if iso3=="ZAF" | iso3=="TTO"
sort sex
*** generate qx series ***
gen q0=1-lx1
gen q1=1-lx5/lx1
forvalues j=5(5)100 {
** forvalues j=5(5)105 {
    local jj=`j'+5
    gen q`j'=1-lx`jj'/lx`j'
}
keep source iso3 year sex v5q0 v45q15 q*
sort source iso3 year sex
save `dbase'
*** generate rate of change in qx, 5p0 and 45p15 over years ***
*** get the list of iso3+sex in the database ***
egen isosex=group(source iso3 sex)
*** keep only countries with at least two CYs
gen ncy=.
bysort isosex: replace ncy=_N
drop if ncy<2
drop isosex
egen isosex=group(iso3 sex source)
sum isosex
global nss=r(max)
sort isosex
save `dbase',replace
renpfix q sq
keep source iso3 isosex year sex sq* v5q0 v45q15
rename v5q0 sv5q0
rename v45q15 sv45q15
rename year syear
sort source iso3 sex syear 
save `stands'
*** expand the qx database ***
qui forvalues j=1/$nss {
    use `dbase',clear
	keep if isosex==`j'
	local nin=ncy[1]
    expand _N
    sort source iso3 sex year
	gen id=_n
	sort id
	tempfile ttt
	save `ttt',replace
	use `stands', clear
	keep if isosex==`j'
	tempfile cstan temp
	gen round=1
	save `cstan', replace
	drop round
	save `temp',replace
	local int=2
	while `int'<=`nin' {
	    use `cstan',clear
       	cap append using `temp'
		replace round=`int' if round==.
		save `cstan', replace
		local int=`int'+1
	}
	sort round source iso3 sex syear
	gen id=_n
    sort id
    merge id using `ttt'
    cap append using `expands'
    save `expands',replace
	erase `temp'
	erase `cstan'
	erase `ttt'
}

*** generate lag ***
gen lag=year-syear
*** only keeping the positive lags
keep if lag>0 & lag<=15
foreach nn of numlist 0 1 5(5)100 {
    gen logitq`nn'=-0.5*ln(q`nn'/(1-q`nn'))
	gen logitsq`nn'=-0.5*ln(sq`nn'/(1-sq`nn'))
	gen logitdiff`nn'=logitq`nn'-logitsq`nn'
}
gen logit5q0=-0.5*ln(v5q0/(1-v5q0))
gen logitsv5q0=-0.5*ln(sv5q0/(1-sv5q0))
gen logit45q15=-0.5*ln(v45q15/(1-v45q15))
gen logitsv45q15=-0.5*ln(sv45q15/(1-sv45q15))
gen difflogit5=logit5q0-logitsv5q0
gen difflogit45=logit45q15-logitsv45q15
keep source iso3 sex year difflogit* logitdiff* lag
reshape long logitdiff, i(source iso3 sex year lag) j(age)
save `ratebase'

*****************************************************
*** 2. get the database for different standard ******
*****************************************************
use "$datadir/ltbase_final.dta",clear
save `base'
*** iso3--> gbd_region
** use "$datadir/iso_reg.dta",clear
** sort iso3 

use "j:/DATA/IHME_COUNTRY_CODES/IHME_COUNTRY_CODES_Y2013M07D26.DTA",clear
keep iso3 gbd_region_name gbd_superregion_name
duplicates drop iso ,force
save `regs'
use "$datadir/ltbase_final",clear
** keep if subs==2
*** keep only the non-HIV life tables in the matching database
keep if adult_CDR<=0.0001
renpfix lx l
sort iso3 year sex
erase `dbase'
save `dbase'


*** estimate regular non-HIV parameters first ***
tempfile pars
local sexs = "male female"
foreach ss of local sexs {
	use `dbase',clear
	keep if sex=="`ss'"
	reshape long l, i(source iso3 sex year) j(age)
	egen mlx=mean(l), by(gbd_region age)		    
	sort iso3 sex year age
    bysort iso3 sex year: gen oqx=1-l[_n+1]/l
	sort iso3 sex year age
	bysort iso3 sex year: gen sqx=1-mlx[_n+1]/mlx
	sort iso3 sex year age
	bysort iso3 sex year: gen sq5=1-mlx[3]
	sort iso3 sex year age
	bysort iso3 sex year: gen sq45=1-mlx[14]/mlx[5]
	gen logitoqx=-0.5*ln(oqx/(1-oqx))
	gen logitsqx=-0.5*ln(sqx/(1-sqx))
	gen logitsq5=-0.5*ln(sq5/(1-sq5))
	gen logitsq45=-0.5*ln(sq45/(1-sq45))
	gen difflogit5=(logit5q0-logitsq5)
	gen difflogit45=(logit45q15-logitsq45)
	gen logitdiff=logitoqx-logitsqx
	preserve
	keep source  iso3 logitsqx logitsq5 logitsq45 age sex gbd_region
	duplicates drop gbd_region source iso3 sex age, force
	gen standard="GBD"
	cap append using `stans'
	save `stans', replace
	restore
	cap append using `ratebase'
	keep if sex=="`ss'"
	foreach num of numlist 0 1 5{
        preserve
    	regress logitdiff difflogit5 if age==`num', noc
		mat bb=e(b)
		mat bb=bb[1,1]
        mat vs=e(V)
    	mat vs=vs[1,1]
		set seed 1234567
    	drawnorm sim_difflogit5, n(1000) means(bb) cov(vs) clear		
		gen sex="`ss'"
		gen age=`num'
		gen sim=_n-1
        cap append using `pars'
        save `pars',replace		
		restore
	}		
	foreach num of numlist 10(5)30 {
	    preserve
		regress logitdiff difflogit5 difflogit45 if age==`num', noc
		mat bb=e(b)
		mat bb=bb[1,1..2]
        mat vs=e(V)
    	mat vs=vs[1..2,1..2]
		set seed 1234567
    	drawnorm sim_difflogit5 sim_difflogit45, n(1000) means(bb) cov(vs) clear
		gen sex="`ss'"
		gen age=`num'
		gen sim=_n-1
        cap append using `pars'
        save `pars',replace		
		restore
	}	
	foreach num of numlist 35(5)100 {
	    preserve
		regress logitdiff difflogit45 if age==`num', noc
		mat bb=e(b)
		mat bb=bb[1,1]
        mat vs=e(V)
    	mat vs=vs[1,1]
		set seed 1234567
    	drawnorm sim_difflogit45, n(1000) means(bb) cov(vs) clear		
		gen sex="`ss'"
		gen age=`num'
		gen sim=_n-1
        cap append using `pars'
        save `pars',replace		
		restore		
	}	
}
use `pars',clear
replace sim_difflogit45=0 if sim_difflogit45==.
replace sim_difflogit5=0 if sim_difflogit5==.
save "J:/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/modelpar_sim.dta",replace
save "J:/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/modelpar_sim_$S_DATE.dta",replace



*** HIV related settings  7/5/2012
*** no HIV counterfactuals for all high income countries with low HIV death rates 
use "J:\Project\Mortality\GBD Envelopes\04. Lifetables\02. MORTMatch\cluster\data\hiv_cdr.dta",clear
egen adulthiv_max=max(adult_CDR_HIV), by(iso3)
keep iso3 adulthiv_max
duplicates drop iso3, force
merge 1:m iso3 using "j:/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/country_time_standards.dta"
keep if _merge==3
drop _merge
keep iso3 sex adulthiv
duplicates drop iso3 sex, force
keep iso3 sex
save "J:\Project\Mortality\GBD Envelopes\04. Lifetables\02. MORTMatch\cluster\data\nohivapplication.dta",replace


*** extending to older ages ***
tempfile malelts femalelts lts 
  *** males ***
global working "J:\Project\Mortality\GBD Envelopes\04. Lifetables\01. Master empirical life table database\dataset\HMD Life Tables\mltper_5x1"
local sfiles: dir "$working" files "*.txt", respectcase
foreach file of local sfiles {
	cd "$working"
    infix year 1-10 str age 11-21 mx 23-31 qx 32-40 ax 41-46 lx 47-55 dx 56-63 nLx 63-71 Tx 72-80 ex 81-87 using `file', clear
	drop if year==.
	gen iso3=reverse(substr(reverse("`file'"),16,.))
	cap append using `malelts'
	save `malelts', replace
}
gen sex="male"
save `malelts', replace
*** females ***
global working "J:\Project\Mortality\GBD Envelopes\04. Lifetables\01. Master empirical life table database\dataset\HMD Life Tables\fltper_5x1"
local sfiles: dir "$working" files "*.txt", respectcase
foreach file of local sfiles {
	cd "$working"
    infix year 1-10 str age 11-21 mx 23-31 qx 32-40 ax 41-46 lx 47-55 dx 56-63 nLx 63-71 Tx 72-80 ex 81-87 using `file', clear
	drop if year==.
	gen iso3=reverse(substr(reverse("`file'"),16,.))
	cap append using `femalelts'
	save `femalelts', replace
}
gen sex="female"
save `femalelts', replace
append using `malelts'

gen newage=.
replace newage=0 if age=="0"
replace newage=1 if age=="1-4" 
replace newage=110 if age=="110+"
forvalues x=3/23 {
 local n1=(`x'-2)*5
 local n2=(`x'-2)*5+4
 replace newage=`n1' if age=="`n1'-`n2'"
}
drop age
rename newage age

tempfile hmdlts mxdata
save `hmdlts'
save `mxdata'

drop if age>105
keep iso3 sex year age qx
keep if age>75
sort iso3 sex year age
tempfile hmds
save `hmds'


***** iso3 from KT database *****
global working "J:\Project\Mortality\GBD Envelopes\04. Lifetables\01. Master empirical life table database\dataset\KTdata"
tempfile kts
local sfiles: dir "$working" files "*.txt", respectcase
cd "$working"
qui foreach file of local sfiles {
    insheet using `file', comma clear
	gen iso3=substr("`file'",2,3)
	gen sex=substr("`file'",1,1)
	cap append using `kts'
	save `kts',replace
	noisily dis "`file'"
}
keep iso3
duplicates drop iso3,force
sort iso3
merge iso3 using `hmds'
keep if _merge==3 & year>=1970
drop _merge
*gen lnqx=ln(qx)
gen logitqx=ln(qx/(1-qx))
reshape wide qx logitqx, i(iso3 sex year) j(age)
forvalues w=80(5)105 {
    drop if qx`w'==.
}
keep qx* iso3 sex year logitqx80
reshape long qx, i(iso3 sex year) j(age)
rename logitqx80 i_logitqx80
gen logitqx=ln(qx/(1-qx))
sort iso3 sex year age
bysort iso3 sex year: gen logitdiff=logitqx[_n+1]-logitqx
drop if age==105
tempfile ktmx pars
save `ktmx'

char age [omit] 80
**no lndiff values for 105 age group
tempfile ratiopar
local sexs="male female"
foreach ss of local sexs {
	use `ktmx',clear
	keep if sex=="`ss'"
	xi:xtmixed logitdiff i.age i_logitqx80 || iso3:
	mat par_r_`ss'=e(b)
	mat par_r_`ss'=par_r_`ss'[1,1..6]
    matname par_r_`ss' vage85 vage90 vage95 vage100 par_logitqx80 cons, col(1..6) explicit
	clear
	svmat par_r_`ss',names(col)
	gen sex="`ss'"
	cap append using `ratiopar' 
	save `ratiopar',replace
	matrix drop par_r_`ss'
}
rename cons par_85cons
gen vage80=0
renpfix v par_v
reshape long par_vage, i(sex) j(age)
sort sex age
save "J:/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/par_age_85plus_qx_alter.dta",replace
save "J:/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/par_age_85plus_qx_alter_$S_DATE.dta",replace

*** mx for the open age interval ***
use `ktmx',clear
keep iso3 sex year
duplicates drop iso3 sex year,force
tempfile mxiso
save `mxiso'

use `mxdata',clear
keep iso3 sex year age mx 
keep if age>75
merge m:1 iso3 sex year using `mxiso'
keep if _merge==3
drop _merge
gen lnmx=ln(mx)
drop mx
reshape wide lnmx, i(iso3 sex year) j(age)

tempfile mxpar
local sexs="male female"
foreach ss of local sexs {
	preserve
	keep if sex=="`ss'"
	reg lnmx110 lnmx105, noc
    clear
	set obs 1
	gen sex="`ss'"
	gen parlnmx=_b[lnmx105]
	cap append using `mxpar'
	save `mxpar',replace
	restore
}
use `mxpar',clear
save "J:/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/par_age_110plus_mx.dta",replace
save "J:/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/par_age_110plus_mx_$S_DATE.dta",replace

***** generate ax values for the 80 plus age groups

*** ax and qx relationship in 80+ age groups ***
use `hmdlts',clear
keep iso3 sex  year age qx ax
keep if age>75
keep if year>1950
gen sqx=qx^2
tempfile qxax
save `qxax'

tempfile axpar
local sexs="male female"
foreach s of local sexs {
	forvalues j=80(5)105 {
        use `qxax',clear
	    keep if sex=="`s'"
	    reg ax qx sqx if sex=="`s'" & age==`j'
		mat ax_`s'_`j'=e(b)
		mat ax_`s'_`j'=ax_`s'_`j'[1,1..3]
		matname ax_`s'_`j' par_qx par_sqx par_con, col(1..3) explicit
		clear
		svmat ax_`s'_`j', names(col)
		gen sex="`s'"
		gen age=`j'
		cap append using `axpar'
		save `axpar',replace
	}
}
use `axpar',clear
sort sex age
save "J:/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/ax_par.dta",replace
save "J:/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/ax_par_$S_DATE.dta",replace
