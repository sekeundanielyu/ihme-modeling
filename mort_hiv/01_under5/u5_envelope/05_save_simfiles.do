

clear all
set more off
cap restore, not
cap log close

di `1'

	if (c(os)=="Unix") {
		** global arg gets passed in from the shell script and is parsed to get the individual arguments below
		global j ""
		global ctmp ""
		local sim = `1'
		qui do "get_locations.ado"
	} 
	if (c(os)=="Windows") { 
		global j ""
		qui do "get_locations.ado"
	}
	
	local start = `sim'*100
	local end = `sim'*100+99
	
	use "allnonshocks.dta", clear
	keep if (sim >= `start' & sim <= `end')
	
	forvalues i = `start'/`end' {
		preserve
		keep if sim == `i'
		reshape long deaths pys, i(ihme_loc_id year sex sim) j(age, string)
		saveold "noshock_u5_deaths_sim_`i'.dta",replace
		restore
	}
