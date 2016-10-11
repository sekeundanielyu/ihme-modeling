/// Natural History Model

** ******************************************************************************************************
** Setup
** ******************************************************************************************************	

// settings
	clear all
	set more off
	set mem 2g
	cap restore
	cap log close
	
// locals
	
	local acause whooping
	local custom_version v8  
	local age_start=4     
	local age_end=16    
	// a: average age of notifcation
	local a 3

// define filepaths
	cap mkdir "J:/WORK/04_epi/01_database/02_data/`acause'/GBD2015//`custom_version'/"
	cap mkdir "J:/WORK/04_epi/01_database/02_data/`acause'/GBD2015//`custom_version'/results"
	cap mkdir "J:/WORK/04_epi/01_database/02_data/`acause'/GBD2015//`custom_version'/results/age_sex_split_files"
	cap mkdir "J:/WORK/04_epi/01_database/02_data/`acause'/GBD2015//`custom_version'/results/for_age_sex_split"
	local outdir "J:/WORK/04_epi/01_database/02_data//`acause'/GBD2015//`custom_version'/results"
	
// get population for birth cohort at average age of notification by year
	adopath + J:/Project/Mortality/shared/functions
	get_env_results
	keep year_id location_id sex_id age_group_id mean_pop mean_env_hivdeleted
	rename mean_env_hivdeleted mean_env 
	
	merge m:1 location_id using "J:/WORK/04_epi/01_database/02_data/whooping/GBD2015/temp/iso3.dta", keepusing(iso3) keep(3)nogen
	rename sex_id sex
	keep if sex==3
	keep if year>=1980-`a'
	keep if inlist(age_group_id,2,3,4) 
	rename year_id year
	rename mean_pop pop
	collapse(sum) pop, by(location_id iso3 year) fast
	replace year=year+`a'
	
	keep location_id iso3 year pop 
	
	drop if year<1980 | year>2015
	
	tempfile population
	save `population', replace
	
	
// Prep WHO case notification data
	
	insheet using "J:\WORK\04_epi\01_database\02_data\whooping\GBD2015\data\who_pertussis_case_notifications_May 12 2016.csv", comma names clear
	rename iso_code iso3
	keep iso3 v*
	reshape long v, i(iso3) j(year)
	rename v cases
	replace year=2020-year		
	drop if cases==.
	drop if iso3==""
	gen whodata=1
	drop if year==1980 | year==1981
	tempfile whodata
	save `whodata', replace 


// prep US territories

	import excel using "J:\WORK\04_epi\01_database\02_data\whooping\GBD2015\data\US_territories.xlsx", firstrow clear
	rename ihme_loc_id iso3
	rename year_start year
	keep iso3 year cases
	drop if cases==.
	tempfile US_terri
	save `US_terri', replace


// Prep pertussis historical data	
	use "J:\Project\Causes of Death\codem\models\A06\natural_history_model\data\UK_Aust_JPN_population_for_agesexsplit.dta", clear
	keep if iso3=="XEW"
	replace iso3="GBR"
	keep iso3 year pop*
	preserve
	collapse (sum) pop2, by(iso3 year)
	replace year=year+`a'
	rename pop2 ukpop
	replace ukpop=ukpop*100000
	tempfile uk_pop
	save `uk_pop', replace
	restore
	drop pop17 pop18 pop19 pop20 pop21 pop22 pop23 pop_tot pop_source pop91 pop93 pop94 pop92
	egen total=rowtotal(pop*)
	collapse(sum)total, by(iso3 year)
	rename total ukpop
	replace ukpop=ukpop*100000
	tempfile uk_pop_all
	save `uk_pop_all', replace

	insheet using "J:\Project\Causes of Death\codem\models\A06\natural_history_model\data\Pertussis_Notification_Extraction.csv", clear
	keep if iso3=="XEW"
	append using  "J:\Project\Causes of Death\codem\models\A06\natural_history_model\data\DTP3_pre_1940.dta"
	append using `whodata'
	replace cases=notifications if cases==. 
	replace cases=notification if notifications>cases & notifications!=.
	duplicates drop iso3 year, force
	keep year cases iso3 vacc_rate whodata
	replace iso3="GBR" if iso3=="XEW"
	replace vacc_rate=0 if year<=1923
	
	append using `US_terri' 
	
	tempfile historical
	save `historical', replace

// get updated covariate	          
    
	use "J:\WORK\04_epi\01_database\02_data\whooping\GBD2015\data\DTP3_coverage_prop.dta", clear
	
	rename year_id year
	drop if year<1980
	keep location_id year mean_value
	duplicates drop location_id year, force
	rename mean_value dtp3
	tempfile covs
	save `covs', replace
	
	
