//Master Script for Updated COPD Process
//Step 1: Calculate conversion factor for Gold Class to IHME severities. Only affects USA 2005 and implies some Gold Class Squeezing. Output is age/sex specific factors.
//Step 2: Squeeze gold class draws, apply conversion factors to convert from gold class to severity.
//Step 3: Upload data.

//prepare stata
	clear all
	set more off
	
	macro drop _all
	set maxvar 32000
// Set to run all selected code without pausing
	set more off
// Remove previous restores
	cap restore, not
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		local prefix "/home/j"
		set odbcmgr unixodbc
		local code "/ihme/code/epi/strUser/nonfatal/COPD"
		local stata_shell "/ihme/code/epi/strUser/nonfatal/stata_shell.sh"
		local output "/share/scratch/users/strUser/copd/"
	}
	else if c(os) == "Windows" {
		local prefix "J:"
		local code "C:\Users\strUser\Documents\Code\nonfatal\COPD"
	}
	
	local ver_desc = "v13"
	local folder_name = "`ver_desc'"
	local stage1 0
	local stage2 0
	local stage3 1
	
	//me_ids for folder creation
	local asympt 3065
	local mild 1873
	local moderate 1874
	local severe 1875
	
	//report outputs 
	local test_clust -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors

	
//Stage 1: Create new gold class severity splits
	if `stage1' ==1 {
		do "`code'/01_gc_to_sev_conversion.do" "`ver_desc'"
	}
	
//Stage 2: Apply the conversion to all countries and create COPD severity draws
	if `stage2' == 1 {
		//make a folder to store the results
			cap mkdir "`output'/`folder_name'"
		//now populate the me_ids for the various splits
			cap mkdir "`output'/`folder_name'/`asympt'" 
			cap mkdir "`output'/`folder_name'/`mild'" 
			cap mkdir "`output'/`folder_name'/`moderate'"
			cap mkdir "`output'/`folder_name'/`severe'"
			
		//pull epi locations
		get_location_metadata, location_set_id(9) clear

		local iter 0
		
		local jobs
		//local location_ids 102 68 69 168 165
		foreach loc_id of local location_ids{

			! qsub -N sq_`loc_id'_`iter' -pe multi_slot 4 -P proj_custom_models -l mem_free=4G -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors "`stata_shell'" "`code'/02_squeeze_apply_conversion.do" "`folder_name' `loc_id' `output' `asympt' `mild' `moderate' `severe'"
			
			di "`loc_id' | sq_`loc_id'_`iter'"
			
			local old_id `old_id' sq_`loc_id'_`iter'
			
			local iter = `iter'+1		
			
			
		}
	}

//Stage 3: Upload results
	if `stage3'==1{
		if `stage2' ==1{
			! qsub -N copd_checker -hold_jid "`old_id'" -pe multi_slot 15 -P proj_custom_models -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors "`stata_shell'" "`code'/03_check_outputs.do" "`output' `folder_name'"
		}
		else{
			! qsub -N copd_checker -pe multi_slot 15 -P proj_custom_models -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors "`stata_shell'" "`code'/03_check_outputs.do" "`output' `folder_name'"
			di "COMPLETE!"
		}
	
	}
	clear
	
	
	