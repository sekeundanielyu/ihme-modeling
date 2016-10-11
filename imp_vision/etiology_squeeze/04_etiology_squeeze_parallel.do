

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
** Description:	squeeze etiologies into best corrected envelope
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
		// directory for steps code
		local code_dir `6'
		local location_id `7'

		}
	

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE


// Get list of modelable_entity_id that will be squeezed (all EXCEPT near vision 2424)
			
				insheet using "`in_dir'/input_vision_meid_codebook.csv", clear
				levelsof modelable_entity_id if modelable_entity_id != 2424, local(meids) clean
				levelsof variable_name if modelable_entity_id != 2424, local(names) clean

		
		   	//load prevalence draws for each meid 
		   	quietly {
		   	foreach meid in `meids' {
			   		
			   		//Name meids 
			   		insheet using "`in_dir'/input_vision_meid_codebook.csv", clear
			   		
			   		levelsof variable_name if modelable_entity_id == `meid', local(name) clean
			   		levelsof measure_id if modelable_entity_id == `meid', local(measure_id) clean //all are prevalence except trachoma, which is proportion 


			   	noisily di "LOAD DRAWS FROM MEID `meid' - `name'"

		   		if `cluster' == 1 get_draws, gbd_id_field(modelable_entity_id) source(epi) gbd_id(`meid') measure_ids(`measure_id') location_ids(`location_id') clear
		   		
		   			***DIAGNOSTICS
		   			if `cluster' == 1 & `cluster_check' == 1 cap mkdir "`out_dir'"
		   			if `cluster' == 1 & `cluster_check' == 1 save "`out_dir'/get_data_`name'", replace 
		   			if `cluster' == 0 use "`out_dir'/get_data_`name'", clear 

			   		keep if age_group_id <= 21
			   		drop if age_group_id == 1 //drop under 5, so that we just do discrete age groups 
			   		gen variable_name = "`name'"
					order variable_name year_id sex_id age_group_id age_group_id draw_*
					sort year_id sex_id age_group_id
		   		tempfile `name'_all
				save ``name'_all', replace
		   		}	//next meid 
		   		}




//Loop over every year and sex for given location 
	* local year_id 2000
	* local sex_id 1 
	//year_ids
		local year_ids "1990 1995 2000 2005 2010 2015"
	//sex_ids
		local sex_ids "1 2"



	foreach year_id in `year_ids' {
		foreach sex_id in `sex_ids' {



		//Pull dismod results for each cause, year and sex specific 
		foreach name in `names' {
			di "`name'"
			use ``name'_all' if year_id == `year_id' & sex_id == `sex_id', clear 
			tempfile `name'_temp

			save ``name'_temp', replace
			}

	
**************************************************************************			
** Bring in the best correct prevelence envelopes 
**************************************************************************
	foreach sev in low_mod low_sev blind {		
		insheet using "`root_j_dir'/03_steps/`date'/03_adjust_for_refractive_error/03_outputs/01_draws/best_corrected/`sev'_best_corrected_`location_id'_`year_id'_`sex_id'.csv", comma clear
		
		rename `sev'_bestcorrected_draw_* draw_*
		order age_group_id draw_*
		
		tempfile `sev'_envelope
		save ``sev'_envelope', replace		
		
	}

************************************************************************	
** Post hoc adjustment to trachoma and vitamin a: some locations are supposed to have a prevalence of zero.
** Make that adjustment now
************************************************************************		
if 1==1 {
	insheet using "`in_dir'/zero_prevalence_vita_trach_2015locations.csv", clear
	keep if location_id==`location_id'
	
	local low_trach_prev_0 = trach_prev_0
	local blind_trach_prev_0 = trach_prev_0
	local vita_prev_0 = vita_prev_0
		
	// change the tempfiles to reflect this info
	foreach name in blind_trach low_trach vita {
		di in red "`name'"
		use ``name'_temp', clear
	
		foreach var of varlist draw_* {
			qui replace `var' = `var' * ``name'_prev_0'
			}
		
		save ``name'_temp', replace
		}
	}



