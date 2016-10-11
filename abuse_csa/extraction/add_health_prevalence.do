// DATE: September 17, 2015
// PURPOSE: CLEAN AND EXTRACT CSA DATA FROM NAT'L LONGITUDINAL STUDY OF ADOLESCENT HEALTH AND COMPUTE PREVALENCE IN 5 YEAR AGE-SEX GROUPS FOR EACH YEAR 


// Set up
	clear all
	set more off
	set mem 2g
	capture restore not
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j "J:"
	}

// Create locals for relevant files and folders
	local data_dir "$j/DATA/USA/LONGITUD_STUDY_ADOLESCENT_HEALTH_ADD_HEALTH/2007_2009"
	local prepped_dir "$j/WORK/05_risk/risks/abuse_csa/data/exp/01_tabulate/prepped"


** *********************************************************************
** 1.) Clean and create CSA indicator 
** *********************************************************************

	// Bring in main dataset for Wave 4 (2007-2009) 
	use "`data_dir'/USA_ADD_HEALTH_2007_2009_PU_DS23_Y2013M10D02.DTA", clear 
	renvars *, lower 
	gen age = iyear4 - h4od1y
	rename bio_sex4 sex

	recode h4ma5 (2 = 1) (3 = 1) (4 = 1) (5 = 1) (6 = 0) (96 = .) (98 = .)
	rename h4ma5 abuse_ipv

	keep aid age sex abuse_ipv 
	tempfile data 
	save `data', replace 

	// Bring in survey design information, which is stored in a separate dta 
	use "`data_dir'/USA_ADD_HEALTH_2007_2009_PU_DS29_GRAND_SAMP_WTS_Y2013M10D02.DTA", clear 
	renvars *, lower

	// Merge the two together
	merge 1:1 aid using `data', keep(3) nogen


** ****************************************************************************************
** 2.) Calculate prevalence in each year/age/sex subgroup and save compiled/prepped dataset
** ****************************************************************************************

// Create empty matrix for storing calculated results for each year, sex, age group
	mata
		age = J(1,1,-999)
		sex = J(1,1,-999)
		sample_size = J(1,1,-999)
		mean = J(1,1,-999.999)
		standard_error = J(1,1,-999.999)
		lower = J(1,1,-999.999)
		upper = J(1,1,-999.999)
	end

// Set age groups
	egen age_start = cut(age), at(15(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	levelsof age_start, local(ages)
	drop age
	

// Specify survey design
	// note that a strata variable is not available and that the authors of the study found that "using a strata varaible only minimally affects the standard errors"
	// want to use cross-sectional weight 
	svyset cluster2 [pweight=gswgt4_2]

	foreach sex in 1 2 {	
			foreach age of local ages {
				
				svy linearized, subpop(if age_start == `age' & sex == `sex'): mean abuse_ipv
				di in red "Age: `age' Sex: `sex'"
				qui: count if age_start == `age' & sex == `sex'

				if r(N) != 0 {
					preserve
					keep if age_start == `age' & sex == `sex'	
					mata: age = age \ `age'
					mata: sex = sex \ `sex'
					
					mata: sample_size = sample_size \ `e(N_sub)'
			
					matrix mean_matrix = e(b)
					local mean_scalar = mean_matrix[1,1]
					mata: mean = mean \ `mean_scalar'
					
					matrix variance_matrix = e(V)
					local se_scalar = sqrt(variance_matrix[1,1])
					mata: standard_error = standard_error \ `se_scalar'
					
					local degrees_freedom = `e(df_r)'
					local lower = invlogit(logit(`mean_scalar') - (invttail(`degrees_freedom', .025)*`se_scalar')/(`mean_scalar'*(1-`mean_scalar')))
					mata: lower = lower \ `lower'
					local upper = invlogit(logit(`mean_scalar') + (invttail(`degrees_freedom', .025) * `se_scalar') / (`mean_scalar' * (1 - `mean_scalar')))
					mata: upper = upper \ `upper'
					restore
				}
			}
		}
	

// Get stored prevalence calculations from matrix
	clear

	getmata age sex sample_size mean standard_error upper lower
	drop if _n == 1 // Drop empty top row of matrix
	replace standard_error = (3.6/sample_size)/(2*1.96) if standard_error == 0 // Greg's standard error fix for binomial outcomes


// Create variables that are always tracked
	gen iso3 = "USA"
	gen healthstate = "abuse_csa"
	gen survey_name = "National Longitudinal Study of Adolescent Health"
	gen year_start = 2007
	gen year_end = 2009
	rename age age_start
	gen age_end = age_start
	gen data_type = "Survey: unspecified"
	gen source_type = 2
	label define source_type 2 "Survey"
	label values source_type source_type
	gen orig_uncertainty_type = "SE" 
	gen national_type = 1 // Nationally representative
	gen urbanicity_type = "representative" // Representative
	gen units = 1
	gen nid = 120195


// Specify Epi covariates
		gen contact = 1 // study asked about contact CSA, as opposed to noncontact as well
		gen noncontact = 0
		gen intercourse = 0 
		gen child_16_17 = 0
		gen child_18 = 1
		gen child_18plus = 0
		gen child_over_15 = 1
		gen child_under_15 = 0
		gen nointrain = 0
		gen perp3 = 0
		gen notviostudy1 = 1
		gen parental_report = 0
		gen school = 0
		gen anym_quest = 0

// Organize
		order iso3 year_start year_end sex age_start age_end sample_size mean lower upper standard_error, first
		sort sex age_start age_end  year_start

// Save 

save "`prepped_dir'/add_health_prepped.dta", replace












