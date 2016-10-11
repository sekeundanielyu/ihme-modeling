** DATE: 20 April 2011 
** OUTLINE OF CODE: 
** 	Prep 
** 		- load GPR estimates and sims
** 		
** 	
** 		
** 	Get sex-specific estimates
** 		- merge on sex model coefficients
** 		- calculate sex-ratio 
** 		- calculate male and female 5q0 for each simulation 
** 		
** 	Get age-specific estimates
** 		- merge on age model coefficients for each model 
** 		- calculate each probability 
** 		- scale probabilities (first infant-child, then enn-lnn-pnn) 
** 		- convert to q-space to get the sex-specific estiamtes for each age
** 		- combine sex-specific estimates for each age to get both sexes estimates 
** 		- scale both sexes estimate to the 5q0(both) estimate for that simulation 
** 		- calculate rates of change for each age group 
** 			 
** 	Collapse
** 		- collapse to find mean and 2.5 and 97.5 percentiles 
** 		


** ***************************	
** Prep
** ***************************
	
	clear all 
	set more off
	pause on
	capture log close
	local test = 0
	
	if (c(os)=="Unix") {
		** global arg gets passed in from the shell script and is parsed to get the individual arguments below
		local jroot ""
		set odbcmgr unixodbc
		local code_dir "`1'"
		local ihme_loc_id "`2'"
		local ctemp "`3'"
		local location_id `4'
		local output_version_id `5'
		
		if (`test' == 1) {
			local code_dir ""
			local ihme_loc_id "IND_43901"
			local ctemp = 1
		}
		
		if ("`ctemp'" == "1") {
			global root ""
		} 
		else {
			global root "`jroot'"
		}
		local child_dir ""
		qui do "get_locations.ado"
	} 
	if (c(os)=="Windows") { 
		global root ""
		local jroot ""
		local ihme_loc_id "IND"
		local child_dir ""
		qui do "get_locations.ado"
	}
	
	
	
	di "$arg"
	di "`ihme_loc_id'"

	cd ""
	global pop_file "population_gbd2015.dta"
	global births_file "births_gbd2015.dta"
	
	insheet using "modeling_hierarchy.csv", clear
	if ("`ihme_loc_id'" != "IND" & "`ihme_loc_id'" != "GBR") keep if parent_id == `location_id'
	if ("`ihme_loc_id'" == "IND") keep if level_3 == 1 & regexm(path_to_top_parent,",163,")
	if ("`ihme_loc_id'" == "GBR") keep if level_3 == 1 & regexm(path_to_top_parent,",95,")
	if (_N > 0) {
		levelsof location_id, local(subnat_shocks)
		local need_subnat_shocks = 1
	}
	else {
		local need_subnat_shocks = 0
	}
	

** save GPR 5q0 estimates for later use
	insheet using "`child_dir'/results/estimated_5q0_noshocks.txt", clear
	
	keep if ihme_loc_id == "`ihme_loc_id'"
	drop if year > 2015.5 | year < 1949.5	
	rename med q5med
	rename lower q5lower
	rename upper q5upper
	keep ihme_loc_id year q5* 
	isid ihme_loc_id year
	tempfile estimates
	save `estimates', replace
	
** get sex-ratios at birth 
	use "$births_file", clear
	keep if ihme_loc_id == "`ihme_loc_id'"	
	keep ihme_loc_id year sex births
	reshape wide births, i(ihme_loc_id year) j(sex, string)
	gen birth_sexratio = birthsmale/birthsfemale
	keep ihme_loc_id year birth_sexratio
	replace year = year + 0.5
	replace birth_sexratio = 1.05 if birth_sexratio == . 
	tempfile sex_ratio
	save `sex_ratio', replace 

** ***************************	
** Load sims from GPR
** ***************************
	insheet using "gpr_`ihme_loc_id'_sim.txt", clear 
	rename sim simulation
	rename mort q5_both
	drop if year > 2015.5 | year < 1949.5
	
	cap rename iso3 ihme_loc_id
	duplicates drop ihme_loc_id year simulation, force

	tempfile sims
	save `sims', replace 
	
** ***************************	
** Produce estimates from sex-model 
** ***************************
	
** merge simulated 5q0(both)'s with the sex model parameters 
	merge m:1 ihme_loc_id simulation using "data/fit_models/sex_model_simulated_parameters_other.dta"
	drop if _m == 2
	drop _m 
	
	tostring q5_both, gen(merge_q5_both) format(%9.3f) force
	merge m:1 merge_q5_both simulation using "data/fit_models/sex_model_simulated_parameters_bins.dta"
	drop if _m == 2
	drop _m merge_q5_both

** merge in birth sex-ratios 
	merge m:1 ihme_loc_id year using `sex_ratio'
	drop if _merge==2
	replace birth_sexratio=1.05 if _merge==1
	drop _merge 

