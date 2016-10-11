clear all
set more off

** Set directories
	if c(os) == "Windows" {
		global j "J:"
	}
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}

**File Locations
local rawdata	"C:/Users//Work/Data"
*"J:/WORK/05_risk/risks/occ/occ_overall/2013/01_exp/02_nonlit/02_inputs/05_other" 
local outdata	"J:/WORK/05_risk/risks/occ/raw/occ_inj"

**Producing the Square
quietly adopath + J:/WORK/10_gbd/00_library/functions

*Get all years, age groups, and sexes
quietly get_demographics, gbd_team("cov") make_template clear
keep location_id year_id age_group_id sex_id
tempfile square
save `square', replace

*Get all locations
quietly include "J:/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
get_location_metadata, location_set_id(9) clear

	*Only want National and subnational
keep if level >= 3
keep location_id ihme_loc_id
merge 1:m location_id using `square'
	
	*Drop pesky location GBR_4749
drop if _merge == 1			
drop _merge
drop age_group_id

sort ihme_loc_id year_id sex_id
duplicates drop location_id year_id sex_id, force

save `square', replace

*Bring in injury dataset
import delimited "`rawdata'/occ_inj_inputs.csv"
