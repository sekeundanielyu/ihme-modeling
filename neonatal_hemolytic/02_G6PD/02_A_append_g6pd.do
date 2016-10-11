******************************************************************************************************
** NEONATAL HEMOLYTIC MODELING
** PART 2: G6PD
** Part A: Prevalence of G6PD
** 6.9.14

** We get G6PD prevalence from the GBD Dismod models of congenital G6PD (modeled by Nick Kassebaum in
** GBD2013).  This script simply finds the outputs for the Dismod model number Nick gave me, and 
** appends them all into one big dataset for use in my later code.  

** Note - this script replaces the python one from GBD2013. 
*****************************************************************************************************


clear all
set more off
set graphics off
set maxvar 32000


/*  //////////////////////////////////////////////
		WORKING DIRECTORY
////////////////////////////////////////////// */ 

// discover root
	if c(os) == "Windows" {
		local j "J:"
		// Load the PDF appending application
		quietly do "`j'/Usable/Tools/ADO/pdfmaker_acrobat11.do"
	}
	if c(os) == "Unix" {
		local j "/home/j"
		ssc install estout, replace 
		ssc install metan, replace
	} 
	

// locals
local me_id 2112 // "G6PD deficiency"

// functions
run "`j'/WORK/10_gbd/00_library/functions/fastpctile.ado"
run "`j'/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
run "`j'/WORK/10_gbd/00_library/functions/get_draws.ado"

// directories 	
	local working_dir = "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/01_prep/neonatal_hemolytic/02_g6pd"
	local log_dir = "`j'/temp/User/neonatal/logs/neonatal_hemolytic"
	local out_dir "`working_dir'"
	capture mkdir "`out_dir'"
	
	local plot_dir "`out_dir'/time_series"
	capture mkdir "`plot_dir'"
	
// Create timestamp for logs
    local c_date = c(current_date)
    local c_time = c(current_time)
    local c_time_date = "`c_date'"+"_" +"`c_time'"
    display "`c_time_date'"
    local time_string = subinstr("`c_time_date'", ":", "_", .)
    local timestamp = subinstr("`time_string'", " ", "_", .)
    display "`timestamp'"

	
	//log
	capture log close
	log using "`log_dir'/02_A_append_g6pd_`timestamp'.smcl", replace

************************************************************************************

// get draws from best congenital G6PD model 
get_draws, gbd_id_field(modelable_entity_id) gbd_id(`me_id') source(epi) measure_ids(5) location_ids() year_ids() age_group_ids(2) sex_ids() status(best) clear
tempfile g6pd_data
save `g6pd_data'

// store best model version 
local best_model_version = model_version_id[1]

// format
keep location_id sex_id year_id draw*
rename sex_id sex 
rename year_id year

// export 
export delimited "`out_dir'/g6pd_model_`best_model_version'_prev.csv", replace
