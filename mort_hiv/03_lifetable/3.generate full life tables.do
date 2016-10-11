*** Life table generator
*** one that fits all
*** faster iterations by column instead of row
*** space-time weights for life tables and HIV age pattern from ICD10 VR data.
*** Dec 30th 2013
clear
set more off
clear matrix
set memory 5000m
adopath + "/home/OUTPOST/haidong/ado"
adopath + "/home/OUTPOST/c11/ado"
    if c(os) == "Unix" {
        global dirs "/home/j"
    }
    else if c(os) == "Windows" {
        global dirs "J:"
    }
*** register files ***
global datadir "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data"
use "$datadir/ltbase_final",clear
drop if iso3=="BRA" & year==2010
drop if iso3=="IRQ" & year==2008
drop if iso3=="PRK"
drop if iso3=="TON" & year>=2006
drop if ciso=="CHN" & (iso3=="CHN" | iso3=="HKG")
** use "/home/j/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/ltbase_final_30 Dec 2013.dta",clear

*** March 16 2014
drop if iso3=="XBC" & sex=="male"
drop if iso3=="XCE" & sex=="male"
drop if iso3=="XCF" & sex=="male"
drop if iso3=="XCC" & sex=="male"
drop if iso3=="XCH" & sex=="male"
drop if iso3=="XCO" & sex=="male"
drop if iso3=="XCO" & sex=="female"
drop if iso3=="XCQ" & sex=="male"
drop if iso3=="XFC" & sex=="male"
drop if iso3=="XLC" & sex=="male" & year<1990
drop if iso3=="XMG" & sex=="male"
drop if iso3=="XNC" & sex=="male"
drop if iso3=="XYC" & sex=="male"


***

*** fix 1
drop if adult_CDR>=0.001
drop if iso3=="ZAF"
drop if iso3=="XIR" & year<2000

*** fix 2
drop if iso3=="AFG"

tempfile base
save `base'

tempfile zafbase
***6/30/2014
append using "$datadir/ZAF_life_tables.dta"
save `zafbase'

** use "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/model testing/result/weights_all levels.dta",clear
use "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/weights/weights_all levels.dta",clear

replace weights= 0 if lag>15 & lag<-15

tempfile wlevel
save `wlevel'

*** get the entry pars ***
*** the counter-factual ones ***

use "$dirs/DATA/IHME_COUNTRY_CODES/IHME_COUNTRY_CODES_Y2013M07D26.DTA",clear
keep iso3 gbd_region_name gbd_superregion_name gbd_country_iso
rename gbd_country_iso ciso
duplicates drop iso3, force
merge 1:m iso3 using "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/sims/entry_$nn.dta"
drop if _merge==1
drop _merge


 ** keep if iso3=="AZE" | iso3=="CHN" | iso3=="BRA" | iso3=="BMU" | iso3=="THA" | iso3=="XIR" | iso3=="XIU" | iso3=="EGY" | iso3=="MNE" | iso3=="MNG" | iso3=="PRI" | iso3=="PRK" | iso3=="TUN" | iso3=="XCP" | iso3=="ZAF" | iso3=="USA" | iso=="GBR" | iso3=="IRQ" | iso3=="TON" | iso3=="TTO" | iso3=="XAC" | iso3=="XCB" | iso3=="XCC" | iso3=="XGO" | iso3=="XJM" | iso3=="XMX" | iso3=="ZAF"

** keep if iso3=="USA" | iso3=="ZAF" | iso3=="CHN"
 
keep iso3 sex year v5q0 v45q15 *CDR gbd_region_name gbd_super ciso
keep if year>1969
replace adult_CDR=0 if adult_CDR==.
replace kid_CDR=0 if kid_CDR==.
gen sim=$nn
merge m:1 sex using "$datadir/hivratio_kid.dta",nogen
merge m:1 sex using "$datadir/hivratio_adult.dta",nogen
rename v5q0 obs_v5q0
rename v45q15 obs_v45q15
tempfile changehiv
save `changehiv'

*** not applying the HIV counterfactuals to countries with good VR data and empirical life tables. 

*** THA issue?? 2/7/2014
merge m:1 iso3 sex using "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/nohivapplication.dta"

** replace kid_CDR = 0 if _merge==3
** replace adult_CDR = 0 if _merge==3

replace kid_CDR = 0 if _merge==3 & iso3!="THA"
replace adult_CDR = 0 if _merge==3 & iso3!="THA"
drop _merge
merge 1:1 iso3 sex year using "$datadir/adult_45m15_prediction.dta"
drop if _merge==2


** 6/30/2014
replace adult_CDR=adult_CDR*0.6 if iso3=="ZAF"
replace kid_CDR=kid_CDR*0.6 if iso3=="ZAF"

    *** not adjustment CDR upward if possible. 8/23/2013
gen c_v5q0=1-exp(-5*((ln(1-obs_v5q0)/(-5))-par_kid_hiv*kid_CDR))
gen c_v45q15=1-exp(-45*((ln(1-obs_v45q15)/(-45))-par_adult_hiv*adult_CDR*((ln(1-obs_v45q15)/(-45))/p45m15))) if _merge==3 & ((ln(1-obs_v45q15)/(-45))/p45m15)<1
replace c_v45q15=1-exp(-45*((ln(1-obs_v45q15)/(-45))-par_adult_hiv*adult_CDR)) if _merge==1
replace c_v45q15=1-exp(-45*((ln(1-obs_v45q15)/(-45))-par_adult_hiv*adult_CDR)) if _merge==3 & ((ln(1-obs_v45q15)/(-45))/p45m15)>=1

** 4/9/2014
replace c_v45q15=obs_v45q15 if c_v45q15>obs_v45q15
replace c_v5q0=obs_v5q0 if c_v5q0>obs_v5q0
replace c_v45q15=0.03*obs_v45q15 if c_v45q15<0
*** 

drop _merge

duplicates drop iso3 sex year, force
keep iso3 year c_v5q0 c_v45q15 sex gbd_region_name gbd_superregion_name ciso
gen c_logit5q0=-0.5*ln(c_v5q0/(1-c_v5q0))
gen c_logit45q15=-0.5*ln(c_v45q15/(1-c_v45q15))
*** expand to 18 five-year age groups between ages 0 and 84***
expand 22
sort iso3 sex year
bysort iso3 sex year: gen rank=_n
gen age=(rank-2)*5
replace age=0 if rank==1
replace age=1 if rank==2
sort sex age
drop rank
sort iso3
tempfile tdata
save `tdata'
keep iso3 sex year c_v5q0 c_v45q15 gbd* ciso
duplicates drop iso3 sex year, force
tempfile hivfree freematched
merge 1:1 iso3 sex year using "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/match_specs.dta"
keep if _merge==3
drop _merge

** 6/30/2014
replace match=20 if iso3=="ZAF"


egen isosex=group(iso3 sex)
save `hivfree'
sum isosex
global macs=r(max)

