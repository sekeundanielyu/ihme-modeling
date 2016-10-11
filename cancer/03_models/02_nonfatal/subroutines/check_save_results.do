// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Checks the Epi database for an upload with the requested parameters (arguments), then saves the requested verification file. For use after save results

** **************************************************************************
** 			
** **************************************************************************
// accept arguments
	args timestamp modelable_entity_id description verification_file

// Toggle connection settings
	run "[filepath]/functions/create_connection_string.ado"
	create_connection_string, server("modeling-epi-db")
	local epi_conn = r(conn_string)	

// verify upload
	noisily di "checking with query 'SELECT * from epi.model_version WHERE last_updated > '`timestamp'' AND modelable_entity_id=`modelable_entity_id' AND description='`description'' AND model_version_status_id=1'"
	odbc load, exec("SELECT * from epi.model_version WHERE last_updated > '`timestamp'' AND modelable_entity_id=`modelable_entity_id' AND description='`description'' AND model_version_status_id=1") `epi_conn' clear
	di _N
	if !_N local upload_error = 1
	else local upload_error = 0

// 
	if `upload_error' {
		noisily di "ERROR: Error during upload."
		exit, clear
	}
	else{
		// save file indicating completion
		clear
		set obs 1
		generate str var1 = "done"
		save "`verification_file'", replace
	}
** **************************************************************************
** 	END	
** **************************************************************************	