** calculate predicted sex-ratio    
	gen q5_sexratio_pred = exp(intercept + regbd + reiso + rebin)

** generate predicted values using sex ratio at birth 
	gen q5_female = (q5_both*(1+birth_sexratio))/(1+q5_sexratio_pred*birth_sexratio)
	gen q5_male = q5_female*q5_sexratio_pred
	assert q5_female > 0
	assert q5_male > 0

** formatting
	drop q5_sexratio_pred
	keep ihme_loc_id year q5_* simulation birth_sexratio 
	renpfix q5_ q5
	reshape long q5, i(ihme_loc_id year simulation) j(sex, string)
	order ihme_loc_id year simulation sex q5
	sort ihme_loc_id year simulation
	isid ihme_loc_id year sex simulation
	gen log_q_u5 = log(q5)
	rename q5 q_u5_ 

** ***************************
** Produce estimates from age model 
** ***************************	

** merge simulated 5q0(both)'s with the age model parameters 
	merge m:1 ihme_loc_id simulation using "data/fit_models/age_model_simulated_parameters_other.dta"
	drop if _m == 2 
	drop _m 
	
	tostring log_q_u5, gen(merge_log_q_u5) format(%9.2f) force
	merge m:1 merge_log_q_u5 simulation using "data/fit_models/age_model_simulated_parameters_bins.dta"
	drop if _m == 2
	drop _m merge_log_q_u5
	gen yearmerge = round(year)
	tempfile tomerge
	save `tomerge', replace

** Load in HIV term info and maternal ed
	insheet using "`child_dir'/data/prediction_input_data.txt", clear	
	keep ihme_loc_id year hiv maternal_educ
	rename maternal_educ m_educ
	gen yearmerge = round(year)
	duplicates drop
	merge 1:m ihme_loc_id yearmerge using `tomerge'
	keep if _merge == 3
	drop _merge yearmerge
	
** Produce estimates for each age and sex 
	foreach age in enn lnn pnn inf ch { 
		gen pred_`age' = . 
		foreach sex in male female { 
			replace pred_`age' = intercept_`age'_`sex' + regbd_`age'_`sex' + reiso_`age'_`sex' + rebin_`age'_`sex' + error_`age'_`sex' + hiv*hivcoeff_`age'_`sex' + m_educ*m_educcoeff_`age'_`sex' + 1*s_compcoeff_`age'_`sex' if sex == "`sex'"
		} 
		replace pred_`age' = exp(pred_`age')
	} 
	keep ihme_loc_id year simulation sex birth_sexratio q_u5_ pred*
	
