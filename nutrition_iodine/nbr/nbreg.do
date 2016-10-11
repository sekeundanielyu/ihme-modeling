
/// negative binomial regression for iodine deficiency


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
	
	local acause nutrition_iodine
	local age_start=4   /* age_group_id 4 corresponds to age_name "post neonatal" */
	local age_end=21    /* age_group_id 21 corresponds to age_name 80+ yrs */
	local custom_version v10 
	

** *********************************************************************************************************
	
	// get envelope
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
	use "`acause'_GBD2015.dta", clear
	rename sex sex_id 
	rename year year_id 
	rename cf_corr cf
	drop if year<1980
	drop if cf==.
		drop if sample_size==0
		drop if age_group_id<`age_start' | age_group_id>`age_end'
	keep location_id location_name year sex age_group_id cf sample_size 
    tempfile raw_data
	save `raw_data', replace
	
// Get covariate
      insheet using "hh_iodized_salt_pc.csv", comma names clear
	  
	 	
		drop if year<1980
		keep location_id year mean_value
		duplicates drop location_id year, force
		gen iodized_salt=mean_value
		tempfile covs
		save `covs', replace
	
		use `raw_data', clear
		merge m:1 location_id year using `covs', keep(3) nogen
		


// want death numbers in order to do count model of negative binomial (cf model)
   gen deaths=cf*sample_size
   drop if sample_size<1

save "raw_input_data.dta", replace	


	replace deaths=0 if deaths<.5
	drop if year<1980 

// create female covariate
	gen female=.
	replace female=1 if sex_id==2
	replace female=0 if sex_id==1


// drop subnational data 
	merge m:1 location_id using "location_id_parent.dta", keep(3)nogen
	
	drop if parent=="Brazil" | parent=="China" | parent=="India" | parent=="Japan" | parent=="Kenya" | parent=="Mexico" | parent=="Saudi Arabia" | parent=="Sweden" | parent=="United Kingdom" | parent=="United States" | parent=="South Africa"
	
	save "data_for_nbreg.dta", replace
** *********************************************************************************************************

	log using "nbr_log.smcl", replace
	

// run negative binomial regression 
					
		di in red "CF MODEL"
			nbreg deaths iodized_salt i.age_group_id female, exposure(sample_size)
	
** **********************************************************************************************************
	cap log close 	
	
// predict out for all country-year-age-sex
	use `pop_env', clear
	merge m:1 location_id year using `covs', nogen

	drop if year<1980

	gen female=.
	replace female=1 if sex_id==2
	replace female=0 if sex_id==1
	
// 1000 DRAWS 
	
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
	
	// Generate draws of the prediction
		levelsof age_group_id, local(ages)
		levelsof year, local(year)
		local counter=0
		generate alpha = exp(b_alpha)
		forvalues j = 1/1000 {
			local counter = `counter' + 1
			di in red `counter'
			quietly generate xb_d`j' = 0
			quietly replace xb_d`j'=xb_d`j'+b__cons[`j']
			quietly replace xb_d`j'=xb_d`j'+iodized_salt*b_iodized_salt[`j']
			quietly replace xb_d`j'=xb_d`j'+female*b_female[`j']


			foreach a of local ages {
					quietly replace xb_d`j'=xb_d`j'+b_`a'age_group_id[`j'] if age_group_id==`a'
					}
					
			
			// rename
			quietly rename xb_d`j' draw_`counter'
			
			quietly replace draw_`counter' = exp(draw_`counter') * env
			  
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
		
	// add cause_id
	gen cause_id=388
	
	outsheet using "draws/death_draws.csv", comma names replace
	
