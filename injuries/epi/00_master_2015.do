// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Launch any or all steps of the nonfatal injuries process
//				

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// SET GLOBALS

   // define directory that contains steps code (cloned repo)
      local code_dir = "/ihme/code/injuries/ngraetz/inj/gbd2015"
   // define directory that will contain results
      local out_dir = "/snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015"
   // define directory on clustertmp that holds intermediate files
      local tmp_dir = "/ihme/injuries"
   // define the date of the run in format YYYY_MM_DD: 2014_01_09
	  local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
      local date = subinstr(`"`date'"'," ","_",.)
	// define the steps to run as space-separated list: 01 02 03a 03b (blank for all)
		local steps = ""
	// define the sequence of your steps (1=run parallelized on the cluster, 0=run in series to check intermediate results)
		local parallel 0

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// RUN MODEL (NO NEED TO EDIT BELOW THIS LINE)

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

// Copy some necessary inputs that are manually generated from a previous GBD. Will need to write code if these ever change.
	// Follow-up studies
	if regexm("`steps'", "02b") == 1 {
		cap mkdir "`out_dir'/03_steps/`date'/01b_pooled_followup"
		cap mkdir "`out_dir'/03_steps/`date'/01b_pooled_followup/03_outputs"
		cap mkdir "`out_dir'/03_steps/`date'/01b_pooled_followup/03_outputs/03_other"
		import delimited "$prefix/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/01b_pooled_followup/03_outputs/03_other/pooled_followup_studies.csv", delim(",") varn(1) case(preserve) clear
		export delimited "`out_dir'/03_steps/`date'/01b_pooled_followup/03_outputs/03_other/pooled_followup_studies.csv", delim(",") replace
		file open finished using "`out_dir'/03_steps/`date'/01b_pooled_followup/finished.txt", replace write
		file close finished
	}

// run model
	model_custom, code_dir("`code_dir'") out_dir("`out_dir'") tmp_dir("`tmp_dir'") date("`date'") steps("`steps'") parallel(`parallel')
	
