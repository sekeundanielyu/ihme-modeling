//Filename: sanitation_rr_prep.do
//July 1, 2014
//Purpose: Prepare and save draws and mean estimates for WSH Relative Risks 

//Script to run things on the cluster
//do  "/home/j/WORK/01_covariates/02_inputs/water_sanitation/code/03_final_prep/sanitation_new_rr_prep_code.do"

clear
set more off
set maxvar 30000

// Set directories
	if c(os) == "Windows" {
		global j "J:"
		set mem 1g
	}
	if c(os) == "Unix" {
		global j "/home/j"
		set mem 8g
	} 
	
//set relevant locals
	local out_dir_draws		"/clustertmp/WORK/05_risk/02_models/02_results"
	local out_dir_means		"$j/WORK/05_risk/02_models/02_results"
	local rf_new			"wash_sanitation"
	local output_version	4
	
//Prep RRs
	do "$j/WORK/01_covariates/02_inputs/water_sanitation/code/03_final_prep/gen_new_rr.do"
	
** Create RR template
	** Make up a few causes
	clear
	set obs 6
	
	** Risk
	gen risk = "`rf_new'"
	gen gbd_age_start = 0
	gen gbd_age_end = 80
	gen sex = 3
	gen year = 0 
	gen mortality = 1 
	gen morbidity = 1 
	
	**gen parameter
	gen id = _n
	tostring(id), replace
	gen parameter = "cat" + id
	drop id 
	
	**gen causes
	gen acause = "diarrhea"
	/*expand 2, gen(copy)
	gen acause = "diarrhea" if copy==0
	replace acause = "intest_paratyph" if copy==1 
	
	drop copy
	expand 2 if acause=="diarrhea", gen(copy)
	replace acause = "intest_typhoid" if copy == 1
	drop copy*/

	//Sanitation Categories - order is based on levels of risk
	**sewer +  handwashing = cat 6
	**sewer - handwashing = cat5
	**improved (other than sewer) + handwashing = cat4
	**unimproved + handwashing = cat3	
	**improved (other than sewer) - handwashing = cat2
	**unimproved - handwashing = cat1
	
	forvalues n = 1/6 {
	
	if `n'==1 {
	
		gen rr_mean =  $cat1_mean
		gen rr_lower = $cat1_lower
		gen rr_upper = $cat1_upper
		
		}
	
	else {
		
		replace rr_mean = $cat2_mean if parameter == "cat2"
		replace rr_lower = $cat2_lower if parameter == "cat2"
		replace rr_upper = $cat2_upper if parameter == "cat2"
		
		replace rr_mean = $cat3_mean if parameter == "cat3"
		replace rr_lower = $cat3_lower if parameter == "cat3"
		replace rr_upper = $cat3_upper if parameter == "cat3"
		
		replace rr_mean = $cat4_mean if parameter == "cat4"
		replace rr_lower = $cat4_lower if parameter == "cat4"
		replace rr_upper = $cat4_upper if parameter == "cat4"
		
		replace rr_mean = $cat5_mean if parameter == "cat5"
		replace rr_lower = $cat5_lower if parameter == "cat5"
		replace rr_upper = $cat5_upper if parameter == "cat5"
		
		replace rr_mean = $cat6_mean if parameter == "cat6"
		replace rr_lower = $cat6_lower if parameter == "cat6"
		replace rr_upper = $cat6_upper if parameter == "cat6"
		
		}
	}

	** Generate 1000 draws using the uncertainty interval for all RRs
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