** **************************************************************************
** RUNTIME CONFIGURATION
** **************************************************************************

// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		macro drop _all
		set mem 700m
		set maxvar 32000
	// Set to run all selected code without pausing
		set more off
	// Set graph output color scheme
		set scheme s1color
	// Remove previous restores
		cap restore, not
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}
// Close previous logs
	cap log close
	
// Create timestamp for logs
	local c_date = c(current_date)
	local c_time = c(current_time)
	local c_time_date = "`c_date'"+"_" +"`c_time'"
	display "`c_time_date'"
	local time_string = subinstr("`c_time_date'", ":", "_", .)
	local timestamp = subinstr("`time_string'", " ", "_", .)
	display "`timestamp'"
	

** ************* ************* ************* ************* ************* ***********
				// PREP NEW SALT DATA
** ************* ************* ************* ************* ************* ***********

// bring in diet dataset and prep
	
	//use salt data
	use "`salt_data'", clear
	
	keep if ihme_data ==0

** ************* ************* ************* ************* ************* ***********
				// CLEAN UP PARAMETERVALUES & STANDARD ERRORS
** ************* ************* ************* ************* ************* ***********

// define a variable that will contain mean. Want dietary sodium values to be energy adjusted, so use the mean_1enadj var from the expert group 
	gen exp_mean = mean_1enadj
	
// clean up all the units so that everything is in the same units (i.e. not g and mg - just g)
	replace exp_mean = exp_mean / 1000 if unit_1 == 2 // unit_1 == 2 indicates units are mg. Turn miligrams into grams
	
// the urinary sodium data should not be energy-adjusted (but the dietary sodium data should be)
	replace exp_mean = mean_1unadj if gbd_cause == "Sodium" & met == 1
	
// where the energy-adjusted data is missing for the dietary data, replace it with the non-energy-adjusted values
	replace exp_mean = mean_1unadj if gbd_cause == "Sodium" & met == 2 & mean_1enadj == .

// where there are weird uncertainty estimates (ie sd_other=3 means IQR), blank them out and impute uncertainty in code below. 
	// blank out values for energy adjusted and non-energy adjsuted SD measures provided by the expert group
	replace sd_1unadj = . if sd_oth == 3
	replace sd_1enadj = . if sd_oth == 3
	
// where sd_oth == 1, this indicates it is a SD. Want to generate SE by dividing by sqrt(samplesize) 
	// prep sample size data
	destring effective_sample_size, replace ignore(",")
	
	// where samplesize is missing, and we only have SD (not SE), replace the missing sample size with the 10th percentile of sample size for that risk factor to allow us to compute SE
	levelsof gbd_cause, local(cause)
	foreach c of local cause {
		di in red "`c'"
		summ effective_sample_size if gbd_cause == "`c'", detail
		local pctile = `r(p10)'
		replace effective_sample_size = `pctile' if gbd_cause == "`c'" & effective_sample_size == . 
	}
	
// Compute SE
	gen se_1unadj = sd_1unadj/(sqrt(effective_sample_size)) if sd_oth == 1 // not energy adjusted
	gen se_1enadj = sd_1enadj/(sqrt(effective_sample_size)) if sd_oth == 1 // energy adjusted
	
// replace se values with values in the SD variables when sd_oth == 2, since this denotes that SE is being reported in the sd column
	replace se_1unadj = sd_1unadj if sd_oth == 2
	replace se_1enadj = sd_1enadj if sd_oth == 2
	
// make units for SE's consistent with those of mean
	// if unit_1 == 2 values reported are in mg/day. Change mg to grams
	replace se_1unadj = se_1unadj / 1000 if unit_1 == 2 
	replace se_1enadj = se_1enadj / 1000 if unit_1 == 2 
	
// We want to impute values for SE and SD when they are reported as 0. It is implausible that SE or SD can take on these values if the sample size is > 1
	// blank out the SE values in these situations to fill in below during imputation
	replace se_1unadj = . if se_1unadj == 0 & effective_sample_size > 1
	replace se_1enadj = . if se_1enadj == 0 & effective_sample_size > 1
	
