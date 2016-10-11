// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	multiply short-term incidences by durations to get prevalence of short-term injury outcomes by ecode-ncode-platform, then multiply by DW to get YLDs

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// PREP STATA (DON'T EDIT)

	// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

// If no check global passed from master, assume not a test run
	if "`1'" == "" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "05a"
		local 5 scaled_short_term_en_prev_yld_by_platform

		local 8 "/share/code/injuries/ngraetz/inj/gbd2015"
	}
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
    // directory where the code lives
    local code_dir `8'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for standard code files
	adopath + "$prefix/WORK/10_gbd/00_library/functions"

	// write log if running in parallel and log is not already open
	log using "`out_dir'/02_temp/02_logs/`step_num'.smcl", replace name(master)
	
	// check for finished.txt produced by previous step
	if "`hold_steps'" != "" {
		foreach step of local hold_steps {
			local dir: dir "$prefix/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/03_steps/`date'" dirs "`step'_*", respectcase
			// remove extra quotation marks
			local dir = subinstr(`"`dir'"',`"""',"",.)
			capture confirm file "$prefix/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/03_steps/`date'/`dir'/finished.txt"
			if _rc {
				di "`dir' failed"
				** BREAK
			}
		}
	}	
	
// Filepaths
	local gbd_ado "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local dw_out_dir  "`out_dir'/01_inputs"
	local stepfile "`code_dir'/`functional'_steps.xlsx"
	
// Import functions & start timer
	adopath + "`code_dir'/ado"
	adopath + `gbd_ado'	
	local slots 1	


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
	
// SET LOCALS
// set memory (gb) for each job
	local mem 2
// set type for pulling different years (cod/epi); this is used for what parellel jobs to submit based on cod/epi estimation demographics, not necessarily what inputs/outputs you use
	local type "epi"
// set subnational=no (drops subnationals) or subnational=yes (drops national CHN/IND/MEX/GBR)
	local subnational "yes"
// set code file from 01_code to run in parallel (change from template; just "name.do" no file path since it should be in same directory)
	local code "`step_name'/calculate_st_prev_ylds.do"
// Set this local to 0 if you want to zip up all old files and/or clean the 02_temp folder when you are done running this step
	local debug 0

// Get short-term (st) DWs using custom function
local category "st"
get_ncode_dw_map, out_dir("`dw_out_dir'") category("`category'") prefix("$prefix")

** now we insheet that file and save as a stata file for easy access throughout the jobs
import delimited "`dw_out_dir'/`category'_dws_by_ncode.csv", delim(",") clear asdouble
save "`dw_out_dir'/`category'_dws_by_ncode.dta", replace

get_demographics, gbd_team("epi")
get_populations, year_id($year_ids) location_id($location_ids) sex_id($sex_ids) age_group_id($age_group_ids) clear
save "`dw_out_dir'/pops.dta", replace

// parallelize by location/year/sex
foreach location_id of global location_ids {
	foreach year of global year_ids {
		foreach sex of global sex_ids {
		! qsub -P proj_injuries -o /share/temp/sgeoutput/ngraetz/output -e /share/temp/sgeoutput/ngraetz/errors -N stprev_`location_id'_`year'_`sex' -pe multi_slot 4 -l mem_free=8 "`code_dir'/stata_shell.sh" "`code_dir'/`code'" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `location_id' `year' `sex'"
		}
	}
}


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
