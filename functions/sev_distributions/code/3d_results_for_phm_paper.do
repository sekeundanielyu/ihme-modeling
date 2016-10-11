// In preparation for PHM Submission of Paper - have code ready to recreate the tables and graphs in the paper.

clear all
set more off

**********************************************************************************************************************************************************************************************
// Table 1 - Data Descriptive Stats
// Table 1: Number of respondents by age, sex, and dataset to be included in the analysis. Each MEPS and NESARC respondent averaged 1.9 observations. AHS respondents only had one observation.
local surveys nesarc meps ahs
foreach survey of local surveys {
	di "`surveys'"
	di "`survey'"
	if "`survey'" == "meps" {
		local addition = "_chronic_conditions_only"
	}
	else {
		local addition = ""
	}
	use "strDir/2a_`survey'_prepped_to_crosswalk`addition'.dta", clear
	keep if pcs !=. & mcs != .

	if "`survey'" == "ahs" rename agegr age_gr

	if "`survey'" != "ahs" duplicates drop id, force // one observation per person
	gen count = 1
	collapse (sum) count, by(age_gr sex)

	reshape wide count, i(age_gr) j(sex)
	rename count1 `survey'_males
	rename count2 `survey'_females

	if "`survey'" == "ahs" {
		decode age_gr, gen(_a)
		replace _a = substr(_a,1,2)
		drop age_gr
		destring _a, gen(age_gr)
		replace age_gr = 15 if age_gr == 18
		drop _a
	}
	drop if age_gr==.
	tempfile `survey'
	save ``survey'', replace
}

use `meps', clear
merge 1:1 age_gr using `ahs', nogen
merge 1:1 age_gr using `nesarc', nogen

outsheet using "strDir/table_1.csv", comma names replace


**********************************************************************************************************************************************************************************************
// Figure 1 - Mapping Function
// Made using R using the following code:

/*
library(foreign)
library(mgcv)
data <- read.dta("J:/Project/GBD/Systematic Reviews/ANALYSES/MEPS/input/2a_meps_crosswalk_key.dta")
## sort
data <- data[order(data$sf),]
## set model
model <- loess(dw ~ sf, data=data, span=.88, control=loess.control(surface=c("direct")))
## see what your model looks like
#plot(model$x,model$y)
#lines(model$x,model$fitted)
## fit model to prediction
dw_hat <- predict(model,newdata=data.frame(sf=data$predict))
## see what your prediction looks like
jpeg('J:/Project/GBD/Systematic Reviews/ANALYSES/MEPS/output/3d_forpaper/figure_1')
plot(data$predict,dw_hat, xlim = c(40,130),pch=19, col="grey", xlab="SF-12 Composite Score", ylab="Disability Weight")
#lines(model$x,model$fitted, xlim = c(40,130))
points(data$sf,data$dw,col="red")
dev.off()


## outsheet it
#write.dta(data.frame(data,dw_hat),file="J:/Project/GBD/Systematic Reviews/ANALYSES/MEPS/int/1) MEPS Lowess_r_interpolation.dta",convert.factors="string")
*/


**********************************************************************************************************************************************************************************************
// Figure 2 - Validation Graph


// estimates
local est "strDir/3a_meps_dw_draws"

use "`est'//1", clear
forvalues draw = 2/1000 {
	merge 1:1 condition using "`est'//`draw'",nogen
	di in red "`draw'"
}
egen dw_t = rowmean(dw_t*)
keep co dw_t


rename co como

replace dw_t = 0 if dw_t < 0

gen i = 1
reshape wide dw_t, i(i) j(como) string

tempfile mult
save `mult', replace

use "strDir/2b_meps_lowess_r_interpolation.dta", clear
merge 1:1 key using "strDir/2a_meps_prepped_to_crosswalk_chronic_conditions_only.dta", nogen


gen i = 1
merge m:1 i using `mult', nogen

// multiply thorugh
local multiply
foreach como of varlist t* {
	cap confirm variable dw_t`como'
	if !_rc {
	di in red "ya"
	//	replace dw_t`como' = 0 if dw_t`como' == .
		//	replace dw_t`como' = 0 if dw_t`como' < 0
		replace dw_t`como' = (1-dw_t`como'*`como')
		local multiply `multiply' dw_t`como' *
	}
}
local multiply `multiply' 1
gen dw_prediction = 1-(`multiply')

collapse (mean) dw_pred dw_hat, by(age)

rename dw_pred mean_dwpredicted
rename dw_hat  mean_dwobseved

drop if age < 15 // data errors in the survey data

replace mean_dwpred = mean_dwpred+.015	// the 'baseline disability' as predicted by the model

scatter mean_dwo age, msymbol(Oh) mcolor(blue)  || scatter mean_dwp age, msymbol(Th) mcolor(orange) ytitle("dw") xtitle("age group")  title()
graph export "strDir/figure_2.eps", replace

**********************************************************************************************************************************************************************************************
// Figure 4 - Anxiety Histogram

use "strDir/tmental_anxiety.dta", clear

rename DW_diff_data anxiety_dw
qui summ anxiety_dw
local start = `r(min)'
hist anxiety_dw, fraction bcolor(black) width(.025) start(`start') ///
	addplot(pci 0 .0 .2 .0, lwidth(thick) lcolor(green) || ///
			pci 0 .09 .2 .09, lwidth(thick) lcolor(orange) || ///
			pci 0 .34 .2 .34, lwidth(thick) lcolor(red)) legend(off)

graph export "strDir/figure_4.eps", replace
