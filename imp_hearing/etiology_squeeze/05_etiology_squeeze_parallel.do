// *********************************************************************************************************************************************************************
** Description:	make prevalence estimates by etiology
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
	
	

	**********************************
	** LOAD DISMOD RESULTS
	**********************************
		
		//INPUT ETIOLOGY MEIDS
			*1282 Chronic otitis media
			*2311 Age-related and other hearing loss unsqueezed (PROPORTION MODEL)
			*2918 Hearing loss due to H influenzae type B meningitis unsqueezed
			*2920 Hearing loss due to meningococcal meningitis unsqueezed
			*2922 Hearing loss due to other meningitis unsqueezed
			*2924 Hearing loss due to pneumococcal meningitis unsqueezed
		*local meids "1282 2311 2918 2920 2922 2924"
		import excel using "`in_dir'\input_hearing_meid_codebook.xlsx", clear firstrow 
		levelsof modelable_entity_id, local(meids)


		foreach meid in `meids' {

			//Load 2311 as proportion (because that's how it's modeled in Dismod)
			if `meid' == 2311 {
				local cause "other"
				get_draws, gbd_id_field(modelable_entity_id) source(epi) gbd_id(`meid') measure_ids(18) location_ids(`location_id') clear
				}

			//Load rest as prevalence 
			else get_draws, gbd_id_field(modelable_entity_id) source(epi) gbd_id(`meid') measure_ids(5) location_ids(`location_id') clear
			keep if age_group_id <= 21 

			//save tempfiles 
			if `meid' == 1282 local cause "otitis"
			if `meid' == 2918 local cause "meningitis_hib"
			if `meid' == 2920 local cause "meningitis_meningo"
			if `meid' == 2922 local cause "meningitis_other"
			if `meid' == 2924 local cause "meningitis_pneumo"

			rename draw* `cause'_draw*
			tempfile `cause'_temp //tempfiles for year-sex specific data (used below)
			tempfile `cause'_dismod
			save ``cause'_dismod', replace 
			}



