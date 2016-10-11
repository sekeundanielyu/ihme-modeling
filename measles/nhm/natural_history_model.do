/// Natural History Model

** ******************************************************************************************************
** Setup
** ******************************************************************************************************	
	
// settings
	clear all
	set more off
	cap restore
	cap log close
	
// locals
	
	local acause measles
	local custom_version v18   
	local age_start=2     
	local age_end=16     
	// a: average age of notification
	local a 3

	
	// get population for birth cohort at average age of notification by year
	use "pop_data_all.dta", clear  
	rename sex_id sex
	keep if inlist(age_group_id,2,3,4) & year >= 1980-3 & sex == 3 
	rename year_id year
	replace year=year+`a'
	
	keep location_id year mean_pop 
	rename mean_pop pop
	drop if year<1980 | year>2015
	collapse(sum) pop, by(location_id year) fast
	tempfile population
	save `population', replace
 	
	
	// get all population

	use "pop_data_all.dta", clear  
	rename sex_id sex
	keep if sex==2
	rename year_id year
	rename mean_pop pop
	keep if year>=1980
	drop if age_group_id<`age_start' | age_group_id>`age_end'
	replace age_group_id=0 if age_group_id==2| age_group_id==3 | age_group_id==4
	collapse(sum) pop, by(location_id age_group_id year) fast
	tempfile population_all
	save `population_all', replace

	// get necessary location information
	use "sr_64_31_103.dta", clear
	tempfile sr_64_31_103
	save `sr_64_31_103', replace

	use "iso3.dta", clear
	drop if location_id==533
	duplicates drop location_name, force
	tempfile iso3
	save `iso3', replace


// prep WHO supplementary immunization activity (SIA) data 
    // get SIA data prior to 2000
	insheet using "Standardized_measles_SIAs_2Dec2011.csv", clear 
	rename country location_name
	rename yr year
	drop if reached==.
	drop if target==0 & reached==0
	keep if year <2000
	replace location_name="The Bahamas" if location_name=="Bahamas"
	replace location_name="Hong Kong Special Administrative Region of China" if location_name=="Hong Kong"
	replace location_name="Saint Kitts and Nevis" if location_name=="Saint Kitts & Nevis"
	replace location_name="Sao Tome & Principe" if location_name=="Sao Tome and Principe"
	replace location_name="United Arab Emirates" if location_name=="UAE"
	replace location_name="Vietnam" if location_name=="VietNam"
	replace location_name="Central African Republic" if location_name=="CAR"
	replace location_name="North Korea" if location_name=="DPRKorea"
	replace location_name="Democratic Republic of the Congo" if location_name=="DRCongo" 
	replace location_name="United Kingdom" if location_name=="UK"
	replace location_name="Sao Tome and Principe" if location_name=="Sao Tome & Principe"
	merge m:1 location_name using `iso3', keep(3)nogen
	
	tempfile sia_1987_1999
	save `sia_1987_1999', replace
	
	// get new SIA data 
	import excel using "WHO_SIA_2000_2015.xlsx", firstrow clear
	drop if target==0 & reached==0
    drop if target==. | reached==.
   	rename country location_name
    
	// collapse across country and years
	
	collapse (sum) targe reached, by (location_name year)
	
	replace location_name="The Bahamas" if location_name=="Bahamas (the)"
	replace location_name="Cape Verde" if location_name=="Cabo Verde"
	replace location_name="Comoros" if location_name=="Comoros (the)"
	replace location_name="North Korea" if location_name=="Democratic People's Republic of Korea (the)"
	replace location_name="Dominican Republic" if location_name=="Dominican Republic (the)"
	replace location_name="Gambia" if location_name=="Gambia (the)"
	replace location_name="Marshall Islands" if location_name=="Marshall Islands (the)"
	replace location_name="Niger" if location_name=="Niger (the)"
	replace location_name="South Korea" if location_name=="Republic of Korea (the)"
	replace location_name="Moldova" if location_name=="Republic of Moldova (the)"
	replace location_name="Russia" if location_name=="Russian Federation (the)"
	replace location_name="Russia" if location_name=="Russian Federation"
	replace location_name="Central African Republic" if location_name=="Central African Republic (the)"
	replace location_name="Democratic Republic of the Congo" if location_name=="Democratic Republic of the Congo (the)"
	replace location_name="Democratic Republic of the Congo" if location_name=="Democratic Republic of Congo"
	replace location_name="Congo" if location_name=="Congo (the)"
	replace location_name="United Arab Emirates" if location_name=="United Arab Emirates (the)"
    replace location_name="Iran" if location_name=="Iran (Islamic Republic of)"
    replace location_name="Sudan" if location_name=="Sudan (the)"
    replace location_name="Syrian Arab Republic" if location_name=="Syrian Arab Republic (the)"
    replace location_name="Laos" if location_name=="Lao People's Democratic Republic (the)"
	replace location_name="Laos" if location_name=="Lao People's Democratic Republic"
    replace location_name="Philippines" if location_name=="Philippines (the)"
	replace location_name="Bolivia" if location_name=="Bolivia (Plurinational State of)"
	replace location_name="Cote d'Ivoire" if location_name=="Côte d'Ivoire"
	replace location_name="The Gambia" if location_name=="Gambia"
	replace location_name="Federated States of Micronesia" if location_name=="Micronesia (Federated States of)"
	replace location_name="Syria" if location_name=="Syrian Arab Republic"
	replace location_name="Macedonia" if location_name=="The former Yugoslav Republic of Macedonia"
	replace location_name="Tanzania" if location_name=="United Republic of Tanzania"
	replace location_name="Venezuela" if location_name=="Venezuela (Bolivarian Republic of)"
	replace location_name="Vietnam" if location_name=="Viet Nam"
	replace location_name="Congo" if location_name=="congo"	
	merge m:1 location_name using `iso3', keep(3)nogen
	
    append using `sia_1987_1999'
	tempfile who_sia
	save `who_sia', replace
	

	use `population_all', clear
	keep if age_group_id<=8
	collapse (sum) pop, by(location_id year)
	merge 1:1 location_id year using `who_sia', keep(3) nogen
	gen supp=reached/pop
	
	_pctile supp, p(50)
	local median=r(r1)
	replace supp=`median' if supp==.
	
	replace supp=.99 if supp>1
	keep location_id year sup*
	tempfile no_lag
	save `no_lag', replace
	// generate lags for 1-6 years
	forvalues x=1/5 {
		replace year=year+1
		rename supp supp_lag`x'
		tempfile lag`x'
		save `lag`x'', replace
		}
	use `no_lag', clear
	forvalues x=1/5 {
		merge 1:1 location_id year using `lag`x'', nogen
		replace supp_lag`x'=0 if supp_lag`x'==.
		}
	replace supp=0 if supp==.
	drop if year<1980 | year>2015
	
	tempfile SIAs
	save `SIAs', replace
	
	
// get the covariate
	use "measles_vacc_cov_prop.dta", clear
	rename year_id year
	drop if year<1980
	keep location_id year mean_value
	duplicates drop location_id year, force
	gen ln_unvacc=ln(1-mean_value)
	tempfile covs
	save `covs', replace