qui forvalues y=1/$macs {
    tempfile counterg2_`y' matched_`y'
    use `hivfree',clear
    keep if isosex==`y'
    local gbd=gbd_region[1]
    local super=gbd_super[1]
    save `counterg2_`y''
    local ss=sex[1]
    local cc=iso3[1]
    local ci=ciso[1]
    sort iso3 sex year
    keep c_v5q0 c_v45q15 year match
    order c_v5q0 c_v45q15
    local yn=_N
    mkmat c_v5q0 c_v45q15 year match, matrix(years)
    tempfile matched
    forvalues t=1/`yn' {
		if "`cc'"=="ZAF" {
			use `zafbase',clear
		}
		else {
			use `base',clear
   		}
		cap drop if shock==1
        keep if sex=="`ss'"
        local i=_N+1
        set obs `i'
        replace v5q0= years[`t',1] in `i'
        replace v45q15=years[`t',2] in `i'
        local qratio=years[`t',1]/years[`t',2]
        replace logit5q0=-0.5*ln(v5q0/(1-v5q0)) in `i'
        replace logit45q15=-0.5*ln(v45q15/(1-v45q15)) in `i'
        mahascore logit5q0 logit45q15, gen(dist) refobs(`i') compute_invcovarmat
        drop if _n==`i'
        sort dist
        ** keep if _n<=years[`t',4] | iso3=="`cc'" 
        *** keep the national life tables as well
        keep if _n<=years[`t',4] | iso3=="`cc'" | ciso=="`ci'"
 
 ** 6/30/014
        if "`cc'"=="ZAF" {
            keep if iso3=="ZAF"
        }         
        gen w=1
        ** replace w=0 if iso3=="`cc'"
        replace w=0 if iso3=="`cc'" | ciso=="`ci'"
        gen wlag=years[`t',3]-year
        ** drop if iso3=="`cc'" & (wlag>10 | wlag<-10)
        drop if (iso3=="`cc'" | ciso=="`ci'") & (wlag>30 | wlag<-30)

        *** March 19 2014
        gen abslag=abs(wlag)
        sort w abslag
        ***
        
        keep if _n<=years[`t',4]
        
        gen region="other super region"
        ** replace region="country" if iso3=="`cc'"
        replace region="country" if iso3=="`cc'" | ciso=="`ci'"
        ** replace region="gbd" if iso3!="`cc'" & gbd_region_name=="`gbd'"
        replace region="gbd" if (iso3!="`cc'" | ciso!="`ci'" ) & gbd_region_name=="`gbd'"

        ** replace region="super region" if iso3!="`cc'" & gbd_region_name!="`gbd'" & gbd_superregion=="`super'"
        replace region="super region" if (iso3!="`cc'" | ciso!="`ci'") & gbd_region_name!="`gbd'" & gbd_superregion=="`super'"

        gen lag=years[`t',3]-year
        keep source iso3 sex year lx* gbd_region_name gbd_superregion_name lag region
        reshape long lx, i(source iso3 sex year) j(age)
        sort source iso3 sex year age
        bysort source iso3 sex year: gen qx=1-lx[_n+1]/lx 
        gen logitqx=-0.5*ln(qx/(1-qx))
        merge m:1 sex lag region using `wlevel'
        keep if _merge==3
        drop _merge
        
        *** only care about ages upto 80-84 for now
        ** keep if age<=80
        sort iso3 sex year age
        ** egen tweight=sum(weights),by(age)
        ** gen w_logitqx=logitqx*weights/tweight
        ** collapse (sum) w_logitqx, by(sex age)
        ** gen sqx=exp(-2*w_logitqx)/(1+exp(-2*w_logitqx))
        ** drop w_logit
        
        
        egen tweight=sum(weights),by(age)
        gen w_qx=qx*weights/tweight
        collapse (sum) w_qx, by(sex age)
        gen sqx=w_qx
        drop w_qx
        
        
        reshape wide sqx, i(sex) j(age)
        gen ref_year=years[`t',3]
        cap append using `matched_`y''
        save `matched_`y'', replace
    }
    gen ref_iso3="`cc'"
    save `matched_`y'',replace
    matrix drop years
    erase `counterg2_`y''
    noisily dis "counter-factual : `y' of $macs done"    
}

use `matched_1',clear
forvalues b=2/$macs {
    append using `matched_`b''
}


gen sq5=1-(1-sqx0)*(1-sqx1)
gen sq45=1-(1-sqx15)*(1-sqx20)*(1-sqx25)*(1-sqx30)*(1-sqx35)*(1-sqx40)*(1-sqx45)*(1-sqx50)*(1-sqx55)
reshape long sqx, i(ref_iso3 ref_year sex) j(age)
gen logitsqx=-0.5*ln(sqx/(1-sqx))
gen logitsq5=-0.5*ln(sq5/(1-sq5))
gen logitsq45=-0.5*ln(sq45/(1-sq45))
rename ref_iso3 iso3
rename ref_year year
tempfile smstan
save `smstan'

****************************************
*** merge pars and  by model ***
*** make counter-factual predictions ***
****************************************
gen sim=$nn
merge m:1 sim sex age using "$datadir/modelpar_sim.dta"
keep if _merge==3
drop _merge
sort iso3 sex age year
save `smstan',replace

*** **********************
*** predict hivfree-life tables ***
*** **********************

use `hivfree',clear
gen c_logit5q0=-0.5*ln(c_v5q0/(1-c_v5q0))
gen c_logit45q15=-0.5*ln(c_v45q15/(1-c_v45q15))
expand 22
sort iso3 sex year
bysort iso3 sex year: gen rank=_n
gen age=(rank-2)*5
replace age=0 if rank==1
replace age=1 if rank==2
cap drop rank
merge 1:1 iso3 sex age year using `smstan'
keep if _merge==3
drop _merge
sort  iso3 sex year age
gen plqx_c = logitsqx + sim_difflogit5*(c_logit5q0- logitsq5)+ sim_difflogit45*(c_logit45q15- logitsq45)
gen c_pqx = exp(-2*plqx_c)/(1+exp(-2*plqx_c))
keep   iso3 year c_v45q15 sex age c_v5q0 c_pqx sqx
**** get predicted 45q15 and 5q0 for first stage
gen lx=1
sort  iso3 sex year age
bysort  iso3 sex year: replace lx=lx[_n-1]*(1-c_pqx[_n-1]) if _n>1
sort  iso3 sex year age
bysort  iso3 sex year: gen p45q15=1-lx[14]/lx[5]
sort  iso3 sex year age
bysort  iso3 sex year: gen p5q0=1-lx[3]
drop lx
sort  iso3 sex year age
tempfile tpqx tallouts
sort  iso3 sex year age
reshape wide  c_pqx sqx, i( iso3 sex year) j(age)
save `tpqx'


***************************
***iterations to slove for qx55 that satisfy both predicted relative risks and target 45q15 
***************************
tempfile v5not v5equal
keep if round(p5q0/c_v5q0,0.0000000001)==1
local left=_N
if `left'>0 {
    foreach nn of numlist 0 1 5 10 {
        gen qx_adj`nn'=c_pqx`nn'
    }    
    save `v5equal'
}

use `tpqx',clear
keep if round(p5q0/c_v5q0,0.0000000001)!=1
local left=_N
if `left'>0 {
    local cnum = 10
    local citer = 30
    local ccat=1    
    
    gen crmin = 0.0001
    gen crmax = 0.6
    
    gen cadj = .
    gen adj5q0_min = .
    gen rc_min=.
    gen diffc_min = . 
    
    while `ccat'<=`citer' {
        local cq=0
        while `cq'<=`cnum' {
            cap: gen y`cq' = .
            replace y`cq' = crmin + `cq'*((crmax-crmin)/`cnum')
            local cqq=`cq'+1
            cap: gen rc`cqq'= .
            replace rc`cqq'=y`cq'
            local cq=`cq'+1    
            cap: gen adj5q0`cqq'= .
            replace adj5q0`cqq' = 1-[1-(c_pqx0/c_pqx1)*rc`cqq']*[1-rc`cqq']
            cap: gen diffc`cqq'= . 
            replace diffc`cqq' = abs(adj5q0`cqq'-c_v5q0) if adj5q0`cqq'!= 0
        }    
        cap: drop diffc_min
        order diffc*
        egen diffc_min = rowmin(diffc1-diffc11)
        
        replace rc_min= . 
        forvalues cqq=1/11 {
            replace rc_min=rc`cqq' if diffc`cqq'==diffc_min
        }
        
        count if rc_min == .
        if (`r(N)'!=0) {
            noisily: dis "`ccat'"
            pause
        }
        
        replace cadj=abs(crmax-crmin)/10
        replace crmax=rc_min+2*cadj
        replace crmin=rc_min-2*cadj
        replace crmin=0.0001 if crmin<0
        
        local ccat=`ccat'+1
    }
    foreach nn of numlist 0 1 5 10 {
        gen qx_adj`nn'=(c_pqx`nn'/c_pqx1)*rc_min
    }
    save `v5not'

}
noisily dis "kid scenario 1 done"

cap append using `v5equal'

tempfile after5
drop y0-y10 rc1-rc11 diffc1-diffc11 adj5q01-adj5q011 *min* *max* crmin crmax cadj
save `after5'

*** ***************
*** adjust 45q15 ***
** ****************
tempfile adultover
use `after5',clear
keep if round(p45q15/c_v45q15,0.00000001)!=1 
local left=_N
if `left'>0 {
    tempfile adultover
    local num = 20
    local iter = 30
    local cat=1
        
    gen rmin = .0001
    gen rmax = 0.99999
    
    gen adj = .
    gen adj45q15_min = .
    gen r_min = .
    gen diff_min = .
    
    while `cat'<=`iter' {
        local q=0
        while `q'<=`num' {
            cap: gen y`q' = .
            replace y`q' = rmin + `q'*((rmax-rmin)/`num')
            local qq=`q'+1
            cap: gen r`qq' = .
            replace r`qq'=y`q'
            local q=`q'+1    
            
            cap: gen adj45q15`qq' = .
            replace adj45q15`qq' = 1-[1-(c_pqx15/c_pqx55)*r`qq']*[1-(c_pqx20/c_pqx55)*r`qq']*[1-(c_pqx25/c_pqx55)*r`qq']*[1-(c_pqx30/c_pqx55)*r`qq']*[1-(c_pqx35/c_pqx55)*r`qq']*[1-(c_pqx40/c_pqx55)*r`qq']*[1-(c_pqx45/c_pqx55)*r`qq']*[1-(c_pqx50/c_pqx55)*r`qq']*[1-r`qq']
            cap: gen diff`qq' = .
            replace diff`qq' = abs(adj45q15`qq'-c_v45q15)
        }
        cap: drop diff_min
        order diff*
        egen diff_min=rowmin(diff1-diff21)
        replace r_min=.
        forvalues qq=1/21 {
            replace r_min = r`qq' if diff`qq'==diff_min
        }
        
        count if r_min == .
        if (`r(N)'!=0) {
            noisily: dis "`ccat'"
            pause
        }        

        replace adj=(rmax-rmin)/20
        replace rmax=r_min + 2*adj
        replace rmin=r_min - 2*adj
        replace rmin=0.0001 if rmin<0
        local cat=`cat'+1
    }      
    ** adjust 55 plus as well
    foreach nn of numlist 15(5)100 {
        gen qx_adj`nn'=(c_pqx`nn'/c_pqx55)*r_min

    }
    save `adultover'
}
noisily dis "old guys scenario 1 done"

use `after5',clear
keep if round(p45q15/c_v45q15,0.00000001) == 1 
local left=_N
if `left'>0 {
    tempfile adultequal
    gen r_min = 1
    
    foreach nn of numlist 15(5)100 {
        gen qx_adj`nn'=c_pqx`nn'
    }    
    save `adultequal'
}

cap append using `adultover'
drop y0-y10 r1-r21 diff1-diff21 adj45q151-adj45q1521  rmin rmax adj
reshape long c_pqx sqx qx_adj, i(iso3 sex year) j(age)    
keep   iso3 year c_v45q15 sex c_v5q0 age qx_adj c_pqx sqx
tempfile tallouts
save `tallouts'

************************************
*** generate the full life table ***
************************************

*** get the pars for mx in 110+ age group
use "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/par_age_110plus_mx.dta",clear
sort sex
local mxf=parlnmx[1]
local mxm=parlnmx[2]

tempfile struc
use `tallouts',clear
keep  iso3 sex year
duplicates drop  iso3 sex year, force
expand 24
bysort  iso3 sex year: gen rank=_n
gen age=0 if rank==1
replace age=1 if rank==2
replace age=(rank-2)*5 if rank>2
drop rank
sort  iso3 sex year age
save `struc'
use `tallouts',clear
sort  iso3 sex year age
merge  iso3 sex year age using `struc'
drop _merge
gen logitqx=ln(qx_adj/(1-qx_adj))
sort sex age  iso3 year 
merge sex age using "$datadir/par_age_85plus_qx_alter.dta"
drop _merge
sort  iso3 sex year age
bysort  iso3 sex year:gen prediff=par_85cons+par_logitqx80*logitqx[18]+par_vage
sort  iso3 sex year age
bysort  iso3 sex year:gen pqx=qx_adj if _n==18
sort  iso3 sex year age
bysort  iso3 sex year:replace pqx=exp(ln(pqx[_n-1]/(1-pqx[_n-1]))+prediff[_n-1])/(1+exp(ln(pqx[_n-1]/(1-pqx[_n-1]))+prediff[_n-1])) if _n>18 & _n<24
replace qx_adj=pqx if age>80 & qx_adj==.
replace qx_adj=1 if age==110
keep  iso3 sex year age sqx c_pqx c_v5q0 c_v45q15 qx_adj
gen lx=1

*** replace over 1 predicted qx with 0.99
replace qx_adj=0.99 if qx_adj>1 & qx_adj!=.


sort  iso3 sex year age
bysort  iso3 sex year: replace lx=lx[_n-1]*(1-qx_adj[_n-1]) if _n>1
gen nn=5
replace nn=1 if age==0
replace nn=4 if age==1
gen dx=.
sort  iso3 sex year age
bysort  iso3 sex year: replace dx=lx-lx[_n+1] 
replace dx=lx if age==110
gen ax=.
sort  iso3 sex year age
bysort  iso3 sex year: replace ax=((-5/24)*dx[_n-1]+2.5*dx+(5/24)*dx[_n+1])/dx if _n>3 & _n<23
replace ax=2.5 if ax<0 & age>5 & age<110
replace ax=2.5 if ax>5 & age>5 & age<110

*** re-calculate ax for 80+ age groups based on empirical findings
sort sex age
merge sex age using "$datadir/ax_par.dta"
gen qx_square=qx_adj^2
replace ax=par_qx*qx_adj+par_sqx*qx_square+par_con if age>75 & par_con!=.
drop _merge qx_square par_qx par_sqx par_con

gen k1=.
sort  iso3 sex year age
bysort  iso3 sex year: replace k1=1.352 if qx[1]>0.01 & sex[1]=="male"
sort  iso3 sex year age
bysort  iso3 sex year: replace k1=1.361 if qx[1]>0.01 & sex[1]=="female"
sort  iso3 sex year age
bysort  iso3 sex year: replace k1=1.653-3.013*qx[1] if qx[1]<=0.01 & sex[1]=="male"
sort  iso3 sex year age
bysort  iso3 sex year: replace k1=1.524-1.627*qx[1] if qx[1]<=0.01 & sex[1]=="female"
gen mx=.
gen double nLx=.
sort  iso3 sex year age
bysort  iso3 sex year: replace mx=qx/(nn-(nn-ax)*qx) if _n>3 & _n<24
sort  iso3 sex year age
bysort  iso3 sex year: replace nLx = nn*lx[_n+1]+ax*dx if _n>3 & _n<24
sort  iso3 sex year age
bysort  iso3 sex year: replace ax=1 if _n>17 & _n<23 & (mx>=1|mx<=0) 
sort  iso3 sex year age
bysort  iso3 sex year: replace mx=qx/(nn-(nn-ax)*qx) if _n>17 & _n<24
sort  iso3 sex year age
bysort  iso3 sex year: replace nLx = nn*lx[_n+1]+ax*dx if _n>17 & _n<24

*** get mx in the open age interval 110+
sort  iso3 sex year age
bysort  iso3 sex year: gen lnmx105=ln(mx[23])

replace mx=exp(`mxf'*lnmx105) if age==110 & sex=="female"
replace mx=exp(`mxm'*lnmx105) if age==110 & sex=="male"

cap drop lnmx105

replace nLx=lx/mx if age==110
sort  iso3 sex year age
bysort  iso3 sex year:replace nLx=(0.05+3*qx_adj[1])+(0.95-3*qx_adj[1])*lx[2] if _n==1
sort  iso3 sex year age
bysort  iso3 sex year: replace nLx=0.35+0.65*lx[2] if _n==1 & qx_adj[1]>0.1
sort  iso3 sex year age
bysort  iso3 sex year: replace nLx=(k1*lx[2]+(4-k1)*lx[3]) if _n==2
sort  iso3 sex year age
bysort  iso3 sex year: replace nLx=2.5*(lx[3]+lx[4]) if _n==3
sort  iso3 sex year age
bysort  iso3 sex year: replace mx=dx/nLx if _n<4
sort  iso3 sex year age
bysort  iso3 sex year: replace ax=(qx+nn*mx*qx-nn*mx)/(mx*qx) if _n<4

        cap replace ax=0.2 if age==0 & sex=="male" & ax<=0
        cap replace ax=0.2 if age==0 & sex=="male" & ax>=1
        cap replace ax=0.15 if age==0 & sex=="female" & ax<=0
        cap replace ax=0.15 if age==0 & sex=="female" & ax>=1    

        cap replace ax=1.35 if age==1 & sex=="male" & ax<=0
        cap replace ax=1.35 if age==1 & sex=="male" & ax>=4
        cap replace ax=1.36 if age==1 & sex=="female" & ax<=0
        cap replace ax=1.36 if age==1 & sex=="female" & ax>=4    

        cap replace ax=2.5 if age==5 & sex=="male" & ax<=0
        cap replace ax=2.5 if age==5 & sex=="male" & ax>=5
        cap replace ax=2.5 if age==5 & sex=="female" & ax<=0
        cap replace ax=2.5 if age==5 & sex=="female" & ax>=5    
        
egen lid=group( iso3 sex year)
cap sum lid
local nlid=r(max)
gen double Tx=nLx
gsort iso3 sex year -age
bysort iso3 sex year: replace Tx=Tx[_n-1]+nLx if _n>1
gen double ex=Tx/lx
replace ax=ex if age==110
save `tallouts',replace
tempfile newtallouts
save `newtallouts'

*** keep ax values for later use
keep iso3 sex year age ax
rename ax ax_hivfree
tempfile axs
save `axs'

use `newtallouts',clear
cap lab drop agelbl
keep  iso3 sex year age c_v5q0 c_v45q15 qx_adj sqx c_pqx
rename qx_adj c_pqx_adj
tempfile newall
sort  iso3 sex year age
save `newall'


*** only keep the ones that will be used in final step
clear
set obs 1000
gen sim=_n-1
expand 10
sort sim
bysort sim: gen secsim=_n
set seed 1234567
sample 10
keep if sim==$nn

if _N>0 {
    global max=_N
    mkmat sim secsim, mat(locals)
}
else {
    global max=1
    set obs 1
    replace sim=$nn
    replace secsim=1
    mkmat sim secsim, mat(locals)
}



tempfile simouts
forvalues w=1/$max {
    local h=locals[`w',2]
    use "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/sims/entry_$nn.dta",clear
    keep iso3 sex year v45q15 v5q0 hivprev
    sort  iso3 sex year
    merge  iso3 sex year using `newall'
    keep if _merge==3
    drop _merge
    gen sim=$nn
    gen secsim=`h'
    merge m:1 iso3 sex using "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/hivtype.dta"
    replace types="concen" if _merge==1
    drop if _merge==2
    drop _merge
    merge m:1 sex sim types age using "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/hiv_rr.dta"
    drop if _merge==2
    drop _merge
    
    replace hivrr=1 if age==40
    
    sort secsim iso3 sex year age
    bysort secsim iso3 sex year: replace v5q0=v5q0[1] if v5q0==.
        bysort secsim iso3 sex year: replace c_v5q0=c_v5q0[1] if c_v5q0==.
    bysort secsim iso3 sex year: replace v45q15=v45q15[1] if v45q15==.
    bysort secsim iso3 sex year: replace c_v45q15=c_v45q15[1] if c_v45q15==.

    
    merge m:1 iso3 sex year age using `axs',nogen
    gen nn=5
    replace nn=1 if age==0
    replace nn=4 if age==1
    gen mx_nohiv= c_pqx_adj/(nn-(nn-ax)*c_pqx_adj)
    gen amxdiff=abs([ln(1-v45q15)-ln(1-c_v45q15)]/-45)
    gen kmxdiff=abs([ln(1-v5q0)-ln(1-c_v5q0)]/-5)
        
    keep   iso3 year v45q15 sex age v5q0 c_v* mx_nohiv ax *mxdiff secsim hivrr hivprev nn
    tempfile secpqx secouts
    cap lab drop agelbl
    cap lab drop agelabels
    save `secpqx'

    keep if kmxdiff<=0.00001
    local left=_N
    if `left'>0 {
        tempfile kzerohiv
        gen mx=mx_nohiv
        keep if age<15
        save `kzerohiv'
    }

    tempfile sec5over
    use `secpqx',clear
    keep if kmxdiff>0.00001
    local cnum = 10
    local citer = 50
    local ccat=1    
        
    gen crmin = 0.002
    gen crmax = 100

    gen cadj = .
    gen adj5q0_min = .
    gen rc_min=.
    gen diffc_min = . 
    while `ccat'<=`citer' {
        local cq=0
        while `cq'<=`cnum' {
            cap: gen y`cq' = .
            replace y`cq' = crmin + `cq'*((crmax-crmin)/`cnum')
            local cqq=`cq'+1
            cap: gen rc`cqq'= .
            replace rc`cqq'=y`cq'
            local cq=`cq'+1    
            cap: gen adj5q0`cqq'= .
            sort iso3 sex year age
            gen qx`cqq'=nn*(mx_nohiv+hivrr*kmxdiff*rc`cqq')/[1+(nn-ax)*(mx_nohiv+hivrr*kmxdiff*rc`cqq')]
            bysort iso3 sex year: replace adj5q0`cqq' = 1-(1-qx`cqq'[1])*(1-qx`cqq'[2])
            cap: gen diffc`cqq'= . 
            replace diffc`cqq' = abs(adj5q0`cqq'-v5q0) if adj5q0`cqq'!= 0
        }    
        cap drop qx*
        cap: drop diffc_min
        order diffc*
        egen diffc_min = rowmin(diffc1-diffc11)
        replace rc_min= . 
        forvalues cqq=1/11 {
                replace rc_min=rc`cqq' if diffc`cqq'==diffc_min
        }
        
        count if rc_min == .
        if (`r(N)'!=0) {
            noisily: dis "`ccat'"
            pause
        }
            
        replace cadj=abs(crmax-crmin)/10
        replace crmax=rc_min+2*cadj
        replace crmin=rc_min-2*cadj
        replace crmin=0.000001 if crmin<0
        local ccat=`ccat'+1
    }
    gen mx=mx_nohiv+hivrr*rc_min*kmxdiff
    keep   iso3 year v45q15 sex age v5q0 c_v* mx_nohiv ax *mxdiff secsim hivrr hivprev nn mx
    keep if age<15
    save `sec5over'                
    
    
    use `secpqx',clear
    keep if amxdiff<=0.00001
    local left=_N
    if `left'>0 {
        tempfile azerohiv
        gen mx=mx_nohiv
        keep if age>=15
        save `azerohiv'
    }

    tempfile sec45
    use `secpqx',clear
    keep if amxdiff>0.00001
    local cnum = 100
    local citer = 50
    local ccat=1    
        
    gen crmin = 0.002
    gen crmax = 50

    gen cadj = .
    gen adj45q15_min = .
    gen rc_min=.
    gen diffc_min = . 
    while `ccat'<=`citer' {
        local cq=0
        while `cq'<=`cnum' {
            cap: gen y`cq' = .
            replace y`cq' = crmin + `cq'*((crmax-crmin)/`cnum')
            local cqq=`cq'+1
            cap: gen rc`cqq'= .
            replace rc`cqq'=y`cq'
            local cq=`cq'+1    
            cap: gen adj45q15`cqq'= .
            sort iso3 sex year age
            gen qx`cqq'=nn*(mx_nohiv+hivrr*amxdiff*rc`cqq')/[1+(nn-ax)*(mx_nohiv+hivrr*amxdiff*rc`cqq')]
            bysort iso3 sex year: replace adj45q15`cqq' = 1-(1-qx`cqq'[5])*(1-qx`cqq'[6])*(1-qx`cqq'[7])*(1-qx`cqq'[8])*(1-qx`cqq'[9])*(1-qx`cqq'[10])*(1-qx`cqq'[11])*(1-qx`cqq'[12])*(1-qx`cqq'[13])
            cap: gen diffc`cqq'= . 
            replace diffc`cqq' = abs(adj45q15`cqq'-v45q15) if adj45q15`cqq'!= 0
        }    
        cap drop qx*
        cap: drop diffc_min
        order diffc*
        egen diffc_min = rowmin(diffc*)
        replace rc_min= . 
        forvalues cqq=1/101 {
                replace rc_min=rc`cqq' if diffc`cqq'==diffc_min
        }
        
        count if rc_min == .
        if (`r(N)'!=0) {
            noisily: dis "`ccat'"
            pause
        }
            
        replace cadj=abs(crmax-crmin)/100
        replace crmax=rc_min+2*cadj
        replace crmin=rc_min-2*cadj
        replace crmin=0.000001 if crmin<0
        local ccat=`ccat'+1
    }
    gen mx=mx_nohiv+hivrr*rc_min*amxdiff
    keep   iso3 year v45q15 sex age v5q0 c_v* mx_nohiv ax *mxdiff secsim hivrr hivprev nn mx
    keep if age>=15
    cap append using `kzerohiv'
    cap append using `azerohiv'
    cap append using `sec5over'
    sort iso3 sex year age
    replace mx=mx_nohiv if age>75
    gen qx_adj=nn*mx/(1+(nn-ax)*mx)
    keep   iso3 year v45q15 sex v5q0 age qx_adj secsim nn mx
    tempfile secouts                    
    save `secouts'


    gen lx=1
    sort  iso3 sex year age
    bysort  iso3 sex year: replace lx=lx[_n-1]*(1-qx_adj[_n-1]) if _n>1
    gen dx=.
    sort  iso3 sex year age
    bysort  iso3 sex year: replace dx=lx-lx[_n+1] 
    replace dx=lx if age==110
    ** * merge in hiv free ax values
    merge 1:1 iso3 sex year age using `axs'
    drop _merge
    gen nLx=.
    sort  iso3 sex year age
    bysort  iso3 sex year: replace nLx = nn*lx[_n+1]+ax*dx
    replace nLx=lx/mx if age==105
    replace nLx=lx/mx if age==110
    
    egen lid=group( iso3 sex year)
    save `secouts',replace
    tempfile newsecouts
    keep iso3 sex year age nLx
    egen double Tx0=sum(nLx), by(iso3 sex year)
    reshape wide nLx, i(iso3 sex year) j(age)
    gen double Tx1=Tx0-nLx0
    gen double Tx5=Tx1-nLx1
    forvalues j=10(5)110 {
        local jj=`j'-5
        gen double Tx`j'=Tx`jj'-nLx`jj'
    }
    reshape long nLx Tx, i(iso3 sex year) j(age)
    drop nLx
    merge 1:1 iso3 sex year age using `secouts'
    drop _merge
    gen double ex=Tx/lx
    replace secsim=`h'
    cap append using `simouts'
    save `simouts',replace
    local files="secpqx azerohiv kzerohiv sec5over secouts"
    foreach f of local files {
        cap erase ``f''
    }
}

