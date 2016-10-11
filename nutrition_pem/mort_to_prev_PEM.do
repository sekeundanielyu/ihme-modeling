** Purpose: calculate prevalence of PEM from deaths, duration & CFR


// settings
	clear all
	set mem 700m
	set more off
	set maxvar 8000
	cap restore, not

// Define J drive (data) for cluster (UNIX) and Windows (Windows)
				if c(os) == "Unix" {
					global prefix "/home/j"
					set odbcmgr unixodbc
				}
				else if c(os) == "Windows" {
					global prefix "J:"
				}			

	
	// gbd cause (acause)
				local acause nutrition_pem
							
			// locals 
				local model_version_id v1
				local measure prevalence
				local measure_id 5
				
			// Make folders to store COMO files
		
					
        capture mkdir "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws"
		capture mkdir "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`model_version_id'"
		capture mkdir "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`model_version_id'/marasmus"
		capture mkdir "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`model_version_id'/kwashiorkor"	
		
	// locals
    local acause nutrition_pem
	local version 02
	local deaths    "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015/temp/codcorrect_draws.dta" 
	local cfr 		"$prefix/Project/GBD/mort_to_prev/data/PEM_cfr_draws.csv"
	local dur 		"$prefix/Project/GBD/mort_to_prev/data/duration_draws.csv"
	local pop 		"$prefix/WORK/04_epi/01_database/02_data/nutrition_pem/GBD2015/data/pop_data_all.dta"	
	local savedir 	"/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws"
	capture mkdir "`savedir'"


	local make_graphs 0
	

	
** ************* ************* ************* ************* ************* ***********
					// GENERATE CASE FATALITY DRAWS
** ************* ************* ************* ************* ************* ***********

	clear
	set obs 1
// make mean case fatality rate: the CFR is from Lapidus et al
	gen effsize = 		0.044718581
// make variables for the upper and lower CIs of the CFR
	gen effsize_l =		0.03822424
	gen effsize_u =		0.051212923
	
	expand 1000
	gen num = _n - 1
	
// log transform for taking draws (don't want CFR draws to be below 0)
	gen lt_effsize = 		logit(effsize)
	gen lt_effsize_l = 		logit(effsize_l)
	gen lt_effsize_u = 		logit(effsize_u)
	
// calculate the sd from the confidence intervals
	gen lt_diff_upper_effsize = 	lt_effsize - lt_effsize_l 								// median-lower
	gen lt_diff_lower_effsize = 	lt_effsize_u - lt_effsize 								// upper-median
	gen lt_sd_effsize = 			(lt_diff_lower_effsize + lt_diff_upper_effsize) / 2
	replace lt_sd_effsize = 		lt_sd_effsize / invnorm(0.975) 							// invnorm(.975) yields the critical value 1.96
	
// simulate to make draws of the CFR
	gen effsizesims = 		rnormal(lt_effsize, lt_sd_effsize)
	replace effsizesims = 	invlogit(effsizesims)
	
	
// reshape so that can merge with rest of data
	drop lt_* effsize effsize_*
	gen draw = 1
	reshape wide effsizesims, i(draw) j(num)
	drop draw
	forvalues n = 0/999 {
		rename effsizesims`n' cfr`n'
	}
	gen year_id = 1990
	expand 6, gen(d)
	replace year_id = 1995 if _n == 2
	replace year_id = 2000 if _n == 3
	replace year_id = 2005 if _n == 4
	replace year_id = 2010 if _n == 5
	replace year_id = 2015 if _n == 6
	order year_id
	drop d
	gen cause = "A18.1.a"
	
	save "`savedir'/cfr_draws.dta", replace
	

** ****************************************************************************************************
			// GENERATE DURATION DRAWS
** ****************************************************************************************************

	clear
	set obs 1
// make a variable that has mean duration: the duration is from Isanaka et al.
	gen effsize = 		0.123203285  // this number is the number of days duration (as provided by the paper = 45) divided by 365.25
// make variables for the upper and lower CIs of the duration
	gen effsize_l =		0.084873374
	gen effsize_u =		0.186173854
	
	expand 1000
	gen num = _n - 1
	
// log transform for taking draws (don't want duration to be below 0)
	gen ln_effsize = 		ln(effsize)
	gen ln_effsize_l = 		ln(effsize_l)
	gen ln_effsize_u = 		ln(effsize_u)
	
// calculate the sd from the confidence intervals
	gen ln_diff_upper_effsize = 	ln_effsize - ln_effsize_l 								// median-lower
	gen ln_diff_lower_effsize = 	ln_effsize_u - ln_effsize 								// upper-median
	gen ln_sd_effsize = 			(ln_diff_lower_effsize + ln_diff_upper_effsize) / 2
	replace ln_sd_effsize = 		ln_sd_effsize / invnorm(0.975) 							// invnorm(.975) yields the critical value 1.96
	
// simulate to make draws of the duration
	gen effsizesims = 		rnormal(ln_effsize, ln_sd_effsize)
// take back out of log space
	replace effsizesims = 	exp(effsizesims)
	
// reshape so that can merge with rest of data
	drop ln_* effsize effsize_*
	gen draw = 1
	reshape wide effsizesims, i(draw) j(num)
	drop draw
	forvalues n = 0/999 {
		rename effsizesims`n' dur`n'
	}
	gen year_id = 1990
	expand 6, gen(d)
	replace year_id = 1995 if _n == 2
	replace year_id = 2000 if _n == 3
	replace year_id = 2005 if _n == 4
	replace year_id = 2010 if _n == 5
	replace year_id = 2015 if _n == 6
	order year_id
	drop d
	gen cause = "A18.1.a"
	
	save "`savedir'/duration_draws.dta", replace
		
	
