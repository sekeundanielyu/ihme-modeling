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
		// directory for steps code
		local code_dir `6'
		local location_id `7'

		}

//Loop over every year and sex for given location 
	//year_ids
		local year_ids "1990 1995 2000 2005 2010 2015"
	//sex_ids
		local sex_ids "1 2"

	foreach year_id in `year_ids' {
		foreach sex_id in `sex_ids' {

		** Bring in prevalence by etiology and severity 
		forvalues sev=20(15)95 {
			use "`root_tmp_dir'/03_steps/`date'/05_etiology_squeeze/03_outputs/01_draws/etiology_prevalence_severity`sev'_`location_id'_`year_id'_`sex_id'", clear 
			tempfile working_sev`sev'
				save `working_sev`sev'', replace
			}


			insheet using "`in_dir'/Tinnitus_codebook.csv", clear
					gen standard_error = sqrt(pct_tinnitus*(1-pct_tinnitus)/sample_size)
					sum standard_error if standard_error != 0
					keep if pct_tinnitus!=.
					tempfile ring
					save `ring', replace
				
				// save info as locals
					** local sev 35
					forvalues sev=20(15)95 {
						use `ring', clear
						keep if threshold==`sev'
						local mu pct_tinnitus
						local sigma standard_error
						local alpha_`sev' = `mu' * (`mu' - `mu' ^ 2 - `sigma' ^2) / `sigma' ^2 
						local beta_`sev'  = `alpha_`sev'' * (1 - `mu') / `mu'
					}

			
		// go through each etiology separately and make tempfiles for each.
		cap restore, not

	
		foreach cause in cong_other otitis other meng_pneumo meng_hib meng_meningo meng_other {
			forvalues sev=20(15)95 {
				use `working_sev`sev'', clear
				keep age `cause'*
				
				local draw 0
			
				forvalues draw = 0/999 {
					di in red "Draw `draw'! `cause'!! `step_name'"
					
						gen ring_sev`sev'_`draw' = rbeta(`alpha_`sev'', `beta_`sev'')

						gen r`cause'_sev`sev'_draw_`draw'=`cause'_sev`sev'_draw_`draw'*ring_sev`sev'_`draw'
						gen nr`cause'_sev`sev'_draw_`draw'=`cause'_sev`sev'_draw_`draw'*(1-ring_sev`sev'_`draw')
						drop ring_sev`sev' `cause'_sev`sev'_draw_`draw'
				}
				
				// save ringing and not ringing in separate tempfiles so we can then save all the separate outputs.	
				preserve 
					keep age r`cause'_sev`sev'_*
					rename r`cause'_sev`sev'_* *
					tempfile r`cause'_sev`sev'
					save `r`cause'_sev`sev'', replace
				restore
				preserve 
					keep age nr`cause'_sev`sev'*
					rename nr`cause'_sev`sev'_* *
					tempfile nr`cause'_sev`sev'
					save `nr`cause'_sev`sev'', replace
				restore	
			
			
			}
		}


		**local cause otitis
		**local sev 20
		**local ring r
		foreach cause in otitis cong_other other meng_pneumo meng_hib meng_meningo meng_other {
			forvalues sev=20(15)95 {
				foreach ring in nr r {
					di in red "SAVING `cause' `sev' `ring'"
					
					import delimited "`in_dir'/output_hearing_meid_codebook", clear
					levelsof modelable_entity_id if variable_name == "`ring'`cause'_sev`sev'", local(meid)
					cap mkdir "`out_dir'/03_outputs/01_draws/`meid'"

					use ``ring'`cause'_sev`sev'', clear
					format *draw* %16.0g
					outsheet using "`out_dir'/03_outputs/01_draws/`meid'/5_`location_id'_`year_id'_`sex_id'.csv", c replace

				}
			}
		}



		//Next sex	
		}
	//Next year 
	}