*** keep only the useful ones ***
use `newtallouts',clear
compress
save "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/sims/LT_sim_nohiv_$nn.dta",replace
use `simouts',clear
compress
save "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/sims/LT_sim_withhiv_withsim_$nn.dta",replace


*** compile HIV and ENVELOPE related variables
use `newtallouts',clear
replace mx=lx/Tx if age==100
drop if age>=105
keep iso3 sex year age mx
rename mx nohiv_mx
tempfile combined
save `combined'

use `simouts',clear
replace mx=lx/Tx if age==100
drop if age>=105
keep secsim iso3 sex year age mx
rename mx hiv_mx
merge m:1 iso3 sex year age using `combined'
drop _merge
merge m:1 iso3 sex year age using "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/pop_100.dta"
keep if _merge==3
drop _merge
gen envelope_nohiv=nohiv_mx*pop
gen envelope_withhiv=hiv_mx*pop
replace age=80 if age>80
collapse (sum) envelope* pop  hiv_mx nohiv_mx, by(secsim iso3 sex year age)
gen HIVfrac=( hiv_mx- nohiv_mx)/ hiv_mx
replace HIVfrac=0 if HIVfrac<0
replace  hiv_mx=. if  age==80
replace  nohiv_mx=. if age==80
save `combined',replace

*** small countries with odd population numbers
use `newtallouts',clear
replace mx=lx/Tx if age==80
drop if age>80
keep iso3 sex year age mx
rename mx nohiv_mx
tempfile sixs
save `sixs'

use `simouts',clear
replace mx=lx/Tx if age==80
drop if age>80
keep iso3 sex year age mx secsim
rename mx hiv_mx
merge m:1 iso3 sex year age using `sixs'
drop _merge
merge m:1 iso3 sex year age using "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/pop_80.dta"
keep if _merge==3
drop _merge
gen envelope_nohiv=nohiv_mx*pop*1000
gen envelope_withhiv=hiv_mx*pop*1000
gen HIVfrac=( hiv_mx- nohiv_mx)/ hiv_mx
replace HIVfrac=0 if HIVfrac<0
replace  hiv_mx=. if  age==80
replace  nohiv_mx=. if age==80
append using `combined'
gen deaths_HIV=envelope_withhiv*HIVfrac
compress

