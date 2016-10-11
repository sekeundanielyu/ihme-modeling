cap restore, not

clear all
set mem 300m
set maxvar 30000
set more off


// rename variables
foreach survey of global surveys {

	insheet using "$SAVE_DIR/3b_`survey'_severity_distributions_current.csv", comma clear

	cap rename yld_cause cause
	/*
	foreach var of varlist  dist_mean dist_lci dist_uci {
		rename `var' `survey'`var'
	}
	*/
	tempfile `survey'
	save ``survey'', replace

}

use `meps', clear
rename (dist_mean dist_lci dist_uci) (mepsdist_mean mepsdist_lci mepsdist_uci)
local list ahs1mo ahs12mo nesarc
foreach survey of local list {
	merge 1:1 cause grouping healthstate severity using ``survey'', nogen
}
drop ahs1mo_dw ahs12mo_dw nesarc_dw
order  cause grouping healthstate severity hhseqid js_seq meps* ahs1* ahs12* nesar*

outsheet using "$SAVE_DIR/3c_distributions_compiled_${date}.csv", comma replace


// compile a mean distribution - use AHS12month only
preserve

local list meps ahs12mo nesarc
foreach survey of local list {
	use  "$SAVE_DIR/3b_`survey'_severity_distributions_1000_draws_current.dta", clear
	cap rename yld_cause cause
	keep cause grouping healthstate severity dist*
	forvalues i = 0/999 {
		rename dist`i' `survey'dist`i'

	}
	tempfile `survey'
	save ``survey'',replace
}
clear
gen cause = ""
gen grouping = ""
gen healthstate = ""
gen severity = .
foreach survey of local list {
	merge 1:1 cause grouping healthstate severity using ``survey'',nogen
}
keep cause grouping healthstate severity meps* ahs* nesarc*

// need to know how many surveys used each variable to get mean
gen surveys = 0
replace surveys = surveys + 1 if  mepsdist1 != .
replace surveys = surveys + 1 if  ahs12modist1 != .
replace surveys = surveys + 1 if  nesarcdist1 != .

// gen mean distribution
forvalues i = 0/999 {
	foreach survey of local list {
		replace `survey'dist`i' = 0 if `survey'dist`i' == .
	}
	gen dist`i' = (mepsdist`i' + nesarcdist`i' + ahs12modist`i')/(surveys)
}

keep cause grouping healthstate severity dist*

egen MEAN_meandist = rowmean(dist*)
egen MEAN_lcidist  = rowpctile(dist*), p(2.5)
egen MEAN_ucidist  = rowpctile(dist*), p(97.5)

order cause grouping healthstate severity MEAN* dist*
save "$SAVE_DIR/3c_mean_severity_distribution_${date}.dta", replace

keep cause grouping healthstate severity MEAN*

tempfile mean
save `mean', replace
restore

merge 1:1 cause grouping healthstate severity using `mean', nogen

order cause grouping healthstate severity hhseqid js_seq MEAN* meps* ahs1* ahs12* nesar*

rename MEAN_meandist MEANdist_mean
// get other half of distirbution for ones with only asymptomatic
bys cause: egen max = max(severity)
replace hhseqid = 999 if max == 0 // just for display reasons, this is already the case
preserve
keep if max == 0
keep cause grouping healthstate
tempfile asyms
save `asyms', replace
insheet using "$gbd_dws", comma clear // get mean weight
egen js_seq_dw = rowmean(draw*)
keep hhseqid js_seq_dw
drop if hhseqid == .
tempfile dws
save `dws', replace
insheet using "$dir/gbd_2013_maps/${causename}.csv", comma clear
merge m:m hhseqid using `dws'
keep cause grouping healthstate severity hhseqid js_seq_dw
merge m:1 cause grouping healthstate using `asyms', keep(3) nogen
gen symmarker = 1
tempfile syms
save `syms', replace
restore
append using `syms'
bys cause grouping healthstate: carryforward max, replace
sort cause grouping healthstate severity
foreach var of varlist MEANdist_mean-nesarcdist_uci {
	bys cause: carryforward `var', replace
	replace `var' = 1-`var' if symmarker== 1
	replace `var' = . if max == 0 & hhseqid == 999 & symmarker== 1
}

// get mean weights - sumproduct mean distributions over DWs
local list meps ahs1mo ahs12mo nesarc MEAN

foreach dist of local list {
	gen `dist'weight = js_seq_dw*`dist'dist_mean
	bys cause: egen `dist'_finalweight = total(`dist'weight )
	drop `dist'weight
	order cause `dist'_finalweight
	replace `dist'_finalweight = . if `dist'_finalweight == 0
}

// bring in sequalae titles
preserve
import excel using "$j/WORK/00_dimensions/00_schema/dimensions.xlsx", first sheet(sequelae) clear
keep acause grouping healthstate sequela_name
rename acause cause
tempfile seqnames
save `seqnames', replace
restore

merge m:1 cause grouping healthstate using `seqnames', keep(3) nogen
order cause grouping healthstate sequela_name severity hhseqid js_seq_dw MEAN_finalweight nesarc_finalweight ahs12mo_finalweight ahs1mo_finalweight meps_finalweight

sort cause grouping severity

outsheet using "$SAVE_DIR/3c_distributions_compiled_${date}.csv", comma replace
outsheet using "$SAVE_DIR/3c_distributions_compiled_current.csv", comma replace
