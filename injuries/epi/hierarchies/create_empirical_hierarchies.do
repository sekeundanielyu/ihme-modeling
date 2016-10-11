// Purpose:		This code creates an n-code disability weight hierarchy for one value of "hosp" (0 (outpatient), 1 (inpatient) , or 2 (pooled))

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
	local check=99
	if `check'==1 {
		local 1 $prefix/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 02b
		local 5 hierarchies
		local 6 /snfs2/HOME/ngraetz/local/inj/gbd2015
		local 7 1
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
    // directory where the code lives
    local code_dir `6'
    // platform
    local hosp `7'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	
	// write log if running in parallel and log is not already open
	log using "`out_dir'/02_temp/02_logs/`step_num'_`hosp'.smcl", replace
	if !_rc local close_log 1
	else local close_log 0
	
	// check for finished.txt produced by previous step
	if "`hold_steps'" != "" {
		foreach step of local hold_steps {
			local dir: dir "`root_j_dir'/03_steps/`date'" dirs "`step'_*", respectcase
			// remove extra quotation marks
			local dir = subinstr(`"`dir'"',`"""',"",.)
			capture confirm file "`root_j_dir'/03_steps/`date'/`dir'/finished.txt"
			if _rc {
				di "`dir' failed"
				BREAK
			}
		}
	}	

// START CODE

// Import functions
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	adopath + "`code_dir'/ado"
// Filepaths
	local inj_dir `root_j_dir'
	local steps_dir "`inj_dir'/03_steps/`date'"
	
