** Compile STGPR results with regenerated subnationals, which are the DisMod scaled to 

clear all
set more off
cap restore, not


if c(os) == "Unix" {
		global prefix "/home/j"
		local prescale_dir "`1'"
		di "`prescale_dir'"
		local postscale_dir "`2'"
		di "`postscale_dir'"
		local stgpr "`3'"
		di "`stgpr'"
		local stgpr_subs "`4'"
		di "`stgpr_subs'"
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local location_id = 6
		local prescale_dir "J:\WORK\05_risk\risks\drugs_alcohol\data\exp\prescale"
		local postscale_dir "J:\WORK\05_risk\risks\drugs_alcohol\data\exp\postscale"
		local stgpr "J:/WORK/05_risk/risks/drugs_alcohol/data/exp/stgpr/alcohol_lpc.dta"
		local stgpr_subs "J:/WORK/05_risk/risks/drugs_alcohol/data/exp/stgpr/resplit_subnats/alcohol_lpc_postsub.dta"
	}

	** get subnational locations
	insheet using "$prefix/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/locations.csv", clear
	isid location_id
	keep if level > 3
	levelsof location_id, local(subs)
	
	use "`stgpr'", clear
	foreach sub of local subs {
		di "`sub'"
		drop if location_id == `sub'
		append using "`postscale_dir'/split_total_consumption_`sub'.dta"
	}
	isid location_id year_id
	
	save "`stgpr_subs'", replace
	save "$prefix/WORK/05_risk/risks/drugs_alcohol/data/exp/stgpr/resplit_subnats/archive/alcohol_lpc_postsub_$S_DATE.dta", replace
	
	
	
	
	
	
	