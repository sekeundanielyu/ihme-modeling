** **************************************************************************
// Purpose:	Launch steps to process compiled incidence and mortality registry data and get it ready for various modeling processes
** **************************************************************************
** **************************************************************************
** Configuration
** 		Sets application preferences (memory allocation, variable limits) 
** 		Accepts/Sets Arguments. Defines the J drive location.
** **************************************************************************

// Clear memory and set memory and variable limits
	clear all
	set more off

// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"
	
// Get date
	local today = date(c(current_date), "DMY")
	local year = string(year(`today')) + "_" + string(month(`today'),"%02.0f") + "_" + string(day(`today'),"%02.0f")
	local time =  substr("`c(current_time)'", 1, length("`c(current_time)'") - 3)
	
** **************************************************************************
** SET DIRECTORY AND DETERMINE WHICH STEPS TO RUN
** **************************************************************************		
// database directory
	global directory "$j/WORK/07_registry/cancer/04_outputs/01_mortality_incidence"
	
// Select Steps to Run: 1 = yes, 0 = no
	// Compile MI results
		local step_01_CMR	 				= 0

	// Drop and Check
		local step_02_DaC	 				= 1
		
	// Combine and Project
		local step_03_CaP	 				= 0

	// Combine and Project
		local step_04_VaC	 				= 0

** **************************************************************************
** Launch Scripts 
** **************************************************************************	
// Remind User to Record Prep
	noisily di in red "Remember to record data compile in sources/00_Documentation/DataPrep_and_DataCompile_Records.xlsx"
	
	local time_start = "`time'"
	di "$directory'"
	
	if `step_01_CMR' == 1{
		do "$directory/code/01_compile_postModel_MI_master.do"
	}
	
	if `step_02_DaC' == 1{
		do "$directory/code/02_drop_andCheck.do" 
	}
	
	if `step_03_CaP' == 1{
		do "$directory/code/03_combine_andProject.do"
	}
	
	if `step_04_VaC' == 1 {
		do "$directory/code/04_validate_andCalculateDeaths.do" 
	}

	local time_end = substr("`c(current_time)'", 1, length("`c(current_time)'") - 3)
	di "started at `time_start', ended at `time_end'"
	
** **************************************************************************
** END
** **************************************************************************	
