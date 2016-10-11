// Date:February 25, 2016
// Purpose: Developing crosswalk for those DHS / other surveys where we just have spousal smoking and we want to shift 

***********************************************************************************
** SET UP
***********************************************************************************

// Set application preferences
	clear all
	set more off
	cap restore, not
	set maxvar 32700

// change directory
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}


	cap log close 

// Prepare location names & demographics for 2015

	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & inlist(level, 3, 4)

	keep ihme_loc_id location_id location_ascii_name super_region_name super_region_id region_name region_id

	tempfile countrycodes
	save `countrycodes', replace

// Set up locals 
	local data_dir "$prefix/WORK/05_risk/risks/smoking_shs/data/exp"
	local logs "H:/dismod_risks/smoking_shs/03_adjust/logs"
	local dismod_dir "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/"


***********************************************************************************
** CROSSWALK FOR SPOUSAL SMOKING TO GOLD STANDARD ANY SHS EXPOSURE IN HOUSEHOLD
***********************************************************************************


// 1) Prep raw data to be crosswalked 
	
	insheet using "`data_dir'/02_compile/unadjusted_compiled_estimates.csv", comma names clear 

	// treating children as women in the model?
	//drop if sex == "Both" & age_start >= 15 // for adults, running sex-specific models 
	gen sex_new = 2 if sex == "Female" 
	replace sex_new = 1 if sex == "Male"
	expand 2 if sex == "Both", gen(expanded)
	replace sex_new = 1 if sex == "Both" & expanded == 0 
	replace sex_new = 2 if sex == "Both" & expanded == 1 
	

	// child sex specifications 
	//replace sex_new = 3 if sex == "Both"
	//replace sex_new = 3 if age_start < 15

	drop sex 
	rename sex_new sex 

	// Create women, men and child dummies 
	gen adult_women = sex == 2 & age_start >= 15
	gen adult_men = sex == 1 & age_start >= 15
	gen children = age_start < 15

	merge m:1 location_id using `countrycodes', keep(3) nogen 

	// Calculate standard deviation for all data points so that 1,000 draws can be generated
		// standard error from upper and lower bounds
			replace standard_error = (upper - lower) / (2 * 1.96) if standard_error == .
		
		// Use Wilson's score interval to approximate standard error where we only have sample size
			gen approximated_se = standard_error == .
			replace standard_error = sqrt(1/sample_size * mean * (1 - mean) + 1/(4 * sample_size^2) * invnormal(0.975)^2) if standard_error == .
			

	// Logit transform proportion (dependent variable)
		gen logit_mean = logit(mean)
		replace logit_mean = logit(.01) if mean < .01
		replace logit_mean = logit(.99) if mean == 1

// Run crosswalk	
	// Children as baseline 

	levelsof sex, local(sexes) 

	tempfile compiled
	save `compiled', replace


	log using "`logs'/spousal_smoking_reg_results_updated.smcl", replace

		xi: mixed logit_mean i.cv_anybody_smoking*adult_men i.cv_anybody_smoking*adult_women cv_act_of_smoking || super_region_name: cv_act_of_smoking cv_anybody_smoking || region_name:cv_act_of_smoking cv_anybody_smoking || location_ascii_name: cv_act_of_smoking cv_anybody_smoking

		tempfile all 
		save `all', replace 

		predict bg*, reffect

		keep super_region_id super_region_name region_id region_name location_id location_ascii_name bg1 bg2 bg4 bg5 bg7 bg8 

		rename bg1 super_reffect_act
		rename bg2 super_reffect_anybody
		rename bg4 reg_reffect_act 
		rename bg5 reg_reffect_anybody 
		rename bg7 country_reffect_act
		rename bg8 country_reffect_anybody
			

		collapse (first) super_reffect_act super_reffect_anybody reg_reffect_act reg_reffect_anybody country_reffect_act country_reffect_anybody, by(super_region_id region_id location_id)
	
		tempfile reeffects_location
		save `reeffects_location', replace

			// Total cross walk to standard definition is sum of fixed effect coefficient of def plus random effect for age (one of bg1-bg10) plus supreregion re plus region re

				use `all', clear 
				** Extract coefficients

				// First extract def coefficient 

				mat b = e(b)' // ' creates columnar matrix rather than default row matrix by transposing
				
				// Coefficient for logit_mean: cv_anybody_smoking
				mat b1 =b[1,1]
				mat v = e(V)
				mat v1 = v[1,1]

				// Coefficient for logit_mean: cv_anybody_smoking*adult_men
				mat b2 = b[3,1] 
				mat v2 = v[3,3]

				// Coefficient for logit_mean: cv_anybody_smoking*adult_women
				mat b3 = b[6,1]
				mat v3 = v[6,6]

				// Coefficent for cv_act_of_smoking 
				mat b4 = b[7,1] 
				mat v4 = v[7,7]

			
				** Use the drawnorm function to create draws using the mean and standard deviations from the covariance matrix 

				forvalues i=1/4 { 
					clear 
					set obs 1000 
					drawnorm coeff`i', means(b`i') cov(v`i')
					gen id = _n
					tempfile coeff_`i'
					save `coeff_`i'', replace

				}

				use `coeff_1', clear
					
					forvalues i=2/4 {
						merge 1:1 id using `coeff_`i'', nogen
					}

 				order id coeff1 coeff2 coeff3 coeff4
 				rename coeff1 coeff_anybody
 				rename coeff2 coeff_anybody_men
 				rename coeff3 coeff_anybody_women
 				rename coeff4 coeff_act

 				gen sex = 1 
				reshape wide coeff*, i(sex) j(id)

				expand 2, gen(sex_new)
				replace sex = 2 if sex_new == 1 
				drop sex_new 

				foreach var of varlist coeff_anybody_men* { 
					replace `var' = 0 if sex == 2 
				}

				foreach var of varlist coeff_anybody_women* { 
					replace `var' = 0 if sex == 1 
				}

				tempfile feffects
				save `feffects', replace


// Apply regression results to non-gold standard data
	use `compiled', clear


	 ** 1,000 draws from normal distribution around raw mean	
			forvalues d = 1/1000 {
				quietly {
					gen double mean_`d' = exp(rnormal(ln(mean), ln(1+standard_error/mean)))
					replace mean_`d' = exp(rnormal(ln(0.999), ln(1+standard_error/0.999))) if mean == 1
					replace mean_`d' = exp(rnormal(ln(0.001), ln(1+standard_error/0.001))) if mean == 0
					gen double adjmean_`d' = .
				}
			}


		 //forvalues d = 1/1000 {
			//gen double mean_`d' = rnormal(mean, standard_deviation_new)
			//gen double adjmean_`d' = .
	//	}

	** Merge on fixed effects based on sex & random effects based on region and country
	merge m:1 sex using `feffects', nogen 

	merge m:m super_region_id region_id location_id using `reeffects_location', nogen
	//merge m:m region_id using `reeffects_location', nogen 
	//merge m:1 location_id using `reeffects_location', nogen 

	** If missing region effect, take average of regions in the same super-region

	foreach var in anybody act { 

		bysort super_region_id: egen mean_sr_`var' = mean(reg_reffect_`var')
		bysort super_region_id: replace reg_reffect_`var' = mean_sr_`var' if reg_reffect_`var' == 0 

	}


	//egen global_avg = mean(reg_reffect)
	//replace reg_reffect = global_avg if reg_reffect == . 


// CROSSWALK
	
	// Adjusting for two covariates: 
		// cv_anybody_smoking = adjusting for surveys where the question was just asked of whether a child's parent smokes or an individual's partner/spouse smokes
		// cv_act_of_smoking = adjusting for surveys where the question is just about whether someone you live with smokes, rather than whether they smoke regularly in your presence 
	
	levelsof sex, local(sexes)

		foreach sex of local sexes { 

			di in red `sex'

			if `sex' == 1 { 

				forvalues d = 1/1000 { 

					replace adjmean_`d' = invlogit((coeff_anybody`d' + coeff_anybody_men`d' + super_reffect_anybody + reg_reffect_anybody) * (0-cv_anybody_smoking) + logit(mean_`d')) if cv_anybody_smoking == 1 & cv_act_of_smoking == 0 & adult_men == 1

					replace adjmean_`d' = invlogit((coeff_act`d') * (0-cv_act_of_smoking) + logit(mean_`d')) if cv_act_of_smoking == 1 & cv_anybody_smoking == 0 & adult_men == 1 

					replace adjmean_`d' = invlogit((coeff_anybody`d' + coeff_anybody_men`d' + super_reffect_anybody +reg_reffect_anybody) * (0-cv_anybody_smoking) + (coeff_act`d') * (0-cv_act_of_smoking) + logit(mean_`d')) if cv_anybody_smoking == 1 & cv_act_of_smoking == 1 & adult_men == 1 

					}
				}

			// reference group 
			if `sex' == 2 { 

				forvalues d = 1/1000 { 
					
					replace adjmean_`d' = invlogit((coeff_anybody`d' + coeff_anybody_women`d' + super_reffect_anybody + reg_reffect_anybody) * (0-cv_anybody_smoking) + logit(mean_`d')) if cv_anybody_smoking == 1 & cv_act_of_smoking == 0 & adult_women == 1 

					replace adjmean_`d' = invlogit((coeff_act`d') * (0-cv_act_of_smoking) + logit(mean_`d')) if cv_act_of_smoking == 1 & cv_anybody_smoking == 0 & adult_women == 1 

					replace adjmean_`d' = invlogit((coeff_anybody`d' + coeff_anybody_women`d' + super_reffect_anybody + reg_reffect_anybody) * (0-cv_anybody_smoking) + (coeff_act`d') * (0-cv_act_of_smoking) + logit(mean_`d')) if cv_anybody_smoking == 1 & cv_act_of_smoking == 1 & adult_women == 1 

					}

			}
		}

	// Replace for children 

		forvalues d = 1/1000 { 

			replace adjmean_`d' = invlogit((coeff_anybody`d' + super_reffect_anybody + reg_reffect_anybody) * (0-cv_anybody_smoking) + logit(mean_`d')) if cv_anybody_smoking == 1 & cv_act_of_smoking == 0 & child == 1 

			replace adjmean_`d' = invlogit((coeff_act`d') * (0-cv_act_of_smoking) + logit(mean_`d')) if cv_act_of_smoking == 1 & cv_anybody_smoking == 0 & child == 1 

			replace adjmean_`d' = invlogit((coeff_anybody`d' + super_reffect_anybody + reg_reffect_anybody) * (0-cv_anybody_smoking) + (coeff_act`d') * (0-cv_act_of_smoking) + logit(mean_`d')) if cv_anybody_smoking == 1 & cv_act_of_smoking == 1 & child == 1 

		}



// Compute mean and 95% CI from draws
		egen adjusted_mean = rowmean(adjmean_*)
		egen adjusted_lower = rowpctile(adjmean_*), p(2.5)
		egen adjusted_upper = rowpctile(adjmean_*), p(97.5)
		gen adjusted_se = (adjusted_upper - adjusted_lower) / (2 * 1.96)

// Flag crosswalked datapoints 
	gen crosswalked = 1 if adjusted_mean != . 


****************

/*
// Graph outcomes -- this is when both are alternative definitions

	foreach var in adult_women adult_men children { 
		twoway scatter adjusted_mean mean if cv_anybody_smoking == 1 & cv_act_of_smoking == 1  & `var' == 1, mcolor(green) || line mean mean, title("Adjustment for `var'") lcolor(blue)
	}