** ************* ************* ************* ************* ************* ***********
					// PREP DEATH DRAWS
** ************* ************* ************* ************* ************* ***********

	use "`deaths'", clear
	keep if metric_id==1
	drop rei_id metric_id measure_id
	/*
	tostring age, replace force format(%12.3f)
	destring age, replace force
	*/	
// clean up age groups	
	
	drop if age == 97 // this is all under 5
	drop if age == 99 // this is all ages
	
// no deaths from PEM under age .1
	drop if age < 3
	
// merge with pop/deaths envelope file
	merge 1:1 location_id year age sex using "`pop'"
	drop if _m != 3 
	drop _m
	
// calculate death rate from death draws divided by total population
	forvalues n = 0/999 {
		gen mort_`n' = draw_`n' / mean_pop
	}
	drop draw*

	gen cause="A18.1.a"
	tempfile mort_draws
	save `mort_draws', replace
	
	

** ************* ************* ************* ************* ************* ***********
					// BRING EVERYTHING TOGETHER & CALCULATE PREV
** ************* ************* ************* ************* ************* ***********
	use `mort_draws', clear
	merge m:1 cause year using "`savedir'/cfr_draws.dta", nogen
	merge m:1 cause year using "`savedir'/duration_draws.dta", nogen
	
// prevalence = (mortality rate/case_fatality) * duration
	forvalues n = 0/999 {
		gen draw_`n' = (mort_`n' / cfr`n') * dur`n'
			}
	
	keep location_id year age sex draw*
	egen pem_prev_mean = rowmean(draw_*)
	egen pem_prev_lci = rowpctile(draw_*), p(2.5)
	egen pem_prev_uci = rowpctile(draw_*), p(97.5)
	
// save the file
		/* keep iso year age sex *mean *lci *uci */
		save "`savedir'/PEM_prevalence_draws_`model_version_id'.dta", replace

** *********************************************************************************
//  Assign proportions to marasmus and kwashiorkor
	
	use "`savedir'/PEM_prevalence_draws_`model_version_id'.dta", clear
	drop *mean *lci *uci 
	
	preserve

	
	foreach draw of varlist draw_* {
	  // 96.6% of PEM cases assigned to marasmus for age <1 yr 
		replace `draw' = `draw'*0.966 if age <=4
	  //92.6% of PEM cases assigned to marasmus for 1-4yrs 
		replace `draw' = `draw'*0.926 if age==5
		}
	  //replace negative values with zeros
		foreach a of varlist draw_0-draw_999 {
		replace `a'=0 if `a'<0
	}
	
	gen modelable_entity_id=1607
	save "`savedir'/marasmus_draws_`model_version_id'.dta", replace
	
	restore
	preserve
	foreach draw of varlist draw_* {
	// 3.4% of PEM cases assigned to kwashiorkor for age <1 yr 
		replace `draw' = `draw'*0.034 if age <=4
	// 7.4% of PEM cases assigned to kwashiorkor for 1-4yrs
		replace `draw' = `draw'*0.074 if age==5
	// for ages 5yrs and over, kwashiorkor is no longer considered a sequela
		replace `draw' = `draw'*0 if age >5
		}
    //replace negative values with zeros
		foreach a of varlist draw_0-draw_999 {
		replace `a'=0 if `a'<0
	}
	gen modelable_entity_id=1606
	save "`savedir'/kwashiorkor_draws_`model_version_id'.dta", replace
	
** *********************************************************************************
// Format for como

	use "`savedir'/marasmus_draws_`model_version_id'.dta", clear
	gen measure_id=5
	
	levelsof(location_id), local(ids) clean
	levelsof(year_id), local(years) clean

global sex_id "1 2"

foreach location_id of local ids {
		foreach year_id of local years {
			foreach sex_id of global sex_id {
					qui outsheet if location_id==`location_id' & year_id==`year_id' & sex_id==`sex_id' using "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`model_version_id'/marasmus/`measure_id'_`location_id'_`year_id'_`sex_id'.csv", comma replace
				}
			}
		}
	
	
	use "`savedir'/kwashiorkor_draws_`model_version_id'.dta", clear
	gen measure_id=5
	
	levelsof(location_id), local(ids) clean
	levelsof(year_id), local(years) clean

global sex_id "1 2"

foreach location_id of local ids {
		foreach year_id of local years {
			foreach sex_id of global sex_id {
					qui outsheet if location_id==`location_id' & year_id==`year_id' & sex_id==`sex_id' using "/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`model_version_id'/kwashiorkor/`measure_id'_`location_id'_`year_id'_`sex_id'.csv", comma replace
				}
			}
		}
		
		
// save results and upload
	
	
	do /home/j/WORK/10_gbd/00_library/functions/save_results.do
    save_results, modelable_entity_id(1607) description(marasmus prevalence `model_version_id') mark_best(yes) in_dir(/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`model_version_id'/marasmus) metrics(prevalence)

	
	do /home/j/WORK/10_gbd/00_library/functions/save_results.do
    save_results, modelable_entity_id(1606) description(kwashiorkor prevalence`model_version_id') mark_best(yes) in_dir(/ihme/gbd/WORK/04_epi/01_database/02_data/`acause'/temp/draws/`model_version_id'/kwashiorkor) metrics(prevalence)

	
	


