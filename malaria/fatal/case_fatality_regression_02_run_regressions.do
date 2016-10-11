//A case fatality/natural history model to make estimates for malaria.
clear all
set more off
cap restore, not
set trace off

//set OS
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		local prefix "/home/j"
		set odbcmgr unixodbc
		local datapath "/snfs3/strUser/malaria_draws"
		adopath + "/ihme/code/general/strUser/malaria"
	}
	else if c(os) == "Windows" {
		local prefix "J:"
		local datapath "`prefix'/temp/strUser/Malaria"
		adopath + "C:/Users/strUser/Documents/Code/malaria"
	}
	adopath + "`prefix'/WORK/10_gbd/00_library/functions"
//Locals
	//file structure
	local main_path J:\WORK\03_cod\02_models\02_results\malaria\models
	local data_path "`prefix'/WORK/01_covariates/02_inputs/malaria/cfr_model"
	
	//data/squares
	local demos `main_path'/malaria_cfr_pred_sq_upd.dta
	local data `main_path'/malaria_cfr_dataset_upd.dta
	
	//The governator	
	local model_gov "`prefix'/WORK/01_covariates/02_inputs/malaria/model_maker/cfr_model_gov.xlsx"
	
	
	
//Begin running models
	import excel "`model_gov'", clear firstr

	//keep only rows with models we want to run
	keep if regress_me==1
	levelsof model_num, local(themodels)
	tempfile govern
	save `govern', replace
	
	
	//run the models
	foreach mmm of local themodels{
		local pred_files
		local data_pred
		local draw_files
		local beta_files
		use `govern', clear
		keep if model_num == `mmm'
		
		tempfile themodel
		save `themodel', replace
		
		//load the locals governing the model process
		foreach var of varlist *{
			qui levelsof `var', local(`var')
			local `var' ``var''
		} //close local generation
		
		//check age and sex seperation models
		local age_range = subinstr("`age_range'", ","," ", .) //space delimit
		local age_range = subinstr("`age_range'", "-",",",. ) //comma delimit the range
		
		local sex_range = subinstr("`sex_range'", ","," ", .) //space delimit
		local sex_range = subinstr("`sex_range'", "-",",",. ) //comma delimit the range
		
		foreach ar of local age_range{
			foreach sr of local sex_range{
				use `data', clear
				di in red "age: `ar' | sex: `sr'"
				//subset by the desire age range
				keep if inrange(age_group,`ar') & inrange(sex_id, `sr')
				
				//drop Sao Tome, Yemen and Comoros if requested
				if `drop_locs' ==1 {
					di "DROPPPING LOCS"
					drop if inlist(location_id,215,176,157)
				}
				
				sum age_group sex
				
				//get logs prepped
				local a =subinstr("`ar'",",","-",.)
				local s =subinstr("`sr'",",","-",.)
				
				//merge in the envelope from demos
				merge m:1 location_id year_id sex_id age_group using `demos', assert(2 3) keep(3) keepusing(mean_env_hivdeleted) nogen
				
				//set outliers (mostly for testing)
				if `manual_outliers'==1{
					di "DROPPING OUTLIERS"
					drop if sex_id ==2 & site == "Nouna [rural]" & year_id == 2002
					
					if `model_num' ==18 {
						drop if location_id == 181 //madagascar points 18
					}
					else if `model_num' == 19 {
						drop if data_type == "Vital Registration" //VR that we added 19
					}
					else if `model_num' == 20{
						drop if submission_datapoint==0 //20
					}
					
					
				}

				cap log close
				log using "J:/temp/strUser/Malaria/outputs/intermediate/malaria_`s'_`a'_`model_num'.log", replace
				
				di in red "`model_form' `model_outcome' `model_iv_equation'"
				
				`model_form' `model_outcome' `model_iv_equation'
				di "`e(cmdline)'"

				log close

				//predict for the datapoints
				preserve
					//first the linear predictions
					predict default_prediction
					predict linear_fit, xb
					predict linear_se, stdp
					
					//get rmse
					//rmse as sqrt(mean(r$residuals^2))
					//generate residuals without random effects
					gen resid = `model_outcome' - linear_fit
					predict resid_fit, residuals
					gen resid_sq = resid^2
					sum resid_sq
					local rmse = sqrt(`r(mean)')
					
					
					//back transform the linear prediction
					gen con_linear_fit = `back_transform'(linear_fit)
					
					//get deaths and implied cause fractions
					gen est_deaths = con_linear_fit * mean_untreated_cases
					gen est_cf = est_deaths/mean_env_hivdeleted
					
					
					//if we had random effects
					if `num_reffs' > 0 {
						predict fitted_predictions, fit
						gen con_fitted_predictions = `back_transform'(fitted_predictions)
					}
					
					gen model_num = `model_num'
					
					save "J:/temp/strUser/Malaria/outputs/intermediate/data_preds_`s'_`a'_`model_num'.dta", replace
					local data_pred `data_pred' "J:/temp/strUser/Malaria/outputs/intermediate/data_preds_`s'_`a'_`model_num'.dta"
				restore	
				
				//predict for the square
				use `demos', clear
				keep if inrange(age_group,`ar') & inrange(sex_id, `sr')
				
				//drop Sao Tome, Yemen and Comoros if requested
				if `drop_locs' ==1 {
					di "DROPPPING LOCS"
					drop if inlist(location_id,215,176,157)
				}
				
				
				predict linear_fit, xb
				predict linear_se, stdp
				gen con_linear_fit = `back_transform'(linear_fit)
				gen est_deaths = con_linear_fit * mean_untreated_cases
				gen est_cf = est_deaths/mean_env_hivdeleted
				gen model_num = `model_num'
				gen model_form = "`model_form' `model_outcome' `model_iv_equation'" 
				save "J:/temp/strUser/Malaria/outputs/intermediate/initial_preds_`s'_`a'_`model_num'.dta", replace
				local pred_files `pred_files' "J:/temp/strUser/Malaria/outputs/intermediate/initial_preds_`s'_`a'_`model_num'.dta"
				count if est_cf > 1
				if `ignore_errors' != 1 & `r(N)' >0{
					di "CF OVER 1"
					sadf
				}

				//now do draws
				di "DO THINGS THE BETAS WAY"
				
				//extract betas
				matrix m = e(b)'
				//matrix list m
				matrix m = m[1..(rowsof(m)-`=`num_reffs'+1'),1]
				
				//matrix list m
				**extract betas
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
				
				**find covariance matrix of betas
				matrix C = e(V)
				matrix C = C[1..(colsof(C)-`=`num_reffs'+1'), 1..(rowsof(C)-`=`num_reffs'+1')]
				
				
				//save the betas
				preserve
					mat hold = m'
					clear
					svmat hold
					local iter 1
					foreach b of local betas{
						rename hold`iter' `b'
						local iter = `iter'+1
					}
					gen ar = "`a'"
					gen sr = "`s'"
					
					save "J:/temp/strUser/Malaria/outputs/intermediate/betas_`s'_`a'_`model_num'.dta", replace
					local beta_files `beta_files' "J:/temp/strUser/Malaria/outputs/intermediate/betas_`s'_`a'_`model_num'.dta"
					
				restore
				
				//mat list m
				//mat list C
				di "`betas'"
				
				drawnorm `betas', means(m) cov(C)
				
				//do the draws manually for now
				di "GENERATING DRAWS"
				forvalues i = 1/`number_draws' {
					local drawnum = `i'-1
					//get the draw in logit cfr land
					gen draw_`drawnum' = b__cons[`i'] + (b_log_mort_rate[`i'] * log_mort_rate) + cond(sex_id ==1, b_1sex_id[`i'], b_2sex_id[`i'])				
				}
				
				egen est_mean_logitcfr_pre = rowmean(draw_*)
				
				//converting to deaths
				di "CONVERTING TO DEATHS and Cap at envelope"
				forvalues i = 1/`number_draws'{
					local drawnum = `i'-1
					//get the draw in logit cfr land
	
					replace draw_`drawnum' = (`back_transform'(draw_`drawnum')) * (map_untreated_incidence_`drawnum' * pop_scaled)

					
					//cap at envelope
					replace draw_`drawnum' = mean_env_hivdeleted if draw_`drawnum'>mean_env_hivdeleted
					
					//cap at 0
					replace draw_`drawnum' = 0 if draw_`drawnum'<0
				}
				
				//find mean upper and lower
				egen deaths_mean = rowmean(draw*)
				egen deaths_lower = rowpctile(draw*), p(2.5)
				egen deaths_upper = rowpctile(draw*), p(97.5)
				
				
				save "J:/temp/strUser/Malaria/outputs/intermediate/draws_`s'_`a'_`model_num'.dta", replace
				local draw_files `draw_files' "J:/temp/strUser/Malaria/outputs/intermediate/draws_`s'_`a'_`model_num'.dta"
				
			} //close age
		} //close sex
		
		//set trace on
		
		//append the results together

		//append draw files
		clear
		append using `draw_files'
		save "J:/temp/strUser/Malaria/outputs/draws_`model_num'.dta", replace

		clear
		append using `data_pred'
		save "J:/temp/strUser/Malaria/outputs/data_preds_`model_num'.dta", replace
		
		clear
		append using `beta_files'
		save "J:/temp/strUser/Malaria/outputs/beta_files_`model_num'.dta", replace
		//set trace off
		
	} //close model running
	
	
	