// Date: 18 March 2015
// Purpose: Pool incidence rate of HCV and HBV among IV drug users. This is used instead of a relative risk for calculating the PAF of  HCV & HBV due to injecting drug use, as well as the PAF of cirrhosis and liver cancer due to HCV & HBV. 

// Set up
	clear all 
	set more off
	capture restore, not

// Create locals for relevant files & folders
	local data_dir "J:/WORK/05_risk/risks/drug_use/data/rr"
	
foreach virus in c b {
	import excel using "`data_dir'/raw/hcv_hbv_incidence_for_idu_meta_analysis.xlsx", firstrow sheet("h`virus'v_metan_input") clear
	drop if Exclude == 1 | Exclude == .
	destring Cases, replace
	cap: replace PersonYears = round(CalculatedPersonYears,1) if PersonYears == .
	split CI, parse(", ") gen(ci_)
	destring ci_1, replace
	destring ci_2, replace

	
	** Calculate confidence interval for each data point based on poisson distribution around number of cases
	gen rownum = _n
	levelsof rownum, local(rows)
	foreach r of local rows {
		preserve
		keep if rownum == `r'
		ci Cases, poisson
		gen lower = `r(lb)'
		gen upper = `r(ub)'
		tempfile row`r'
		save `row`r'', replace
		restore
	}
	clear
	foreach r of local rows {
		append using `row`r''
	}
	
	** Calculate incidence rate and corresponding CI
	gen incidence = Cases / PersonYears
	gen incidence_lower = lower /  PersonYears
	replace incidence_lower = ci_1 / 100 if ci_1 != . 
	replace incidence_lower = round(incidence_lower, .001)
	gen incidence_upper = upper / PersonYears
	replace incidence_upper = ci_2 / 100 if ci_2 != . 
	replace incidence_upper = round(incidence_upper, .001)
	
	** Save before meta-analysis
	export excel "J:/WORK/05_risk/risks/drug_use/data/rr/raw/hcv_hbv_incidence_for_idu_meta_analysis_cleaned.xlsx", firstrow(variables) sheet("h`virus'v_metan_input") replace

	** Random effects meta-analysis to estimate pooled incidence rate
	metan incidence incidence_lower incidence_upper, random label(namevar == StudyName)
	graph export "`data_dir'/graphs/`virus'_forestplot.png", replace 
	
	** Generate draws of pooled incidence rate
	clear
	set obs 1
	forvalues d = 0/999 {
		gen risk`d' = rnormal(`r(ES)', `r(seES)')
	}
	/*
	** Save for PAF calculations
	gen x = 1 // For merge
	save "`data_dir'/prepped/hepatitis_`virus'_risk_draws.dta", replace	
	*/
}

