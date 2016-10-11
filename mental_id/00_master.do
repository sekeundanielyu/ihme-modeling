// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This master file runs the steps involved in cod/epi custom modeling for a functional group, using the steps spreadsheet as a template for launching the code
//				This master file should be used for submitting all steps or selecting one or more steps to run in "steps" global

** Description:	run id custom code

//To run master code:
	** qlogin
	** cd /ihme/code/epi/struser/id
	** git checkout develop 
	** git pull https://struser/scm/cudm/id.git develop
	** stata-mp
	** do "/ihme/code/epi/struser/id/00_master.do"

**Three ways to run individual step code: 
		**NOTE: unless you are running all steps from model_custom, you need make sure your directories exist (there are date-stamped out_dir and tmp_dir folders in 03_steps). 
			//Or you use an old output and tmp folder that you rename to today's date 
		*1) locally - Edit cluster_0 settings 
		*2) On cluster, interactively or non-parallelized - Set cluster_check 1 and manually set locals 
		*3) On cluster from master file - Set cluster_check 0 


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
** SET GLOBALS
	

		// define the sequence of your steps (1=run parallelized on the cluster, 0=run in series to check intermediate results)
		local parallel 1
		// define the steps to run as space-separated list: 01 02 03a 03b (blank for all)
		local steps = "02 03 09 99"
		//If you want error and outputs saved to sgeoutput, run special diagnostic ado file


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

	** define directory that contains steps code
		if `parallel' == 0 local code_dir = "C:/Users/struser/Documents/Git/id"
		if `parallel' == 1 local code_dir = "/ihme/code/epi/struser/id"		
	** define directory that will contain results
		//Note: while named "out_dir", this actually is the root j directory, in which output directories are created by model_custom
			//for final runs, change the out_dir from J:/temp/struser to J:/WORK 
     		local out_dir = "$prefix/temp/struser/imp_id"
    ** define directory on clustertmp that holds intermediate files (this is passed into step files as "root_tmp_dir" not "tmp_dir")
    	if `parallel' == 0 local tmp_dir = "$prefix/temp/struser/imp_id/tmp_dir"
    	if `parallel' == 1 local tmp_dir = "/share/scratch/users/struser/id/tmp_dir"
 	** define the date of the run in format YYYY_MM_DD: 2014_01_09
 		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
     	local date = subinstr(`"`date'"'," ","_",.)


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// RUN MODEL (NO NEED TO EDIT BELOW THIS LINE)


	if "`steps'" == "" local steps "_all"
   
  run "$prefix/WORK/10_gbd/00_library/functions/model_custom/model_custom.ado"
   

// run model
	model_custom, code_dir("`code_dir'") out_dir("`out_dir'") tmp_dir("`tmp_dir'") date("`date'") steps("`steps'") parallel(`parallel')
	
