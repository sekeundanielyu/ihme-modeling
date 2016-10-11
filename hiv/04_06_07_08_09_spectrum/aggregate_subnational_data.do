
set more off

local iso = "`1'"
di "`iso'"
local dir = "`2'"
local stage = "`3'"

cd "/strPath/`stage'"

** Save iso_ART_data.csv in stage folder

local f_list: dir . files "`iso'_*_ART_data.csv", respectcase
di `f_list'

local first_file = 1
foreach f in `f_list' {
	if `first_file' {
		insheet using `f', clear
		tempfile tmp_agg
		save `tmp_agg'
		
		local first_file = 0
	}
	else {
		insheet using `f', clear
		append using `tmp_agg'
		save `tmp_agg', replace
	}
}

collapse (sum) hiv_deaths-pop_art, by(run_num year age sex)

sort run_num year sex age

outsheet using "`iso'_ART_data.csv", replace comma

** Save iso_coverage.csv
local f_list: dir . files "`iso'_*_coverage.csv", respectcase
di `f_list'

local first_file = 1
foreach f in `f_list' {
	if `first_file' {
		insheet using `f', clear
		tempfile tmp_agg
		save `tmp_agg'
		
		local first_file = 0
	}
	else {
		insheet using `f', clear
		append using `tmp_agg'
		save `tmp_agg', replace
	}
}

collapse (sum) coverage eligible_pop, by(run_num year age sex type)

sort run_num year sex age type

outsheet using "`iso'_coverage.csv", replace comma

exit, clear STATA
