// URI
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

			// Define J drive (data) for cluster (UNIX) and Windows (Windows)
				if c(os) == "Unix" {
					global prefix "/home/j"
					set odbcmgr unixodbc
				}
				else if c(os) == "Windows" {
					global prefix "J:"
				}
			
			// Close any open log file
				cap log close

** ********************************************************************************************************
// locals
	local acause uri
	local age_start=2   /* age_group_id 2 corresponds to age_name "early neonatal" */
	local age_end=21    /* age_group_id 21 corresponds to age_name 80+ yrs */
	local custom_version v15  

// Make folders
	capture mkdir "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws"
	capture mkdir "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`custom_version'"
** *********************************************************************************************************

// define filepaths
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015//`custom_version'/"
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015//`custom_version'/results"
	
	local outdir "$prefix/WORK/04_epi/01_database/02_data//`acause'/GBD2015//`custom_version'/"

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
	use "$prefix/WORK/04_epi/01_database/02_data//`acause'/GBD2015/data/`acause'_GBD2015.dta", clear
	
	 
	rename sex sex_id 
	rename year year_id 
	rename cf_corr cf
	
	drop if year_id<1980
	drop if cf==.
	drop if sample_size==0
	drop if age_group_id<`age_start' | age_group_id>`age_end'
	keep location_id location_name year_id sex_id age_group_id cf sample_size 
    tempfile raw_data
	save `raw_data', replace

	
// get covariates

    use "$prefix/WORK/04_epi/01_database/02_data//`acause'/GBD2015/data/LDI_pc.dta", clear
	
	drop if year_id<1980
	keep location_id year_id mean_value
	duplicates drop location_id year_id, force
	gen ln_LDI=ln(mean_value)
	tempfile covs
	save `covs', replace
		
	use `raw_data', clear
	merge m:1 location_id year_id using `covs', keep(3) nogen
	

// want death numbers in order to do count model of negative binomial 
   gen deaths=cf*sample_size
   drop if sample_size<1
   save "`outdir'/raw_input_data.dta", replace	
   

	replace deaths=0 if deaths<.5
	drop if year<1980 

// drop national level data for countries with subnationals /* the model does not perform well when including national level data */ 
	drop if inlist(location_id,130,95,6,102,135,163,180,67,93,196,152)  
	
// drop if cause fraciton is greater than the 97th percentile value
	
	centile cf, centile (97)
	gen pc_97th=r(c_1)
	drop if cf > pc_97th
	
	save "`outdir'/data_for_nbreg", replace

** *********************************************************************************************************

	log using "`outdir'/nbr_log.smcl", replace
	
	di in red "CF MODEL"
			nbreg deaths ln_LDI i.age_group_id, exposure(sample_size)

	cap log close 
** **********************************************************************************************************

// predict out for all country-year-age-sex
	use `pop_env', clear
	merge m:1 location_id year_id using `covs', nogen
    drop if year_id<1980
	
// 1000 DRAWS 
// Create draws from these matrices to get parameter uncertainty (for each coefficient and the constant)
	// create a columnar matrix (rather than default, which is row) by using the apostrophe
		matrix m = e(b)'
	// create a local that corresponds to the variable name for each parameter
		local covars: rownames m
	// create a local that corresponds to total number of parameters
		local num_covars: word count `covars'
	// create an empty local that you will fill with the name of each beta (for each parameter)
		local betas
	// fill in this local
		forvalues j = 1/`num_covars' {
			local this_covar: word `j' of `covars'
			local covar_fix=subinstr("`this_covar'","b.","",.)
			local covar_rename=subinstr("`covar_fix'",".","",.)
	// Rename dispersion coefficient 
			if `j' == `num_covars' {
            local covar_rename = "alpha"
        }
			local betas `betas' b_`covar_rename'
		}
	// store the covariance matrix 
		matrix C = e(V)
		/* matrix C = C[1..(colsof(C)-1), 1..(rowsof(C)-1)] */
	// use the "drawnorm" function to create draws using the mean and standard deviations from your covariance matrix
		drawnorm `betas', means(m) cov(C)
	
	// Generate draws of the prediction
		levelsof age_group_id, local(ages)
		local counter=0
		
		    gen alpha = exp(b_alpha)
		   	forvalues j = 1/1000 {
			local counter = `counter' + 1
			di in red `counter'
			quietly generate xb_d`j' = 0
			quietly replace xb_d`j'=xb_d`j'+b__cons[`j']
					
			quietly replace xb_d`j'=xb_d`j'+ln_LDI*b_ln_LDI[`j']
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
	
	sort location_id year_id age_group_id
	drop if draw_0==.
	drop if year_id<1980 
	/* tempfile death_draws
	save `death_draws', replace */
	
	//add cause_id
	gen cause_id=328
	
	outsheet using /ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`custom_version'/death_draws.csv, comma names replace


// save results

do /home/j/WORK/10_gbd/00_library/functions/save_results.do
save_results, cause_id(328) description(`acause' custom `custom_version') mark_best(yes) in_dir(/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`custom_version')