************************************************************************	
// turn trachoma into prevalence from proportion
************************************************************************			
if 1==1 {
	// for low vision
		use `low_trach_temp', clear

		rename draw_* low_trach_draw_*
		merge 1:1 age_group_id using `low_mod_envelope', nogen
		rename draw_* low_mod_bestcorrected_draw_*
		merge 1:1 age_group_id using `low_sev_envelope', nogen
		rename draw_* low_sev_bestcorrected_draw_*
		
		forvalues c=0/999 {
			replace low_trach_draw_`c' = low_trach_draw_`c' * (low_mod_bestcorrected_draw_`c' + low_sev_bestcorrected_draw_`c')
		}
		
		keep variable_name age_group_id low_trach_draw_*
		rename low_trach_draw_* draw_*
		
		save `low_trach_temp', replace
	
	// for blind
		use `blind_trach_temp', clear

		rename draw_* blind_trach_draw_*
		merge 1:1 age_group_id using `blind_envelope', nogen	
		rename draw_* blind_bestcorrected_draw_*
		
		forvalues draw=0/999 {
			replace blind_trach_draw_`draw' = blind_trach_draw_`draw' * blind_bestcorrected_draw_`draw'
		}
		
		keep variable_name age_group_id blind_trach_draw_*
		rename blind_trach_draw_* draw_*
		
		save `blind_trach_temp', replace
}

************************************************************************			
// game plan: get everything so it is split as low vision moderate, low vision severe, and blind
	** all the different etiologies being squeezed: meng_pneumo, meng_hib, meng_meningo, meng_other, oncho, trach, rop, vita, glauc, cat, mac, diabetes, enceph 
	** rop and oncho already split, don't need to do antyhing with them
