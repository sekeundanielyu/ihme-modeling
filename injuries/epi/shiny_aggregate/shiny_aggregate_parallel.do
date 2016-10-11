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
	if "`1'"=="" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "06b"
		local 5 long_term_final_prev_by_platform
		local 6 "/share/code/injuries/ngraetz/inj/gbd2015"
		local 7 165
		local 8 2010
		local 9 1
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
    // iso3
	local location_id `7'
	// year
	local year `8'
	// sex
	local sex `9'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for standard code files
	adopath + "$prefix/WORK/10_gbd/00_library/functions"

	// Load common inputs 
	insheet using "`code_dir'/ncode_names.csv", comma names clear
		rename n_code ncode 
		keep ncode ncode_name_short
		tempfile ncodes 
		save `ncodes', replace
	insheet using "`code_dir'/convert_to_new_age_ids.csv", comma names clear
		tempfile age_ids 
		save `age_ids', replace
	get_demographics, gbd_team("epi")
	get_populations, year_id(`year') location_id(`location_id') sex_id(`sex') age_group_id($age_group_ids) clear
		tempfile pops 
		save `pops', replace

	// Aggregate non-shock incidence (shock incidence is for weird years... maybe make a different slider year input in Shiny)
	use "/share/injuries/03_steps/`date'/04b_scaled_short_term_en_inc_by_platform/03_outputs/02_summary/nonshocks/collapsed/incidence_`location_id'_`year'_`sex'.dta", clear
	rename age age_start
	merge m:1 age_start using `age_ids', keep(3) nogen
	merge m:1 age_group_id using `pops', keep(3) nogen
	merge m:1 ncode using `ncodes', keep(3) nogen
	drop ncode
	rename ncode_name_short ncode
	replace mean = mean * pop_scaled
	fastcollapse mean, type(sum) by(ecode ncode)
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/_inj/05_diagnostics/shiny_data/nonshock_incidence"
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/_inj/05_diagnostics/shiny_data/nonshock_incidence/`location_id'"
	outsheet using "$prefix/WORK/04_epi/01_database/02_data/_inj/05_diagnostics/shiny_data/nonshock_incidence/`location_id'/incidence_`location_id'_`year'_`sex'.csv", comma names replace

	// Aggregate long-term prevalence
	use "/share/injuries/03_steps/`date'/06b_long_term_final_prev_by_platform/03_outputs/02_summary/`location_id'/prevalence_`location_id'_`year'_`sex'.dta", clear
	rename age age_start
	merge m:1 age_start using `age_ids', keep(3) nogen
	merge m:1 age_group_id using `pops', keep(3) nogen
	merge m:1 ncode using `ncodes', keep(3) nogen
	drop ncode
	rename ncode_name_short ncode
	replace mean = mean * pop_scaled
	fastcollapse mean, type(sum) by(ecode ncode)
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/_inj/05_diagnostics/shiny_data/prevalence"
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/_inj/05_diagnostics/shiny_data/prevalence/`location_id'"
	outsheet using "$prefix/WORK/04_epi/01_database/02_data/_inj/05_diagnostics/shiny_data/prevalence/`location_id'/prevalence_`location_id'_`year'_`sex'.csv", comma names replace

	// Aggregate long-term YLDs
	// Get summary N/E prevalence matrix to split aggregate N-code YLDs back to E/N 
	insheet using "/share/injuries/03_steps/2016_02_08/07_long_term_final_prev_and_matrices/03_outputs/02_summary/NEmatrix/NEmatrix_`location_id'_`year'_`sex'.csv", comma names clear
		rename mean e_prop
		tempfile ne_matrix
		save `ne_matrix', replace
	insheet using "`code_dir'/ncode_yld_sequela_ids.csv", comma names clear
		levelsof(sequela_id), l(sequela_ids)
		tempfile ncode_to_seq
		save `ncode_to_seq', replace
	get_demographics, gbd_team("epi")
	run "`code_dir'/ado/get_ncode_outputs.do" // Needed to hack out some stuff from the real get_outputs to handle the fact that Tom uploads N-code YLD aggregates to some fake ass sequela ids
	// Loop over N-codes to pull from database 
	local all_ylds = ""
	foreach sequela_id of local sequela_ids {
		local all_ylds = "`all_ylds' `sequela_id'"
	}
	get_ncode_outputs, topic(sequela) sequela_id(`all_ylds') measure_id(3) location_id(`location_id') year_id(`year') sex_id(`sex') age_group_id($age_group_ids) clear
	// Merge N-codes by sequela_id
	merge m:1 sequela_id using `ncode_to_seq', keep(3) nogen
	rename n_code ncode
	// Collapse granular spinal lesion N-codes for matrix splitting
	foreach lesion in N33 N34 {
		replace ncode = "`lesion'" if regexm(ncode, "`lesion'") == 1
	}
	fastcollapse val, type(sum) by(ncode age_group_id)
	rename val mean 
	// Merge matrix and split 
	merge 1:m ncode age_group_id using `ne_matrix', keep(3) nogen
	replace mean = mean * e_prop
	// Final collapse 
	fastcollapse mean, type(sum) by(ncode ecode)
	merge m:1 ncode using `ncodes', keep(3) nogen
	drop ncode
	rename ncode_name_short ncode
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/_inj/05_diagnostics/shiny_data/ylds"
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/_inj/05_diagnostics/shiny_data/ylds/`location_id'"
	outsheet using "$prefix/WORK/04_epi/01_database/02_data/_inj/05_diagnostics/shiny_data/ylds/`location_id'/ylds_`location_id'_`year'_`sex'.csv", comma names replace

	// END

