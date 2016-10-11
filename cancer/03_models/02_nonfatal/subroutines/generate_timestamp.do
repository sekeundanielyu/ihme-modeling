// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Generates a timestamp in the format of the gbd databases

** **************************************************************************
** 			
** **************************************************************************

// Set timestamp. 
	local date = c(current_date)
	local time = c(current_time)
	local today = date("`date'", "DMY")
	local year = year(`today')
	local month = month(`today')
	local day = day(`today')
	local length : length local month
	if `length' == 1 local month = "0`month'"
	local length : length local day
	if `length' == 1 local day = "0`day'"
	global timestamp = "`year'-`month'-`day' `time'"

** **************************************************************************
** 	END	
** **************************************************************************