// Begin timing
	// start_timer, dir("`diag_dir'") name("`name'") slots(`slots')
	
	set type double, perm
	di "hosp = `hosp'"
	di "date = `date'"
	di "envir = `envir'"
	di "step name = `step_name'"
	di "OS = `c(os)'"
	** store n-code disability weights for regressions later
	insheet using "`out_dir'/01_inputs/lt_t_dws_by_ncode.csv", comma names clear
	egen dw=rowmean(draw*)
	rename n_code ncode
	keep ncode dw
	tempfile n_dw_map
	save `n_dw_map', replace
	levelsof ncode, local(n_codes) clean
	foreach ncode of local n_codes {
		use `n_dw_map', clear
		keep if ncode == "`ncode'"
		local dw_`ncode' = dw[1]
	}
	
	** load the parameters we will need for this code
	adopath + "`code_dir'/ado"
	hierarchy_params, prefix($prefix) repo(`code_dir') steps_dir(`steps_dir')
	
	// Get number of ncodes (for use in sizing matrix later)
	local num_n = wordcount("$ncodes")
	
	tempfile current_dataset
	
	** start with correct prepped dataset: filepath set in the hierarchy_params.ado file
	use "$prepped_filepath", clear

	if `hosp' != 2 keep if inpatient == `hosp' | inpatient == .
	save `current_dataset', replace
	
	** create locals for no-LT and all-LT info so that we can iteratively adjust them separately for each severity
	local no_lt ${no_lt}
	local no_lt_sev ${no_lt_sev}
	local all_lt ${all_lt}
	local all_lt_sev ${all_lt_sev}
	
	
	while "`no_lt' `all_lt'" != " " {
		
		** for debugging purposes
		di "no_lt: `no_lt'"
		di "no_lt_sev: `no_lt_sev'"
		di "no_lt_tot: `no_lt_tot'"
		di "all_lt: `all_lt'"
		di "all_lt_sev: `all_lt_sev'"
		di "all_lt_tot: `all_lt_tot'"
	
		use `current_dataset', clear
	
		** add recent additions to the 100% LT groups to a local (used to append on these DWs after regression model is done)
		local all_lt_tot `all_lt_tot' `all_lt'
		local no_lt_tot `no_lt_tot' `no_lt'
		
		** drop variables that previously resulted in negative DWs (or are a priori no-LT)
		local num_no_lt = wordcount("`no_lt'")
		forvalues x = 1/`num_no_lt' {
			local n = word("`no_lt'",`x')
			local sev = word("`no_lt_sev'",`x')
			if inlist(`sev',9,`hosp') drop INJ_`n' 
		}
		
		local no_lt 
		local no_lt_sev 
		
		** set indicated N-code/hosp combinations to 100% LT
		local num_caps = wordcount("`all_lt'")
		
		forvalues x = 1/`num_caps' {
			local ncode = word("`all_lt'",`x')
			local sev = word("`all_lt_sev'",`x')
			cap confirm variable INJ_`ncode'
			if !_rc {
				if inlist(`sev',9,`hosp') {
					
					replace logit_dw = logit(1 - ((1 - invlogit(logit_dw)) / (1 - (INJ_`ncode')*(`dw_`ncode'')))) if INJ_`ncode' != 0
					
					** IB: If estimated DW was less than GBD DW for the given ncode, the logit of the resulting DW will be missing.
					** I am adjusting these DWs back to our threshold for 0 disability
					replace logit_dw = .00001 if logit_dw == . & INJ_`ncode' != 0
					drop INJ_`ncode'
					
				}
			}
		}	
		
		local all_lt 
		local all_lt_sev 
		
		
		** save adjusted dataset
		save `current_dataset', replace
		** run regression to get predicted effects of comos and INJuries
		mixed logit_dw age_gr##sex##never_injured INJ* if (TIME <= 0 | TIME > 364) || iso3: || id:
		
		** Generate matrices to hold results
		clear mata
		mata: INJ = J(`num_n',1,"")
		foreach col in DW_O DW_S DW_T N {
			mata: `col' = J(`num_n', 1, .)
		}
		local c = 1
		** record resulting DW for each N-code
		foreach como of varlist INJ* {
			preserve
			keep if  `como' > 0
			summ `como'
			local n = `r(sum)'
			if `n' {
				** account for probabilistic mapping that has partial values for dummy
				replace `como' = 1
				predict dw_obs
				replace dw_obs = invlogit(dw_obs) 				

				replace `como' = 0	
				predict dw_s
				replace dw_s = invlogit(dw_s)		
			
				gen dw_t = (1 - ((1-dw_obs)/(1-dw_s)))		
			
				summ dw_t
				local mean_dw_tnoreplace = `r(mean)'
				summ dw_obs
				local mean_dw_o = `r(mean)'
				summ dw_s
				local mean_dw_s `r(mean)'
				
				** drop INJ_ prefix from n-code
				local short_como = subinstr("`como'","INJ_","",.)
				
				** set 0 LT N-codes for next iteration of regression based on which resulting DWs are negative
				if `mean_dw_tnoreplace' < 0 {
					local no_lt `no_lt' `short_como'
					local no_lt_sev `no_lt_sev' `hosp'
				}
				** cap LT at GBD DW
				if `mean_dw_tnoreplace' > `dw_`short_como'' {
					local all_lt `all_lt' `short_como'
					local all_lt_sev `all_lt_sev' `hosp'
				}
				mata: INJ[`c', 1] = "`short_como'"		
				mata: DW_T[`c', 1] = `mean_dw_tnoreplace'
				mata: DW_O[`c', 1] = `mean_dw_o'
				mata: DW_S[`c', 1] = `mean_dw_s'
				mata: N[`c', 1] = `n'
				local c = `c' + 1
			}
			else drop `como'
			restore
		}
		
		** keep only the relevant part of the matrix (the part that was filled in by N-codes above)
		local c = `c' - 1
		foreach col in INJ DW_O DW_S DW_T N {
			mata: `col' = `col'[1::`c',1]
		}
	
	}
	
	** Get results into dataset once there are no more adjustments to make
	clear 
	getmata INJ DW_O DW_S DW_T N
	assert DW_T != .
	
	** keep relevant variables
	keep INJ N DW_T
	rename (DW_T INJ) (dw_`hosp' ncode)
	
	
	** Add on DW and N for N-codes we dropped (either no-LT or all-LT)
	
	** ** merge on N's for n-codes we dropped
	
	merge 1:1 ncode using "`out_dir'/01_inputs/replacement_Ns.dta", nogen
	drop if regexm(ncode,"^GS")
	
	replace N = N_`hosp' if N == .
	drop N_*
	rename N N_`hosp'
	
	** ** Merge on DWs for 100% LT data
	merge 1:1 ncode using `n_dw_map', nogen
	if `hosp' == 0 {
		** hacky attempt to say ncode is a word in `all_lt_tot' and not in $hosp_only. regexm() doesn't work bc/, for
		** example, it will return 1 if N10 is in all_lt_tot and ncode == N1
		replace dw_`hosp' = dw if dw_`hosp' == . & subinword("`all_lt_tot'",ncode,"",.) != "`all_lt_tot'" & ///
		subinword("${hosp_only}",ncode,"",.) == "${hosp_only}"
	}
	else replace dw_`hosp' = dw if dw_`hosp' == . & subinword("`all_lt_tot'",ncode,"",.) != "`all_lt_tot'"
	drop dw
	
	** ** set DW = 0 for all no-LT n-codes
	replace dw_`hosp' = 0 if dw_`hosp' == . & subinword("`no_lt_tot'",ncode,"",.) != "`no_lt_tot'"
	
	
	** save the results of this severity's regression analysis
	save "`out_dir'/02_temp/03_data/post_regression_`hosp'.dta", replace
		
	
	// write check file to indicate sub-step has finished
	file open finished using "`out_dir'/02_temp/01_code/checks/finished_`hosp'.txt", replace write
	file close finished
	
// End timer
	// end_timer, dir("`diag_dir'") name("`name'")
	
// Close log and delete if successful run
	log close emp_hierarchy
	erase "`log_file'"
	