** ******************************************************************************************************
** Modeling incidence
** ******************************************************************************************************	

// prepare inputs for regression
		use `historical', clear
		collapse(max)cases (min)vacc_rate, by(iso3 year) fast
		drop if iso3=="ISO_code" | iso3==""
	
	// get population
		merge 1:1 iso3 year using `population'
		keep if _merge==3 | iso3=="GBR"
		drop _m
		merge 1:1 iso3 year using `uk_pop', keep(1 3) nogen
		replace pop=ukpop if pop==.
		drop ukpop
	// merge on covariates	
		merge 1:1 location_id year using `covs', keep(1 3) nogen
		replace vacc_rate=dtp3 if vacc_rate==.
		drop if vacc_rate==.
		drop dtp3
	    
	// format
		keep year cases iso3 vacc_rate pop 
		replace pop=floor(pop)
		gen inc_rate=(cases/pop)*100000
		drop if inc_rate==.
		gen ln_inc=ln(inc_rate)
		gen ln_vacc=ln(vacc_rate)
		gen ln_unvacc=ln(1-vacc_rate)
		drop if inc_rate>20000
	// ln_unvaccinated bins - diagnostic tool
		centile ln_unvacc, centile(5(5)95)
		local bin=1
		forvalues n = 1/20 {
			local unvacc_`n'=r(c_`n')
			}
		gen ln_unvacc_bin=1
		forvalues b=2/19 {
			local a=`b'-1
			replace ln_unvacc_bin=`b' if ln_unvacc>`unvacc_`a'' & ln_unvacc<=`unvacc_`b''
			}
		replace ln_unvacc_bin=20 if ln_unvacc>`unvacc_19'
	save "`outdir'\incidence_input_data_for_xtmixed.dta", replace
	// RUN INCIDENCE REGRESSION
	log using "`outdir'/`acause'_cases_log.smcl", replace
	
		xtmixed ln_inc || _all: R.iso3 || _all: R.ln_unvacc_bin
		quietly {
		predict RE_iso3 RE_unvacc, reffects
		preserve
		collapse(mean)vacc_rate RE_unvacc, by(ln_unvacc_bin)
		gen ln_unvacc=ln(1-vacc_rate)
		tw scatter RE_unvacc ln_unvacc, mcolor(maroon) mlab(ln_unvacc_bin) msize(medium) ||  ///
		line RE_unvacc ln_unvacc, lcolor(teal) lwidth(medthick) ///
		title("Random effects on ln(unvaccinated)") subtitle("Based on model: xtmixed ln_inc ln_unvacc|| _all: R.iso3 || _all: R.ln_unvacc_bin", size(small)) ///
		legend(off) ylabel(, angle(horizontal) labsize(small)) xlabel(, labs(small)) ytitle(RE) xtitle("ln(unvaccinated)")
		graph export "`outdir'\unvacc_bin_REs_ln.png", replace

		tw scatter RE_unvacc vacc_rate, mcolor(maroon) msize(medium) ||  ///
		line RE_unvacc vacc_rate, lcolor(teal) lwidth(medthick) ///
		title("Random effects on ln(unvaccinated)") subtitle("Based on model: xtmixed ln_inc ln_unvacc || _all: R.iso3 || _all: R.ln_unvacc_bin", size(small)) ///
		legend(off) ylabel(, angle(horizontal) labsize(small)) xlabel(, labs(small)) ytitle(RE) xtitle("Vaccination rate")
		graph export "`outdir'\unvacc_bin_REs.png", replace
		restore
		}
		
		xtmixed ln_inc ln_unvacc || iso3:

	log close	
	
	// set our standard random effect to that on switzerland, where the pertussis monitoring system is thought to capture a large percentage of cases
		cap drop RE*
		predict RE_iso3, reffects
		preserve
		keep if iso3=="CHE"
		local standard_RE=RE_iso3
		restore
	
	// predict out
		// set up covariates
		use `population', clear
		collapse(sum)pop, by(location_id iso3 year)
		/* merge m:1 iso3 using `regions', keep(3) nogen */
		merge 1:1 location_id year using `covs', keep(3) nogen
		rename dtp3 vacc_rate	
		gen ln_unvacc = ln(1-vacc_rate)
		
	// set up 1000 draws based on coefficients and variance/covariance matrix
		// set up matrix of coefficients
		matrix m = e(b)'
		// drop coefficients on RE and error terms
		matrix m = m[1..(rowsof(m)-2),1]
		// set up local with covariate names
		local covars: rownames m
		local num_covars: word count `covars'
		local betas
		forvalues j = 1/`num_covars' {
			local this_covar: word `j' of `covars'
			local covar_fix=subinstr("`this_covar'","b.","",.)
			local covar_rename=subinstr("`covar_fix'",".","",.)
			local betas `betas' b_`covar_rename'
		}
		// set up covariance matrix
		matrix C = e(V)
		// drop covariances on RE and error terms
		matrix C = C[1..(colsof(C)-2), 1..(rowsof(C)-2)]
		// generate a normal distribution of coefficients on each covariate given the average coefficient value and the covariance matrix
		drawnorm `betas', means(m) cov(C)
	
	// generate 1000 draws, adding 1 covariate at a time to the linear prediction 
		// xb_d`j' represents linear_draw`number'; we rename to 'ensemble_d`j'' because that's the CODEm terminology and other code calls on those variable names
		compress
		local counter=0
		forvalues j = 1/1000 {
			local counter = `counter' + 1
			di in red `counter'
			quietly generate xb_d`j' = 0
			quietly replace xb_d`j'=xb_d`j'+b__cons[`j']
			// UPDATE THESE ROWS IF COVARIATES CHANGE
			quietly replace xb_d`j'=xb_d`j'+ln_unvacc*b_ln_unvacc[`j']
			quietly replace xb_d`j'=xb_d`j'+`standard_RE'
			quietly rename xb_d`j' ensemble_d`counter'
			// we did the regression in log space on incidence per 100,000, so exponentiate and multiply by population/100,000 to get an incident case estimate
			quietly replace ensemble_d`counter' = exp(ensemble_d`counter') * (pop/100000)
		}
	drop if year <1980 
	renvars ensemble_d1-ensemble_d1000  \ cases_d0-cases_d999 
	tempfile all
	save `all', replace
	keep year location_id iso3 cases*
	save "`outdir'\cases_draws.dta", replace 

** ******************************************************************************************************
** Modeling CFR
** ******************************************************************************************************	

// prep cfr data 
	
	insheet using "J:\Project\Causes of Death\codem\models\A06\natural_history_model\data\cfr_input_data.csv", names clear
	drop if ignore==1
	// drop outliers
	drop if iso3=="UGA" & yearstart==1951
	// format
	rename parametervalue cfr
	rename numerator_ deaths
	rename effective_sample cases
	keep iso3 year* age* mid* cfr deaths cases notification
	replace mid_point_year=1980 if mid_point_year<1980
	gen year=mid_point_year
	drop mid* years yeare age* notification
	tempfile cfr_GBD2010
	save `cfr_GBD2010'
	
	// add additional cfr data from collaborators
	insheet using "J:\Project\Causes of Death\codem\models\A06\natural_history_model\data\gbd2013_whooping_cough_lit.csv", comma names clear
	rename mean cfr
	rename numerator deaths
	rename denominator cases
	keep iso3 year* age* mid* cfr deaths cases
	gen year=year_start
	tempfile cfr_expert
	save `cfr_expert'
	
	use `cfr_GBD2010', clear
	append using `cfr_expert'
	
	// merge on location ids	
	merge m:1 iso3 using "J:\WORK\04_epi\01_database\02_data\whooping\GBD2015\data\iso3.dta", keep(3) nogen
	// merge on covs
	merge m:1 location_id year using `covs', keep(1 3) nogen
	drop cfr
	gen cfr = deaths/cases
		
	drop if cfr>.5
	save "`outdir'\cfr_input_data_for_nbreg.dta", replace

	// run CFR regression!
	log using "`outdir'\cfr_log.smcl", replace

		replace cases=1 if cases<1 & cases!=.
		nbreg deaths ln_LDI health, exposure(cases)
		 
	log close
	
	// predict for 	all places
		use `population', clear
		collapse(sum)pop, by(location_id iso3 year)
		merge 1:1 location_id year using `covs', keep(3) nogen
		
		// set up 1000 draws based on coefficients and variance/covariance matrix
		// set up matrix of coefficients
		matrix m = e(b)'
		
		// set up local with covariate names
		local covars: rownames m
		local num_covars: word count `covars'
		local betas
		forvalues j = 1/`num_covars' {
			local this_covar: word `j' of `covars'
			local covar_fix=subinstr("`this_covar'","b.","",.)
			local covar_rename=subinstr("`covar_fix'",".","",.)
      
      // Rename dispersion coefficient (is also called _const, like intercept) 
        if `j' == `num_covars' {
          local covar_rename = "alpha"
        }
        
			local betas `betas' b_`covar_rename'
		}
		// set up covariance matrix
		matrix C = e(V)
		
		// generate a normal distribution of coefficients on each covariate given the average coefficient value and the covariance matrix
			
		drawnorm `betas', means(m) cov(C)
		
		// generate the dispersion parameter
	   		
		generate alpha = exp(b_alpha)
				
		// generate 1000 draws, adding 1 covariate at a time to the linear prediction 
			// xb_d`j' represents linear_draw`number'
		local counter=0
			forvalues j = 1/1000 {
			local counter = `counter' + 1
			di in red `counter'
			quietly generate xb_d`j' = 0
			quietly replace xb_d`j'=xb_d`j'+b__cons[`j']
			quietly replace xb_d`j'=xb_d`j'+ln_LDI*b_ln_LDI[`j']
			quietly replace xb_d`j'=xb_d`j'+health*b_health[`j']
			quietly rename xb_d`j' cfr_d`counter'
			quietly replace cfr_d`counter' = exp(cfr_d`counter')
			quietly replace cfr_d`counter' = rgamma(1/alpha[`j'],alpha[`j']*cfr_d`counter')
		}
		
	save "`outdir'\cfr_draws.dta", replace 
	
	
** **********************************************************************************************************************************************
** Calculating nhm deaths as deaths=cfr*cases
** **********************************************************************************************************************************************		
		
    use "`outdir'\cases_draws.dta", clear
	merge 1:1 location_id year using "`outdir'\cfr_draws.dta", keep(3) nogen
		
		
	// multiply cases and cfr at the draw level
	forvalues x=1(1)1000 {
		gen deaths_d`x'=cases_d`x'*cfr_d`x'
		drop cases_d`x' cfr_d`x'
		}	
	keep year iso3 location_id deaths_d* 
	
save "`outdir'/death_draws.dta", replace /* This file needs to be age-sex splitted before combining with CODEm deaths */



	
	
	
	
