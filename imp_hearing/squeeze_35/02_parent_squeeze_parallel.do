// *********************************************************************************************************************************************************************
** Description:	squeeze parent hearing envelope with discrete categories (0-19 dB, 20-34 dB, 35-49 dB, 50-64 dB, 80-94 dB, 95+ dB) and 35+ inf
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
	

		** load DisMod draws for hearing loss envelopes 
		local meids "2788 2629 2406 2630 2631 2632 2633 2410"


		foreach healthstate in _hearing_0_19db _hearing_20_34db _hearing_35db _hearing_35_49db _hearing_50_64db _hearing_65_79db _hearing_80_94db _hearing_95db  { 
		   if "`healthstate'" == "_hearing_0_19db" local meid 2788 
		   if "`healthstate'" == "_hearing_20_34db" local meid 2629
		   if "`healthstate'" == "_hearing_35db" local meid 2406
		   if "`healthstate'" == "_hearing_35_49db" local meid 2630
		   if "`healthstate'" == "_hearing_50_64db" local meid 2631
		   if "`healthstate'" == "_hearing_65_79db" local meid 2632
		   if "`healthstate'" == "_hearing_80_94db" local meid 2633
		   if "`healthstate'" == "_hearing_95db" local meid 2410

		   	di "" _new "***" _new "" _new "LOADING DISMOD DRAWS FOR MEID `meid' HEALTHSTATE `healthstate'" _new "" _new "***"
		   
		   	//load prevalence draws
		 		  	get_draws, gbd_id_field(modelable_entity_id) source(epi) gbd_id(`meid') measure_ids(5) location_ids(`location_id') clear
					keep if age_group_id <= 21 
			
			//save temp file 
				tempfile `healthstate'_draws 
				save ``healthstate'_draws', replace
			}
		

//Loop over every year and sex for given location 
	//year_ids
		local year_ids "1990 1995 2000 2005 2010 2015"
	//sex_ids
		local sex_ids "1 2"

	foreach year_id in `year_ids' {
		foreach sex_id in `sex_ids' {


		** run whatever transformations on draws you need here
		** combine all info into one file
			
			local i 0 
			foreach db in 0_19db 20_34db 35db 35_49db 50_64db 65_79db 80_94db 95db {
				use `_hearing_`db'_draws' if year_id == `year_id' & sex_id == `sex_id', clear
				rename draw* draw*_`db'
				if `i' == 0 tempfile working_temp 
				else merge 1:1 age_group_id using `working_temp', nogen
				save `working_temp', replace
				local ++ i 
				}

	

		
			local draw 0
			quietly {
				forvalues draw = 0/999 {
					noisily di in red "Draw `draw'!! `step_name' loop 1 ~~~ year `year_id' sex `sex_id'"
		
					use `working_temp', clear		
					
					** (1) squeeze 35+, 0-19, and 20-34 to sum up to 1 
					
						gen total= draw_`draw'_0_19db + draw_`draw'_20_34db + draw_`draw'_35db
						
						foreach db in 0_19db 20_34db 35db {
							gen draw_`draw'_`db'_squeeze1 = draw_`draw'_`db' * (1/total)
						}
						
						drop total						
					
					** (2) squeeze categorical results into 35+ parent envelope 
						
						gen total= draw_`draw'_35_49db + draw_`draw'_50_64db + draw_`draw'_65_79db + draw_`draw'_80_94db + draw_`draw'_95db
						

						foreach db in 35_49db 50_64db 65_79db 80_94db 95db {
							gen draw_`draw'_`db'_prop = draw_`draw'_`db' * (1/total)
							gen draw_`draw'_`db'_squeeze2 = draw_`draw'_`db'_prop * draw_`draw'_35db_squeeze1
							}
						
						drop total						
					
					** rename prevalence estimates for the categories of interest
						gen draw_`draw'_20 = draw_`draw'_20_34db_squeeze1
						gen draw_`draw'_35 = draw_`draw'_35_49db_squeeze2
						gen draw_`draw'_50 = draw_`draw'_50_64db_squeeze2
						gen draw_`draw'_65 = draw_`draw'_65_79db_squeeze2
						gen draw_`draw'_80 = draw_`draw'_80_94db_squeeze2
						gen draw_`draw'_95 = draw_`draw'_95db_squeeze2
					
					
					save `working_temp', replace
				}
			}
			
			use `working_temp', replace

			
		** save draws in intermediate location
			format draw* %16.0g
			save "`tmp_dir'/03_outputs/01_draws/categorical_prevalence_envelopes_`location_id'_`year_id'_`sex_id'.dta", replace
			
	
		
		//Next sex	
		}
	//Next year 
	}
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// CHECK FILES (NO NEED TO EDIT THIS SECTION)

cap log close 

	// write check file to indicate sub-step has finished
		file open finished using "`tmp_dir'/02_temp/01_code/checks/finished_loc`location_id'.txt", replace write
		file close finished
