// PURPOSE: LAUNCH PARALLELIZING CODE TO EXTRACT SECONDHAND SMOKE DATA FROM BRFSS AND COMPUTE PHYSICAL ACTIVITY PREVALENCE IN 5 YEAR AGE-SEX GROUPS FOR EACH YEAR 

// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		set maxvar 32000
		capture restore, not
	// Set to run all selected code without pausing
		set more off
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}

// Local repo 
	local repo `1'
	
// Bring in 2013 iso3 code
	
	insheet using "/snfs1/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/brfss/state_fips_codes.csv", comma clear
	drop state 
	rename state_name us_state 
	
// Create locals for relevant files and strings
	levelsof us_state, local(us_states)
	
	local code_dir "`repo'/smoking_shs/01_exp/01_tabulate"

// Parallelize by healthstate, national-level iso3, year and sex
	foreach us_state of local us_states {
			di "STATE = `us_state'" 
			!qsub -N "`us_state'" -l mem_free=4G -pe multi_slot 4 ///
			"`code_dir'/stata_shell.sh" ///
			"`code_dir'/02_brfss_calc_prevalence.do" ///
			"`us_state'"
		}
			
		
	
