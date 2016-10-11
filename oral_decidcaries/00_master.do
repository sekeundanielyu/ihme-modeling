// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 		08 August 2014
// Updated on 2 February 2016
// Purpose:	Perform post-DisMod modifications to oral conditions
// do "/home/j/WORK/04_epi/02_models/01_code/06_custom/oral/00_master.do"

/*
Oral model tags :
oral_edent			2337	Edentulism and severe tooth loss
oral_edent			2584	Difficulty eating due to edentulism and severe tooth loss
oral_perio			2336	Chronic periodontal diseases
oral_permcaries		2335	Permanent caries
oral_permcaries		2583	Tooth pain due to permanent caries
oral_decidcaries	2334	Deciduous caries
oral_decidcaries	2582	Tooth pain due to deciduous caries

STEPS BY CAUSE:
	oral_edent
		1) split parent [2337] by 0.444(0.438 – 0.451) to get difficulty eating [2584]
	oral_perio
		2) multiply model by *(1-prev_2337) at the CYAS level
	oral_permcaries
		3) multiply parent model by *(1-prev_2337) at the CYAS level
		4) split into tooth pain...
			- Data-rich = 0.0595 (0.0506 - 0.0685)
			- Data-poor = 0.0997 (0.0847 - 0.1146)
	oral_decidcaries
		5 ) split into tooth pain...
			- Data-rich = 0.0233 (0.0198 - 0.0268)
			- Data-poor = 0.0380 (0.0323 - 0.0437)
*/

// PREP STATA
	clear
	set more off
	pause on
	set maxvar 3200
	if c(os) == "Unix" {
		global prefix "/home/j/"
		set odbcmgr unixodbc
		set maxvar 32767
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		set maxvar 32767
	}

	// make connection string
	run "$prefix/WORK/10_gbd/00_library/functions/create_connection_string.ado"
	create_connection_string, database(epi) server(modeling-epi-db)
	local epi_str = r(conn_string)

// ****************************************************************************
// Manually defined macros
	** User
	local username USER

	** Steps to run (1 2 3 4 5 from above)
	** If you run steps 2 and 3, you MUST also run the severity split of 4 and 5. Run one at a time.
	local run_steps 1 2 3 4 5

	** Modelable_entity_ids to upload (2335 2336 2582 2583 2584 3091 3092 3093)
	local me_uploads 2335 2336 2582 2583 2584 3091 3092 3093

	** Sweep directory
	local sweep 0

	** Where is your local repo for this code?
	local prog_dir "/homes/`username'/oral_custom_code"
// ****************************************************************************
// Directory macros
	local tmp_dir "/ihme/gbd/WORK/04_epi/02_models/01_code/06_custom/oral"
	capture mkdir "`tmp_dir'"

// ****************************************************************************
// Load current best models
	local edent_id 2337
	local perio_id 2336
	local permcaries_id 2335
	local decidcaries_id 2334
	odbc load, exec("SELECT model_version_id, modelable_entity_id, best_user FROM epi.model_version WHERE is_best = 1 and modelable_entity_id IN(`edent_id', `perio_id', `permcaries_id', 'decidcaries_id')") `epi_str' clear
	count if (best_user != "user1") & (best_user != "user2") & (modelable_entity_id == `perio_id' | modelable_entity_id == `permcaries_id')
	if `r(N)' > 0 {
		quietly {
			noisily di "Are you running periodontal or the permanent caries parent (steps 2 or 3)?"
			noisily di "Split models are already marked as best."
			noisily di `"Type "q" to continue..."'
			pause
			sleep 1000
			noisily di "CONTINUING"
		}
	}