** *******************************************************************************************************************
** Modeling incidence
** *******************************************************************************************************************	

	insheet using "who_measles_case_notifications.csv", comma names clear
	rename iso_code iso3
	keep iso3 v*
	reshape long v, i(iso3) j(year)
	rename v cases
	replace year=2020-year
		
	// merge on location_id
		merge m:1 iso3 using "location_id.dta", keep(3) nogen
	// get population
		merge 1:1 location_id year using `population', keep(3) nogen
	// get ihme covariates		
		merge 1:1 location_id year using `covs', keep(3) nogen
	// get WHO SIA data
		merge 1:m location_id year using `SIAs', keep(1 3) nogen
		replace supp=0 if supp==.
		forvalues x=1/5 {
			replace supp_lag`x'=0 if supp_lag`x'==.
			}

	 // prep data for regression, drop outliers
		keep year cases location_id iso3 ln_unvacc pop supp* 
		gen inc_rate=(cases/pop)*100000
		drop if inc_rate==.
		drop if inc_rate>95000
		
		
	// generate transformed variables 
		gen ln_inc=ln(inc_rate)
		save "data_for_regression.dta", replace
	
	// set up log version of continuous SIA covariate
		forvalues x=1/5 {
			replace supp_lag`x'=.000000001 if supp_lag`x'==0
			gen ln_supp_lag`x'=ln(supp_lag`x')
			}
		replace supp=.000000001 if supp==0	
		gen ln_supp=ln(supp)

	
	// RUN INCIDENCE REGRESSION!	
	
		drop if year<1995 
		
		// merge on SRs and regions
		
		merge m:1 location_id using "sr_all.dta", keepusing(super_region region) keep(3)nogen
		log using "`acause'_cases_log.smcl", replace		
		
		xtmixed ln_inc ln_unvacc supp_lag1 supp_lag2 supp_lag3 supp_lag4 supp_lag5 || super_region: || region: || iso3:
		log close
	
	// predict out
		
		use `population', clear
		collapse(sum)pop, by(location_id year)
		
		merge 1:1 location_id year using `covs', keep(3) nogen		
			
		merge 1:1 location_id year using `SIAs', keep(1 3) nogen	
		replace supp=0 if supp==.
		forvalues x=1/5 {
			replace supp_lag`x'=0 if supp_lag`x'==.
			}	
		
		forvalues x=1/5 {
			replace supp_lag`x'=.000000001 if supp_lag`x'==0
			gen ln_supp_lag`x'=ln(supp_lag`x')
			}
		replace supp=.000000001 if supp==0	
		gen ln_supp=ln(supp)
		
		// set up 1000 draws based on coefficients and variance/covariance matrix
			
			matrix m = e(b)'
			local cons = m[7,1]
			//generating a standard random effect (given 0% vaccinated, the combination of the RE and the constant will lead to an incidence of 95,000/100,000)
			local standard_RE=ln(95000)-`cons'
			matrix m = m[1..(rowsof(m)-4),1]
			local covars: rownames m
			local num_covars: word count `covars'
			local betas
			forvalues j = 1/`num_covars' {
				local this_covar: word `j' of `covars'
				local covar_fix=subinstr("`this_covar'","b.","",.)
				local covar_rename=subinstr("`covar_fix'",".","",.)
				local betas `betas' b_`covar_rename'
			}
		
			matrix C = e(V)
			matrix C = C[1..(colsof(C)-4), 1..(rowsof(C)-4)]
			drawnorm `betas', means(m) cov(C)
			
			compress
			local counter=0
			forvalues j = 1/1000 {
				local counter = `counter' + 1
				di in red `counter'
				quietly generate xb_d`j' = 0
				quietly replace xb_d`j'=xb_d`j'+b__cons[`j']
				quietly replace xb_d`j'=xb_d`j'+ln_unvacc*b_ln_unvacc[`j']	
				forvalues x=1/5 {
					quietly replace xb_d`j'=xb_d`j'+supp_lag`x'*b_supp_lag`x'[`j']
					}
				quietly replace xb_d`j'=xb_d`j'+`standard_RE'
				quietly rename xb_d`j' ensemble_d`counter'
				// we did the regression in log space on incidence per 100,000, so exponentiate and multiply by population/100,000 to get an incident case estimate
				quietly replace ensemble_d`counter' = exp(ensemble_d`counter') * (pop/100000)
			}
		keep year location_id ensemble*
		save "results/cases_draws.dta", replace 


	// prep incidence for 3 SRs	
		preserve
		merge m:1 location_id using "parent_id_3SR.dta", keep(3)nogen
		tempfile subnat_3SRs
		save `subnat_3SRs', replace
		restore
			
	   	preserve
		merge m:1 location_id using "location_id.dta", keep(3) nogen
		keep if iso3=="BMU" | iso3=="GRL" | iso3=="PRI" | iso3=="VIR"
		tempfile BMU_GRL_PRI_VIR
		save `BMU_GRL_PRI_VIR', replace
		restore
		
		
		use "pop_data_all.dta", clear
		rename year_id year
		rename sex_id sex
		keep if sex == 3 & year >= 1980
		keep if inlist(age_group_id,2,3,4,5)
		keep location_id year mean_pop
		rename mean_pop pop
		collapse(sum) pop, by(location_id year) fast
		tempfile population_u5
		save `population_u5', replace
			
				
		insheet using "who_measles_case_notifications.csv", comma names clear
		rename iso_code iso3
		keep iso3 v*
		reshape long v, i(iso3) j(year)
		rename v cases
		replace year=2020-year	
		merge m:1 iso3 using `sr_64_31_103', keep(3) nogen
		merge 1:1 location_id year using `population_u5', keep(3) nogen
		gen inc_rate=(cases/pop)
	
	    outsheet using "who_measles_case_notifications_1980_2015_3SRs.csv", comma names replace
	
	// get previous & next year estimates for stand-alone missing years
		preserve
		replace year=year+1
		rename inc_rate prev_year_inc
		keep iso3 year prev
		tempfile prev
		save `prev', replace
		restore
		preserve
		replace year=year-1
		rename inc_rate next_year_inc
		keep iso3 year next
		tempfile next
		save `next', replace
		restore
		merge 1:1 iso3 year using `prev', keep(1 3) nogen
		merge 1:1 iso3 year using `next', keep(1 3) nogen
		replace inc_rate=prev if inc_rate==.
		replace inc_rate=next if inc_rate==.
		drop prev next 
		
	// get region & SR averages for still-missing country years
		// region averages
		preserve 
		collapse (mean) inc_rate, by(parent sr_id year)
		rename inc_rate reg_rate
		tempfile reg
		save `reg', replace
		
		// super region averages
		collapse (mean) reg_rate, by(sr_id year)
			/* fix 1 outlier
			replace reg_rate=.0075495 if super==31 & year==1980   */
		rename reg_rate sr_rate
		tempfile sr
		save `sr', replace
		restore 
	
		// apply region and super region averages to missing data
		merge m:1 parent year using `reg', nogen
		merge m:1 sr_id year using `sr', nogen
		replace inc_rate=reg_rate if inc_rate==.
		replace inc_rate=sr_rate if inc_rate==.
		drop reg_rate sr_rate
		// generate error
		gen SE=sqrt((inc_rate*(1-inc_rate))/pop)
	    
		
	// get region & SR averages of error for country-years with 0 cases reported
		preserve 
		collapse (mean) SE, by(parent year)
		rename SE reg_SE
		tempfile regse
		save `regse', replace
		restore
		
		preserve
		collapse (mean) SE, by(sr_id year)
		rename SE sr_SE
		tempfile srse
		save `srse', replace
		restore
		
		merge m:1 parent year using `regse', nogen
		merge m:1 sr_id year using `srse', nogen
		replace SE=reg_SE if SE==0
		replace SE=sr_SE if SE==0
		replace SE = sqrt(1/pop * inc_rate * (1 - inc_rate) + 1/(4 * pop^2) * invnormal(0.975)^2) if SE == 0 
		drop cases 
	    
	// generate 1000 draws!
		forvalues x=1/1000 {
			gen ensemble_d`x'=rnormal(inc_rate, SE)
			replace ensemble_d`x'=0 if ensemble_d`x'<0
			replace ensemble_d`x'=ensemble_d`x'*pop
			}
		drop inc SE pop
	
		save "results/reported_cases_draws.dta", replace
		
	// bring together
		use "results/cases_draws.dta", clear
		merge m:1 location_id using `sr_64_31_103', keep(1 2) nogen
		append using "results/reported_cases_draws.dta"
		append using `subnat_3SRs'
	    renvars ensemble_d1-ensemble_d1000  \ cases_d0-cases_d999 
		save "results/combined_cases_draws.dta", replace
		