//Loop over every year and sex for given location 
	//year_ids
		local year_ids "1990 1995 2000 2005 2010 2015" 
	//sex_ids
		local sex_ids "1 2"

	foreach year_id in `year_ids' {
		foreach sex_id in `sex_ids' {

	//Pull in hearing-aid adjusted severity levels from previous step 
	use "`root_tmp_dir'/03_steps/`date'/04_hearing_aids_adjustment/03_outputs/01_draws/adjusted_categorical_parent_envelopes_`location_id'_`year_id'_`sex_id'.dta", clear 
	tempfile envelope
	save `envelope', replace
		
	**********************************
	** Adjust input etiologies such that it is prevalence of hearing loss due to x etiology by severity
	**********************************

	***AGE-RELATED/ OTHER HEARING LOSS 
		// turn other hearing loss from proportion into prevalence by severity (assume proportion same across all severities)
			use `other_dismod' if year_id == `year_id' & sex_id == `sex_id', clear
			merge 1:1 age_group_id using `envelope', nogen
			
			//Prevalence of other hearing loss at given severity = proportion of other hearing loss * (hearing aid adjusted) prevalence at given severity 
			forvalues sev=20(15)95 {
				forvalues draw=0/999 {
					gen other_sev`sev'_draw_`draw' = other_draw_`draw' * adjusted_`draw'_`sev'
				}
			}
			
			drop other_draw* adjusted*
			
			tempfile other_temp
			save `other_temp', replace
				
	*** OTITIS  (coming in already as prevalence)
		
			clear
			set obs 1000
			gen x = rbeta(540*0.8, 540*0.2)
			xpose, clear
			//Generate 1000 draws of the proportion of hearing loss due to otitis that is mild 
			forvalues num = 1/1000 {
				local draw = `num' - 1
				rename v`num' prop_mild_`draw'
				}
			gen om = "om"
			tempfile prop_mild
			save `prop_mild', replace
			clear			
			
			use `otitis_dismod' if year_id == `year_id' & sex_id == `sex_id', clear
			gen om = "om"
			merge m:m om using `prop_mild', keep(1 3) nogen

			forvalues draw=0/999 {
				//Calculate prevalence of mild and moderate hearing loss due to otitis
				gen otitis_sev20_draw_`draw' = otitis_draw_`draw' * prop_mild_`draw'
				gen otitis_sev35_draw_`draw' = otitis_draw_`draw' * (1 - prop_mild_`draw')
				//Other severities have zero prevalence 
				forvalues sev=50(15)95 {
					gen otitis_sev`sev'_draw_`draw' = 0
					}
				}			
			
			drop otitis_draw* prop_mild*
			
			save `otitis_temp', replace
			

	*** MENINGIITS 
		// menigitis is coming in as 26+ db rather than 35+ db estimates.  crosswalk using nhanes data
			
			foreach acause in meningitis_pneumo meningitis_hib meningitis_meningo meningitis_other {
				use ``acause'_dismod' if year_id == `year_id' & sex_id == `sex_id', clear
				merge 1:1 _n using "`in_dir'/crosswalks_map_for_meningitis.dta", nogen
				forvalues draw=0/999 {
					replace crosswalk`draw' = crosswalk`draw'[1]
					gen `acause'_35_draw_`draw' = `acause'_draw_`draw' * crosswalk`draw'
					gen `acause'_2034_draw_`draw' = `acause'_draw_`draw' * (1 - crosswalk`draw')
					}	
				drop crosswalk* `acause'_draw*
				save ``acause'_temp', replace
				}
		
		// proportionally split meningitis prevalences by the envelope 
			use `meningitis_pneumo_temp', clear
			merge 1:1 age_group_id using `meningitis_hib_temp', nogen
			merge 1:1 age_group_id using `meningitis_meningo_temp', nogen
			merge 1:1 age_group_id using `meningitis_other_temp', nogen	
			

			merge 1:1 age_group_id using `envelope', nogen
			
			rename meningitis* meng*
			
			tempfile meng_temp
			save `meng_temp', replace
			
			forvalues draw=0/999 {
				di in red "draw `draw' for meng loop"
				foreach acause in meng_pneumo meng_hib meng_meningo meng_other {
					
					//Total hearing loss envelope (all severities, all causes)
					egen total = rowtotal(adjusted_`draw'*)
					
					//Calculate each severity's proportion of all hearing loss (and apply to meningitis at given severity)
					forvalues sev=20(15)95 {
						gen prop_`sev' = adjusted_`draw'_`sev' / total
						// 20-34 meningitis drawn directly from crosswalk remainder 
						if `sev' == 20 gen `acause'_sev`sev'_draw_`draw' = `acause'_2034_draw_`draw'
						//35+ categories calculated by proportion of that severity * prevalence of 35+ meningitis 
						else 		   gen `acause'_sev`sev'_draw_`draw' = prop_`sev' * `acause'_35_draw_`draw'
						}
					drop prop* total `acause'_35_draw_`draw' `acause'_2034_draw_`draw'
				}
				
				drop adjusted_`draw'_*
			}

			save `meng_temp', replace			
			
**********************************
** Start the squeezing stuff
**********************************		

		** 1) Prevalence at birth assumed to be all congenital.  prevalence remains constant (no excess mortality or remision)
		** 2) Squeeze congenital, other, otitis, and all meningitis 
		** 3) Stream out congenital over all ages again (since it got adjusted during squeeze)
		
		forvalues sev=20(15)95 {
			use `envelope', clear
			keep age_group_id adjusted*`sev'
			merge 1:1 age_group_id using `other_temp', nogen keepusing(*sev`sev'*)
			merge 1:1 age_group_id using `otitis_temp', nogen keepusing(*sev`sev'*)
			merge 1:1 age_group_id using `meng_temp', nogen keepusing(*sev`sev'*)
	
			tempfile working_sev`sev'
			save `working_sev`sev'', replace
			}
	
		** SQUEEZE!
				
				** 1) first make it so congenital prevalence is constant based off of birth prevalence 
				**	local draw 0
				**	local sev 95
					quietly {
						
						forvalues sev=20(15)95 {
							
							use `working_sev`sev'', clear
							
							forvalues draw=0/999 {
								di in red "DRAW `draw'! sev `sev', make congenital loop"	
							
								summ adjusted_`draw'_`sev' if age_group_id==2 //neonatal
								gen cong_other_sev`sev'_draw_`draw' = `r(mean)'
								
							}
						
							save `working_sev`sev'', replace

						
						}
					}

					
					quietly {
						
					**	local sev 20
					**	local draw 0
						forvalues sev=20(15)95 {
							
							use `working_sev`sev'', clear
							
							
							forvalues draw=0/999 {
								
								noisily di in red "DRAW `draw'! sev `sev', squeeze"						
								
								// squeeze the all etiologies into the envelope
									gen total = otitis_sev`sev'_draw_`draw' + meng_pneumo_sev`sev'_draw_`draw' + meng_hib_sev`sev'_draw_`draw' + meng_meningo_sev`sev'_draw_`draw' + meng_other_sev`sev'_draw_`draw' + other_sev`sev'_draw_`draw' + cong_other_sev`sev'_draw_`draw'
							
								foreach etiology in otitis cong_other other meng_pneumo meng_hib meng_meningo meng_other {
									gen proportion_`etiology' = `etiology'_sev`sev'_draw_`draw' / total
									replace `etiology'_sev`sev'_draw_`draw' = adjusted_`draw'_`sev' * proportion_`etiology' 
									drop proportion_`etiology'
								}
							}
							
							save `working_sev`sev'', replace						
						}					
					}

	
				** 3) Make it so congenital prevalence is constant based off of birth prevalence (may have been altered during squeeze)
				**	local draw 0
				**	local sev 95
					quietly {
						
						forvalues sev=20(15)95 {
							
							use `working_sev`sev'', clear
							
							forvalues draw=0/999 {
								di in red "DRAW `draw'! sev `sev', make second congenital loop"	
							
								summ cong_other_sev`sev'_draw_`draw' if age_group_id==2 //neonatal
								replace cong_other_sev`sev'_draw_`draw' = `r(mean)'
				
							}
						
							save `working_sev`sev'', replace

						}
					}


			
	//Save an intermediate file
	save "`tmp_dir'/03_outputs/01_draws/etiology_prevalence_severity`sev'_`location_id'_`year_id'_`sex_id'", replace 
	}
					

			} //next sev 

			} // end quietly



		//Next sex	
		}
	//Next year 
	}