// Generate coefficient of variation using non-missing SE variables, then use the computed CV to impute for missing SE values
	// replace mean with 1% of the median exp_mean value if exp_mean is 0 so that SE estimates can be imputed for these observations. If exp_mean =0,  the imputed value will go to 0 since we multiply CV by exp_mean to generate the imputed SE's
		// tag which observations had mean reported as 0
		gen mean_zero = 0
		replace mean_zero = 1 if exp_mean == 0
		// calculate the median value of exp_mean 
		summ exp_mean, detail
		local med_mean `r(p50)'
		di `med_mean'
		// replace instances where exp_mean =0 with 0.01 * the median exp_mean value across the dataset
		replace exp_mean = 0.01 * `med_mean' if mean_zero == 1
		
	// Impute for non-energy adjusted data points
		// compute CV
		generate CV = (se_1unadj * sqrt(effective_sample_size)) / exp_mean
		// compute mean CV across data set
		summ CV
		local avg_CV `r(mean)'
		di `avg_CV'
		// impute for missing SE values 
		replace se_1unadj = (`avg_CV'*exp_mean)/sqrt(effective_sample_size) if se_1unadj == .
		drop CV
		
	// Impute for energy-adjusted data points
		// compute CV
		generate CV = (se_1enadj * sqrt(effective_sample_size)) / exp_mean
		// compute mean CV across data set
		summ CV
		local avg_CV `r(mean)'
		di `avg_CV'
		// impute for missing SE values 
		replace se_1enadj = (`avg_CV'*exp_mean)/sqrt(effective_sample_size) if se_1enadj == .	
		drop CV
		
	// switch exp_mean back to 0 for data points that we replaced 
		replace exp_mean = 0 if mean_zero == 1
		drop mean_zero
	
// generate overall standard error estimates
	gen standard_error = se_1enadj
	replace standard_error = se_1unadj if gbd_cause == "Sodium" & met == 1 // use unadjusted values when met == 1 bc these are from urinary excretion, not consumption, and should therefore not be energy adjusted to a 2000 cal diet
	
// generate standard deviation by converting SE's. At this point no SE's should be missing and they should correctly reflect unadjusted or adjusted values depending on whether the data is met 1 (urinary) or met 2 (dietary)
	gen standard_deviation = standard_error * sqrt(effective_sample_size)
	
// drop data points that expert group marked as not to be used
	drop if use != 1

// drop data points for mean and SD from the expert group. We will use the cleaned values generated above	
	drop mean_* sd_*
	
// merge on gbd super regions
	merge m:1 location_id using "`isos'", keepusing(gbd_super_region iso3 parent_id) keep(3) nogen //as of 11/2/15, NIUE Is the only country that doesn't merge in. We don't estimate for it, so drop it

// merge on development status
	merge m:1 iso3 year_start using "`income_status'", keepusing(developed) keep(1 3)
	
	//Assign parent development status to the child
	//note, I might need to add parent id and keep merge==2 in the above merge at some point
	levelsof location_id if developed==., local(child_mis)
	foreach child of local child_mis {
		qui levelsof parent_id if location_id == `child', local(theparent)
		qui levelsof year_start if location_id == `child', local(theyears)
		
		foreach yyy of local theyears {
			count if location_id ==`theparent' & year_start ==`yyy'
			//make sure there is a matching country year
			if `r(N)' == 0 {
				summ developed if location_id ==`theparent'
				local dev_start = round(`r(mean)')
			} 
			else {
				qui levelsof developed if location_id ==`theparent' & year_start ==`yyy', local(dev_stat)
			}
			di "`child' _ `theparent' _ `yyy' _ `dev_stat'"
			replace developed = `dev_stat' if location_id ==`child' & year_start==`yyy'
		}
	
	}
	//check to make sure it worked
	count if developed ==. & _merge==1 
	if `r(N)' >0{
		di "A child did not get its parent development status"
		asdfadsf
	}
	drop _merge
// drop the overall data points (conglomerate)
	drop if age_all == 1

// save	
	tempfile na
	save `na', replace
	
** ************* ************* ************* ************* ************* ***********
				// BREAK OUT OBSERVATIONS FOR SURVEYS THAT HAVE BOTH DIETARY AND URINARY DATA
** ************* ************* ************* ************* ************* ***********

// bring in duplicate dataset with list of duplicate points
	use "`dups'", clear
	keep urine diettwin
	duplicates drop
	rename diettwin id
	
// merge onto diet data and keep exp, sd, development status data for the dietary twin data
	merge 1:1 id using `na', keep(master match) keepusing(exp_mean standard_deviation developed)
	drop _m
	rename exp_mean mean_dietary
	rename standard_deviation sd_dietary
	
// merge onto the diet data again, now just keeping the data for the urinary twin data
	rename id diettwin
	rename urine id
	merge 1:1 id using `na', keep(master match)
	rename exp_mean mean_urinary
	rename standard_deviation sd_urinary
	
// RE ADDED THIS make a variable to indicate if the urinary data has a diet twin
	gen u_hastwin = 1
	gen u_id = id
	
// make an id variable: the old id variable is no longer applicable because it just applies to the urinary data
	drop id
	egen id = group(svy age_start age_end year_start year_end country sex)
	
// clean up dataset
	keep country year_start year_end age* effective sd* mean* id gbd_* u_hastwin u_id diettwin developed level ihme_data
	
// put data into log space
	gen ln_mean_urinary = ln(mean_urinary)
	gen ln_mean_dietary = ln(mean_dietary)

// save
	tempfile preregress
	save `preregress', replace
	
*** * ****************************************************************************
*** 		ADJUST FOR URINARY BY REGION/INCOME
***			we will generate two adjustment factors - one for devleoping region and one for devleoped. Data for SSA was too sparse to use for this region --> combine with SE asia data for devleoping adjustment.
*** * *****************************************************************************

// put each observation (dietary or urinary) into its own row
	reshape long mean_ sd_ ln_mean_, i(id) j(state) string
	drop if id == .
	
// compute ln of sd. ln of sd = ln(1 + sd/mean)
	gen ln_sd = ln(1+ sd_ / mean_)
	
// create an indicator to use in crosswalk. urinary will =1 when an observation is dietary and needs to be adjusted to the optimal level (urinary data). urinary data is optimal and will be tagged as urinary = 0
	gen urinary = 1
	replace urinary = 0 if regexm(state, "urinary")
	
// run regression - by development status with interaction for urinary
	regress ln_mean i.developed#urinary [aw= 1/ln_sd^2] if level==3 &ihme_data==0

// store coefficients in locals for adjustment. Want by development status
	// developing
	local developing_scalar = _b[0b.developed#1.urinary]
	local developing_se = _se[0b.developed#1.urinary]
	
	// developed
	local developed_scalar = _b[1.developed#1.urinary]
	local developed_se = _se[1.developed#1.urinary]
	

*** * *********************************************************************************
*** 				APPLY ADJUSTMENT TO DATA
*** * *********************************************************************************

// We only want to adjust dietary data points. We will drop all urinary data points, as well as dietary data points from surveys that also have a urinary twin. We will then adjust the remaining dietary data points.

// Drop diet duplicates for studies where there are both dietary and urinary observations. We only want the urinary data points in the final data set when we have both types of data from a single survey
	use `preregress', clear
	drop id
	rename u_id id
	merge 1:1 id using `na'

	levelsof diettwin if _merge == 3, local(both_types)

	use `na', clear
	foreach type of local both_types {
		di `type'
		drop if id == `type'
	}
	// also drop if id = 1896. This is marked has having a diet twin, but only has data for one type of measurement
	drop if id == 1896
	
// keep dietary data only for adjustment. dietary data has met = 2
	keep if met == 2
	
// take draws from the raw data
	expand 1000
	bysort id: gen sims = _n 
	gen raw_diet_data_draws = rnormal(exp_mean, standard_error)
	reshape wide raw_diet_data_draws, i(id) j(sims)

	tempfile preadj
	save `preadj', replace

// make adjustment based on development status 
	gen beta_mean = .
	gen beta_se = .
	// fill in values for development status first
		replace beta_mean = `developed_scalar' if developed == 1
		replace beta_se = `developed_se' if developed == 1
		replace beta_mean = `developing_scalar' if developed == 0 
		replace beta_se = `developing_se' if developed == 0
	
// make 1000 draws of adjustment	
	forvalues n = 1/1000 {
		// convert raw data to ln
		replace raw_diet_data_draws`n' = ln(raw_diet_data_draws`n')
		// generate 1000 draws of the development status beta
		gen beta`n' = rnormal(beta_mean, beta_se)
		// apply adjustment
		gen new_diet_data`n' = raw_diet_data_draws`n' - beta`n'
		// convert back into normal space
		replace new_diet_data`n' = exp(new_diet_data`n')
	}
	
	drop raw_diet_data_draws* beta* beta_mean beta_se
	
