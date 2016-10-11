/*******************************************
Description: This is the first lower-level script submitted by 
06_save_results.do. 06_save_results_parallel.do does two things: 
1. submits another lower-level script (not parallelized)
that formats mild_imp prevalence data and runs save_results 
(we do not run a second DisMod model for mild impairment) and 
2. appends and formats modsev prevalence data and saves it to 04_big_data for 
upload into the final DisMod model. 

*******************************************/

clear all 
set more off
set maxvar 30000
version 13.0

// priming the working environment
if c(os) == "Windows" {
			local j "J:"
			local working_dir = "H:/neo_model"
		}
		if c(os) == "Unix" {
			local j "/home/j"
			ssc install estout, replace 
			ssc install metan, replace
			local working_dir = "/homes/User/neo_model" 
		} 

// arguments
local acause `1'
local me_id `2'

// test arguments
/*local acause "neonatal_preterm"
local me_id 1557*/

// locals

// directories
local out_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/temp_outputs"
local upload_dir "`j'/WORK/04_epi/01_database/02_data"

// functions
run "`j'/WORK/10_gbd/00_library/functions/save_results.do"
run "`j'/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
run "`j'/WORK/10_gbd/00_library/functions/get_outputs_helpers/query_table.ado"

******************************************************************

// submit mild/asymp (prevalence only) jobs - will get into format for save_results function (because we don't run DisMod for mild/asymp)
!qsub -pe multi_slot 20 -l mem_free=8g -N mild_prev_save_`me_id' -P proj_custom_models "`working_dir'/stata_shell.sh" "`working_dir'/enceph_preterm_sepsis/model_custom/save_results/06_save_results_parallel_parallel_mild.do" "`acause' `me_id'"
!qsub -pe multi_slot 20 -l mem_free=8g -N asymp_prev_save_`me_id' -P proj_custom_models "`working_dir'/stata_shell.sh" "`working_dir'/enceph_preterm_sepsis/model_custom/save_results/06_save_results_parallel_parallel_asymp.do" "`acause' `me_id'"

// submit modsev jobs for each age
local ages 0 2 3 4
foreach age_id in `ages' {
	!qsub -pe multi_slot 20 -l mem_free=8g -N modsev_save_results_`me_id'_`age_id' -P proj_custom_models "`working_dir'/stata_shell.sh" "`working_dir'/enceph_preterm_sepsis/model_custom/save_results/06_save_results_parallel_parallel_modsev.do" "`acause' `me_id' `age_id'"
}
