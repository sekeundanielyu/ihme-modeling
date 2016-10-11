**Filename: hygiene_rr_prep_code.do
**Purpose: Prep relative risks for handwashing and diarrheal diseases. 
**Calculating and saving burden of handwashing separately. 

**To run this script on the cluster
**do "/home/j/WORK/01_covariates/02_inputs/water_sanitation/code/03_final_prep/hygiene_rr_prep_code.do"

**Set directories
	if c(os) == "Windows" {
		global j "J:"
		set mem 1g
	}
	if c(os) == "Unix" {
		global j "/home/j"
		set mem 8g
	} 

**Housekeeping
clear
set more off
set maxvar 30000
set obs 2

	**Set relevant locals
	local out_dir_draws		"/clustertmp/WORK/05_risk/02_models/02_results"
	local out_dir_means		"$j/WORK/05_risk/02_models/02_results"
	local rf_new			"wash_hygiene"
	local output_version	2
	
	**save RRs from the study (Freeman et al 2014) 
	local rr_handwashing 0.60
	local upper_handwashing 0.68
	local lower_handwashing 0.53

	**Prep data
	gen risk = "`rf_new'"
	gen acause = "diarrhea"
	
	gen gbd_age_start = 0
	gen gbd_age_end = 80 
	
	gen sex = 3
	
	gen mortality = 1
	gen morbidity = 1
	
	gen year = 0
	
	gen id = _n 
	gen parameter = "cat1" if id==1
	replace parameter = "cat2" if id==2 

	gen rr_mean = 1/`rr_handwashing' if id==1 
	gen rr_lower = 1/`upper_handwashing' if id==1
	gen rr_upper = 1/`lower_handwashing' if id==1 
	
	replace rr_mean = 1 if id == 2 
	replace rr_lower = 1 if id == 2 
	replace rr_upper = 1 if id == 2 
	drop id
	
	**add typhoid and paratyphoid
	expand 2, gen(copy)
	replace acause = "intest_paratyph" if copy==1 
	
	drop copy
	expand 2 if acause=="diarrhea", gen(copy)
	replace acause = "intest_typhoid" if copy == 1
	drop copy
	
	** Create two categories and 1000 draws
	gen sd = ((ln(rr_upper)) - (ln(rr_lower))) / (2*invnormal(.975))
	forvalues draw = 0/999 {
		gen rr_`draw' = exp(rnormal(ln(rr_mean), sd))
	}	
	
	***************************************
	** Save mean/lower/upper on the J drive**
	***************************************
	cap mkdir "`out_dir_means'/`rf_new'/rr/`output_version'"
	outsheet risk year gbd_age_start gbd_age_end sex morbidity mortality acause parameter rr_mean rr_lower rr_upper using "`out_dir_means'/`rf_new'/rr/`output_version'/rr_G.csv", comma replace

	***************************
	** Save draws on clustertmp**
	***************************
	cap mkdir "`out_dir_draws'/`rf_new'/rr/`output_version'"
	drop *mean *lower *upper 
	outsheet risk year gbd_age_start gbd_age_end sex morbidity mortality acause parameter rr* using "`out_dir_draws'/`rf_new'/rr/`output_version'/rr_G.csv", comma replace
	
*******************************
**********end of code***********
*******************************