// Load countries
	odbc load, exec("SELECT location_id FROM shared.location_hierarchy_history INNER JOIN shared.location USING(location_id) WHERE location_set_version_id = (SELECT location_set_version_id FROM shared.location_set_version lsv WHERE location_set_id = 35 AND gbd_round = 2015 AND end_date IS NULL) AND most_detailed = 1 ORDER BY sort_order") `epi_str' clear
	levelsof location_id, local(locations)

// ****************************************************************************
foreach run_step of local run_steps {
// 1) oral_edent --> split parent [2337] by 0.444(0.438 – 0.451) to get difficulty eating [2584]
	if `run_step' == 1 {
		** Set up results directory
		local child_id 2584
		local asymp_id 3093
		capture mkdir "`tmp_dir'/`child_id'"
		capture mkdir "`tmp_dir'/`child_id'/00_logs"
		capture mkdir "`tmp_dir'/`child_id'/01_draws"
		capture mkdir "`tmp_dir'/`asymp_id'"
		capture mkdir "`tmp_dir'/`asymp_id'/01_draws"
		** Bootstrap
		clear
		local M = 0.444
		local L = 0.438
		local U = 0.451
		local SE = (`U'-`L')/(2*1.96)
		drawnorm prop_, n(1000) means(`M') sds(`SE')
		gen num = _n
		replace num = num-1
		gen metric = "prevalence_incidence"
		reshape wide prop_, i(metric) j(num)
		saveold "`tmp_dir'/`child_id'/tooth_loss_split.dta", replace
		foreach loc of local locations {
			!qsub -P proj_custom_models -pe multi_slot 4 -l mem_free=8g -N "tooth_loss_split_`loc'" "`prog_dir'/stata_shell.sh" "`prog_dir'/01_edent_tooth_loss.do" "`tmp_dir' `edent_id' `child_id' `asymp_id' `loc'"
		}
	}

// 2) oral_perio --> multiply model by *(1-prev_2337) at the CYAS level
	if `run_step' == 2 {
		** Set up results directory
		local perio_id 2336
		capture mkdir "`tmp_dir'/`perio_id'"
		capture mkdir "`tmp_dir'/`perio_id'/00_logs"
		capture mkdir "`tmp_dir'/`perio_id'/01_draws"
		foreach loc of local locations {
			!qsub -P proj_custom_models -pe multi_slot 4 -l mem_free=8g -N "perio_split_`loc'" "`prog_dir'/stata_shell.sh" "`prog_dir'/02_03_edent_split_perio_permcaries.do" "`tmp_dir' `edent_id' `perio_id' `loc'"
		}
	}

// 3) oral_permcaries --> multiply parent model by *(1-prev_2337) at the CYAS level
	if `run_step' == 3 {
		** Set up results directory
		local permcaries_id 2335
		capture mkdir "`tmp_dir'/`permcaries_id'"
		capture mkdir "`tmp_dir'/`permcaries_id'/00_logs"
		capture mkdir "`tmp_dir'/`permcaries_id'/01_draws"
		foreach loc of local locations {
			!qsub -P proj_custom_models -pe multi_slot 4 -l mem_free=8g -N "permcaries_split_`loc'" "`prog_dir'/stata_shell.sh" "`prog_dir'/02_03_edent_split_perio_permcaries.do" "`tmp_dir' `edent_id' `permcaries_id' `loc'"
		}
	}