** ***********************************************************************************************************************
** Modeling CFR
** ***********************************************************************************************************************

// get covariates

    use "LDI_pc.dta", clear
	rename year_id year
	drop if year<1980
	keep location_id year mean_value
	duplicates drop location_id year, force
	gen ln_LDI=ln(mean_value)
	drop mean_value
	tempfile LDI
	save `LDI', replace
	
	use "malnutrition_prop_under_2sd.dta", clear
	rename year_id year
	drop if year<1980
	keep location_id year mean_value
	duplicates drop location_id year, force
	gen ln_mal=ln(mean_value)
	tempfile mal
	save `mal', replace
	
	use `LDI', clear
	merge 1:1 location_id year using `mal', keep(3)nogen
	
	// merge on iso3
	merge m:1 location_id using "iso3.dta", keepusing(iso3) keep(3)nogen
	tempfile covs
	save `cfr_covs', replace


// get population for birth cohort at average age of notification by year
	use "pop_data_all.dta", clear  
	
	keep if inlist(age_group_id,2,3,4) & year >= 1980-`a' & sex == 3 
	rename year_id year
	replace year=year+`a'
	
	keep location_id year mean_pop 
	rename mean_pop pop
	drop if year<1980 | year>2015
	collapse(sum) pop, by(location_id year) fast
	merge m:1 location_id using "sr_all.dta", keep(3)nogen
	tempfile population
	save `population', replace

	
 // get measles COD data 
    use "measles_GBD2015.dta", clear  
    // keep only 1980+, age in range, non-outlier with raw data and a non-zero samplesize
	keep if year>=1980
	drop if age_group_id>16
	drop if cf_corr==.
	drop if sample_size==0
	gen deaths=cf_corr*sample_size
	collapse(sum) deaths sample_size, by(location_id year) fast
	merge m:1 location_id using "`indir'/iso3.dta", keep(3)nogen
	tempfile deaths
	save `deaths', replace
		
		
 // generate WHO notification and VR death-based CFR for SRs 31, 64 &103
	insheet using "who_measles_case_notifications.csv", comma names clear
	rename iso_code iso3
	keep iso3 v*
	reshape long v, i(iso3) j(year)
	rename v cases
	replace year=2020-year
		
	merge 1:1 iso3 year using `deaths', keep(3) nogen
	merge m:1 location_id using "sr_all.dta", keepusing(super_region) keep(3)nogen
		
	keep if super_region==64 | super_region==31 | super_region==103
	keep iso3 year deaths cases 
	gen cfr=deaths/cases
	drop if cfr>1

	drop cfr
	tempfile WHO
	save `WHO', replace

		
// pull in CFR data
	insheet using "measles_cfr_data_2010.csv", names clear
	rename countryiso3 iso3
	replace iso3="MHL" if iso3==""
		
		// format
		rename parametervalue cfr
		rename numerator deaths
		rename effectivesample cases
		rename hospitaly hospital
		rename outbreaky outbreak 
		rename midpointyearofdatacollection midpointyear
		gen urban=0
		replace urban=1 if urbanicitystring=="Urban"
		gen rural=0
		replace rural=1 if urbanicitystring=="Rural"
		gen mixed=0
		replace mixed=1 if urbanicitystring=="Mixed"
		keep iso3 year* age* mid* cfr deaths cases hospital outbreak urbanicitystring urban rural mixed
		tempfile cfr_GBD2010
		save `cfr_GBD2010', replace
		
		//add new cfrs from literature
		
		insheet using "measles_new cfrs_GBD2013.csv", names clear
		gen rural=1 if urbanicity==2
		replace rural=0 if urbanicity==.
		keep iso3 year* age* mid* cfr deaths cases hospital outbreak rural
		tempfile cfr_GBD2013
		save `cfr_GBD2013', replace
		
		//add on new cfrs from collaborators
		
		insheet using "gbd2013_measles_collab_1.csv", comma names clear
		drop if is_raw=="excluded_review"
		gen rural=0 if urbanicity==4
		rename year_midpoint midpointyear
		rename numerator deaths
		rename denominator cases
		gen cfr=deaths/cases
		keep iso3 year* age* mid* cfr deaths cases hospital outbreak rural 
		tempfile cfr_collab_1
		save `cfr_collab_1', replace
		
		insheet using "gbd2013_measles_collab_2.csv", comma names clear
		drop if data_status=="outlier"
		drop if issues=="duplicate" 
		gen rural=0 if urbanicity==4
		rename midpoint_yr_collection midpointyear
		gen deaths=numerator
	    rename denominator cases
		gen cfr=deaths/cases
		keep iso3 year* age* mid* cfr deaths cases hospital outbreak rural
		tempfile cfr_collab_2
		save `cfr_collab_2', replace
		
		use `cfr_GBD2010', clear
		append using `cfr_GBD2013'
		append using `cfr_collab_1'
		append using `cfr_collab_2'
		
	// add on WHO-derived cfrs
		
		append using `WHO'
		keep iso3 year* age* cases hosp mid* outb deaths rural
		
	// replace
		
		replace midpointyear=1980 if midpointyear<1980 & year==.
		replace year=midpointyear if year==.
		
	// get LDI covariate	
		merge m:1 iso3 year using `cfr_covs', keep(1 3) nogen
		
		gen cfr = deaths/cases
		drop if cfr>.4
		gen ln_cfr=ln(cfr)	
		replace hospital=0 if hospital==.
		replace outbreak=0 if outbreak==.
		replace rural=0 if rural==.
		duplicates drop iso3 year agestart ageend deaths cases, force
		drop if year<1980 | year>2015
		
		save "cfr_input_data_raw.dta", replace
	
	    merge m:1 iso3 using "sr_all.dta", keep(3)nogen
	    ** 95th percentile for super_region 64 = .025
	    drop if cfr>.025 & super_region==64
	
	
	// drop data from hill tribes or ethnic minorities 
	
	drop if iso3=="THA" & yearstart==1984
	drop if iso3=="ETH" & yearstart==1981
	drop if iso3=="IND" & yearstart==1991
	drop if iso3=="IND" & yearstart==1992 & cfr>0.15
	
	// drop data from Senegal which are from studies conducted in Ibel village (a remote village with difficult transportation), and an unspecified rural area (data collected by lay interviewers and no information on case definition)
	drop if iso3=="SEN" & midpointyear==1983
	drop if iso3=="SEN" & midpointyear==1985
	
	save "cfr_input_data_excluding_outliers.dta", replace
    
	drop ln_LDI ln_mal
	merge m:1 location_id year using `cfr_covs', keep(3) nogen
	
	log using "cfr_log_excluding_outliers.smcl", replace
	
	menbreg deaths ln_mal hospital outbreak rural, exposure(cases) || iso3:
	
	log close

        predict iso_RE, remeans reses(iso_RE_se)
		collapse (mean) iso_RE iso_RE_se, by(iso3 super_region)
		tempfile iso_RE
		save `iso_RE', replace
		
		bysort super_region: egen super_RE = mean(iso_RE)
		collapse (mean) super_RE, by (super_region)
		tempfile super_RE
		save `super_RE', replace
		
		use `iso_RE', clear
		preserve
		keep if iso3=="CHN"
		local iso_RE_CHN=iso_RE
		local iso_RE_se_CHN=iso_RE_se
		restore
		
		preserve
		keep if iso3=="MEX"
		local iso_RE_MEX=iso_RE
		local iso_RE_se_MEX=iso_RE_se
		restore
		
		preserve
		keep if iso3=="GBR"
		local iso_RE_GBR=iso_RE
		local iso_RE_se_GBR=iso_RE_se
		restore
		
		preserve
		keep if iso3=="USA"
		local iso_RE_USA=iso_RE
		local iso_RE_se_USA=iso_RE_se
		restore
		
		preserve
		keep if iso3=="BRA"
		local iso_RE_BRA=iso_RE
		local iso_RE_se_BRA=iso_RE_se
		restore
		
		preserve
		keep if iso3=="IND"
		local iso_RE_IND=iso_RE
		local iso_RE_se_IND=iso_RE_se
		restore
		
		preserve
		keep if iso3=="KEN"
		local iso_RE_KEN=iso_RE
		local iso_RE_se_KEN=iso_RE_se
		restore
		
		
		preserve
		keep if iso3=="JPN"
		local iso_RE_JPN=iso_RE
		local iso_RE_se_JPN=iso_RE_se
		restore
		
	
	    preserve
		keep if iso3=="SWE"
		local iso_RE_SWE=iso_RE
		local iso_RE_se_SWE=iso_RE_se
		restore
		
		preserve
		keep if iso3=="ZAF"
		local iso_RE_ZAF=iso_RE
		local iso_RE_se_ZAF=iso_RE_se
		restore
		

	// predict for all places
	use `population', clear
	collapse(sum)pop, by(location_id year)
	merge m:1 location_id using "sr_all.dta", keep(3) nogen
	merge m:1 location_id using "all_subnationals.dta" 
	
	merge m:1 iso3 year using `covs', keep(1 3) nogen
		

    merge m:1 iso3 using `iso_RE', nogen
	merge m:1 super_region using `super_RE', nogen	
	
	
	// missing country random effects are replaced with the average random effect at the global level (i.e., 0)
	replace iso_RE=0 if iso_RE==.
	// countries with missing standard errors are replaced with global standard deviation of the country random effects
	gen global_variance=_b[var(_cons[iso3]):_cons]
	gen global_sd=sqrt(global_variance)
	replace iso_RE_se = global_sd if missing(iso_RE_se)
	
	// missing subnational random effects and SEs are replaced with country random effects and SEs
	replace iso_RE=`iso_RE_CHN' if CHN_sub==1
	replace iso_RE_se=`iso_RE_se_CHN' if CHN_sub==1
	replace iso_RE=`iso_RE_IND' if IND_sub==1
	replace iso_RE_se=`iso_RE_se_IND' if IND_sub==1
	replace iso_RE=`iso_RE_GBR' if GBR_sub==1
	replace iso_RE_se=`iso_RE_se_GBR' if GBR_sub==1
	replace iso_RE=`iso_RE_MEX' if MEX_sub==1
	replace iso_RE_se=`iso_RE_se_MEX' if MEX_sub==1
	replace iso_RE=`iso_RE_USA' if USA_sub==1
	replace iso_RE_se=`iso_RE_se_USA' if USA_sub==1
	replace iso_RE=`iso_RE_BRA' if BRA_sub==1
	replace iso_RE_se=`iso_RE_se_BRA' if BRA_sub==1
	replace iso_RE=`iso_RE_KEN' if KEN_sub==1
	replace iso_RE_se=`iso_RE_se_KEN' if KEN_sub==1
	replace iso_RE=`iso_RE_JPN' if JPN_sub==1
	replace iso_RE_se=`iso_RE_se_JPN' if JPN_sub==1
	replace iso_RE=`iso_RE_SWE' if SWE_sub==1
	replace iso_RE_se=`iso_RE_se_SWE' if SWE_sub==1
	replace iso_RE=`iso_RE_ZAF' if ZAF_sub==1
	replace iso_RE_se=`iso_RE_se_ZAF' if ZAF_sub==1
	
		matrix m = e(b)'
		matrix m = m[1..(rowsof(m)-2),1]
		local covars: rownames m
		local num_covars: word count `covars'
		local betas
		forvalues j = 1/`num_covars' {
			local this_covar: word `j' of `covars'
			local betas `betas' b_`this_covar'
			}
		matrix C = e(V)
		matrix C = C[1..(colsof(C)-2), 1..(rowsof(C)-2)]
		drawnorm `betas', means(m) cov(C)
	
		local counter=0
		compress
		forvalues j = 1/1000 {
			local counter = `counter' + 1
			di in red `counter'
			quietly generate xb_d`j' = 0
			quietly replace xb_d`j'=xb_d`j'+b__cons[`j']
			quietly replace xb_d`j'=xb_d`j'+ln_mal*b_ln_mal[`j']
			quietly replace xb_d`j'=xb_d`j'+rnormal(iso_RE, iso_RE_se) 
			quietly rename xb_d`j' cfr_d`counter'
			quietly replace cfr_d`counter' = exp(cfr_d`counter')
		}
		
				
	save "cfr_draws_excluding_outliers.dta", replace 
	
** ************************************************************************************************************************
** Calculating deaths
** ************************************************************************************************************************
 use "cfr_draws_excluding_outliers.dta", clear
	drop if location_id==4749
	// rename cfr
	renvars cfr_d1-cfr_d1000 \ cfr_0-cfr_999
	merge m:m location_id year using "results/combined_cases_draws.dta", nogen
	renvars ensemble_d1-ensemble_d1000 \ cases_d0-cases_d999  
		
	// multiply cases and cfr at the draw level
	forvalues x=0(1)999 {
		gen deaths_d`x'=cases_d`x'*cfr_`x'
		drop cases_d`x' cfr_`x'
		}	
	renvars deaths_d0-deaths_d999 \ ensemble_d1-ensemble_d1000
	keep year iso3 location_id ensemble_d* 
	
	save "results/death_draws.dta", replace
	
	