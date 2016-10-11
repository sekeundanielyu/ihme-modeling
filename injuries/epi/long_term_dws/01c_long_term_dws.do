** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************

** Description:	Use health sytem access (capped) covariate to generate a "% treated" for each country-year. 
** 				Combining this % with the Ncode-specific treated and untreated DWs, generate a custom DW for 
**				each country-year.

** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** LOAD SETTINGS FROM MASTER CODE (NO NEED TO EDIT THIS SECTION)

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
	// test arguments
	if "`1'"=="" {
		local 1 _inj
		local 2 gbd2015
		local 3 2015_08_17
		local 4 01c
		local 5 long_term_dws
		local 6 /snfs2/HOME/ngraetz/local/inj
	}	
	** functional group (i.e. _inj)
	local functional `1'
	** gbd version (i.e. gbd2013)
	local gbd `2'
	** timestamp of current run (i.e. 2014_01_17)
	local date `3'
	** step number of this step (i.e. 01a)
	local step_num `4'
	** name of current step (i.e. first_step_name)
	local step_name `5'
	** local repo (repository where code is being run from)
	local repo `6'	
	** step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
	local hold_steps `7'
	** step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
	local last_steps `8'
	** directory for steps code
	local code_dir "`repo'/`gbd'"
	** directory for external inputs
	local in_dir "$prefix/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/02_inputs"
	** directory for output on the J drive
	local out_dir "$prefix/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/03_steps/`date'/`step_num'_`step_name'"
	** directory for output on clustertmp
	local tmp_dir "/clustertmp/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/03_steps/`date'/`step_num'_`step_name'"
	** directory for standard code files
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	
	** write log if running in parallel and log is not already open
	** log using "`out_dir'/02_temp/02_logs/`step_num'.smcl", replace name(master)
	
	** check for finished.txt produced by previous step
	if "`hold_steps'" != "" {
		foreach step of local hold_steps {
			local dir: dir "$prefix/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/03_steps/`date'" dirs "`step'_*", respectcase
			** remove extra quotation marks
			local dir = subinstr(`"`dir'"',`"""',"",.)
			capture confirm file "$prefix/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/03_steps/`date'/`dir'/finished.txt"
			if _rc {
				di "`dir' failed"
				BREAK
			}
		}
	}	

** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** WRITE CODE HERE

** Settings
	local debug 0
	if missing("$check") global check 0
	
** Filepaths
	local tmp_dw_dir = "/clustertmp/WORK/04_epi/03_outputs/01_code/02_dw/03_custom"
	local j_dw_dir = "${prefix}/WORK/04_epi/03_outputs/01_code/02_dw/03_custom"
	local data_dir "`tmp_dir'/02_temp/03_data"
	local draw_out "/share/epi/injuries/lt_dws/draws"
	cap mkdir "`draw_out'"
	local summ_out "/share/epi/injuries/lt_dws/summary"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local checkfile_dir "`tmp_dir'/02_temp/01_code/checks"
	local gbd_ado "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	cap mkdir "`checkfile_dir'"
	cap mkdir "`summ_out'"
	cap mkdir "`draw_out'"
	
	
** update adopath
	adopath + "`code_dir'/ado"
	adopath + "`gbd_ado'"
	
** get long-term DWs
	foreach cat in lt_u lt_t {
		get_ncode_dw_map, out_dir("`data_dir'") category("`cat'") prefix("$prefix")
		rename draw* `cat'_dw*
		tempfile `cat'
		save ``cat''
	}
	
	
** merge treated onto untreated
	merge 1:1 n_code using `lt_u', assert(match) nogen
	gen tmp = 1
	local dw_file "`data_dir'/dws_spinal.dta"
	save "`dw_file'", replace
	
	
** Create long-term DWs
	get_pct_treated, prefix("$prefix") code_dir("`code_dir'")
	gen tmp = 1
	local pct_treated_file "`data_dir'/pct_treated.dta"
	save "`pct_treated_file'", replace
	
	get_demographics, gbd_team(epi)
	foreach l of global location_ids {
		local name `functional'_`step_num'_`l'
		** file open check using "`checkfile_dir'/`l'.txt", write replace
		** file close check
		
		** (5/14/14: each job below uses ~0.5 GB)
		! qsub -P proj_injuries -N `name' -pe multi_slot 4 "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh" "`code_dir'/`step_name'/00_generate_dws.do" "`functional' `gbd' `repo' `l' `dw_file' `pct_treated_file' `checkfile_dir' `tmp_dir' `draw_out' `summ_out' `gbd_ado'"
		if "`holds'" == "" local holds `functional'_`step_num'_`l'
		else local holds `holds',`functional'_`step_num'_`l'
	}
	
** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************

