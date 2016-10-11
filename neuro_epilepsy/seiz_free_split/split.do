// *********************************************************************************************************************************************************************


	//If running on cluster, use locals passed in by model_custom's qsub
	else if `cluster' == 1 {
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
		// directory for steps code
		local code_dir `6'
		local location_id `7'

		}
	

// *********************************************************************************************************************************************************************

			get_draws, gbd_id_field(modelable_entity_id) source(epi) gbd_id(2403) measure_ids(5 6) location_ids(`location_id') clear
			keep if age_group_id <= 21 //5yr ranges (is this all we need to do?)
		
		//save temp file 
			tempfile data 
			save `data', replace
	
			
// Load meta-analysis results and create 1000 draws from the mean and SE
	cd "`in_dir'" 
		clear all
		tempfile merge_master
		save `merge_master', replace emptyok

		use "Epilepsy_TxSeizureFree_prop.dta" if location_id == `location_id', clear 
		
		
		// Final: We want to use a beta distribution to model the mean and standard error
	
		levelsof YMean, local(mu)
		levelsof YSE, local(sigma)
		clear all
		set obs 1000
		local alpha = `mu' * (`mu' - `mu' ^ 2 - `sigma' ^2) / `sigma' ^2 
		local beta  = `alpha' * (1 - `mu') / `mu'
		gen alpha_gammas = rgamma(`alpha', 1)
		gen beta_gammas = rgamma(`beta', 1)
		gen SeizureFree = alpha_gammas / (alpha_gammas + beta_gammas)
		
		gen n = _n - 1
		drop *_gammas

		save `merge_master', replace

//Loop over every year and sex for given location 
	//year_ids
		local year_ids "1990 1995 2000 2005 2010 2015"
	//sex_ids
		local sex_ids "1 2"


	foreach year_id in `year_ids' {
		foreach sex_id in `sex_ids' {

	use `data', clear
	keep if year_id == `year_id' & sex_id == `sex_id' 

//reshape for easy merging with results
	reshape long draw_, i(age_group_id measure_id) j(n)
	
	tempfile use_file
	save `use_file', replace


// Load regression results and merge with meta-analysis (which is not year-specific)
cd "`in_dir'" 
local i 0 
*local result "Severe"
foreach result in Idiopathic Severe Treat_Gap {
	if "`result'" == "Treat_Gap" local result_stub = "_tg"
	if "`result'" == "Severe" local result_stub = "_sev"
	if "`result'" == "Idiopathic" local result_stub = "_idio"
	use "`result'_draws.dta" if location_id == `location_id' & year_id == `year_id', clear
	gen n = _n - 1
	rename final_draws`result_stub' `result'
	if `i' == 0 {
		merge 1:1 n using `merge_master', nogen 
		tempfile merge 
		} 
	else merge 1:1 n using `merge', nogen 
	
	save `merge', replace 
	local ++ i 
}

merge 1:m n using `use_file', nogen keepusing(age_group_id measure_id n draw_)


// PERFORM SPLITS 

	// Split 1: Envelope to Idiopathic/Secondary
	gen idio = draw_ * Idiopathic
	gen sec = draw_ * (1 - Idiopathic)

	foreach split in idio sec {
		// Split 2: Prevalence to Severe/Not Severe
		gen `split'_sev = `split' * Severe
		gen `split'_nonsev = `split' * (1 - Severe)
		
		// Split 3: Non-Severe to Treated and Untreated
		gen `split'_treat = `split'_nonsev * (1 - Treat_Gap)
		gen `split'_untreat = `split'_nonsev * Treat_Gap
		
		// Split 4: Treated to Seizures and No Seizures
		gen `split'_noseizure = `split'_treat * SeizureFree
		gen `split'_seizure = `split'_treat * (1 - SeizureFree)
		
		// Final: Combine Not-Severe Untreated and Not-Severe Treated w/Seizures
		gen `split'_symptom = `split'_seizure + `split'_untreat
		
		// Combine them all together
		rename `split' `split'_all
	}

	drop *_treat *_untreat *_seizure Severe Treat_Gap SeizureFree

tempfile compiled
save `compiled', replace

	local outputs = "sev noseizure symptom all"

	foreach split in idio sec {
		foreach output in `outputs' {
			di in red "Outsheeting `split' `output' for year `year_id' sex `sex_id'"

			use `compiled', clear
			keep `split'_`output' age_group_id measure_id n
			rename `split'_`output' draw_
			
			count if draw_ == . | draw_ < 0 | draw_ > 1
			if `r(N)' > 0 {
				di in red "Draw impossible!"
				BREAK
				}

			reshape wide draw_, i(age_group_id measure_id) j(n)
			cap mkdir "`out_dir'/03_outputs/01_draws/`split'_`output'" 
			cd "`out_dir'/03_outputs/01_draws/`split'_`output'"

			preserve 
			//save prevalence
			keep if measure_id == 5 
			drop measure_id
			outsheet using 5_`location_id'_`year_id'_`sex_id'.csv, comma replace
			restore 
			//save incidence
			keep if measure_id == 6
			drop measure_id
			outsheet using 6_`location_id'_`year_id'_`sex_id'.csv, comma replace
			}
		}


//Next sex	
		}
	//Next year 
	}

// *********************************************************************************************************************************************************************