** Scaling and both sex-estimates 
	** scale (this scales within each simulation, for males and females)
		gen scale = pred_inf + pred_ch 
		foreach var in pred_inf pred_ch {
			replace `var' = `var'/scale 
		}
		drop scale 
		
		gen scale = (pred_enn + pred_lnn + pred_pnn) / pred_inf
		foreach var in pred_enn pred_lnn pred_pnn { 
			replace `var' = `var'/scale 
		} 
		drop scale 
		
	** output some results in the space of the model for diagnostic purposes
	preserve
	sort ihme_loc_id sex year simulation 
	isid ihme_loc_id sex year simulation 
	drop q*
	
	foreach pred in enn lnn pnn inf ch { 	
		noisily: di "`pred'"
		by ihme_loc_id sex year: egen pred_`pred'_med = mean(pred_`pred')
		by ihme_loc_id sex year: egen pred_`pred'_lower = pctile(pred_`pred'), p(2.5)
		by ihme_loc_id sex year: egen pred_`pred'_upper = pctile(pred_`pred'), p(97.5)
		drop pred_`pred'
	}	
	
	drop simulation
	order ihme_loc_id sex year pred* 
	duplicates drop
	isid ihme_loc_id sex year
	saveold "`ihme_loc_id'_modelspace_sims.dta", replace
	restore
			
	** convert to q-space (for each simulation, for males and females) 
		gen q_enn_ = (q_u5_ * pred_enn)
		gen q_lnn_ = (q_u5_ * pred_lnn) / ((1-q_enn_))
		gen q_pnn_ = (q_u5_ * pred_pnn) / ((1-q_enn_)*(1-q_lnn_))
		gen q_ch_  = (q_u5_ * pred_ch)  / ((1-q_enn_)*(1-q_lnn_)*(1-q_pnn_))
		gen q_inf_ = (q_u5_ * pred_inf)	
		drop pred*
		
	** generate estimates for both sexes combined (for each simulation) 
		reshape wide q_enn_ q_lnn_ q_pnn_ q_ch_ q_inf_ q_u5_, i(ihme_loc_id year simulation birth_sexratio) j(sex, string) 
		
		** ratio of live males to females at the beginning of each period 
		gen r_enn = birth_sexratio 
		gen r_lnn = r_enn*(1-q_enn_male)/(1-q_enn_female)
		gen r_pnn = r_lnn*(1-q_lnn_male)/(1-q_lnn_female)
		gen r_ch  = r_pnn*(1-q_pnn_male)/(1-q_pnn_female)
		
		replace q_enn_both = (q_enn_male) * (r_enn/(1+r_enn)) + (q_enn_female) * (1/(1+r_enn))
		replace q_lnn_both = (q_lnn_male) * (r_lnn/(1+r_lnn)) + (q_lnn_female) * (1/(1+r_lnn)) 
		replace q_pnn_both = (q_pnn_male) * (r_pnn/(1+r_pnn)) + (q_pnn_female) * (1/(1+r_pnn)) 
		replace q_ch_both  = (q_ch_male)  * (r_ch/(1+r_ch))   + (q_ch_female)  * (1/(1+r_ch)) 
		replace q_inf_both = (q_inf_male) * (r_enn/(1+r_enn)) + (q_inf_female) * (1/(1+r_enn))
			
	** scale each estimate for both sexes combined (for each simulation) 
		gen prob_enn_both = q_enn_both/q_u5_both					
		gen prob_lnn_both = (1-q_enn_both)*q_lnn_both/q_u5_both 			
		gen prob_pnn_both = (1-q_enn_both)*(1-q_lnn_both)*q_pnn_both/q_u5_both					
		gen prob_ch_both  = (1-q_enn_both)*(1-q_lnn_both)*(1-q_pnn_both)*q_ch_both/q_u5_both	
		gen prob_inf_both = q_inf_both/q_u5_both 

		gen scale = prob_inf_both + prob_ch_both
		replace prob_inf_both = prob_inf_both / scale
		replace prob_ch_both = prob_ch_both / scale 
		drop scale 
		
		gen scale = (prob_enn_both + prob_lnn_both + prob_pnn_both) / prob_inf_both
		foreach age in enn lnn pnn { 
			replace prob_`age'_both = prob_`age'_both / scale
		} 
		drop scale 
		
		replace q_enn_both = (q_u5_both * prob_enn_both)
		replace q_lnn_both = (q_u5_both * prob_lnn_both) / ((1-q_enn_both))
		replace q_pnn_both = (q_u5_both * prob_pnn_both) / ((1-q_enn_both)*(1-q_lnn_both))
		replace q_inf_both = (q_u5_both * prob_inf_both) 
		replace q_ch_both  = (q_u5_both * prob_ch_both)  / ((1-q_enn_both)*(1-q_lnn_both)*(1-q_pnn_both))	

** Some formatting
	drop prob* r*

	reshape long q_enn q_lnn q_pnn q_inf q_ch q_u5, i(ihme_loc_id year simulation birth_sexratio) j(sex, string)
	replace sex = subinstr(sex, "_", "", 1)
	isid ihme_loc_id year sex simulation 
	
** Generate neonatal estimates
	gen q_nn = 1 - (1-q_enn)*(1-q_lnn)
	
** Save simulations 
	preserve
	keep ihme_loc_id year sex simulation q_enn q_lnn q_nn q_pnn q_inf q_ch q_u5
	gen rat_enn = q_enn/q_u5
	gen rat_lnn = q_lnn/q_u5
	gen rat_nn = q_nn/q_u5
	gen rat_pnn = q_pnn/q_u5
	gen rat_inf = q_inf/q_u5
	gen rat_ch = q_ch/q_u5
	sort ihme_loc_id sex year
	
	foreach rat in enn lnn nn pnn inf ch { 	
		noisily: di "`rat'"
		by ihme_loc_id sex year: egen rat_`rat'_lower = pctile(rat_`rat'), p(2.5)
		by ihme_loc_id sex year: egen rat_`rat'_upper = pctile(rat_`rat'), p(97.5)
		drop rat_`rat'
	}	
	
	drop simulation
	order ihme_loc_id sex year rat* 
	drop q*
	duplicates drop
	isid ihme_loc_id sex year
	saveold "`ihme_loc_id'_rat_uncert.dta", replace
	
	restore, preserve
	
	keep ihme_loc_id year sex simulation q_enn q_lnn q_pnn q_ch q_u5
	saveold "`ihme_loc_id'_noshocks_sims.dta", replace
	restore
	
** Calculate rates of decline 
	sort simulation ihme_loc_id sex year
		** 1970 = line 21
		** 1990 = line 41
		** 2008 = line 59 
		** 2010 = line 61
	foreach q in enn lnn nn pnn inf ch u5 { 
		by simulation ihme_loc_id sex: gen change_`q'_70_90 = -100*ln(q_`q'[41]/q_`q'[21])/(1990-1970) 
		by simulation ihme_loc_id sex: gen change_`q'_90_10 = -100*ln(q_`q'[61]/q_`q'[41])/(2010-1990)
		by simulation ihme_loc_id sex: gen change_`q'_90_08 = -100*ln(q_`q'[59]/q_`q'[41])/(2008-1990)
	} 	