preserve
keep iso3 sex year age secsim envelope_withhiv deaths_HIV
gen id="_"+string($nn)+"_"+string(secsim)
drop secsim
reshape wide  envelope_withhiv deaths_HIV, i(iso3 sex year age) j(id) str
lab drop agelbl
save "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/sims/envelope_sim_$nn.dta",replace
restore
keep iso3 sex year age secsim HIVfrac
gen id="_"+string($nn)+"_"+string(secsim)
drop secsim
reshape wide HIVfrac, i(iso3 sex year age) j(id) str
lab drop agelbl
tostring age, force replace
save "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/sims/HIVfrac_sim_$nn.dta",replace

*** merge in the under-5 envelopes 
** local w=$nn+1
local w=$nn
use "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/sims/noshock_u5_deaths_sim_`w'.dta",clear
replace age="1" if age=="2"
replace age="1" if age=="3"
replace age="1" if age=="4"
collapse (sum) deaths, by(iso3 sex year age)
tempfile u5s
save `u5s'
drop if age=="1"
collapse (sum) deaths, by(iso3 sex year)
gen age="0"
append using `u5s'
merge 1:1 iso3 sex year age using "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/sims/HIVfrac_sim_$nn.dta"
drop if _merge==2
drop _merge
local v1="envelope_withhiv_$nn"
local v2="deaths_HIV_$nn"
local v3="HIVfrac_$nn"
forvalues w=1/$max {
    local h=locals[`w',2]
    gen `v1'_`h'=deaths
    gen `v2'_`h'=`v3'_`h'*deaths
}
drop deaths HIVfrac*
save `u5s',replace
use "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/sims/envelope_sim_$nn.dta",clear
drop if age<5
tostring age, force replace
append using `u5s'
save "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/sims/envelope_sim_$nn.dta",replace

*** add shocks ***
use "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/sims/entry_$nn.dta",clear
rename simulation sim
        
        ** merge 1:1 sim iso3 sex year using "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/shock_45q15_sim.dta"
        ** HW 5-1-2012
        ** merge 1:1 sim iso3 sex year using "$dirs/Project/Mortality/GBD Envelopes/03. Adult mortality 45q15/Results/shock_45q15_sim.dta"
        ** merge 1:1 sim iso3 sex year using "$dirs/Project/Mortality/GBD Envelopes/03_adult_mortality/data/shocks/war_shocks_sims.dta"
        merge 1:1 sim iso3 sex year using "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/shock_45q15_sim.dta"
keep if _merge==3 | shockq5>v5q0+0.00001
drop _merge
rename shockq5 withshock_5q0
rename shock45q15 withshock_45q15
keep if withshock_5q0!=. | withshock_45q15!=.
keep iso3 sex year v5q0 v45q15 withshock*
sort iso3 sex year
tempfile withshocks
save `withshocks'

*** get the nonshock life table estimates 
use `simouts',clear
keep secsim iso3 sex year age qx_adj ax
rename qx qx
merge m:1 iso3 sex year using `withshocks'
keep if _merge==3
drop _merge
save `withshocks',replace

gen logitqx=ln(qx/(1-qx))
gen sign=-1 if logitqx<0
replace sign=1 if logitqx>=0
keep secsim iso3 sex year age logitqx v* with* sign
reshape wide logitqx sign, i(secsim iso3 sex year) j(age)
local nid=_N
tempfile raws
save `raws'
tempfile adjs
forvalues j=1/`nid' {
    use `raws',clear
    keep if _n==`j'
    if  withshock_5q0[1]==.{
        gen rc=0
    }
    else {
        if round(withshock_5q0[1]/v5q0[1],0.00001)<=1 {
            gen rc=0
        }
        if round(withshock_5q0[1]/v5q0[1],0.00001)>1 & withshock_5q0[1]!=. {
            gen rc=.
            local cnum = 10
            local crmin = -5
            local crmax = -0.0000000000000001
            local citer = 30
            local ccat=1
            while `ccat'<=`citer' {
                expand 11
                local cq=0
                while `cq'<=`cnum' {
                    local y`cq' = `crmin' + `cq'*((`crmax'-`crmin')/`cnum')
                    local cqq=`cq'+1
                    replace rc=`y`cq'' in `cqq'
                    local cq=`cq'+1    
                }
                gen adj5q0= 1-(1-exp(logitqx0*(1+rc))/(1+exp(logitqx0*(1+rc))))*(1-exp(logitqx1*(1+rc))/(1+exp(logitqx1*(1+rc))))
                drop if adj5q0==0 
                gen diffc=abs(adj5q0-withshock_5q0)
                sort diffc
                keep if _n==1
                local cadj=abs(`crmax'-`crmin')/10
                local crmax=rc[1]+2*`cadj'
                local crmin=rc[1]-2*`cadj'
                if `crmax'>0 {
                    local crmax=-0.000000001
                }
                drop adj5q0 diffc
                local ccat=`ccat'+1
            }  
        }
    }
        **** adjust qx values in the 15-59 age groups
        *** basically adjusting the difference in qx from the two steps in log scale
    if  withshock_45q15[1]==.{
        gen r=0
    }
    else {
        if round(withshock_45q15[1]/v45q15[1],0.00001)<=1 {
            gen r=0
        }
        if round(withshock_45q15[1]/v45q15[1],0.00001)>1 {
            gen r=.
            local num = 10
            local rmin = -5
            local rmax =-0.000000000000001
            local iter = 30
            local cat=1
            while `cat'<=`iter'{
                expand 11
                local q=0
                while `q'<=`num' {
                    local y`q' = `rmin' + `q'*((`rmax'-`rmin')/`num')
                    local qq=`q'+1
                    replace r=`y`q'' in `qq'
                    local q=`q'+1    
                }
                gen adj45q15=1-(1-exp(logitqx15*(1+r))/(1+exp(logitqx15*(1+r))))*(1-exp(logitqx20*(1+r))/(1+exp(logitqx20*(1+r))))*(1-exp(logitqx25*(1+r))/(1+exp(logitqx25*(1+r))))*(1-exp(logitqx30*(1+r))/(1+exp(logitqx30*(1+r))))*(1-exp(logitqx35*(1+r))/(1+exp(logitqx35*(1+r))))*(1-exp(logitqx40*(1+r))/(1+exp(logitqx40*(1+r))))*(1-exp(logitqx45*(1+r))/(1+exp(logitqx45*(1+r))))*(1-exp(logitqx50*(1+r))/(1+exp(logitqx50*(1+r))))*(1-exp(logitqx55*(1+r))/(1+exp(logitqx55*(1+r))))
                drop if adj45q15==0 
                gen diff=abs(adj45q15-withshock_45q15)
                sort diff
                keep if _n==1
                local adj=abs(`rmax'-`rmin')/10
                local rmax=r[1]+2*`adj'
                local rmin=r[1]-2*`adj'
                if `rmax'> 0 {
                    local rmax=-0.00000000001
                }
                drop adj45q15 diff
                local cat=`cat'+1
            }  
        }
    }    
    
    foreach nn of numlist 10(5)110 {
        gen qx_shock`nn'=exp(logitqx`nn'*(1+r))/(1+exp(logitqx`nn'*(1+r))) if sign`nn'<0
        replace qx_shock`nn'=exp(logitqx`nn'*(1-r))/(1+exp(logitqx`nn'*(1-r))) if sign`nn'>0
        
    }
    foreach nn of numlist 0 1 5{
        gen qx_shock`nn'=exp(logitqx`nn'*(1+rc))/(1+exp(logitqx`nn'*(1+rc)))
    }        
    drop logitqx* r rc sign*
    cap append using `adjs'
    save `adjs', replace
    noisily dis in red "shock adjustment: `j' of `nid' done"
}
reshape long qx_shock, i(secsim iso3 sex year) j(age)
save `adjs',replace

*** get ax values from nonshock lts
use `simouts',clear
keep secsim iso3 sex year age ax
rename ax ax_noshock
merge 1:1 secsim iso3 sex year age using `adjs'
keep if _merge==3
drop _merge

gen lx=1
sort secsim iso3 sex year age
bysort secsim iso3 sex year: replace lx=lx[_n-1]*(1-qx[_n-1]) if _n>1
gen nn=5
replace nn=1 if age==0
replace nn=4 if age==1
gen dx=.
sort secsim iso3 sex year age
bysort secsim iso3 sex year: replace dx=lx-lx[_n+1] 
replace dx=lx if age==110

gen k1=.
sort secsim iso3 sex year age
bysort secsim iso3 sex year: replace k1=1.352 if qx[1]>0.01 & sex[1]=="male"
sort secsim iso3 sex year age
bysort secsim iso3 sex year: replace k1=1.361 if qx[1]>0.01 & sex[1]=="female"
sort secsim iso3 sex year age
bysort secsim iso3 sex year: replace k1=1.653-3.013*qx[1] if qx[1]<=0.01 & sex[1]=="male"
sort secsim iso3 sex year age
bysort secsim iso3 sex year: replace k1=1.524-1.627*qx[1] if qx[1]<=0.01 & sex[1]=="female"
gen mx_shock=.
gen nLx=.
sort secsim iso3 sex year age
bysort secsim iso3 sex year: replace mx_shock=qx/(nn-(nn-ax)*qx) if _n>3 & _n<24
sort secsim iso3 sex year age
bysort secsim iso3 sex year: replace nLx = nn*lx[_n+1]+ax*dx if _n>3 & _n<24

sort secsim iso3 sex year age
bysort secsim iso3 sex year: gen lnmx105=ln(mx[23])
replace mx_shock=exp(`mxf'*lnmx105) if age==110 & sex=="female"
replace mx_shock=exp(`mxm'*lnmx105) if age==110 & sex=="male"
cap drop lnmx105

replace nLx=lx/mx if age==110
sort secsim iso3 sex year age
bysort secsim iso3 sex year:replace nLx=(0.05+3*qx_shock[1])+(0.95-3*qx_shock[1])*lx[2] if _n==1
sort secsim iso3 sex year age
bysort secsim iso3 sex year: replace nLx=0.35+0.65*lx[2] if _n==1 & qx_shock[1]>0.1
sort secsim iso3 sex year age
bysort secsim iso3 sex year: replace nLx=(k1*lx[2]+(4-k1)*lx[3]) if _n==2
sort secsim iso3 sex year age
bysort secsim iso3 sex year: replace nLx=2.5*(lx[3]+lx[4]) if _n==3
sort secsim iso3 sex year age
bysort secsim iso3 sex year: replace mx=dx/nLx if _n<4

egen lid=group(secsim iso3 sex year)
cap sum lid
local nlid=r(max)
save `adjs',replace
tempfile shockouts
keep secsim iso3 sex year age nLx
egen double Tx0=sum(nLx), by(secsim iso3 sex year)
reshape wide nLx, i(secsim iso3 sex year) j(age)
gen double Tx1=Tx0-nLx0
gen double Tx5=Tx1-nLx1
forvalues j=10(5)110 {
    local jj=`j'-5
    gen double Tx`j'=Tx`jj'-nLx`jj'
}
reshape long nLx Tx, i(secsim iso3 sex year) j(age)
drop nLx
merge 1:1 secsim iso3 sex year age using `adjs', nogen
gen double ex=Tx/lx
save `shockouts'
compress
save "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/sims/LT_sim_shock_$nn.dta",replace

use `shockouts',clear
keep secsim iso3 sex year age mx
merge 1:1 secsim iso3 sex year age using `simouts'
keep if _merge==3
drop _merge
gen shock_extra=(mx_shock-mx)/mx
*** weird STATA precision issue
replace shock_extra=0 if shock_extra<0
keep secsim iso3 sex year age shock_extra
gen id="_"+"$nn"+"_"+string(secsim)
levelsof id, local(ids)
drop secsim
reshape wide shock_extra, i(iso3 sex year age) j(id) str
tostring age, force replace
merge 1:1 iso3 sex year age using "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/sims/envelope_sim_$nn.dta"
drop if _merge==1
drop _merge
foreach ff of local ids {
    replace shock_extra`ff'=0 if shock_extra`ff'==.
    gen envelope_shock`ff'=(shock_extra`ff'+1)*envelope_withhiv`ff'
}
tempfile shockenve
save `shockenve'


** merge in the under-5 shock envelopes
** local uu=$nn+1
local uu=$nn
use "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/sims/shock_u5_deaths_sim_`uu'.dta",clear
keep iso3 sex year age deaths
rename deaths u5deaths_$nn
tempfile shock5
preserve
replace age="1" if age=="2"
replace age="1" if age=="3"
replace age="1" if age=="4"
collapse (sum)  u5deaths_$nn, by(iso3 sex year age)
save `shock5'
restore
keep if age=="enn"|age=="lnn"|age=="pnn"
collapse (sum) u5deaths_$nn, by(iso3 sex year)
gen age="0"
append using `shock5'
** forvalues j=1/10 {
   ** gen  u5deaths_`j'= u5deaths_$nn 
** }
** drop  u5deaths_$nn
** HW 4-1-2012
rename u5deaths_$nn u5deaths
forvalues j=1/10 {
   gen  u5deaths_`j'= u5deaths
}
drop u5deaths


renpfix u5deaths u5deaths_$nn
merge 1:1 iso3 sex year age using `shockenve',nogen
foreach ff of local ids {
    replace envelope_shock`ff'=u5deaths`ff' if age=="0"|age=="1"|age=="enn"|age=="lnn"|age=="pnn"
}
drop u5deaths*
compress
** save "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/sims/envelope_sim_$nn.dta",replace
tempfile single
save `single'

*** aggregation ***
use "$dirs/DATA/IHME_COUNTRY_CODES/IHME_COUNTRY_CODES_Y2013M07D26.DTA",clear
drop if gbd_country_iso3=="ZAF" &  iso3!="ZAF"
keep if indic_cod==1
keep if type=="admin0"
keep gbd_non_developing gbd_region_name gbd_superregion_name iso3
tempfile codess
save `codess'


