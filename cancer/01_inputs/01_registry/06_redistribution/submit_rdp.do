
// Purpose:		Creates file that can be submitted to redistribution, then submits that file

** **************************************************************************
** CONFIGURATION (autorun)
** 		Sets application preferences (memory allocation, variable limits) 
** 		Accepts/Sets Arguments. Defines the J drive location. Loads external functions.
** **************************************************************************
// Clear memory and set memory and variable limits
	clear all
	set mem 5G
	set maxvar 32000
	set more off

// Accept Arguments
	args group_folder data_name data_type resubmit
	
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" global j "J:"	
		
	if inlist("`group_folder'", "", "none") local data_folder = "$j/WORK/07_registry/cancer/01_inputs/sources/`data_name'" 
	else local data_folder = "$j/WORK/07_registry/cancer/01_inputs/sources/`group_folder'/`data_name'"  // autorun

	global data_type = "`data_type'"
		
** ****************************************************************
** Set Macros
**	Data Types, Folder and Script Locations
** ****************************************************************
// Metric Name (cases or deaths) and YLD
	if "$data_type" == "inc" {
		global metric_name = "cases"
		global yll_or_yld = "yld"
	}
	if "$data_type" == "mor" {
		global metric_name = "deaths"
		global yll_or_yld = "yll"
	}

// Code folder
	local code_folder = subinstr("`data_folder'", "$j/", "", 1) + "/code" // no prefix so that it can be sent to python file
	local programs_folder = "$j/WORK/07_registry/cancer/01_inputs/programs"
	
// Input Folder
	global input_folder = "`data_folder'/data/intermediate"
	
// Output folder
	global output_folder "`data_folder'/data/intermediate"
	global archive_folder "`output_folder'/_archive"
	capture mkdir "`output_folder'"
	capture mkdir "`archive_folder'"

** ****************************************************************
** Create Log if running on the cluster
** 		Get date. Close open logs. Start Logging.
** ****************************************************************
// Get date
	local today = date(c(current_date), "DMY")
	global today = string(year(`today')) + "_" + string(month(`today'),"%02.0f") + "_" + string(day(`today'),"%02.0f")

if c(os) == "Unix" {
// Log folder
	local log_folder "/ihme/gbd/WORK/07_registry/cancer/logs/01_inputs/redistribution"
	cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs"
	cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs/01_inputs"
	cap mkdir "`log_folder'"

// Start Log
	capture log close
	 log using "`log_folder'/submit_redistribution_$data_type_$today.log", replace
}
	
** **************************************************************************
** Prepare Data for RDP
** **************************************************************************
// prepare rdp file
	do "$j/WORK/07_registry/cancer/01_inputs/programs/redistribution/code/prep_rdp.do" 

** ****************************************************************
** Prepare Scripts then Run RDP   (need to edit so that it calls python script directly - cmaga 6/2015) 
** ****************************************************************
// Submit job
	do "$j/WORK/07_registry/cancer/01_inputs/programs/redistribution/code/cancer_rdp_master.do" "`group_folder'" "`data_name'" "$data_type" `resubmit'
	
** **************************************************************************
**  END cancer_submit.do
** **************************************************************************
