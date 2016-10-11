// Varicella
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
	local acause varicella
	local age_start=2   
	local age_end=21   
	local custom_version v18  
	
// Make folders on cluster
	capture mkdir "/ihme/codem/data/`acause'/`custom_version'"
	capture mkdir "/ihme/codem/data/`acause'/`custom_version'/draws"
		
** *********************************************************************************************************

// define filepaths
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015//`custom_version'/"
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015//`custom_version'/results"
	
	local outdir "$prefix/WORK/04_epi/01_database/02_data//`acause'/GBD2015//`custom_version'/"

// get envelope, pop, super region for country-age-years without raw data
	adopath + $prefix/Project/Mortality/shared/functions
	get_env_results

	//rename
	rename mean_env_hivdeleted envelope	
	rename mean_pop pop
	rename year_id year
	rename mean_pop pop
	rename mean_env envelope
	//keep necessary variables
	keep location_id year sex age_group_id pop envelope
	drop if age_group_id <`age_start' | age_group_id >`age_end'
	drop if year <1980
	tempfile pop_env
	save `pop_env', replace
	

// Get COD data
	clear all
    adopath + "$prefix/WORK/10_gbd/00_library/functions"
    get_data, cause_ids(342)
	
	drop if year<1980
		drop if cf==.
		drop if sample_size==0
		drop if age_group_id<`age_start' | age_group_id>`age_end'
	keep location_id location_name year sex age_group_id cf sample_size 
    tempfile raw_data
	save `raw_data', replace

	
// get covariates

    use "$prefix/WORK/04_epi/01_database/02_data//`acause'/GBD2015/data/health_system_access_capped.dta", clear
	rename year_id year
	drop if year<1980
	keep location_id year mean_value
	duplicates drop location_id year, force
	rename mean_value health
	tempfile covs
	save `covs', replace
		
	use `raw_data', clear
	merge m:1 location_id year using `covs', keep(3) nogen
	merge m:1 location_id year age_group_id sex using `pop_env', keep(3) nogen

// want death numbers in order to do count model of negative binomial (rate model)
   gen deaths=cf*env
   replace deaths=0 if deaths<.5
   drop if year<1980 


// drop if cause fraciton is greater than the 99th percentile value
	
	centile cf, centile (99)
	gen pc_99th=r(c_1)
	drop if cf > pc_99th

	save "`outdir'/data_for_nbreg", replace

** *********************************************************************************************************

	log using "`outdir'/nbr_log.smcl", replace
	
	nbreg deaths health i.age_group_id, exposure(pop)

	cap log close 
** **********************************************************************************************************

// predict out for all country-year-age-sex
	use `pop_env', clear
	merge m:1 location_id year using `covs', nogen
    drop if year<1980
	
// 1000 DRAWS 
// Your regression stores the means coefficient values and covariance matrix in the ereturn list as e(b) and e(V) respectively
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
					
			quietly replace xb_d`j'=xb_d`j'+health*b_health[`j']
			foreach a of local ages {
					quietly replace xb_d`j'=xb_d`j'+b_`a'age_group_id[`j'] if age_group_id==`a'
					}			
		 
			// rename
			quietly rename xb_d`j' draw_`counter'
			
// nbr as run above stores the prediction as ln_rate, which we multiply by population to get deaths		
		
		quietly replace draw_`counter' = exp(draw_`counter') * pop
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
	
	rename sex sex_id
	rename year year_id
	gen cause_id=342
	
	outsheet using /ihme/codem/data/`acause'/`custom_version'/draws/death_draws.csv, comma names replace 


// save results

do /home/j/WORK/10_gbd/00_library/functions/save_results.do
save_results, cause_id(342) description(`acause' custom `custom_version') mark_best(no) in_dir(/ihme/codem/data/`acause'/`custom_version'/draws)


