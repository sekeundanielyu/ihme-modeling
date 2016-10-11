//Master Script for Updated Pneumo Exclusions
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
	}
	else{
		local prefix J:/
	}
	adopath + `prefix'/WORK/10_gbd/00_library/functions/
	
	//set locals
	local code "/ihme/code/epi/strUser/nonfatal/pneumo"
	local stata_shell "/ihme/code/general/strUser/malaria/stata.sh"
	local stata_mp_shell  "/ihme/code/epi/strUser/nonfatal/stata_shell.sh"
	local output "/share/scratch/users/strUser/pnuemo/"
	
	local ver_desc = "v9"
	local folder_name = "`ver_desc'"
	local generate_files 1
	
	//make directories
	cap mkdir "`output'"
	cap mkdir "`output'`ver_desc'"
	
	
	//report outputs 
	local test_clust -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors
	
	
	//me_ids 
	local coal_workers_ac 1886
	local asbest_ac 1886
	local coal_workers_end 3052
	local asbest_end 3051
	local models coal_workers asbest

	
	//Zero out exclusions
	foreach mmm of local models{
		di "`mmm'"
		if `generate_files' == 1{
			//find countries to 0 out
			if "`mmm'" == "coal_workers"{
				get_covariate_estimates, covariate_name_short(coal_prod_cont_pc) clear
				
				//if over 30 years have 0 coal for a country, declare it coal free (mostly to deal with precision)
				gen no_coal = mean_value ==0
				bysort location_id: egen coal_id = total(no_coal)
				keep if coal_id >30
				
				keep location_id
				duplicates drop
				
				tempfile exclusion
				save `exclusion', replace	
			}
			else if "`mmm'" == "asbest"{
				get_covariate_estimates, covariate_name_short(asbestos_bin) clear
				keep if mean_value ==0
				
				keep location_id
				duplicates drop
				tempfile exclusion
				save `exclusion', replace
			}
			
			//get the list of excluded countries
			levelsof location_id, local(excluded_locs) clean
			
			get_demographics, gbd_team(epi) make_template clear
			keep location_id
			duplicates drop
			
			gen exclusion =0
			foreach loc of local excluded_locs{
				replace exclusion = 1 if location_id == `loc'
			}
			

			
			//launch the jobs
			local jobs
			foreach location_id of global location_ids {
				preserve
					keep if location_id == `location_id'
					local excluded = exclusion[1]
					di "`mmm' `location_id' `excluded'"
					cap mkdir "`output'`ver_desc'/``mmm'_end'/"
					! qsub -N `mmm'_`location_id' -pe multi_slot 1 -P proj_custom_models -l mem_free=2G -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors "`stata_shell'" "`code'/01_pneumo_to_csv.do" "`location_id' `output' `ver_desc' `mmm' ``mmm'_end' ``mmm'_ac' `excluded'"
					local jobs `jobs' `mmm'_`location_id'
				restore
			}
				//di `jobs'
				! qsub -N saver_`mmm' -hold_jid "`jobs'" -pe multi_slot 4 -P proj_custom_models -l mem_free=26G -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors "`stata_mp_shell'" "`code'/02_save_pneumo_results.do" "`output' `ver_desc' `mmm' ``mmm'_end' ``mmm'_ac'"
		}
		else{
		
			do "`code'/02_save_pneumo_results.do" "`output'" "`ver_desc'" "`mmm'" "``mmm'_end'" "``mmm'_ac'"
		}
		
		
		
	}
	clear
	
	