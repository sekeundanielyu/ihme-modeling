**to call on do file from the cluster
**do "/home/j/WORK/01_covariates/02_inputs/breastfeeding/03_final_prep/code/bf_discontinued_rr_code.do"

** Set directories
	if c(os) == "Windows" {
		global j "J:"
		set mem 1g
	}
	if c(os) == "Unix" {
		global j "/home/j"
		set mem 2g
		set odbcmgr unixodbc
	}


clear all
set more off

//Prep regional codes 
	use "`country_codes'", clear
	keep gbd_analytical_region_local gbd_analytical_region_name gbd_analytical_region_id
	duplicates drop 
	sort gbd_analytical_region_local
	tempfile region_codes
	save `region_codes', replace 
	levelsof(gbd_analytical_region_local), local(regions)

local counter = 0
	
**Generate region-specific relative risks 
foreach region of local regions {

	** Set seed (Use www.random.org to get a seed. There should be one seed per risk usually)
	set seed 39407401
	
	** Load data
	clear
	set obs 3
	
	gen risk = "`risk'"
	gen acause = "diarrhea"
	
	**fill in appropriage age groups
	gen gbd_age_start = 0.1 in 1
	gen gbd_age_end = 0.1  in 1 
	
	replace gbd_age_start = 1 in 2
	replace gbd_age_end = 1 in 2
	
	replace gbd_age_start = 0.1 in 3
	replace gbd_age_end = 1 in 3
	
	**generate other necessary variables
	gen sex = 3				/*both sexes*/
	gen mortality = 1
	gen morbidity = 1
	gen year = 0
	
	gen parameter = "cat1"
	replace parameter = "cat2" in 3
	
	****************************************
	*************Relative Risks****************
	****************************************
	
	if ("`region'"=="R1" | "`region'"=="R10" | "`region'"=="R16" | "`region'"=="R6" | "`region'"=="R8"  | "`region'"=="R9") {
	
		**discontinued breastfeeding
		gen rr_mean = 1 if parameter == "cat1"
		gen rr_lower = 1 if parameter == "cat1"
		gen rr_upper = 1 if parameter == "cat1"
		
		}
	
	else {
	
		**discontinued breastfeeding
		gen rr_mean = 2.18 if parameter == "cat1"
		gen rr_lower = 1.14 if parameter == "cat1"
		gen rr_upper = 4.16 if parameter == "cat1"
		}
	
	**continued breastfeeding
	replace rr_mean = 1 in 3
	replace rr_lower = 1 in 3
	replace rr_upper = 1 in 3

** Generate draws (Always generate draws in ln space for RRs)
	gen sd = ((ln(rr_upper)) - (ln(rr_lower))) / (2*invnormal(.975))
	forvalues draw = 0/999 {
		gen rr_`draw' = exp(rnormal(ln(rr_mean), sd))
	}
	drop sd
	
** Save draws and means in separate files
	order risk acause gbd_age_start gbd_age_end sex mortality morbidity parameter year 
	tempfile temp
	save `temp'

	**save mean and uncertainty intervals on J:
	cap mkdir "`out_dir_draws'/discontinued/`risk_version'"
	drop *mean *lower *upper
	outsheet using "`out_dir_draws'/discontinued/`risk_version'/rr_`region'_draws.csv", comma replace
	
	gen region = "`region'"

	tempfile `counter'
	save ``counter'', replace
	di `counter'
	local counter = `counter' + 1

}
******************************************
***********end of code*********************
******************************************

use `0', clear
forvalues x = 1/20 {
	append using ``x''
}
	rename region gbd_analytical_region_local

	merge m:1 gbd_analytical_region_local using `region_codes'
		drop _merge

	rename gbd_analytical_region_name gbd_region_name
	rename gbd_analytical_region_id gbd_region_id

save "`bf_data'/discontinued_rrs_by_region.dta", replace