** ***************************
** Collapse and force consistency in final estimates 
** ***************************		

** Collapse across to find the 2.5 and 97.5 percentiles and mean in all qx estimates and rates of change, by sex, country, and year
	sort ihme_loc_id sex year simulation 
	isid ihme_loc_id sex year simulation 
	
	foreach q in enn lnn nn pnn inf ch u5 { 	
		noisily: di "`q'"
		by ihme_loc_id sex year: egen q_`q'_med = mean(q_`q')
		by ihme_loc_id sex year: egen q_`q'_lower = pctile(q_`q'), p(2.5)
		by ihme_loc_id sex year: egen q_`q'_upper = pctile(q_`q'), p(97.5)
		drop q_`q'
	
		foreach date in 70_90 90_10 90_08 { 
			noisily: di "`date'"
			by ihme_loc_id sex: egen change_`q'_`date'_med = mean(change_`q'_`date')
			by ihme_loc_id sex: egen change_`q'_`date'_lower = pctile(change_`q'_`date'), p(2.5)
			by ihme_loc_id sex: egen change_`q'_`date'_upper = pctile(change_`q'_`date'), p(97.5)
			drop change_`q'_`date'
		} 
	}	
	
	drop simulation
	order ihme_loc_id sex year birth_sexratio q* change*
	duplicates drop
	isid ihme_loc_id sex year