use "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/pop_100.dta",clear
replace age=80 if age>=80
collapse (sum) pop, by(iso3 sex year age)
tempfile pops
save `pops'

use "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/data/pop_80.dta",clear
replace pop=pop*1000
append using `pops'
keep if year>=1970
drop if age<5
reshape wide pop, i(iso3 sex year) j(age)
save `pops',replace

use "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/under5_pop_updated_data_iteration_final.dta",clear
replace age="1" if age=="2"
replace age="1" if age=="3"
replace age="1" if age=="4"
collapse (sum) pys, by(iso3 sex year age)
gen pop=pys
drop pys
reshape wide pop, i(iso3 sex year) j(age) str
merge 1:1 iso3 sex year using `pops'
keep if year>=1970 & year<=2013
keep if _merge==3
drop _merge
gen pop0= popenn+ poplnn+ poppnn
reshape long pop, i(iso3 sex year) j(age) str
merge m:1 iso3 using `codess'
gen type="national" if _merge==3
replace type="subnational" if _merge==1
drop _merge
save `pops',replace

use `single',clear
merge 1:1 iso3 sex year age using `pops'
keep if _merge==3
drop _merge
tempfile large
save `large'

*** get both sexes combined
collapse (sum) envelope_* shock* deaths* pop, by(gbd_non_developing gbd_region gbd_superregion_name type iso3 year age) fast 
gen sex="both"
append using `large'
save `large',replace

preserve
keep if age=="0" | age=="1"
collapse (sum) envelope_* shock* deaths* pop, by(gbd_non_developing gbd_region gbd_superregion_name type iso3 sex year) fast
gen age="under-5"
append using `large'
save `large',replace
restore

drop if age=="enn" | age=="lnn" |age=="pnn"
collapse (sum) envelope_* shock* deaths* pop, by(gbd_non_developing gbd_region gbd_superregion_name type iso3 sex year) fast
gen age="ALL"
append using `large'
save `large',replace

tempfile aggs
gen aggregate="national" if type=="national"
replace agg="subnational" if type=="subnational"
save `aggs',replace

