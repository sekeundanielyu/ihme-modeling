/*
AUTHOR: Ian Bolliger

DATE: 9 Jan 2014

PURPOSE: Expand draws 
*/

capture program drop expand_draws
program define expand_draws
	version 13
	syntax , Age_levels(string) Sex_levels(string) High_income_levels(string)

	foreach var in age sex high_income {
		cap confirm var `var'
		if _rc {
			local mult_factor = wordcount("``var'_levels'")
			expand `mult_factor'
			bysort *: gen tmp = _n
			gen `var' = word("``var'_levels'",tmp)
			destring `var', replace
			drop tmp
		}
	}
	order age sex high_income, first
	
	** make sure you ended up with the right number of observations
	local obs = _N
	local expected = wordcount("`age_levels'")*wordcount("`sex_levels'")*wordcount("`high_income_levels'")
	assert `obs' == `expected'
end