** Merge on GPR 5q0; replace the combined 5q0 estimates with these 
	merge m:1 ihme_loc_id year using `estimates'
	foreach est in med lower upper { 
		replace q_u5_`est' = q5`est' if sex == "both"
	} 
	drop q5* _m
	
	preserve
	drop *lower *upper
	rename *med *med_prescale
	tempfile prescale
	save `prescale', replace
	restore
	
** Force consistency in the male and female 5q0 with the combined 5q0 (medium estimates only) 
	sort ihme_loc_id year sex
	by ihme_loc_id year: gen scale = q_u5_med[1] / (q_u5_med[3]*(birth_sexratio/(1+birth_sexratio)) + q_u5_med[2]*(1/(1+birth_sexratio)))
	replace q_u5_med = q_u5_med*scale if sex!="both"
	gen scale_sexes_u5_to_both_u5 = scale
	gen srb = birth_sexratio
	drop scale
	
** Force consistency in the enn, lnn, nn, pnn, inf, and ch estimates for males and females (medium estimates only) 
	gen prob_enn_med = q_enn_med/q_u5_med					
	gen prob_lnn_med = (1-q_enn_med)*q_lnn_med/q_u5_med 			
	gen prob_pnn_med = (1-q_enn_med)*(1-q_lnn_med)*q_pnn_med/q_u5_med					
	gen prob_ch_med  = (1-q_enn_med)*(1-q_lnn_med)*(1-q_pnn_med)*q_ch_med/q_u5_med	
	gen prob_inf_med = q_inf_med/q_u5_med 
		
	gen scale = prob_inf_med + prob_ch_med
	replace prob_inf_med = prob_inf_med / scale
	replace prob_ch_med = prob_ch_med / scale 
	gen scale_mf_infch_u5 = scale
	drop scale 
	
	gen scale = (prob_enn_med + prob_lnn_med + prob_pnn_med) / prob_inf_med
	foreach age in enn lnn pnn { 
		replace prob_`age'_med = prob_`age'_med / scale
	} 
	gen scale_mf_ennlnnpnn_inf = scale
	drop scale 
	
	replace q_enn_med = (q_u5_med * prob_enn_med)
	replace q_lnn_med = (q_u5_med * prob_lnn_med) / ((1-q_enn_med))
	replace q_pnn_med = (q_u5_med * prob_pnn_med) / ((1-q_enn_med)*(1-q_lnn_med))
	replace q_inf_med = (q_u5_med * prob_inf_med)
	replace q_ch_med  = (q_u5_med * prob_ch_med)  / ((1-q_enn_med)*(1-q_lnn_med)*(1-q_pnn_med))	
	replace q_nn_med  = 1-(1-q_enn_med)*(1-q_lnn_med)
	drop prob*
	
** Recalculate the both sexes combined estimates for enn, lnn, nn, pnn, inf, and child (medium estimates only) 
	sort ihme_loc_id year sex
	** ratio of live males to females at the beginning of each period 
	gen r_enn = birth_sexratio 
	by ihme_loc_id year: gen r_lnn = r_enn*(1-q_enn_med[3])/(1-q_enn_med[2])
	by ihme_loc_id year: gen r_pnn = r_lnn*(1-q_lnn_med[3])/(1-q_lnn_med[2])
	by ihme_loc_id year: gen r_ch  = r_pnn*(1-q_ch_med[3])/(1-q_ch_med[2])
	
	by ihme_loc_id year: replace q_enn_med = (q_enn_med[3]) * (r_enn/(1+r_enn)) + (q_enn_med[2]) * (1/(1+r_enn)) if _n == 1
	by ihme_loc_id year: replace q_lnn_med = (q_lnn_med[3]) * (r_lnn/(1+r_lnn)) + (q_lnn_med[2]) * (1/(1+r_lnn)) if _n == 1 
	by ihme_loc_id year: replace q_pnn_med = (q_pnn_med[3]) * (r_pnn/(1+r_pnn)) + (q_pnn_med[2]) * (1/(1+r_pnn)) if _n == 1
	by ihme_loc_id year: replace q_ch_med  = (q_ch_med[3])  * (r_ch/(1+r_ch))   + (q_ch_med[2])  * (1/(1+r_ch))  if _n == 1
	by ihme_loc_id year: replace q_inf_med = (q_inf_med[3]) * (r_enn/(1+r_enn)) + (q_inf_med[2]) * (1/(1+r_enn)) if _n == 1
	drop r* birth_sexratio
		