// 4) oral_permcaries --> split parent into tooth pain [Data Rich = 0.0595 (0.0506 - 0.0685) // Data Poor = 0.0997 (0.0847 - 0.1146)]
	if `run_step' == 4 {
		** Set up results directory
		local child_id 2583
		local asymp_id 3092
		capture mkdir "`tmp_dir'/`child_id'"
		capture mkdir "`tmp_dir'/`child_id'/00_logs"
		capture mkdir "`tmp_dir'/`child_id'/01_draws"
		capture mkdir "`tmp_dir'/`asymp_id'"
		capture mkdir "`tmp_dir'/`asymp_id'/01_draws"
		** Bootstrap - DATA-RICH
		clear
		local M = 0.0595
		local L = 0.0506
		local U = 0.0685
		local SE = (`U'-`L')/(2*1.96)
		drawnorm prop_, n(1000) means(`M') sds(`SE')
		gen num = _n
		replace num = num-1
		gen metric = "prevalence_incidence"
		reshape wide prop_, i(metric) j(num)
		saveold "`tmp_dir'/`child_id'/tooth_pain_split_D1.dta", replace
		** Bootstrap - DATA-POOR
		clear
		local M = 0.0997
		local L = 0.0847
		local U = 0.1146
		local SE = (`U'-`L')/(2*1.96)
		drawnorm prop_, n(1000) means(`M') sds(`SE')
		gen num = _n
		replace num = num-1
		gen metric = "prevalence_incidence"
		reshape wide prop_, i(metric) j(num)
		saveold "`tmp_dir'/`child_id'/tooth_pain_split_D0.dta", replace
				odbc load, exec("SELECT location_id, parent_id FROM shared.location_hierarchy_history WHERE location_set_version_id=(SELECT location_set_version_id FROM shared.location_set_version WHERE location_set_id = 43 AND end_date IS NULL)") `epi_str' clear
		gen dev = "D0" if parent_id == 44640
		replace dev = "D1" if parent_id == 44641
		foreach loc of local locations {
			levelsof dev if location_id == `loc', local(dev_stat) c
			!qsub -P proj_custom_models -pe multi_slot 4 -l mem_free=8g -N "perm_tooth_pain_`loc'" -hold_jid "permcaries_split_`loc'" "`prog_dir'/stata_shell.sh" "`prog_dir'/04_05_caries_tooth_pain.do" "`tmp_dir' `permcaries_id' `child_id' `asymp_id' `loc' `dev_stat'"
		}
	}

// 5) oral_decidcaries --> split parent into tooth pain [Data Rich = 0.0233 (0.0198 - 0.0268) // Data Poor = 0.0380 (0.0323 - 0.0437)]
	if `run_step' == 5 {
		** Set up results directory
		local child_id 2582
		local asymp_id 3091
		capture mkdir "`tmp_dir'/`child_id'"
		capture mkdir "`tmp_dir'/`child_id'/00_logs"
		capture mkdir "`tmp_dir'/`child_id'/01_draws"
		capture mkdir "`tmp_dir'/`asymp_id'"
		capture mkdir "`tmp_dir'/`asymp_id'/01_draws"
		** Bootstrap - DEVELOPED
		clear
		local M = 0.0233
		local L = 0.0198
		local U = 0.0268
		local SE = (`U'-`L')/(2*1.96)
		drawnorm prop_, n(1000) means(`M') sds(`SE')
		gen num = _n
		replace num = num-1
		gen metric = "prevalence_incidence"
		reshape wide prop_, i(metric) j(num)
		saveold "`tmp_dir'/`child_id'/tooth_pain_split_D1.dta", replace
		** Bootstrap - DEVELOPING
		clear
		local M = 0.0380
		local L = 0.0323
		local U = 0.0437
		local SE = (`U'-`L')/(2*1.96)
		drawnorm prop_, n(1000) means(`M') sds(`SE')
		gen num = _n
		replace num = num-1
		gen metric = "prevalence_incidence"
		reshape wide prop_, i(metric) j(num)
		saveold "`tmp_dir'/`child_id'/tooth_pain_split_D0.dta", replace
		odbc load, exec("SELECT location_id, parent_id FROM shared.location_hierarchy_history WHERE location_set_version_id=(SELECT location_set_version_id FROM shared.location_set_version WHERE location_set_id = 43 AND end_date IS NULL)") `epi_str' clear
		gen dev = "D0" if parent_id == 44640
		replace dev = "D1" if parent_id == 44641
		foreach loc of local locations {
			levelsof dev if location_id == `loc', local(dev_stat) c
			!qsub -P proj_custom_models -pe multi_slot 4 -l mem_free=8g -N "decid_tooth_pain_`loc'" "`prog_dir'/stata_shell.sh" "`prog_dir'/04_05_caries_tooth_pain.do" "`tmp_dir' `decidcaries_id' `child_id' `asymp_id' `loc' `dev_stat'"
		}
	}

}
// ****************************************************************************
local loc_len : word count `locations'
local year_len 6
local measure_len 2
local need_files = `loc_len' * `year_len' * `measure_len'

foreach me_upload of local me_uploads {
// Upload?
	if `me_upload' != . & `me_upload' != 0 {
		// check if files are ready to be uploaded
		local ready 0
		while `ready' == 0 {
			local list_dir: dir "`tmp_dir'/`me_upload'/01_draws" files "*2.csv"
			local exist_files : word count `list_dir'
			if (`exist_files' < `need_files') sleep 60000
			else local ready 1
			if `ready' == 1 di "Ready to upload `me_upload'!"
		}
		quietly {
			local me_upload_use_`me_upload' = `me_upload'
			local me_upload_use_2336 = 3083
			local me_upload_use_2335 = 3084
			local 2335_comment "non edentulous population applied"
			local 2336_comment "non edentulous population applied"
			local 2582_comment "data-rich proportion: 0.0233 (0.0198 to 0.0268); data-poor proportion: 0.0380 (0.0323 to 0.0437)"
			local 2583_comment "data-rich proportion: 0.0595 (0.0506 to 0.0685); data-poor proportion: 0.0997 (0.0847 to 0.1146)"
			local 2584_comment "global proportion: 0.444 (0.438 to 0.451)"
			local 3091_comment "remainder of parent attributed to asymptomatic"
			local 3092_comment "remainder of parent attributed to asymptomatic"
			local 3093_comment "remainder of parent attributed to asymptomatic"
			noisily di "ID: `me_upload'... ``me_upload'_comment'"
			qui do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
			save_results, modelable_entity_id(`me_upload_use_`me_upload'') metrics("incidence prevalence") description("``me_upload'_comment'") in_dir("`tmp_dir'/`me_upload'/01_draws") mark_best("yes")
			noisily di "UPLOADED -> " c(current_time)
		}
	}
}
// ****************************************************************************
// Clear draws?
	if `sweep' == 1 {
		!rm -rf "`tmp_dir'"
	}

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