************************************************************************


	//Vision loss due to meningitis is modeled as <6/12 as per Edmond 2010 (NID 141535)
		//Create crosswalk to <6/18 
			//Load crosswalk map 
			use "$prefix/WORK/04_epi/01_database/02_data/imp_vision/02_nonlit/proportions_map_split_merged_severity_groups", clear 
			tempfile mild_mod_xwalk 
			save `mild_mod_xwalk', replace  
			
			//Load age_group_id template 
			query_table, table_name(age_group) clear 
			keep age_group_id age_group_years_start
			rename age_group_years_start age_start
			keep if age_group_id <= 21 //5yr ranges 
			drop if age_group_id == 1 // under 5 
			merge 1:1 age_start using `mild_mod_xwalk', keep(1 3) nogen 
			
			//Replace neonatal crosswalk with birth
				levelsof mod_p_d_dmild_dmod_dsev_dvb if age_start == 0, local(under5_mean)
				replace mod_p_d_dmild_dmod_dsev_dvb = `under5_mean' if age_group_id < 5 
				levelsof mod_p_d_dmild_dmod_dsev_dvb_se if age_start == 0 , local(under5_se)
				replace mod_p_d_dmild_dmod_dsev_dvb_se = `under5_se' if age_group_id < 5 
			keep age_group_id mod_p_d_dmild_dmod_dsev_dvb mod_p_d_dmild_dmod_dsev_dvb_se

			//Create draws 
			forvalues c=0/999 {
				gen mild_mod_draw_`c' = rnormal(mod_p_d_dmild_dmod_dsev_dvb, mod_p_d_dmild_dmod_dsev_dvb_se) 
				}
			drop mod_p_d_dmild_dmod_dsev_dvb mod_p_d_dmild_dmod_dsev_dvb_se
			save `mild_mod_xwalk', replace  



	************************************************************************
		** 1. proportionally split those that are vision loss in general into low vision (mod + severe) and blind
			** vita meng_pneumo meng_hib meng_meningo meng_other enceph
	************************************************************************
	if 1==1 {
		// Get proportion of low vision (mod + severe) and blind of all vision loss 
			use `low_mod_envelope', clear
			rename draw_* low_mod_bestcorrected_draw_*
			merge 1:1 age_group_id using `low_sev_envelope', nogen
			rename draw_* low_sev_bestcorrected_draw_*
			merge 1:1 age_group_id using `blind_envelope', nogen
			rename draw_* blind_bestcorrected_draw_*
	
			quietly {
				forvalues c=0/999 {
					gen total = low_mod_bestcorrected_draw_`c' + low_sev_bestcorrected_draw_`c' + blind_bestcorrected_draw_`c'
					
					gen low_bestcorrected_draw_`c' = low_mod_bestcorrected_draw_`c' + low_sev_bestcorrected_draw_`c'
					
					foreach sev in low blind {		
						gen `sev'_prop_draw`c'= `sev'_bestcorrected_draw_`c'/total
					}
					
					drop low_mod_bestcorrected_draw_`c' low_sev_bestcorrected_draw_`c' blind_bestcorrected_draw_`c' low_bestcorrected_draw_`c' total					
				}
			}
			
			tempfile envelope_proportions
			save `envelope_proportions', replace
			
			// apply proprotions for vita meng_pneumo meng_hib meng_meningo meng_other enceph
				foreach name in vita meng_pneumo meng_hib meng_meningo meng_other enceph {

					
					use ``name'_temp', clear
					
					//Vitamin A deficiency does not occur under age 0.1
					foreach num of numlist 0/999 {
						if "`name'" == "vita" replace draw_`num' = 0 if inlist(age_group_id, 2, 3) 
					}

					//Load crosswalk map for meningitis from <6/12 to <6/18
					if regexm("`name'", "meng") | "`name'" == "enceph" merge 1:1 age_group_id using `mild_mod_xwalk', nogen

					merge 1:1 age_group_id using `envelope_proportions', nogen
					
					forvalues c=0/999 {
						//Crosswalk meningitis <6/12 to <6/18
						cap replace draw_`c' = draw_`c' * mild_mod_draw_`c'
						cap drop mild_mod_draw_`c'

						gen low_`name'_draw_`c' = low_prop_draw`c' * draw_`c'
						gen blind_`name'_draw_`c' = blind_prop_draw`c' * draw_`c'
						drop draw_`c' low_prop_draw`c' blind_prop_draw`c'
					}
					
					preserve
						drop blind_`name'_draw_*
						rename low_`name'_draw_* draw_*
						replace variable_name = "low_`name'"
						tempfile low_`name'_temp
						save `low_`name'_temp', replace

					restore

						drop low_`name'_draw_* 
						rename blind_`name'_draw_* draw_*
						replace variable_name = "blind_`name'"
						tempfile blind_`name'_temp
						save `blind_`name'_temp', replace
					} // next etiology 
		}			

	************************************************************************
		** 	2. proportionally split low vision (mod + sev) into low vision mod and low vision severe
			** trach glauc cat mac other vita diabetes meng_pneumo meng_hib meng_meningo meng_other enceph
	************************************************************************		
	if 1==1 {
		// Get proportion of mod and sev vision of all low vision (mod + severe)
			use `low_mod_envelope', clear
			rename draw_* low_mod_bestcorrected_draw_*
			merge 1:1 age_group_id using `low_sev_envelope', nogen
			rename draw_* low_sev_bestcorrected_draw_*

			quietly {
				forvalues c=0/999 {
					gen total = low_mod_bestcorrected_draw_`c' + low_sev_bestcorrected_draw_`c'
					
					foreach sev in low_mod low_sev {		
						gen `sev'_prop_draw`c'= `sev'_bestcorrected_draw_`c'/total
					}
					
					drop total low_mod_bestcorrected_draw_`c' low_sev_bestcorrected_draw_`c'					
				}
			}
			
			tempfile envelope_proportions
			save `envelope_proportions', replace

		// apply proprotions for etiologies
		
			foreach name in trach glauc cat mac other vita diabetes meng_pneumo meng_hib meng_meningo meng_other enceph {
				di in red "`name' split low vision"
				use `low_`name'_temp', clear
				
				merge 1:1 age_group_id using `envelope_proportions', nogen

				forvalues c=0/999 {
					gen low_mod_`name'_draw_`c' = low_mod_prop_draw`c' * draw_`c'
					gen low_sev_`name'_draw_`c' = low_sev_prop_draw`c' * draw_`c'
					drop draw_`c' low_sev_prop_draw`c' low_mod_prop_draw`c'
				}
				
				preserve
					drop low_mod_`name'_draw_* 
					rename low_sev_`name'_draw_* draw_*
					replace variable_name = "low_sev_`name'"
					tempfile low_sev_`name'_temp
					save `low_sev_`name'_temp', replace	
				
				restore

					drop low_sev_`name'_draw_* 
					rename low_mod_`name'_draw_* draw_*
					replace variable_name = "low_mod_`name'"
					tempfile low_mod_`name'_temp
					save `low_mod_`name'_temp', replace
					
		
			}
	}



************************
** Moderate Low vision/ Severe Low vision/ Blind squeeze
************************
	// get locals
	insheet using "`in_dir'/output_vision_meid_codebook.csv", comma clear
	count
	local r = r(N)
	di "`r' rows idenitified"

	foreach sev in low_mod low_sev blind { 
		levelsof variable_name if sev == "`sev'", local(`sev'_names) c
		}

	* local sev low_mod
	foreach sev in low_mod low_sev blind { 
		// pull in the envelop file
		use ``sev'_envelope', clear

		foreach name of local `sev'_names {
			di "append `sev' `name'"
			append using ``name'_temp'
			}
		
		order variable_name age_group_id draw_* 
		keep variable_name age_group_id draw_* 
		tempfile `sev'_all_data
		save ``sev'_all_data', replace
				
		
		// gen total draws for secondary causes
		preserve
		drop if variable_name == "" //envelope 
		replace variable_name = ""
		rename draw_* total_*

		collapse (sum) total_*, by(variable_name age_group_id) fast
		tempfile total_`sev'
		save `total_`sev'', replace

		clear
		restore, preserve

		
		
		// get proportion for squeezing
		merge m:1 variable_name age using `total_`sev'', keep(3) nogen


		forvalues c = 0/999 {
				levelsof draw_`c' if age == 2, local(birth_env)
				levelsof `sev'_rop_`c' if age == 2, local(rop_neonatal)
				if `rop_neonatal' > 0.95 * `birth_env' replace `sev'_rop_`c' = 0.95 * `birth_env' 
			
			gen envelope_`c' = draw_`c' - `sev'_rop_`c'
			gen squeeze_`c' = envelope_`c' / total_`c'  

			}


		keep age_group_id squeeze_* envelope_*
		tempfile squeeze_`sev'
		save `squeeze_`sev'', replace

		
		clear

		// squeeze  and save secondary causes
		restore		
		merge m:1 age_group_id using `squeeze_`sev'', keep(1 3) nogen
		merge m:1 age_group_id using ``sev'_rop', keep(1 3) nogen

		
		forvalues c = 0/999 {
			qui replace squeeze_`c' = 1 if variable_name == "" //Don't squeeze envelope
			qui replace draw_`c' = draw_`c' * squeeze_`c' 

		}
		sort variable_name age
		tempfile working_`sev'_temp
		save `working_`sev'_temp', replace
	}

clear

************************
** Apply a post hoc cap on prevalence of vitamin a and ROP 
	** vitamin prevalence in a given severity should never increase after the age of 10
	** ROP prevalence is neonatal throughout life 
************************	
	foreach sev in low_mod low_sev blind { 
		use `working_`sev'_temp', clear
		
		forvalues c=0/999 {
			noisily di in red "DRAW `c'! `step_name', vita cap, `sev', loop 2"
			
			// get cap at different ages		
			summ draw_`c' if variable_name == "`sev'_vita" & age_group_id == 6 
			local vita_cap= `r(mean)'
			
			// apply cap to ages above 10 for vita
			replace draw_`c'= `vita_cap' if variable_name == "`sev'_vita" & age_group_id > 6 & draw_`c' > `vita_cap' 
		}
		
		** replace envelop draws without vita
		preserve
		keep if variable_name == "`sev'_vita"
		replace variable_name = ""
		rename draw_* `sev'_vita_*
		tempfile `sev'_vita
		save ``sev'_vita', replace
		clear
		restore

		
		merge m:1 variable_name age_group_id using ``sev'_vita', keep(1 3) nogen
		merge m:1 variable_name age_group_id using ``sev'_rop', keep(1 3) nogen
	
		forvalues c = 0/999 {
			qui replace draw_`c' = draw_`c' - `sev'_vita_`c' - `sev'_rop_`c' if variable_name == ""
		} 
		drop `sev'_vita_* `sev'_rop_*



		** gen total draws for secondary causes without vita and rop 
		preserve
		drop if variable_name == "" | variable_name == "`sev'_vita" | variable_name == "`sev'_rop"
		replace variable_name = ""
		rename draw_* total_*
		collapse (sum) total_*, by(variable_name age_group_id) fast
		tempfile total
		save `total', replace
		clear
		restore
		
		** get proportion for squeezing
		preserve
		merge m:1 variable_name age_group_id using `total', keep(3) nogen
		
		
		forvalues c = 0/999 {
			qui gen squeeze_`c' = draw_`c' / total_`c' //both draw and total have ROP and vita subtracted 

		}
		
		keep age_group_id squeeze_*
		tempfile squeeze
		save `squeeze', replace
		clear

		** squeeze  and save secondary causes
		restore
		drop if variable_name == ""
	
		merge m:1 age_group_id using `squeeze', keep(1 3) nogen
			
		forvalues c = 0/999 {
			qui replace squeeze_`c' = 1 if variable_name == "`sev'_vita" | variable_name == "`sev'_rop"
			qui replace draw_`c' = draw_`c' * squeeze_`c'
		}
	
		//Save for diagnostics (includes squeeze factor)
		if `cluster' == 1 save "`tmp_dir'/`sev'_squeezed_`location_id'_`year_id'_`sex_id'", replace 

		drop squeeze_*
		cap drop if variable_name == ""
		sort variable_name age_group_id
		tempfile working_`sev'_temp
		save `working_`sev'_temp', replace
		
	}

**********************
** SAVE the vision modelable entities...			
**********************	
	insheet using "`in_dir'/output_vision_meid_codebook.csv", clear
	drop if regexm(variable_name, "ref_error") // refractive error was saved in step 03
	drop if healthstate == "vision_near" //near vision dealt with after this loop 
	count
	local r = r(N)
	di "`r' rows idenitified"
	
	preserve
	forvalues row=1/`r' {
		// id modelable entity we want to save
		keep in `row'
		levelsof acause, local(acause) c
		levelsof grouping, local(grouping) c
		levelsof healthstate, local(healthstate) c
		levelsof sev, local(sev) c
		levelsof variable_name, local(name) c
		levelsof modelable_entity_id, local(meid) c
	
		// bring in the specific etiology/sev for this modelable entity
		use `working_`sev'_temp', clear
		keep if variable_name == "`name'"
		drop variable_name
		
		// save this one
		di in red "SAVING `name'"
		
		cap mkdir "`out_dir'/03_outputs/01_draws/`meid'"
		
		outsheet using "`out_dir'/03_outputs/01_draws/`meid'/5_`location_id'_`year_id'_`sex_id'.csv", comma replace
		
		restore, preserve
	}
	restore, not
								
		
		//Pull 2424, save as 2324
		local meid 2324
		get_draws, gbd_id_field(modelable_entity_id) source(epi) gbd_id(2424) measure_ids(5) location_ids(`location_id') sex_ids(`sex_id') year_ids(`year_id') clear
		cap mkdir "`out_dir'/03_outputs/01_draws/`meid'"
		outsheet using "`out_dir'/03_outputs/01_draws/`meid'/5_`location_id'_`year_id'_`sex_id'.csv", comma replace

											
	clear
	
		//Next sex	
		}
	//Next year 
	}
