// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// SET GLOBALS

	// define directory that contains steps code
	local code_dir = "/homes/User/neo_model/enceph_preterm_sepsis/model_custom"
	// define directory that will contain results
	local out_dir = "/ihme/scratch/users/User/neonatal/enceph_preterm_sepsis"
	// define directory on clustertmp that holds intermediate files
	local tmp_dir = "/ihme/scratch/users/User/neonatal/temp_e_p_s" 
	// define the date of the run in format YYYY_MM_DD: 2014_01_09
	local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
	local date = subinstr(`"`date'"'," ","_",.)
	// define the steps to run as space-separated list: 01 02 03a 03b (blank for all)
	local steps = "06"
	// define the sequence of your steps (1=run parallelized on the cluster, 0=run in series to check intermediate results)
	local parallel 0

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// RUN MODEL
// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	cap log close
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	if "`steps'" == "" local steps "_all"
	qui run "$prefix/WORK/10_gbd/00_library/functions/model_custom/model_custom.ado" 
	
// run model
	model_custom, code_dir("`code_dir'") out_dir("`out_dir'") tmp_dir("`tmp_dir'") date("`date'") steps("`steps'") parallel(`parallel')
	
