
/// Preparing a negative binomial regression for input into codcorrect


// Settings
			// Clear memory and set memory and variable limits
				clear all
				set mem 5G
				set maxvar 32000

			// Set to run all selected code without pausing
				set more off

			// Set graph output color scheme
				set scheme s1color

			// Close any open log file
				cap log close
** ********************************************************************************************************
// locals
	
	local acause diptheria
	local age_start=4     
	local age_end=16    
	local custom_version v14   

	
// get envelope, pop, super region for country-age-years without raw data
adopath + $prefix/Project/Mortality/shared/functions
get_env_results

keep output_version_id year_id location_id sex_id age_group_id mean_pop mean_env_hivdeleted
	//rename
	rename mean_env_hivdeleted envelope	
	rename mean_pop pop
	
	// drop uncessary age groups
	drop if age_group_id <`age_start' | age_group_id >`age_end'
	drop if year_id <1980
	tempfile pop_env
	save `pop_env', replace
	

// Get raw data
	use "diphtheria_GBD2015.dta", clear
	rename sex sex_id 
	rename year year_id 
	rename cf_corr cf
	
	drop if year_id<1980
	drop if cf==.
	drop if sample_size==0
	drop if age_group_id<`age_start' | age_group_id>`age_end'
	keep location_id location_name year_id sex_id age_group_id cf sample_size 
   

	// want death numbers in order to do cf model of negative binomial 
   gen deaths=cf*sample_size
   
   
	// drop subnational data 
	merge m:1 location_id using "location_id_parent.dta", keep(3)nogen

	drop if parent=="Brazil" | parent=="China" | parent=="India" | parent=="Japan" | parent=="Kenya" | parent=="Mexico" | parent=="Saudi Arabia" | parent=="Sweden" | parent=="United Kingdom" | parent=="United States" | parent=="South Africa"

	tempfile raw_data
	save `raw_data', replace
	
	
// Get covariate
      use "DTP3_coverage_prop.dta", clear
	  
	 	
		drop if year_id<1980
	    
		keep location_id year_id mean_value
		duplicates drop location_id year, force
		gen DTP3_coverage_prop=mean_value
		tempfile covs
		save `covs', replace
	
		use `raw_data', clear
		merge m:1 location_id year using `covs', keep(3) nogen
				

	replace deaths=0 if deaths<.5  
    save "raw_input_data.dta", replace	

// drop outliers (i.e., cf greater than the 99th percentile value)
centile cf, centile (99)
local pc_99=r(c_1)
drop if cf > `pc_99'
save "data_for_nbreg.dta", replace

** *********************************************************************************************************

	log using "nbr_log.smcl", replace

	nbreg deaths DTP3_coverage_prop i.age, exposure(sample_size)

	cap log close 	
** **********************************************************************************************************

// predict out for all country-year-age-sex
	use `pop_env', clear
	merge m:1 location_id year using `covs', nogen
	drop if year<1980
	
	
// 1000 DRAWS FOR UNCERTAINTY
/
		matrix m = e(b)'
		local covars: rownames m
		local num_covars: word count `covars'
		local betas
	
		forvalues j = 1/`num_covars' {
			local this_covar: word `j' of `covars'
			local covar_fix=subinstr("`this_covar'","b.","",.)
			local covar_rename=subinstr("`covar_fix'",".","",.)
	
        if `j' == `num_covars' {
          local covar_rename = "alpha"
        }		
			local betas `betas' b_`covar_rename'
		}
	
		matrix C = e(V)
		
	
		drawnorm `betas', means(m) cov(C)
	
	
		local alpha=e(alpha)
		local a=1/`alpha'
		local b=`alpha'
		gen dispersion = rgamma(`a', `b')
		
	// Generate draws of the prediction
		levelsof age_group_id, local(ages)
		local counter=0
		
		gen alpha = exp(b_alpha)
	
		forvalues j = 1/1000 {
			local counter = `counter' + 1
			di in red `counter'
			quietly generate xb_d`j' = 0
			quietly replace xb_d`j'=xb_d`j'+b__cons[`j']
			quietly replace xb_d`j'=xb_d`j'+DTP3_coverage_prop*b_DTP3_coverage_prop[`j']
			foreach a of local ages {
					quietly replace xb_d`j'=xb_d`j'+b_`a'age_group_id[`j'] if age_group_id==`a'
					}

			// rename
			
			quietly rename xb_d`j' draw_`counter'
			
		quietly replace draw_`counter' = exp(draw_`counter') * envelope
		quietly replace draw_`counter' = rgamma(1/alpha[`j'],alpha[`j']*draw_`counter')	
		}

// Rename draws
			forvalues i = 1/1000 {
				local i1 = `i' - 1
				rename draw_`i' draw_`i1'
			}
			
// saving death draws
	
	sort location_id year age_group_id
	drop if draw_0==.
	drop if year<1980 

	// add cause id
	gen cause_id=338
	
	outsheet using "draws/death_draws.csv", comma names replace

	
