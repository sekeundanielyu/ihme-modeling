// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	Get draws of short term durations using draws from treated and untreated for each ncode and draws of health system scores

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM MASTER CODE (NO NEED TO EDIT THIS SECTION)

	// prep stata
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
	if "`1'" == "" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "05b"
		local 5 long_term_inc_to_raw_prev

		local 8 "/share/code/injuries/ngraetz/inj/gbd2015"
	}
	// base directory on J 
	local root_j_dir `1'
	// base directory on clustertmp
	local root_tmp_dir `2'
	// timestamp of current run (i.e. 2014_01_17)
	local date `3'
	// step number of this step (i.e. 01a)
	local step_num `4'
	// name of current step (i.e. first_step_name)
	local step_name `5'
	// step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
	local hold_steps `6'
	// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
	local last_steps `7'
    // directory where the code lives
    local code_dir `8'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for standard code files
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	
	// write log
	log using "`out_dir'/02_temp/02_logs/`step_num'.smcl", name(master) replace
	
	// check for finished.txt produced by previous step
	if "`hold_steps'" != "" {
		foreach step of local hold_steps {
			local dir: dir "$prefix/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/03_steps/`date'" dirs "`step'_*", respectcase
			// remove extra quotation marks
			local dir = subinstr(`"`dir'"',`"""',"",.)
			capture confirm file "$prefix/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/03_steps/`date'/`dir'/finished.txt"
			if _rc {
				di "`dir' failed"
				BREAK
			}
		}
	}	


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
	
// Settings
	local debug 0
	set type double, perm
	set seed 0	
	
// Filepaths
	local gbd_ado "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local pct_file "`out_dir'/01_inputs/pct_treated.dta"
	local dur_file "`out_dir'/01_inputs/durs.dta"
	local output_dir "`tmp_dir'/03_outputs"
	local checkfile_dir "`tmp_dir'/02_temp/01_code/checks"
	
// Import functions
	adopath + `code_dir'/ado
	adopath + "`gbd_ado'"

// Get list of years and ncodes
	load_params
	local expandbyn = wordcount("${n_codes}")
	get_demographics, gbd_team("epi")

// get percent treated
	get_pct_treated, prefix("$prefix") code_dir("`code_dir'")
	save "`pct_file'", replace
	
// Get durations
	import excel ncode=A mean_inp=C se_inp=D ll_inp=E ul_inp=F mean_otp=G se_otp=H ll_otp=I ul_otp=J mean_mul=K ll_mul=L ul_mul=M using "`in_dir'/parameters/short_term_durations.xlsx", cellrange(A10) clear

	foreach i in inp otp {
	// create SE from LL and UL when SE doesn't exist (b/c mean, UL, LL created via expert opinion)
		replace se_`i' = (ul_`i' - ll_`i') / 3.92 if se_`i' == .
		drop ll_`i' ul_`i'
		
	// convert days to years
		foreach var in mean se {
			replace `var'_`i' = `var'_`i' / 365.25
		}
	}
	
	** keep just multipliers
	preserve
	keep ncode *_mul
	tempfile mults
	save `mults'
	restore
	
	** reshape long
	drop *_mul
	reshape long mean_ se_, i(ncode) j(inp_str) string
	gen inpatient = 0
	replace inpatient = 1 if inp_str == "inp"
	drop inp_str
	
	** merge on untreated multipliers
	merge m:1 ncode using `mults', assert(match) nogen
	calc_se ll_mul ul_mul, newvar(se_mul)
	drop ll_mul ul_mul
	
	** generate treated/untreated duration draws
	forvalues x = 0/$drawmax {
		gen treat_`x' = rnormal(mean_,se_)
		gen untreat_`x' = treat_`x' * rnormal(mean_mul,se_mul)
		
		** fix situation where assumed no difference in treat/untreat
		replace untreat_`x' = treat_`x' * mean_mul if se_mul == 0
		
		** cap at 1 year
		replace untreat_`x' = 1 if untreat_`x' > 1
	}
	drop mean_ se_ mean_mul se_mul
	
	** save
	save "`dur_file'", replace
	

// Parallelize the country-year-specific multiplication

	** set mem/slots and create job checks directory
	local code = "durations/durations_parallel.do"
	
// submit jobs
	local n 0
	foreach location_id of global location_ids {
		foreach year of global year_ids {
			local name `functional'_`step_num'_`iso3'_`year'
			! qsub -o /share/temp/sgeoutput/ngraetz/output -e /share/temp/sgeoutput/ngraetz/errors -N stdur_`location_id'_`year' -pe multi_slot 4 -l mem_free=8 "`code_dir'/stata_shell.sh" "`code_dir'/`code'" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `location_id' `year'"
			local n = `n' + 1
		}
	}

	
// wait for jobs to finish before passing execution back to main step file
	local i = 0
	while `i' == 0 {
		local checks : dir "`checkfile_dir'" files "finished_*.txt", respectcase
		local count : word count `checks'
		di "checking `c(current_time)': `count' of `n' jobs finished"
		if (`count' == `n') continue, break
		else sleep 60000
	}
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
