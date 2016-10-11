** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************

** Purpose:		Calculate year-Ncode specific DWs for a given location

** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** LOAD SETTINGS FROM STEP CODE (NO NEED TO EDIT THIS SECTION)

	** prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	
	** functional group (i.e. _inj)
	local functional `1'
	** gbd version (i.e. gbd2013)
	local gbd `2'
	** local repo
	local repo `3'
	** iso3
	local location_id `4'
	** file of DWs
	local dw_file `5'
	** file of % treated for each country-year
	local pct_treated_file `6'
	** Directory for sub-step check files
	local checkfile_dir `7'
	** directory for output (J drive or cluster)
	local tmp_dir `8'
	** Directory to save draws
	local draw_out `9'
	** Directory to save summary output
	local summ_out `10'
	** Directory of general GBD ado functions
	local gbd_ado `11'
	** Step diagnostics directory
	local diag_dir `12'
	** directory for steps code
	local code_dir "`repo'/`gbd'"
	** directory for external inputs
	local in_dir "$prefix/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/02_inputs"
	** directory for standard code files
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	
	** write log if running in parallel and log is not already open
	local log_file "`tmp_dir'/02_temp/02_logs/00_generate_dws_`location_id'.smcl"
	** log using "`log_file'", replace name(gen_dws)
	
	
** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************

** Settings
	set type double, perm

** Import ado functions
	adopath + "`gbd_ado'"
		
** Filepaths
	local out_dir = subinstr("`tmp_dir'","/clustertmp/","/home/j/",.)
	local data_dir "`tmp_dir'/02_temp/03_data"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	
** Start timer
	** local timer_name generate_dws_`iso3'
	** start_timer, dir("`diag_dir'") name("`timer_name'")

	set type double
	use "`pct_treated_file'", clear
	keep if location_id == `location_id'
	levelsof year_id, local(years)
	foreach y of local years {
		preserve
		keep if year == `y'
		merge 1:m tmp using "`dw_file'", assert(match) nogen
		drop tmp
	** Get actual dws
		forvalues x = 0/999 {
			gen draw_`x' = lt_u_dw`x' + ( pct_treated * (lt_t_dw`x' - lt_u_dw`x') )
			drop lt_u_dw`x' lt_t_dw`x'
		}

	** Save file
		keep n_code draw_*
		rename n_code healthstate
		format draw* %16.0g
		export delimited using "`draw_out'/`location_id'_`y'.csv", delim(",") replace
		
	** save summary file
		fastrowmean draw*, mean_var_name("name")
		fastpctile draw*, pct(2.5 97.5) names(ll ul)
		drop draw*
		export delimited using "`summ_out'/`location_id'_`y'.csv", delim(",") replace
		
		restore
	}

