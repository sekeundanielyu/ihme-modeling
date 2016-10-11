// Run a negative binomial regression on data from vivax-only countries

// settings
	clear all
	set more off
	cap restore, not
	cap log close

// locals
	local cause 			A12
	local causename 		"Malaria"
	local age_start 		0.01
	local age_end 			80
	local version			v4
	local pullfreshnums 	0

	

//set OS
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		local prefix "/home/j"
		set odbcmgr unixodbc
		local basepath "`prefix'/temp/strUser/Malaria/vivax"
		adopath + "/ihme/code/general/strUser/malaria"
	}
	else if c(os) == "Windows" {
		local prefix "J:"
		local basepath "J:/temp/strUser/Malaria/vivax"
		adopath + "C:\Users\strUser\Documents\Code\malaria"
	}

// path of ado library
	adopath + "`prefix'/WORK/10_gbd/00_library/functions"
	do "`prefix'/WORK/10_gbd/00_library/functions/save_results.do"
	
// define filepaths
	
	local store_data "`basepath'/malaria_data"
	local results_base "`basepath'/results/"
	local results_version "`results_base'/`version'/"

	local paths basepath store_data results_base results_version
	// create new folders
	foreach path of local paths {
		cap mkdir "``path''"
	
	}

	local malaria_groups "`prefix'/temp/strUser/Malaria/vivax/annex/SUBNATIONALS_countries_with_falciparum_or_vivax.dta"

//prepare locations
	get_location_metadata, location_set_id(35) clear
	keep location_id ihme_loc_id is_estimate most_detailed level parent_id path_to_top_parent
	tempfile locs
	save `locs', replace
// get envelope, pop, super region for country-age-years without raw data
	get_demographics, gbd_team(cod) make_template clear
	tempfile template
	save `template', replace
	
	local years $year_ids
	local locations $location_ids
	local sexes $sex_ids
	local ages $age_group_ids
	
	macro drop year_ids location_ids sex_ids age_group_ids
	
	get_populations_malaria, year_id(`years') location_id(`locations') sex_id(`sexes') age_group_id(`ages') clear
    merge 1:1 location_id year_id age_group_id sex_id using `template', keep(2 3) nogen
	
//merge in location names and format the file
	merge m:1 location_id using `locs', assert(2 3) keep(3) nogen
	rename mean_env envelope
	rename pop_scaled pop	
	rename year_id year
	gen iso3 = ihme_loc_id

//Prepare vivax countries
	preserve
		use `malaria_groups', clear
		keep if group == "vivax" & drop_me==0
		drop drop_me
		gen ihme_loc_id = iso3
		gen year_id = year
				
		
		merge m:1 ihme_loc_id using `locs', assert(2 3) keep(3) nogen
		drop if most_detailed != 1 //this should only drop mexico
		
		//expand to include 2014 and 15
		expand 2 if year==2013, gen(tag)
		replace year = 2014 if tag ==1
		drop tag
		expand 2 if year == 2014, gen(tag)
		replace year = 2015 if tag ==1
		drop tag
		
		tempfile mg
		save `mg', replace
	restore
	//expand years to include 2014 and 2015
	merge m:1 iso3 year using "`mg'", assert(1 3) keep(3) nogen
	replace year_id = year
	
	tempfile pop_env
	save `pop_env', replace
	
// get raw death data
	if `pullfreshnums'==1{
		get_data, cause_ids(345) clear
		
		//do some drops
			drop if cf==.
			drop if sample_size==0
		
			merge m:1 location_id year using `mg', keep(3) nogen
			
			drop deaths 
			rename study_deaths deaths
		//save
		save "`store_data'/malaria_vivax_data.dta", replace
	
	}
	else{
		use "`store_data'/malaria_vivax_data.dta", clear
	}


// run negative binomial regression
	gen sex_id = sex
	gen male = sex_id == 1
	nbreg deaths year male i.age_group_id if age_group_id !=2, exposure(sample_size)

//Add draws to square
	use `pop_env', clear
	replace age_group_id = round(age_group_id)
	gen male = sex_id ==1
// 1000 DRAWS 
// Your regression stores the means coefficient values and covariance matrix in the ereturn list as e(b) and e(V) respectively
// Create draws from these matrices to get parameter uncertainty (for each coefficient and the constant)
	// create a columnar matrix (rather than default, which is row) by using the apostrophe
		matrix m = e(b)'
	// with gnbr, the output also includes a dispersion parameter which we don't need to include in the prediction
	// subtract 1 row to get rid of the coefficient on the dispersion parameter
		matrix m = m[1..(rowsof(m)-1),1]
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
			local betas `betas' b_`covar_rename'
		}
	// store the covariance matrix (again, you don't want the last rows and columns that correspond to dispersion parameter)
		matrix C = e(V)
		matrix C = C[1..(colsof(C)-1), 1..(rowsof(C)-1)]
	
	//now create the draws by recreating the regression
	
	//first grab the dispersion factor
	drawnorm `betas', means(m) cov(C)
	local alpha=e(alpha)
	local a=1/`alpha'
	local b=`alpha'
	gen dispersion = rgamma(`a', `b')
	
	//get rid of the betas
	drop b_*
	
	// use the "drawnorm" function to create draws using the mean and standard deviations from your covariance matrix
	drawnorm `betas', means(m) cov(C)
	
	//figure out the age_group coefficent to use
	gen b_age_group = 0	
	forvalues i = 0/999{
		local iter = `i'+1
		//qui di in red "generating draw `i'"
		
		qui {
		//get the age_group beta we are going to use
			forvalues aaa = 3/21 {
				replace b_age_group = b_`aaa'age_group_id[`iter'] if age_group_id ==`aaa'
				//set trace on
				//replace b_age_group=b_`aaa'age_group_id[`i'] if ==`aaa'
			}	
			
		//the equation: nbreg deaths year i.age_group_id if age_group_id !=2, exposure(sample_size)
		//nbr as run above stores the prediction as ln_cf, which we multiply by dispersion and by envelope to get deaths
			gen draw_`i' = 0
			replace draw_`i' = exp(b__cons[`iter']+ b_year[`iter']*year + b_age_group + b_male[`iter'] * male) *dispersion[`iter'] * envelope
			replace draw_`i' = 0 if age_group_id ==2 
			
			count if draw_`i' ==.
			noi {
			if `r(N)' > 0 {
				di as error "Missing Values Found in draw_`i'"
				BREAK
				asd	
			}
			}
			summ draw_`i'
			
			noi{
			if `r(min)' <0 {
				di as error "Deaths smaller than 0 in draw_`i'"
				tab ihme_loc_id year_id if draw_`i' <0
				BREAK
			}
			}
		}
	}
	compress
	
//get upper lower median and mean
	//fastpctile draw*, pct(2.5 50 97.5) names(lower median upper)
	//fastrowmean draw*, mean_var_name(mean)

//format dataframe
	keep *id* draw* pop //upper lower mean
	drop b_*
	gen model_id = "Vivax"

//save a full copy
	save "`results_version'/deaths_vivax.dta", replace
