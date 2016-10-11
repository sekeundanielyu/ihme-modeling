*Calculate AIR and asbestos PAF correctly

clear all
set more off

** Set directories
	if c(os) == "Windows" {
		global j "J:"
		global prefix "J:"
	}
	if c(os) == "Unix" {
		global j "/home/j"
		global prefix "/home/j"
		set odbcmgr unixodbc
	}

local location_id "`1'"
local sexes "1 2"
local years "1990 1995 2000 2005 2010 2015"
local categories "low high"

*Get mesothelioma deaths from COD 
adopath + "$prefix/WORK/10_gbd/00_library/functions"
get_draws, gbd_id_field(cause_id) gbd_id(483) location_ids("`location_id'") source(dalynator) measure_ids(1) clear

*Keep only death rates for sex-specific estimates and for population above 15
keep if metric_id == 1 & measure_id==1 & sex_id != 3 & age_group_id>=8 & age_group_id<=21

tempfile meso_deaths
save `meso_deaths'

*Get population estimates to determine death rate (deaths/population * 100000)
import delimited "$prefix/WORK/05_risk/risks/occ/raw/exposures/template.csv", clear
keep if location_id == `location_id'

merge m:1 year_id sex_id age_group_id using `meso_deaths', nogen keep(3)

forvalues i = 0/999{
	replace draw_`i' = (draw_`i'/pop_scaled)*100000
}

save `meso_deaths', replace

*Calculate air draws
import delimited "/share/scratch/users/strUser/air_inputs.csv", clear
merge 1:m sex_id age_group_id using `meso_deaths', nogen keep(3)

forvalues i = 0/999 {
	gen exp_`i' = ((draw_`i' - n_`i')/(s_`i' - nstar_`i'))
	drop draw_`i' n_`i' s_`i' nstar_`i'

	*Cap at 0 if negative
	rename exp_`i' draw_`i'
	replace draw_`i' = 0 if draw_`i' < 0
}

*Calculate high, low based on development status
expand 2, gen(dup)
gen parameter = "cat1" if dup == 0
replace parameter = "cat2" if dup == 1
drop dup 

forvalues draw = 0/999{
				
	** High and low exposure draws (cat1=High, cat2=Low)
		*If developed, smaller fraction is in high exposure group
	replace draw_`draw' = 0.1 * draw_`draw' if parameter=="cat1" & developed == 1
	replace draw_`draw' = 0.9 * draw_`draw' if parameter=="cat2" & developed == 1

	replace draw_`draw' = 0.5 * draw_`draw' if parameter=="cat1" & developed == 0
	replace draw_`draw' = 0.5 * draw_`draw' if parameter=="cat2" & developed == 0
}

*Export by year, sex, category
foreach year in `years'{
	foreach sex in `sexes'{
		foreach category in `categories'{
			preserve

			*Export by category, keeping only the right type
			if "`category'" == "low"{
				keep if parameter=="cat2"
			}
			else{
				keep if parameter=="cat1"
			}

			keep if sex_id==`sex' & year_id==`year'

			export delimited using "/share/scratch/users/strUser/occ_carcino/occ_carcino_asbestos/`category'/18_`location_id'_`year'_`sex'.csv", replace
			restore
		}
	} 
}
