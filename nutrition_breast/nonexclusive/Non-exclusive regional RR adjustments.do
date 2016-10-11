**to call on do file from the cluster
**do "/home/j/WORK/01_covariates/02_inputs/breastfeeding/03_final_prep/code/bf_nonexslusive_rr_code.do"
 
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
	set seed 26144934 
	
	** Load data
	clear
	set obs 3
	
	gen risk = "`risk'"
	gen acause = "diarrhea"
	gen sex = 3
	gen year = 0
	gen parameter = "cat1" in 1
	replace parameter = "cat2" in 2
	replace parameter = "cat3" in 3
	
	expand 2, gen(copy)
	
	**exclusive breastfeeding - TMRED 
	expand 2 if _n==6
	replace parameter = "cat4" in 7 
	replace copy =. in 7
	
	gen rr_mean = 1 in 7
	gen rr_lower = 1 in 7
	gen rr_upper = 1 in 7
	
	gen gbd_age_start = 0.01 in 7
	gen gbd_age_end = 0.1 in 7
	
	gen morbidity = 1 in 7
	gen mortality = 1 in 7
	
	**fill in appropriate age groups
	replace gbd_age_start = 0.01 if copy!=.
	replace gbd_age_end = 0.01 if copy!=.
	
	replace morbidity = 1 if copy == 0
	replace mortality = 1 if copy == 1
	replace morbidity = 0 if morbidity == . 
	replace mortality = 0 if mortality == . 
	
	**Assume no risk of diarrhea in developed regions
	if ("`region'"=="R1" | "`region'"=="R10" | "`region'"=="R16" | "`region'"=="R6" | "`region'"=="R8"  | "`region'"=="R9") {
		replace rr_mean = 1 
		replace rr_lower = 1
		replace rr_upper = 1
		}
	
	else {
	
	**no breastfeeding
	**morbidity**
	replace rr_mean = 2.65 in 1
	replace rr_lower = 1.72 in 1
	replace rr_upper = 4.07 in 1
	
	**mortality**
	replace rr_mean = 10.52 in 4
	replace rr_lower = 2.79 in 4
	replace rr_upper = 39.60 in 4
	
	**partial breastfeeding
	**morbidity**
	replace rr_mean = 1.68 in 2
	replace rr_lower = 1.03 in 2
	replace rr_upper = 2.76 in 2
	
	**mortality**
	replace rr_mean = 4.62 in 5
	replace rr_lower = 1.81 in 5
	replace rr_upper = 11.76 in 5
	
	**predominant breastfeeding
	**morbidity**
	replace rr_mean = 1.26 in 3
	replace rr_lower = 0.81 in 3
	replace rr_upper = 1.95 in 3
	
	**mortality**
	replace rr_mean = 2.28 in 6
	replace rr_lower = 0.85 in 6
	replace rr_upper = 6.13 in 6
	}

	**regenerate relative risks for another age group
	drop copy
	expand 2 if _n<=6, gen(copy)
	
	replace gbd_age_start = 0.1 if copy == 1
	replace gbd_age_end = 0.1 if copy == 1 
	drop copy
	
	tempfile diarrhea_rr
	save `diarrhea_rr', replace 
	
	**respiratory diseases - lri/otitis/uri
	clear 
	set obs 3
	
	gen risk = "`risk'"
	gen acause = "lri"
	gen sex = 3
	gen year = 0
	gen parameter = "cat1" in 1
	replace parameter = "cat2" in 2
	replace parameter = "cat3" in 3
	
	expand 2, gen(copy)
	
	**exclusive breastfeeding - TMRED 
	expand 2 if _n==6
	replace parameter = "cat4" in 7 
	replace copy =. in 7
	
	gen rr_mean = 1 in 7
	gen rr_lower = 1 in 7
	gen rr_upper = 1 in 7
	
	gen gbd_age_start = 0.01 in 7
	gen gbd_age_end = 0.1 in 7
	
	gen morbidity = 1 in 7
	gen mortality = 1 in 7
	
	**fill in appropriate age groups
	replace gbd_age_start = 0.01 if copy!=.
	replace gbd_age_end = 0.01 if copy!=.
	
	replace morbidity = 1 if copy == 0
	replace mortality = 1 if copy == 1
	replace morbidity = 0 if morbidity == . 
	replace mortality = 0 if mortality == . 
	
	**no breastfeeding
	**morbidity**
	replace rr_mean = 2.07 in 1
	replace rr_lower = 0.19 in 1
	replace rr_upper = 22.64 in 1
	
	**mortality**
	replace rr_mean = 14.97 in 4
	replace rr_lower = 0.67 in 4
	replace rr_upper = 332.74 in 4
	
	**partial breastfeeding
	**morbidity**
	replace rr_mean = 2.48 in 2
	replace rr_lower = 0.23 in 2
	replace rr_upper = 27.15 in 2
	
	**mortality**
	replace rr_mean = 2.50 in 5
	replace rr_lower = 1.03 in 5
	replace rr_upper = 6.04 in 5
	
	**predominant breastfeeding
	**morbidity**
	replace rr_mean = 1.79 in 3
	replace rr_lower = 1.29 in 3
	replace rr_upper = 2.48 in 3
	
	**mortality**
	replace rr_mean = 1.66 in 6
	replace rr_lower = 0.53 in 6
	replace rr_upper = 5.23 in 6
	
	**regenerate relative risks for another age group
	drop copy
	expand 2 if _n<=6, gen(copy)
	
	replace gbd_age_start = 0.1 if copy == 1
	replace gbd_age_end = 0.1 if copy == 1 
	drop copy
	
	**regenerate relative risks for other diarrheal causes
	expand 2, gen(copy)
	replace acause = "otitis" if copy == 1 
	drop copy
	
	expand 2, gen(copy)
	replace acause = "uri" if copy == 1 
	drop copy
	
	tempfile ari_rr
	save `ari_rr', replace 
	
	**combine both sets of relative risks 
	use `diarrhea_rr'
	append using `ari_rr'
	
** Generate draws (Always generate draws in ln space for RRs)
	gen sd = ((ln(rr_upper)) - (ln(rr_lower))) / (2*invnormal(.975))
	forvalues draw = 0/999 {
		gen rr_`draw' = exp(rnormal(ln(rr_mean), sd))
	}
	drop sd
	

	**UPDATE (7/19/16): Dropping OM and URI as outcomes for nonexclusive breastfeeding
	drop if acause == "otitis" | acause == "uri"

** Save draws and means in separate files
	cap mkdir "`out_dir_draws'/nonexclusive/`risk_version'"
	order risk acause gbd_age_start gbd_age_end sex mortality morbidity parameter year 
	tempfile temp
	save `temp'
	
	*****Save draws on J drive***
	drop *mean *lower *upper
	outsheet using "`out_dir_draws'/nonexclusive/`risk_version'/rr_`region'_draws.csv", comma replace

	gen region = "`region'"

	tempfile `counter'
	save ``counter'', replace
	di `counter'
	local counter = `counter' + 1
	}




use `0', clear
forvalues x = 1/20 {
	append using ``x''
}
	rename region gbd_analytical_region_local

	merge m:1 gbd_analytical_region_local using `region_codes'
		drop _merge

	rename gbd_analytical_region_name gbd_region_name
	rename gbd_analytical_region_id gbd_region_id

save "`bf_data'/nonexclusive_rrs_by_region.dta", replace
	
************************************
**********end of code***************
************************************
	