// For high-income, have some studies where ask whether you live with a smoker 

	foreach var in adult_women adult_men {
		twoway scatter adjusted_mean mean if cv_anybody_smoking == 0 & cv_act_of_smoking == 1  & `var' == 1, mcolor(green) || line mean mean, title("Adjustment for `var'") 
	}

*/


// Replace mean and standard error for non-gold standard data points 
	replace standard_error = adjusted_se if adjusted_se != . 
	replace mean = adjusted_mean if adjusted_mean != . 
	replace lower = adjusted_lower if adjusted_lower != . 
	replace upper = adjusted_upper if adjusted_upper != . 

	// drop if age_start < 15 


// Drop GATS data (alternative definition - do your parents smoke) that was used to inform the crosswalk; only want to keep data on whether someone smoked in your home in your presence during the past 7 days 
	
	drop if regexm(file, "GLOBAL_YOUTH") & crosswalk == . 
	
// FORMAT FOR EPI UPLOADER 

	// Sex should be string for epi uploader 
	tostring sex, replace 
	replace sex = "Male" if sex == "1" 
	replace sex = "Female" if sex == "2" 
	replace sex = "Both" if sex == "3" 


	// Uncertainty
	replace uncertainty_type_value = . if uncertainty_type != "Confidence interval" 
	replace uncertainty_type_value = 95 if uncertainty_type == "Confidence interval"
	replace upper = . if uncertainty_type != "Confidence interval"
	replace lower = . if uncertainty_type != "Confidence interval"

	gen source_type = 26 
	label define source 26 "Survey - other/unknown" 
	label values source_type source
	rename sample_size effective_sample_size

	gen measure = "proportion"
	gen unit_value_as_published = 1 
	gen extractor = "lalexan1" 
	gen is_outlier = 0 
	gen underlying_nid = . 
	gen sampling_type = "" 
	gen recall_type = "Point" 
	gen recall_type_value = "" 
	gen unit_type = "Person" 
	gen input_type = "" 
	gen sample_size = . 
	gen cases = . 
	gen design_effect = . 
	gen site_memo = "" 
	gen case_name = "" 
	gen case_diagnostics = "" 
	gen response_rate = .
	gen note_SR = "" 
	gen note_modeler = "" 
	gen row_num = . 
	gen parent_id = . 
	gen data_sheet_file_path = "" 
	gen description = "GBD 2015: smoking_shs"


	replace uncertainty_type_value = . if lower == . 
		
	keep row_num description measure	nid	file location_name	location_id	location_name	/// 
	sex	year_start	year_end	age_start	age_end	measure	mean	lower	upper	standard_error	effective_sample_size	/// 
	orig_unit_type	uncertainty_type uncertainty_type_value	representative_name	urbanicity_type	case_definition	extractor ///
	unit_value_as_published cv_not_represent	cv_exp_work_home cv_exp_indoor_outdoor source_type is_outlier underlying_nid /// 
	sampling_type recall_type recall_type_value unit_type input_type sample_size cases design_effect site_memo case_name /// 
	case_diagnostics response_rate note_SR note_modeler data_sheet_file_path parent_id


	order row_num description measure	nid	file location_name	location_id	location_name	/// 
	sex	year_start	year_end	age_start	age_end	measure	mean	lower	upper	standard_error	effective_sample_size	/// 
	orig_unit_type	uncertainty_type uncertainty_type_value	representative_name	urbanicity_type	case_definition	extractor /// 
	unit_value_as_published cv_not_represent	cv_exp_work_home cv_exp_indoor_outdoor source_type is_outlier underlying_nid /// 
	sampling_type recall_type recall_type_value unit_type input_type sample_size cases design_effect site_memo case_name /// 
	case_diagnostics response_rate note_SR note_modeler data_sheet_file_path parent_id

	tempfile whole_dataset
	save `whole_dataset', replace

	
	// MALES // 
	preserve

	keep if age_end > 20 & sex == "Male" 

	gen modelable_entity_id = 2512 
	gen modelable_entity_name = "smoking_shs_men"

	export excel using "`dismod_dir'/2512/input_data/gbd2015_smoking_shs$S_DATE.xlsx", firstrow(variables) sheet("extraction") replace
	
	// FEMALES // 

	restore
	
	keep if sex == "Female" // includes children and adult women 

	gen modelable_entity_id = 9419 
	gen modelable_entity_name = "smoking_shs_female"

	export excel using "`dismod_dir'/9419/input_data/gbd2015_smoking_shs$S_DATE.xlsx", firstrow(variables) sheet("extraction") replace

/*

	// CHILDREN // 

	restore

	keep if age_start < 15 

	gen modelable_entity_id = 9418
	gen modelable_entity_name = "smoking_shs_child"

	export excel using "`dismod_dir'/9418/input_data/gbd2015_smoking_shs$S_DATE.xlsx", firstrow(variables) sheet("extraction") replace


// Save another dataset in second hand smoke folder that has a sheet with variable definitions
	//export excel using "`outdir'/compiled_adult_revised.xlsx", firstrow(variables) sheet("Data") sheetreplace
