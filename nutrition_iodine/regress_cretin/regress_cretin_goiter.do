
** Purpose: Predict cretinism prevalence from goiter prevalence 

// Prep STATA
	clear all
	set more off 
	set mem 1g
	cap restore, not 
	cap log close 
	
			
// Prep the cretinism data 
	insheet using "cretins_lit_review_data.csv", comma clear names 
	replace total_goiter_prev=goiter_prev if total_goiter_prev == .	

	replace total_goiter_prev = total_goiter_prev/100

	replace visible_prev = visible_prev/100
	
	replace cret_prev = cret_prev/100

	gen logit_total_goiter_prev=logit(total_goiter_prev)

	gen logit_visible_prev=logit(visible_prev)
	
	gen logit_cret_prev = logit(cret_prev)

// run the regression
	regress logit_visible_prev logit_total_goiter_prev

// predict for missing visible goiter prev
	predict pred_logit_visible_prev
	
	replace logit_visible_prev=pred_logit_visible_prev if logit_visible_prev==.

	tempfile cret_goit_data
	save `cret_goit_data', replace
	
// Prep the dismod output file
    use "goiter_84905.dta", clear
    keep if measure=="prevalence"
    drop if age_group_id>21
    keep location_id year_id age_group_id sex_id measure mean
    rename mean visible_prev
    gen logit_visible_prev = logit(visible_prev)
    gen logit_cret_prev =.
// merge on regions
    merge m:1 location_id using "region_sr.dta", keep(3)nogen
    tempfile dismod_goiter_prev
    save `dismod_goiter_prev', replace

// Prep the goiter file which we use as an indicator for countries with less than 20% total goiter 
    insheet using "idd_input_v12_with_grades.csv", comma clear names 
	keep country_iso3_code year_start year_end sex age_start age_end parameter_value grade_total
	keep if grade_total == 1
	gen year_id = year_start 
	drop year_start year_end 
	
    // Recode variables for merging with the dismod dataset so that years correspond 
	rename country_iso3_code iso3 
	replace year = 1990 if year <1995
	replace year = 1995 if year >=1995 & year <2000
	replace year = 2000 if year >= 2000 & year <2005
	replace year = 2005 if year >=2005 & year <2010
	
    // Just take the highest value in each country since we don't have a complete time series for each country
	collapse (max) parameter_value, by(iso3) 
	tempfile totgoit
	save `totgoit', replace 

// Prep the salt dataset 
	use "hh_iodized_salt_pc.dta", clear 
	rename mean_value hh_iodized_salt_pc
	keep if inlist(year_id, 1990, 1995, 2000, 2005, 2010, 2015) 
	
	// merge on regions
    merge m:1 location_id using "region_sr.dta", keepusing(ihme_loc_id) keep(3)nogen
    rename ihme_loc_id iso3
	keep iso3 location_id year_id hh_iodized_salt_pc
	tempfile salt
	save `salt', replace 	

// run the regression 
    use `cret_goit_data', clear
	log using "`log_fil'", replace
	regress logit_cret_prev logit_visible_prev
	cap log close
	
// Bring in the dismod dataset with transformed goiter prevalences and predict the logit cretinism prevalence 
	gen ref = 1
	drop sex
	gen sex=3
	append using `dismod_goiter_prev'
	
	predict pred_logit_cret_prev 
	gen inv_cret_prev = invlogit(pred_logit_cret_prev)
	rename inv_cret_prev pred_cret_prev 
	drop if ref==1
	
	rename ihme_loc_id iso3
// Merge on countries with total goiter 
	merge m:1 iso3 using `totgoit', nogen
	
// Keep ages 1-4
	keep if age_group_id == 5		
	
// Replace prevalence as zero in countries with less than 20% total goiter prevalence 
	replace pred_cret_prev = 0 if parameter_value < 0.2
	replace pred_cret_prev = 0 if goiter_prev == 0 	
	
// Merge on iodized salt data and set cretinism prev to zero for countries with greater than 90% salt iodization
	merge m:1 iso3 year_id using `salt', nogen
	replace pred_cret_prev = 0 if hh_iodized_salt_pc >= 0.9
	
// Replace cretinism as zero in high income countries 
   	replace pred_cret_prev = 0 if super_region_id==64
		
// Mark other regions as indicated in the UNICEF SOWC reports that have sufficient household salt iodization
	replace pred_cret_prev = 0 if (year_id == 2005 | year_id == 2010 | year_id == 2015) & (region_name == "Central Latin America" | region_name == "Central Europe" ///
	| region_name == "Southeast Asia" | region_name == "East Asia")  
	
	
// Drop missing data for BMU, PRI, India rural, India urban and ZAF subnationals. They are missing because we do not have dismod output for them.	
    drop if pred_cret_prev ==. 
	
   sort iso3 year_id
   save "cretin_prev.dta", replace