// calcualte mean & se. output of rowsd command is actually a se bc this was the unit of variance used to generate the draws of raw data
	egen new_mean_diet_data = rowmean(new_diet_data*)
	egen new_se = rowsd(new_diet_data*)
	
// make new SE variable with crosswalked values
	rename standard_error se_original
	rename new_se standard_error	
	
// Make new SD variable using the crosswalked SE values
	gen sd_original = standard_deviation
	replace standard_deviation = standard_error * sqrt(effective_sample_size)
	
	scatter exp_mean new_mean_diet_data  || line new_mean_diet_data new_mean_diet_data
	
// Replace mean with adjusted values
	replace exp_mean = new_mean_diet_data
	
// clean up to be in same format as rest of dataset so can feed through diet code
	drop new_diet_data* new_mean_diet_data // new_var

	tempfile dietary
	save `dietary', replace
	
// Merge crosswalked values back into the sodium data set
	use `na', clear // It is fine to use `na' here because all the obs we needed to drop above are dropped with the next line
	drop if met == 2
	append using `dietary'
	
	destring period, replace
	
// make a urine validation variable  
/* 1.PABA validated  
   2. “Observed/expected creatinine ratio” or “Strict urine collection protocol”  
   3. Not performed/not reported  
   4. Not applicable)
	It means that any study with Met=1 (24-hour urinary excretion studies) will have the “urine_2” code of either 1, 2, or 3. 
	And all the studies for which Met=2, the “urine_2” value should be 4. 
*/
	gen cv_urine2 = (urine_2 == 2)
	gen cv_urine3 = (urine_2 == 3)
	
	
// fix mistake in dataset
	replace diet_2 = 2 if id == 1221 
	
// fix up met variable: now we have converted the data so that the different metrics are equivalent
	gen urinarystudy = (met == 1) // Rebecca made this 10/8/12 to see how many urinary and dietary studies are included in our final input dataset to Dismod (request of John Powles)
	replace met = 1 if met == 2
	gen cv_met99 = (met == 99)
	
// compare CV of adjusted studies to those of "gold standard" countries (like the US) to see if there are outliers. For some countries like Mexico and Japan, the SE's are very very small. Want to be sure that the SD values that were reported in original data set were not actually SE's
local check_cv = 0
if `check_cv' == 1 {
	// generate CV values for all crosswalked data
	generate CV = (standard_error * sqrt(effective_sample_size)) / exp_mean
	
	// compute average CV of US crosswalked data to use as gold standard value.
	summ CV if country == "United States" & urinarystudy == 0
	local avg_CV `r(mean)'
	di `avg_CV'
	
	// compute difference in each observation's CV from the average of US crosswalked
	gen CV_diff = (CV - `avg_CV')
	
	// compute average difference for each country's crosswalked data
	levelsof country if urinarystudy == 0, local(countries)
	gen avg_CV_diff = .
	foreach c of local countries {
		di "`c'"
		summ CV_diff if country == "`c'" & urinarystudy == 0
		local avg_diff `r(mean)'
		replace avg_CV_diff = `avg_diff' if country == "`c'" 
		}
	
	preserve
	keep if urinarystudy == 0
	levelsof country, local(countries)
	pdfstart using "`graphs'/compare_crosswalk_cvs_`timestamp'.pdf"
	foreach c of local countries {
		graph bar CV_diff if country == "`c'", over(age_start, label(labsize(vsmall))) over(svy, label(labsize(vsmall))) title("`c': difference in CV from USA average") nofill
		pdfappend
		}
	pdffinish, view
	restore
	
	drop CV CV_diff avg_CV_diff
}
	
count if location_id == .
if `r(N)' >0{
	di "missing location id"
	afasdf
}
	
// save
save "`output'/sodium_urinary_dietary_prepped4.dta", replace
	
// close log
	capture log close
	
