// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
** Description:	get refractive error as difference between presenting and best corrected based off of previous regression
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// LOAD SETTINGS FROM STEP CODE (NO NEED TO EDIT THIS SECTION)
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	set type double, perm
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
		local cluster 1 
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local cluster 0
	}
	// directory for standard code files
		adopath + "$prefix/WORK/10_gbd/00_library/functions"
		adopath +  "$prefix/WORK/10_gbd/00_library/functions/get_outputs_helpers"


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
	
	

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE

		** load DisMod draws for vision envelopes 
		foreach meid in 2566 2567 2426 {
		    if `meid' == 2566 local sev "low_mod" 
			if `meid' == 2567 local sev "low_sev" 
			if `meid' == 2426 local sev "blind" 
		   
		   	di "" _new "***" _new "" _new "LOADING DISMOD DRAWS FOR SEV `sev'" _new "" _new "***"
		   
		   	//load prevalence draws
		 		  	get_draws, gbd_id_field(modelable_entity_id) source(epi) gbd_id(`meid') measure_ids(5) location_ids(`location_id') clear
					keep if age_group_id <= 21 //5yr ranges 

				

			** Add South Asia coefficient for the countries in that region
					gen cv_SA = 0
						preserve
						get_location_metadata, location_set_id(9) clear 
						levelsof location_id if super_region_name == "South Asia", sep(,) local(SA_location_ids)
						restore 
					if inlist("`location_id'","`SA_location_ids'") replace cv_SA = 1
					gen sev = "`sev'"

			//save temp file 
				tempfile `sev'_draws 
				save ``sev'_draws', replace
			}
		

//Loop over every year and sex for given location 
	//year_ids
		local year_ids "1990 1995 2000 2005 2010 2015"
	//sex_ids
		local sex_ids "1 2"

	foreach year_id in `year_ids' {
		foreach sex_id in `sex_ids' {



		** this is to get the refractive error set of numbers (all in prevalence space) for each of the mod, sev, blind
			local sev low_mod
			foreach sev in low_mod low_sev blind {		
	
				** bring in the coefficients to adjust from presenting to best corrected
				// note that these coefficients will predict a ratio in logit space
				di "" _new "***" _new "" _new "OPENING DRAWS FOR SEV `sev'" _new "" _new "***"
				use ``sev'_draws', clear
				keep if year_id == `year_id' & sex_id == `sex_id'
				
				quietly {
				local draw 0

					**merge to regression coefficients
					merge 1:1 age_group_id cv_SA sev using "`root_j_dir'/03_steps/`date'/02_regress_best_corrected_presenting/03_outputs/03_other/bc_presenting_coeff.dta", assert(2 3) keep(3) nogen
					
					forvalues draw=0/999 {
						noisily di "DRAW `draw'! `sev' `step_name'"

						// turn into bestcorrected by mulitplying by percentage of presenting that is best corrected found in previous regression and then back transforming from logit space
						rename draw_`draw' presenting_draw_`draw'		
						gen bestcorrected_draw_`draw' = presenting_draw_`draw' * b_p_`draw'

						// get refractive error by taking the difference
						gen ref_error_draw_`draw' = presenting_draw_`draw'- bestcorrected_draw_`draw'
						replace ref_error_draw_`draw'=0 if ref_error_draw_`draw'<0

						drop presenting_draw_`draw'
					}
					
					drop b_p_*
					rename *draw* `sev'_*draw*
					
					tempfile `sev'_temp
					save ``sev'_temp', replace
				}
			}
		
		// Save refractive error to be grabbed...save best corrected to get adjusted more
		
		local sev low_mod
		foreach sev in low_mod low_sev blind {		
			di in red "SAVING `sev' "
					
			insheet using "`in_dir'/output_vision_meid_codebook.csv", clear
			keep if variable_name=="`sev'_ref_error"

			
			levelsof modelable_entity_id, local(meid) c		

			
			// refractive error to be uploaded
				use ``sev'_temp', clear
				
				format *draw* %16.0g
				keep age `sev'_ref_error*
				rename `sev'_ref_error_* *

				cap mkdir "`out_dir'/03_outputs/01_draws/`meid'"

				outsheet using "`out_dir'/03_outputs/01_draws/`meid'/5_`location_id'_`year_id'_`sex_id'.csv", c replace

				
			// best corrected to be further adjusted in following steps 
				use ``sev'_temp', clear
				
				format *draw* %16.0g
				drop *ref_error*

				cap mkdir "`out_dir'/03_outputs/01_draws/best_corrected"

				outsheet using "`out_dir'/03_outputs/01_draws/best_corrected/`sev'_best_corrected_`location_id'_`year_id'_`sex_id'.csv", comma replace

				if "`sev'" == "blind" {
					preserve
					rename blind_bestcorrected_draw_* draw_*
					keep age draw_* 
					cap mkdir "`out_dir'/03_outputs/01_draws/9805"
					outsheet using "`out_dir'/03_outputs/01_draws/9805/5_`location_id'_`year_id'_`sex_id'.csv", comma replace
					restore 
					}
		}			


		//Next sex	
		}
	//Next year 
	}
	
// *********************************************************************************************************************************************************************
