// Date: 			10 March 2015
// Project:		RISK
// Purpose:		Estimate the proportion of victims of lifetime physical or sexual intimate partner violence that have experienced physical or sexual violence in the past 12 months, by age. To do so, we will use individual level data from WHO Multi-country study on women's health and domestic violence that was sent for GBD 2010, and is used to crosswalk various case definitions to gold standard. 

** **************************************************************************
** RUNTIME CONFIGURATION
** **************************************************************************
// Set preferences for STATA
		clear all
		set more off
		set scheme s1color
		cap restore, not
	
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}

// Set seed for random draws
	set seed 55596137

// Bring in individual level IPV dataset
	use "$prefix/WORK/05_risk/02_models/abuse_ipv/01_exp/01_tabulate/data/raw/VAW extract GBD 120504.dta", clear

//  Restrict dataset to individuals that have experienced physical or sexual violence in their lifetime & whom age is not missing
	keep if agegrp_gbd != . & sexphys == 1
	decode agegrp_gbd, gen(age)
	
// Generate draws of the proportion of IPV that is current for each age group
	levelsof age, local(ages)
	local count = 0
	foreach age of local ages {
		preserve
		** Count cases in relevant age group
		count if sexphcur == 1 & age == "`age'"
		local cases = `r(N)'
		
		** Count noncases in relevant age group
		count if sexphcur == 0 & age == "`age'"
		local noncases = `r(N)'
		
		** Generate draws of proportion using beta distribution
		clear
		set obs 1
		gen age = "`age'"
		forvalues d = 0/999 {
			gen fraction_`d' = rbeta(`cases', `noncases')
		}
		
		local count = `count' + 1
		tempfile age`count'
		save `age`count'', replace
		restore
	}

// Append tempfiles for each age
	clear
	local n: word count `ages'
	forvalues age = 1/`n' {
		append using `age`age''
	}

// Make 5 year GBD age groups
	split age, parse("-") gen(age)
	destring age1 age2, replace
	gen agedif = age2 - age1 
	expand 2 if agedif == 9, gen(dup)
	rename age1 age_start
	rename age2 age_end
	replace age_start = age_start + 5 if dup == 1
	replace age_end = age_start + 4
	drop agedif age dup
	sort age_start age_end
	order age_start age_end
	
save "$prefix/WORK/05_risk/02_models/abuse_ipv/01_exp/04_model/data/proportion_current.dta", replace