keep if agg=="national"

preserve
collapse (sum) envelope_* shock* deaths* pop, by(gbd_non_developing sex year age) fast
gen aggregate="developing"
append using `aggs'
save `aggs',replace
restore

preserve
collapse (sum) envelope_* shock* deaths* pop, by(gbd_region sex year age) fast
gen aggregate="GBD region"
append using `aggs'
save `aggs',replace
restore

preserve
collapse (sum) envelope_* shock* deaths* pop, by(gbd_super sex year age) fast
gen aggregate="GBD super region"
append using `aggs'
save `aggs',replace
restore


collapse (sum) envelope_* shock* deaths* pop, by(year sex age) fast
gen aggregate="global"
append using `aggs'

** save "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/sims/envelope_sim_$nn.dta",replace

*** RAKING at the subnational level ***
*** Feb 21st 2014 ***
tempfile rake
save `rake'

use "$dirs/DATA/IHME_COUNTRY_CODES/IHME_COUNTRY_CODES_Y2013M07D26.DTA",clear
keep if gbd_country_iso3!="" | iso3=="CHN" | iso3=="MEX" | iso3=="GBR" | iso3=="IND"
keep iso3 gbd_country_iso3
drop if gbd_country_iso3=="ZAF"
drop if iso3=="HKG" | iso3=="MAC"
merge 1:m iso3 using `rake'
tempfile torake

keep if _merge==3
keep iso3 sex year age gbd_country_iso3 envelope_withhiv* envelope_shock* shock_extra* deaths_HIV* pop
save `torake'

