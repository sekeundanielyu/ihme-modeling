// Date: May 11, 2015
// Purpose: Secondhand-smoke extraction from DHS

***********************************************************************************
** SET UP
***********************************************************************************

// Set application preferences
	clear all
	set more off
	cap restore, not
	set maxvar 32700
	
// change directory
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	cd "$prefix/WORK/04_epi/01_database/01_code/02_central/survey_juicer"

// import functions
	run "./svy_extract_admin/populate_codebooks.ado"
	run "./svy_extract_admin/make_mirror.ado"
	run "./svy_search/svy_search_assign.ado"
	run "./svy_extract/svy_extract_assign.ado"
	run "./svy_extract/svy_encode_apply.ado"
	run "./tabulations/svy_svyset.ado"
	run "./tabulations/svy_subpop.ado"
	run "./tabulations/svy_group_ages.ado"
	
	local rerun_search 0
	
// log file 

log using "$prefix/WORK/05_risk/02_models/abuse_ipv/01_exp/01_tabulate/data/raw/search_vars.smcl"

***********************************************************************************
** RUN SEARCH
***********************************************************************************

// if `rerun_search' == 1 {

// run search for variables (currently case sensative must fix this!!!!!)
	svy_search_assign , /// 
	job_name(ipv_search_vars) /// 																					This is what your final file will be named
	output_dir($prefix/WORK/05_risk/risks/abuse_ipv_exp/data/exp/01_tabulate/raw) /// 							This is where your final file will be saved
	svy_dir($prefix/DATA/MACRO_DHS) ///																				This is the directory of the data you want to search through
	lookat("d105" "D105" "v005" "v007" "v012" "v013" "v021" "v022" "d005" "psu" "primary sampling" "pweight" "strata" "stratum" "v024") /// 	These are the variable names you want to search for
	recur ///																										This tells the program to look in all sub directories
	variables //																										This tells the program to at variable names
	

***********************************************************************************
** CREATE MIRROR DIRECTORY
***********************************************************************************
	
// make a mirror directory of J:/DATA/MACRO_DHS
	make_mirror, ///
	data_root($prefix/DATA/MACRO_DHS) ///																	This is the directory that you want to make a copy ok
	mirror_location($prefix/WORK/05_risk/risks/abuse_ipv_exp/data/exp/01_tabulate/raw/dhs) //			This is where you want to save the copy
	
