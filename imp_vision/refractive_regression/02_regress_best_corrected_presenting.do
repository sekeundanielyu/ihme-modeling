// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Description:	use the vision envelope input data to determine crosswalk from presenting to best corrected
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

	//If running on cluster, use locals passed in by model_custom's qsub
	else if `cluster' == 1 {
		// base directory on J 
		local root_j_dir `1'
		// base directory on clustertmp
		local root_tmp_dir `2'
		// timestamp of current run (i.e. 2014_01_17) 
		local date `3'
		// step number of this step (i.e. 01a)
		local step_num `4'
		// name of current step (i.e. first_step_name)
		local step_name `5'
		// step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
		local hold_steps `6'
		// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
		local last_steps `7'
		// directory for steps code
		local code_dir `8'
		}
	


	// write log if running in parallel and log is not already open
	cap log using "`out_dir'/02_temp/02_logs/`step_num'.smcl", replace
	if !_rc local close_log 1
	else local close_log 0
	

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE

*** LOAD DATA - append 3 severities together 
	

		local i = 0
		foreach meid in 2566 2567 2426 {
			get_data, modelable_entity_id(`meid') clear 
			if `i' == 0 tempfile getdata
			if `i' > 0 append using `getdata', force
			save `getdata', replace 
			local i = `i' + 1
			}
	
	

//Get demographics. Super regions will be used for regression 
		
			get_location_metadata, location_set_id(9) clear 
			keep location_id super_region_id super_region_name
			drop if super_region_id == . 
			duplicates drop location_id, force
			tempfile super_regions
			save `super_regions', replace 

			query_table, table_name(age_group) clear 
			keep age_group_id age_group_years_start age_group_years_end
			keep if age_group_id <= 21 //5yr ranges 
			gen age_group_mid = (age_group_years_start + age_group_years_end) / 2
			tempfile gbd_ages
			save `gbd_ages', replace 


use `getdata', clear
// reshape data to have best corrected and presenting from same nid, location_id, modelable_entity_id, age, sex, and year
			cap drop if cv_selfreport==1 | is_outlier == 1 

			replace site_memo="." if site_memo==""
			
			duplicates drop modelable_entity_id location_id age_start age_end nid sex year_start cv_best_corrected site_memo, force

			keep nid modelable_entity_id location_id site_memo year_start cv_best_corrected sex age_start age_end mean cases sample_size
			order modelable_entity_id location_id site_memo year_start cv_best_corrected sex age_start age_end mean cases sample_size

		
			tempfile data
			save `data'


** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** **
** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** **
		use `data', clear
		// AGGREGATE SEXES
			count if cases == 0
			local countdown = `r(N)'
			while `countdown' != 0 {
				quietly {
					count if cases == 0
					local prev_count = `r(N)'
					sort nid modelable_entity_id location_id site_memo year_start cv_best_corrected age_start age_end sex 
					egen all_sex_group = group(nid modelable_entity_id location_id site_memo year_start age_start age_end cv_best_corrected)
					levelsof all_sex_group, local(groups)
					foreach group of local groups {
						replace sex = "Both" if cases[_n-1] == 0 & all_sex_group == `group' & all_sex_group[_n-1] == `group'
						replace sex = "Both" if cases == 0 & all_sex_group == `group'
						replace sex = "Both" if cases[_n+1] == 0 & all_sex_group == `group' & all_sex_group[_n+1] == `group'
					}
					collapse (sum) cases sample_size, by(nid modelable_entity_id location_id site_memo year_start cv_best_corrected sex age_start age_end) fast
				}
				count if cases == 0
				local countdown = `prev_count' - `r(N)'
			}
		// AGGREGATE AGE GROUPS
			foreach age_tail in front rear {
				count if cases == 0
				local countdown = `r(N)'
				while `countdown' != 0 {
					quietly {
						count if cases == 0
						local prev_count = `r(N)'
						sort nid modelable_entity_id location_id site_memo year_start cv_best_corrected age_start age_end sex
						egen all_age_group = group(nid modelable_entity_id location_id site_memo year_start cv_best_corrected sex)
						levelsof all_age_group, local(groups)
						foreach group of local groups {
							if "`age_tail'" == "front" {
								replace age_end = age_end[_n+1] if cases == 0 & all_age_group == `group' & all_age_group[_n+1] == `group'
								replace age_start = age_start[_n-1] if cases[_n-1] == 0 & all_age_group == `group' & all_age_group[_n-1] == `group'
							}
							else if "`age_tail'" == "rear" {
								replace age_start = age_start[_n-1] if cases == 0 & all_age_group == `group' & all_age_group[_n-1] == `group'
								replace age_end = age_end[_n+1] if cases[_n+1] == 0 & all_age_group == `group' & all_age_group[_n+1] == `group'
							}
						}
						collapse (sum) cases sample_size, by(nid modelable_entity_id location_id site_memo year_start cv_best_corrected age_start age_end sex) fast
					}
					count if cases == 0
					local countdown = `prev_count' - `r(N)'
				}
			}
			gen mean = cases/sample_size
			drop cases sample_size
			
		** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** **
		** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** **


			
			reshape wide mean, i(modelable_entity_id location_id age_start age_end nid year_start site_memo sex) j(cv_best_corrected) 			
				rename mean1 best_corrected
				rename mean0 presenting
				gen ratio = best_corrected/presenting


			tempfile bc_presenting_envelope
			save `bc_presenting_envelope'

			use `bc_presenting_envelope', clear
			merge m:1 location_id using `super_regions', keep(3) nogen


			tempfile x
			save `x', replace

			//create super region dummy variables 
			levelsof super_region_name, local(supers)
			foreach region of local supers {
				local region_short = substr("`region'", 1, 10)
				local region_short=subinstr("`region_short'", " ", "", .)
				local region_short=subinstr("`region_short'", "-", "", .)
				gen `region_short'=0
				replace `region_short'=1 if super_region_name=="`region'"
			}

			
			gen r = best_corrected/presenting
			replace r = . if presenting==0 & best_corrected==0
				
			gen logit_b_p = logit(r)
				gen b_p = invlogit(logit_b_p)
				
			tempfile temp
			save `temp', replace
			clear
		
	

		// Run regressions
			
			quietly {
			clear
			gen age_group_id = .
			tempfile coeffs
			save `coeffs', replace
			*local vision_severity mod_severe
			foreach vision_severity in blindness mod_severe {
				noisily di in red "** ** ** ** ** ** ** ** ** ** ** **"
				noisily di in red "Regressing `vision_severity'"
				noisily di in red "** ** ** ** ** ** ** ** ** ** ** **"
				use `temp', clear
				if "`vision_severity'" == "blindness" keep if inlist(modelable_entity_id,2426)
				if "`vision_severity'" == "mod_severe" keep if inlist(modelable_entity_id,2566,2567)
				gen age_group_mid = (age_start+age_end)/2
		
			merge m:1 location_id year_start using `covs', keep(3)
			
						noisily regress logit_b_p age_group_mid SouthAsia
					
				use `gbd_ages', clear 
				expand 2, gen(SouthAsia)
				keep age_group_mid SouthAsia age_group_id
					
				
				predict logit_b_p, xb
				predict pred_se, stdp
				gen b_p = invlogit(logit_b_p)
				gen se = b_p*(1-b_p)*pred_se
				keep age_group_id b_p se SouthAsia
				tempfile ratios
				save `ratios', replace
				levelsof age_group_id, local(ages)
				levelsof SouthAsia, local(cv_SA)
				clear
				gen age_group_id = .
				tempfile dists
				save `dists', replace
				foreach SA of local cv_SA {
					noisily di in red "Drawing from sample beta distribution for cv_SA = `SA'..."
					foreach age of local ages {
						noisily di in red "     ... age_group_id `age'"
						use `ratios' if age_group_id == `age' & SouthAsia == `SA', clear
						local M = b_p
						local SE = se
						local N = `M'*(1-`M')/`SE'^2
						local a = `M'*`N'
						local b = (1-`M')*`N'
						clear
						set obs 1000
						gen b_p_ = rbeta(`a',`b')
						gen num = _n-1
						gen age_group_id = `age'
						reshape wide b_p_, i(age_group_id) j(num)
						gen cv_SA = `SA'
						append using `dists'
						save `dists', replace
					}
				}
				if "`vision_severity'" == "mod_severe" {
					gen sev = "low_sev"
					expand 2, gen(exp)
					replace sev = "low_mod" if exp == 1
					drop exp
				}
				else if "`vision_severity'" == "blindness" gen sev = "blind"
				append using `coeffs'
				save `coeffs', replace
			}
		}
			order sev cv_SA age_group_id
			gsort -sev cv_SA age_group_id 
			save "`out_dir'/03_outputs/03_other/bc_presenting_coeff.dta", replace

		** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** **
		** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** ** **

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************


