// After running dismod, need to convert conditional probs into rates - and make graphs to make sure everything looks ok


clear all
set more off
if (c(os)=="Unix") {
	global root "/home/j"
}

if (c(os)=="Windows") {
	global root "J:"
}


// do you want to graph?

local compile_data=1

local graph_conditional=1
local graph_conditional_data=1
local graph_mortality_rates=1
local graph_cumulative=1
local graph_survival = 1

local color_none "102 194 165"
local color_high "252 141 98"
local color_ssa "141 160 203"
local color_other "231 138 195"
local color_ssabest "229 196 148"

local color1 "215 48 39"
local color2 "244 109 67"
local color3 "253 174 97"
local color4 "254 224 144"
local color5 "171 217 233"
local color6 "116 173 209"
local color7 "69 117 180"

local dismod_dir "strPath"
local bradmod_dir "strPath"
local graph_dir "strPath"


// Initialize pdfmaker
if 0==0 {
	if c(os) == "Windows" {
		global prefix "$root"
		do "$prefix/Usable/Tools/ADO/pdfmaker_Acrobat11.do"
	}
	if c(os) == "Unix" {
		global prefix "/home/j"
		do "$prefix/Usable/Tools/ADO/pdfmaker.do"
		set odbcmgr unixodbc
	}
}


if `compile_data' {

********* SAVE RAW DATA INPUTS AND FORMAT FOR GRAPHING ************

	// ALL SITES
	foreach sup in ssa high other {
		foreach per in 0_6 7_12 12_24 {
			
			insheet using "`dismod_dir'/HIV_KM_`sup'_`per'//data_in.csv", comma names clear
			keep if super=="none" | super=="`sup'"
			keep if pubmed_id!=.
			replace super="`sup'"
			
			// graphing x-axis
			gen cd4_lower=age_lower*10
			gen cd4_upper=age_upper*10
			egen cd4_point=rowmean(cd4_lower cd4_upper)

			// this allows it to merge with other data	
			gen dur="`per'"
			gen type="raw"
			rename meas_value mean_cond_prob
			destring mean_cond_prob, replace
			
			tempfile raw_`sup'_`per'
			save `raw_`sup'_`per'', replace	
		}
	}
	
	use `raw_ssa_0_6'
	append using `raw_ssa_7_12' `raw_ssa_12_24' `raw_other_0_6' `raw_other_7_12' `raw_other_12_24' `raw_high_0_6' `raw_high_7_12' `raw_high_12_24' 
	sort super
	order type super dur cd4_lower cd4_upper cd4_point pubmed_id
	sort type super dur 
	
	tempfile raw_data
	save `raw_data', replace
	
********* COMPILE PROBABILITY RESULTS *****

 
	******** BRING IN EACH OF THE OUTPUTS
	// keep last 1000
	// Merge together results (on draw# and period (duration))
	
	foreach sup in ssa other high {
	
		foreach per in 0_6 7_12 12_24 {
			
			insheet using "`dismod_dir'/HIV_KM_`sup'_`per'/model_draw2.csv", comma names clear 			
			drop if _n<=4000
			
			keep `sup'*
			gen draw=_n
			gen dur="`per'"
			
			tempfile t`sup'_`per'
			save `t`sup'_`per'', replace
		
		}
		
		use `t`sup'_0_6', clear
		append using `t`sup'_7_12' `t`sup'_12_24'
		tempfile alldur_`sup'
		save `alldur_`sup'', replace
	
	}
	
	use `alldur_ssa', clear
	merge 1:1 dur draw using `alldur_other', nogen
	merge 1:1 dur draw using `alldur_high', nogen
	

	foreach var of varlist _all {
			rename `var' prob`var'
		}
		rename probdur dur
		rename probdraw draw

		
	reshape long prob, i(draw dur) j(super_cd4) string
	reshape wide prob, i(super_cd4 dur) j(draw)
	
	// cd4 and super region
		split super_cd4, parse(_)
		rename super_cd41 super
		rename super_cd42 cd4_lower
		destring cd4_lower, replace
		drop super_cd4

		gen cd4_upper=50 if cd4_lower==0
		replace cd4_upper=100 if cd4_lower==50
		replace cd4_upper=200 if cd4_lower==100
		replace cd4_upper=250 if cd4_lower==200
		replace cd4_upper=350 if cd4_lower==250
		replace cd4_upper=500 if cd4_lower==350
		replace cd4_upper=1000 if cd4_lower==500
		
	// graphing x-axis
		egen cd4_point=rowmean(cd4_upper cd4_lower)
		
	// generate mean, high and low probability estimates
		egen mean_cond_prob=rowmean(prob*)
		egen low_cond_prob=rowpctile(prob*), p(2.5)
		egen high_cond_prob=rowpctile(prob*), p(97.5)
	
		order super dur cd4_lower cd4_upper cd4_point mean_cond_prob low_cond_prob high_cond_prob
		sort super dur cd4_lower cd4_upper cd4_point mean_cond_prob low_cond_prob high_cond_prob
		
		save "`bradmod_dir'/mortality_conditional_prob_output.dta", replace
		
		tempfile full_conditional_output
		save `full_conditional_output', replace
		
	******** CONVERT TO MORTALITY RATES ********

	use `full_conditional_output', clear
	
	
	forvalues i=1/1000 {
		gen rate`i'=.
		replace rate`i'=-(ln(1-prob`i'))/.5 if dur=="0_6"
		replace rate`i'=-(ln(1-prob`i'))/.5 if dur=="7_12"
		replace rate`i'=-(ln(1-prob`i'))/1 if dur=="12_24"
	}

	egen mean_rate=rowmean(prob*)
	egen low_rate=rowpctile(prob*), p(5)
	egen high_rate=rowpctile(prob*), p(95)
	
	order mean_rate
	
	tempfile mortality_rate_output
	save `mortality_rate_output', replace
	
	drop prob* *prob* mean* low* high*
	
	save "`bradmod_dir'/mortality_rate_output.dta", replace
}

