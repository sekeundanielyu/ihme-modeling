
clear all
set more off
cap restore, not

if c(os) == "Unix" {
		global prefix "/home/j"
		local postscale_dir "`1'"
		di "`postscale_dir'"
		local temp_dir "`2'"
		di "`temp_dir'"
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local postscale_dir "J:\WORK\05_risk\risks\drugs_alcohol\data\exp\postscale"
		local temp_dir "/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/temp"
	}
	

local fls: dir "`temp_dir'/loc_agefrac" files "alc_age_frac_*.dta"

clear
foreach fil of local fls {
	di "`fil'"
	append using "`temp_dir'/loc_agefrac/`fil'"
}

forvalues i=999 (-1) 0 {
	local j = `i' + 1
	rename draw_`i' draw_`j'
}

levelsof age_group_id, local(ages)
levelsof sex_id, local(sexes)
levelsof year_id, local(years)

foreach age of local ages {
	foreach sex of local sexes {
		foreach year of local years {
			preserve
			di "`age' `sex' `year'"
			keep if age == `age' & sex == `sex' & year == `year'
			outsheet using "`temp_dir'/alc_age_frac_`year'_`age'_`sex'.csv", comma replace
			restore
		}
	}
}

	
	