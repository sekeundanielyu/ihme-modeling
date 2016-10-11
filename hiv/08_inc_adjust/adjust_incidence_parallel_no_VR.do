set more off

sleep 600000

set maxvar 15000

local iso = "`1'"
local inc_dir = "`2'"
local folder_name = "`3'"

local user "`c(username)'"
local code_dir = "/ihme/code/mortality/`user'/hiv"
adopath + "`code_dir'"



string_seed `iso'

insheet using "/strPath/`iso'_ART_data.csv", clear double
qui: su run_num
local n_draws = r(max)
tempfile tmp_ART_data_`iso'
save `tmp_ART_data_`iso'', replace

cd "/strPath/"
insheet using "adj_countries.csv", clear names

qui: levelsof iso3, local(adj_iso_list) clean

cd "`inc_dir'_ratios"

local tmp_file_list: dir . files "*_inc_ratios*", respectcase

local file_list
foreach f_name in `tmp_file_list' {
	local tmp_iso = subinstr("`f_name'", "_inc_ratios.csv", "", .)
	if `: list tmp_iso in adj_iso_list' { 
		local file_list `file_list' `f_name'
	}
}

local n_files: word count `file_list'

di "`file_list'"

forvalues n = 1/`n_draws'{
	di `n'
	forvalues i = 1/1 {
		local rand_num = round(runiform() * (`n_files'-1)) + 1
		local test: word `rand_num' of `file_list'
		
		qui: insheet using "`test'", clear
		
		qui: ds ratio*
		local n_ratios: word count `r(varlist)'
		
		local col = round(uniform() * (`n_ratios'-1)) + 1
		
		keep year ratio`col'
		rename ratio`col' ratio_`i'
		
		tempfile tmp_ratios_`i'
		save "`tmp_ratios_`i''"
	}

	gen run_num = `n'
	tempfile ratios_`n'
	save `ratios_`n''
}

local temp_i = 1
forvalues n = 1/`n_draws' {
	if `temp_i' == 1 {
		use `ratios_`n'', clear
	}
	else {
		append using `ratios_`n''
	}
	local temp_i = `temp_i' + 1
}

tempfile tmp_ratios
save `tmp_ratios'

use `tmp_ART_data_`iso'', clear

keep if age >=  15 & age <= 45

collapse (sum) new_hiv suscept_pop, by(run_num year)

gen inc = new_hiv/suscept_pop

merge 1:1 run_num year using `tmp_ratios'

drop if _merge != 3

capture drop adj_inc_*
forvalues i = 1/1 {
	gen adj_inc_`i' = inc * ratio_`i' * 100
}

keep year run_num adj_inc_*
reshape wide adj_inc_*, i(year) j(run_num)

forvalues j = 1/1 {
	forvalues i = 1/`n_draws' {
		local product = `i' + `n_draws' * (`j' - 1)
	 	di "`j'`i' `product'"
		rename adj_inc_`j'`i' draw`product'
	}
}


outsheet using "/strPath/`iso'_SPU_inc_draws.csv", comma replace

exit, clear STATA
