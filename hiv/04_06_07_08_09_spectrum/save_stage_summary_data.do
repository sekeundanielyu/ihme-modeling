clear
set more off

local dir "`1'"
local iso "`2'"
local stage "`3'"

local in_dir "/strPath/`stage'"
local out_dir "/strPath/`stage'"

cd "`in_dir'"

insheet using "`iso'_ART_data.csv", clear double

egen hiv_pop = rowtotal(pop_*)
replace hiv_pop = max(0, hiv_pop - pop_neg)

collapse (sum) hiv_deaths new_hiv hiv_pop, by(year run_num)
collapse (mean) hiv_deaths = hiv_deaths new_hiv = new_hiv hiv_pop = hiv_pop ///
	(p2) hiv_deaths_lower = hiv_deaths new_hiv_lower = new_hiv hiv_pop_lower = hiv_pop ///
	(p98) hiv_deaths_upper = hiv_deaths new_hiv_upper = new_hiv hiv_pop_upper = hiv_pop, ///
	by(year)

saveold "`out_dir'/`iso'_ART_summary.dta", replace

exit, clear STATA
