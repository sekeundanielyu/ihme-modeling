// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	Submit jobs to generate E/N incidence matrices 

** *********************************************
// DON'T EDIT - prep stata
** *********************************************

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
		local hold_steps ""
		local last_steps ""
		local step_name "EN_matrices"
		local step_num "03b"
	}
		local check = 99
	if `check'==1 {
		local 1 _inj
		local 2 gbd2015
		local 3 2015_08_17
		local 4 "03b"
		local 5 EN_matrices

		local 8 "/snfs2/HOME/ngraetz/local/inj"
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

	// write log if running in parallel and log is not already open
	cap log using "`out_dir'/02_temp/02_logs/`step_num'.smcl", replace
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

** *********************************************
// WRITE CODE HERE
** *********************************************
	
// Settings
	** which sub-steps to run (leave blank if all)
	local sub_steps  "04"
	** max standard error to allow for a given model before moving to fewer covariates
	local max_se 1.5
	** what age groups are we going to aggregate to? 
	local ages 0 1 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80
	** how many slots to run EN matrix creation code with
	local make_matrix_slots 1
	** are you debugging? If `debug'==0 then the code will delete the contents of the 02_temp/03_data folder
	local debug=1
	
// Filepaths
	local homedir `root_j_dir'
	local data "`tmp_dir'/02_temp/03_data"
	local logs "`out_dir'/02_temp/02_logs"
	local cleaned_dir "`data'/00_cleaned"
	local prepped_dir "`data'/01_prepped"
	local gbd_ado "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
	local summ_dir "`tmp_dir'/03_outputs/02_summary"

// Load ado-files
	adopath + `code_dir'/ado
	adopath + `gbd_ado'
	
	start_timer, dir("`diag_dir'") name("`step_name'")

// Load injuries parameters
	load_params
	
// Set-up filestructure
	foreach folder in 00_cleaned 01_prepped 03_modeled {
		cap mkdir "`data'/`folder'"
	}

// 00) Clean data
	if regexm("`sub_steps'","00") | "`sub_steps'" == "" do "`code_dir'/`step_name'/00_clean_en_data.do" $prefix `homedir' `code_dir' `step_name' `cleaned_dir' `prepped_dir' "`ages'" `data' `logs' `gbd_ado' `diag_dir'


// 01) Prep data
	if regexm("`sub_steps'","01") | "`sub_steps'" == "" {
		local args $prefix `date' `step_num' `step_name' `code_dir' `cleaned_dir' `prepped_dir' `in_dir' `root_j_dir'
		foreach ds in chinese_niss ihme_data chinese_icss hdr nld_iss argentina {
			di `""`code_dir'/`step_name'/01_prep_hospital_data.do" `args' `ds'"'
			!qsub -e /share/temp/sgeoutput/ngraetz/errors -o /share/temp/sgeoutput/ngraetz/output -P proj_injuries -N prep_`ds' -pe multi_slot 32 "`code_dir'/stata_shell.sh" "`code_dir'/`step_name'/01_prep_hospital_data.do" "`args' `ds'"
		}
	}

// 02) Append datasets and further prep
	if regexm("`sub_steps'","02") | "`sub_steps'" == "" do "`code_dir'/`step_name'/02_append_en_data.do" $prefix `prepped_dir' `data' `logs'	
	
// 03) Run en_matrices
	if regexm("`sub_steps'","03") | "`sub_steps'" == "" {
		** if re-running in same timestamp, need to remove the check file indicating process is finished
		cap erase "`tmp_dir'/finished.txt"
		
		** get list of e-codes to loop over
		import delimited using "`data'/02_appended.csv", delim(",") clear
		levelsof e_code, l(e_codes_for_en) clean
		
		** submit jobs
		foreach pf in inp otp {
			foreach e_code of local e_codes_for_en {
				local check_file_dir = "place_holder"
				local name `pf'_`e_code'		
				!qsub -e /share/temp/sgeoutput/ngraetz/errors -o /share/temp/sgeoutput/ngraetz/output -P proj_injuries -N `name' -pe multi_slot 16 "`code_dir'/stata_shell.sh" "`code_dir'/`step_name'/03_create_en_matrix.do" "`pf' `e_code' `code_dir' `max_se' `check_file_dir' $prefix `homedir' `data' `tmp_dir' `gbd_ado' `diag_dir' `name' `make_matrix_slots' `gbd'"
			}
		}
		
	// Wait to finish job until Step 03 has completed
		local complete 0
		while !`complete' {
			cap confirm file "`tmp_dir'/finished.txt"
			if _rc sleep 10000
			else local complete 1
		}
	}
	
// 04) make a custom en_matrix for inj_medical which goes 100% to medical misadventure (N46)
	if regexm("`sub_steps'","04") | "`sub_steps'" == "" {
		// Load params
		load_params
		clear
		local obs 1
		gen n_code=""
		foreach ncode of global n_codes {
			set obs `obs'
			replace n_code="`ncode'" in `obs'
			local ++obs
		}
		forvalues i=0/$drawmax {
			gen draw`i'=0
			replace draw`i'=1 if n_code=="N46"
		}		
		
		expand 2, gen(high_income)
		expand 2, gen(sex)
		replace sex = sex+1
		local age_count = wordcount("`ages'")
		expand `age_count'
		bysort n_code high_income sex : gen n=_n
		gen age = ""
		forvalues i=1/`age_count' {
			replace age=word("`ages'", `i') if n==`i'
		}
		destring age, replace
		drop n
		capture mkdir "`tmp_dir'/03_outputs/01_draws/inp/"
		capture mkdir "`tmp_dir'/03_outputs/01_draws/otp/"
		
		format draw* %16.0g
		order n_code age sex high_income, first
		export delimited "`tmp_dir'/03_outputs/01_draws/inp/inj_medical.csv", delim(",") replace 
		export delimited "`tmp_dir'/03_outputs/01_draws/otp/inj_medical.csv", delim(",") replace 
		
	}


foreach pf in inp otp {
tempfile `pf'
local matrix_dir "`tmp_dir'/03_outputs/02_summary/`pf'"

foreach ecode of global modeled_e_codes {

if "`ecode'" != "inj_medical" {
insheet using "`matrix_dir'/`ecode'.csv", comma names clear
gen ecode = "`ecode'"
cap confirm file ``pf''
if _rc == 0 {
append using ``pf''
save ``pf'', replace
}
else {
save ``pf''
}
}	

else {
di "no inj_medical"
}

}

outsheet using "`matrix_dir'/en_matrix_`pf'.csv", comma names replace
}

** *********************************************
// Write check files
** *********************************************
		
// write check file to indicate step has finished
	file open finished using "`out_dir'/finished.txt", replace write
	file close finished
		
	end_timer, dir("`diag_dir'") name("`step_name'")
	// sum_times, dir("`diag_dir'")
	
// close log if open
	log close master