** Force consistency in the both sexes combined estimates (medium estimates only) 
	gen prob_enn_med = q_enn_med/q_u5_med					
	gen prob_lnn_med = (1-q_enn_med)*q_lnn_med/q_u5_med 			
	gen prob_pnn_med = (1-q_enn_med)*(1-q_lnn_med)*q_pnn_med/q_u5_med					
	gen prob_ch_med  = (1-q_enn_med)*(1-q_lnn_med)*(1-q_pnn_med)*q_ch_med/q_u5_med	
	gen prob_inf_med = q_inf_med/q_u5_med 
		
	gen scale = prob_inf_med + prob_ch_med
	replace prob_inf_med = prob_inf_med / scale
	replace prob_ch_med = prob_ch_med / scale 
	gen scale_both_infch_u5 = scale
	drop scale 
	
	gen scale = (prob_enn_med + prob_lnn_med + prob_pnn_med) / prob_inf_med
	foreach age in enn lnn pnn { 
		replace prob_`age'_med = prob_`age'_med / scale
	} 
	gen scale_both_ennlnnpnn_inf = scale
	drop scale 
	
	replace q_enn_med = (q_u5_med * prob_enn_med)
	replace q_lnn_med = (q_u5_med * prob_lnn_med) / ((1-q_enn_med))
	replace q_pnn_med = (q_u5_med * prob_pnn_med) / ((1-q_enn_med)*(1-q_lnn_med))
	replace q_inf_med = (q_u5_med * prob_inf_med)
	replace q_ch_med  = (q_u5_med * prob_ch_med)  / ((1-q_enn_med)*(1-q_lnn_med)*(1-q_pnn_med))	
	replace q_nn_med  = 1-(1-q_enn_med)*(1-q_lnn_med)
	drop prob*
	
	preserve
	drop scale* srb
	merge 1:1 ihme_loc_id sex year using `prescale', nogen assert(3)
	foreach age in enn lnn pnn ch {
		gen scale_`age' = q_`age'_med/q_`age'_med_prescale
	}
	keep ihme_loc_id sex year scale*
	save "`ihme_loc_id'_scaling_numbers.dta", replace
	restore
	drop scale* srb
	
** Recalculate medium estimates of rates of change 
	sort ihme_loc_id sex year
	foreach q in enn lnn nn pnn inf ch u5 { 
		by ihme_loc_id sex: replace change_`q'_70_90_med = -100*ln(q_`q'_med[41]/q_`q'_med[21])/(1990-1970) 
		by ihme_loc_id sex: replace change_`q'_90_10_med = -100*ln(q_`q'_med[61]/q_`q'_med[41])/(2010-1990)
		by ihme_loc_id sex: replace change_`q'_90_08_med = -100*ln(q_`q'_med[59]/q_`q'_med[41])/(2008-1990)
	} 

** force probabilities <1
	foreach var of varlist q* {
        replace `var' = 0.99 if `var' >.99 | `var' == .
    }
	
** Format and save 
	order ihme_loc_id sex year q* change*
	saveold "`ihme_loc_id'_noshocks.dta", replace
	cap log close

	
	exit, clear

