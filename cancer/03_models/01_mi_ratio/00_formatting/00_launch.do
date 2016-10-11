
// Purpose:	Launch steps to process compiled incidence and mortality registry data and get it ready for various modeling processes

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
	
** **************************************************************************
** SELECT SCRIPTS TO RUN (Manual Input)
** **************************************************************************		
// database directory
	global directory "$j/WORK/07_registry/cancer/02_database/01_mortality_incidence"
	local sources_dir "$j/WORK/07_registry/cancer/01_inputs/sources"
	
// Select Steps to Run: 1 = yes, 0 = no
	// Re-Format CoD VR Data
		local step_00_CoD_VR				= 0

	// Compile by Type
		local step_01_CPD	 				= 1 

	// Merge and Refine
		local step_02_MaR	 				= 1

	// Drop and Check
		local step_03_DaC	 				= 1

	// Calculate MI Ratio
		local step_04_fin	 				= 0
	
** **************************************************************************
** Launch Scripts 
** **************************************************************************	
// Get date
	local today = date(c(current_date), "DMY")
	global today = string(year(`today')) + "_" + string(month(`today'),"%02.0f") +"_"+ string(day(`today'),"%02.0f")
	local time =  substr("`c(current_time)'", 1, length("`c(current_time)'") - 3)

// Remind User to Record Prep
	noisily di in red "Remember to record data compile in sources/00_Documentation/DataPrep_and_DataCompile_Records.xlsx"
	
	local time_start = "`time'"
	di "$directory'"

// Run the selected scripts	
	if `step_00_CoD_VR' {
		do "/home/j/WORK/07_registry/cancer/01_inputs/sources/COD_VR/COD_VR/code/format_COD_VR.do"
	}

	if `step_01_CPD' {
		do "$directory/code/01_compile_prepped_data.do" "$today" "$directory" `sources_dir'
	}
	
	if `step_02_MaR' {
		do "$directory/code/02_merge_andRefine.do" "$today" "$directory" 
	}
	
	if `step_03_DaC' {
		do "$directory/code/03_drop_andCheck.do" "$today"
	}
	
	if `step_04_fin' {
		do "$directory/code/04_finalize.do" "$today" "$directory"
	}
	
	local time_end = substr("`c(current_time)'", 1, length("`c(current_time)'") - 3)
	di "started at `time_start', ended at `time_end'"
	
** **************************************************************************
** END
** **************************************************************************	