tempfile raked
local ccs="CHN IND GBR MEX"
qui foreach c of local ccs {
    use `torake',clear
    levelsof iso3, local(iis)
    keep if gbd_country_iso3=="`c'" | iso3=="`c'"
    replace gbd_country_iso3="`c'" if iso3=="`c'"
    reshape long envelope_withhiv envelope_shock shock_extra deaths_HIV, i(sex year age iso3) j(sim) str
    reshape wide envelope_withhiv envelope_shock shock_extra deaths_HIV pop, i(sim sex year age) j(iso3) str
        ** rename envelope_withhiv`c' totals

        ** local vars = "envelope_withhiv envelope_shock shock_extra deaths_HIV pop"
       *** not rakign pop 5/13/2014
        local vars = "envelope_withhiv envelope_shock shock_extra deaths_HIV"
        foreach v of local vars {
            rename  `v'`c' totals`v'
            egen subsum`v'=rowtotal(`v'*)
            foreach i of local iis {
                cap replace `v'`i'=`v'`i'/(subsum`v'/totals`v')
            }
        drop subsum*
        rename totals`v' `v'`c'
            
        }

        reshape long envelope_withhiv envelope_shock shock_extra deaths_HIV pop, i(sim sex year age) j(iso3) str        
        reshape wide envelope_withhiv envelope_shock shock_extra deaths_HIV, i(sex year age iso3) j(sim) str
        cap append using `raked'
        save `raked',replace
    }
  
use `rake',clear
merge m:1 iso3 sex year age using `raked', update replace
drop _merge

save "$dirs/Project/Mortality/GBD Envelopes/04. Lifetables/02. MORTMatch/cluster/results/sims/envelope_sim_$nn.dta",replace

exit,clear


