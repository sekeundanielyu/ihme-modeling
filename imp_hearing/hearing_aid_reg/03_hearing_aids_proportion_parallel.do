** *********************************************************************************************************************************************************************
** Description:	get prevalence of hearing aid use in each severity
*******************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************



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
		// directory for steps code
		local code_dir `6'
		local location_id `7'

		}
	

	*************************************
	** LOAD INFO
	*************************************
	
	//load hearing aid coverage draws for Norway (since it is the country from regression giving coverage by severity)
			get_draws, gbd_id_field(modelable_entity_id) source(epi) gbd_id(2411) measure_ids(5) location_ids(90) clear
			keep if age_group_id <= 21 
			rename draw* Norway_draw*
			tempfile Norway_hearing_aid_coverage
			save `Norway_hearing_aid_coverage', replace 
	//load hearing aid coverage draws for country of interest 
 		  	get_draws, gbd_id_field(modelable_entity_id) source(epi) gbd_id(2411) measure_ids(5) location_ids(`location_id') clear
			keep if age_group_id <= 21 //5yr ranges 
			tempfile country_hearing_aid_coverage
			save `country_hearing_aid_coverage', replace 


			*** DIAGNOSTICS 
			if `cluster' == 0 {
			cd "/home/j/temp/struser/imp_hearing/scratch"
			run "/home/j/WORK/10_gbd/00_library/functions/get_draws.ado"
			//CLUSTER: load hearing aid coverage draws for Norway (since it is the country from regression giving coverage by severity)
			get_draws, gbd_id_field(modelable_entity_id) source(epi) gbd_id(2411) measure_ids(5) location_ids(90) clear
			keep if age_group_id <= 21 
			rename draw* Norway_draw*
			//CLUSTER: load hearing aid coverage draws for country of interest 
 		  	get_draws, gbd_id_field(modelable_entity_id) source(epi) gbd_id(2411) measure_ids(5) location_ids(58) clear
			keep if age_group_id <= 21 //5yr ranges (is this all we need to do?)
			}


	*************************************
	** CALCULATE RATIO
	*************************************
		merge 1:1 year_id sex_id age_group_id using `Norway_hearing_aid_coverage', nogen 
			forvalues draw = 0/999 {
				gen ratio_draw_`draw' = draw_`draw' / Norway_draw_`draw'
				}
			save `country_hearing_aid_coverage', replace 

//Loop over every year and sex for given location 
	//year_ids
		local year_ids "1990 1995 2000 2005 2010 2015"
	//sex_ids
		local sex_ids "1 2"

	foreach year_id in `year_ids' {
		foreach sex_id in `sex_ids' {


		use `country_hearing_aid_coverage' if year_id == `year_id' & sex_id == `sex_id', clear 

		//Call in Norway severity specific hearing aid coverage (from regression in parent code, recall this is not sex-specific)
		forvalues sev=20(15)65 {
			merge 1:1 age_group_id using "`tmp_dir'/03_outputs/hearing_aids_severity_adjustment_factors_sev_`sev'.dta", nogen
			}

			
			//Country X severity specific hearing aid coverage = (country X hearing aid coverage / Norway hearing aid coverage) * Norway severity specific hearing aid coverage 
			local draw 0	
				forvalues draw = 0/999 {
						di in red "Draw `draw'! `step_name'"
						
						forvalues sev=20(15)65 {
							gen aids_sev_`sev'_draw_`draw' = ratio_draw_`draw' * sev_`sev'_`draw'
							}
						// Use 65 for 80 (the Norway data only gives 65 as a category)
						gen aids_sev_80_draw_`draw'=draw_`draw'*sev_65_`draw'
						// Assume no correction for deafness
						gen aids_sev_95_draw_`draw'=0

				}		
				
				
	*************************************
	** SAVE INFO
	*************************************	
		** save draws in intermediate location
			format *draw* %16.0g
			save "`tmp_dir'/03_outputs/01_draws/hearing_aids_proportions_by_severity_`location_id'_`year_id'_`sex_id'.dta", replace
			
	

		//Next sex	
		}
	//Next year 
	}

// *********************************************************************************************************************************************************************
