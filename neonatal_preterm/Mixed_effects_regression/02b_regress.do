/* **************************************************************************
For some neonatal cause-parameters where we have a sufficient amount of data,
we run a hierarchical mixed-effects regression to generate 
country-year specific estimates of the parameter of interest for these neonatal 
models.  All of these regressions have at minimum ln(NMR) as a covariate, and all(save one)
have at minimum superregion as a random-effects level.  A full map of which models
get what parameters is in the 'dimensions_mini' spreadsheet at 
"J:\WORK\04_epi\02_models\01_code\06_custom\neonatal\data\dimensions_mini_2015.csv". 

There are two circumstances when we are not comfortable running a parameter-specific 
regression:
1. There is too little data to come up with a reliable estimate (usually, when we have only 
	one or two datapoints). Sepsis mild_imp and sepsis modsev_imp, for example.
2. For encephalopathy mild_imp and mosev_imp, and mild_imp and modsev_imp for each of the preterm
	gestational ages. These are now calculated in a single regression by cause, as per Chris' suggestion
	on 6/7/2016 (please see 01_dataprep.do for further documentation.)

This is the code for the parameter-specific regressions.00
*****************************************************************************/

************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM MASTER CODE

	// prep stata
	clear all
	set more off
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	// base directory on J 
	local root_j_dir `1'
	// base directory on /ihme
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
	// directory for output on /ihme
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	
	// write log if running in parallel and log is not already open
	cap log using "`out_dir'/02_temp/02_logs/`step_num'.smcl", replace
	if !_rc local close_log 1
	else local close_log 0

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************


clear all
set more off
set maxvar 32000
//ssc install estout, replace 

/*  //////////////////////////////////////////////
		WORKING DIRECTORY
////////////////////////////////////////////// */

		//root dir
	if c(os) == "Windows" {
		local j "J:"
		// Load the PDF appending application
		quietly do "`j'/Usable/Tools/ADO/pdfmaker_acrobat11.do"
	}
	if c(os) == "Unix" {
		local j "/home/j"
		
	} 
	
	di in red "J drive is `j'"

/* /////////////////////////
///Prep: Pass , parameters,
/// set up logs, etc.
///////////////////////// */

//add code for 'fastpctile' to path
adopath + "`j'/WORK/10_gbd/00_library/functions"
	
///JUST FOR TESTING:fake parameters to make sure code runs locally
/*local acause "neonatal_preterm"
local grouping "ga1"
local covariates "ln_NMR developed"
local random_effects "super_region_id region_id location_id"
local parent_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/" 
local in_dir "`parent_dir'/01_prep/`acause'/`acause'_`grouping'_prepped.dta"
local timestamp "02_16_16" */

 //actual passed parameters
local acause "`1'"
local grouping "`2'"
local covariates "`3'"
local random_effects "`4'"
local parent_dir "`5'"
local in_dir "`6'"
local timestamp "`7'"

di in red "acause is `acause'"
di in red "grouping is `grouping'"
di in red "covariates are `covariates'"
di in red "random effects are `random_effects'"
di in red "parent dir is `parent_dir'"
di in red "in_dir is `in_dir'"
di in red "timestamp is `timestamp'" 

//make output directories and archive files
local out_dir "`parent_dir'/02_analysis/`acause'"
capture mkdir "`out_dir'"
local dirs_to_make draws summary
foreach dirname of local dirs_to_make{
	local `dirname'_out_dir "`out_dir'/`dirname'"
	local archive_`dirname'_out_dir "``dirname'_out_dir'/_archive"
	capture mkdir ``dirname'_out_dir'
	capture mkdir `archive_`dirname'_out_dir'
}

//logging
local log_dir "/ihme/scratch/users/User/neonatal/logs/`acause'/`acause'_`grouping'_regress_`timestamp'.smcl"
capture log close
log using "`log_dir'", replace

// in 01_dataprep.do, we mentioned the annoying detail that when we have
// more than one covariate/random effect, we have to concatenate them into
// a single string in order to pass them through the shell script.  We delimit 
// them with a double underscore in that string.  Here, we separate that long
// string back out into a list of elements.

while regexm("`covariates'", "__")==1{
	local covariates = regexr("`covariates'", "__", " ")
}
di in red "covariates are `covariates'"

while regexm("`random_effects'", "__")==1{
	local random_effects = regexr("`random_effects'", "__", " ")
}
di in red "random_effects are `random_effects'"


/* /////////////////////////
/// Import data prepared in 
/// step 01_dataprep
///////////////////////// */
di in red "importing data"
use "`in_dir'", clear

// drop numerator denominator

gen lt_mean = logit(mean)

local cov_count: word count `covariates'
local re_count: word count `random_effects'
local re_name 
foreach re of local random_effects{
	local re_name `re_name' || `re':
}

/* /////////////////////////////////////////////////////////////////////
/// Run the mixed effects model.  Note that we have transformed the data into
/// logit space to ensure that our predictions stay in the domain of 
/// prevalences/proportions [0,1]. 
///////////////////////////////////////////////////////////////////// */
xtmixed lt_mean `covariates' `re_name'

/////////////////////////////////////////////////////////////////////
/// Predict for fixed effects:
/// This is relatively straightforward.
/// 1. Take the covariates corresponding to the fixed effects, and the 
/// 	covariance of those fixed effects, from the beta and covariance matrices
/// 	(stored by default in the e(b) and e(V) matrices, respectively).  
///		Note that the intercept will be at the end of this list, not the beginning.
/// 2.  Make a list of locals whose names correspond to the entries in the matrices,
/// 	in order (remember to but the intercept last!)
/// 3. 	Use the 'drawnorm' function to generate a new dataset that contains a 
/// 	column for each fixed effect, with a thousand draws (long) for each value.
///		Save this in a temp file for later.
///////////////////////////////////////////////////////////////////// */

//1. Extract fixed effects from matrices
matrix betas = e(b)
local endbeta = `cov_count' + 1
matrix fe_betas = betas[1, 1..`endbeta']
matrix list fe_betas
matrix covars = e(V)
matrix fe_covars = covars[1..`endbeta', 1..`endbeta']
matrix list fe_covars

//2. Generate list of locals that will become column names in the new dataset
local betalist 
forvalues i = 1/`cov_count' {
	local betalist `betalist' b_`i'
}
local betalist `betalist' b_0
di in red "beta list is `betalist'"

//3. Run 'drawnorm' to predict for fixed effects.  
di in red "predicting for fixed effects"
preserve
	drawnorm `betalist', n(1000) means(fe_betas) cov(fe_covars) clear
	gen sim = _n
	tempfile fe_sims
	save `fe_sims', replace
restore

/* /////////////////////////////////////////////////////////////////////
/// Predict for random effects:
/// This is a bit more complex.  
/// 1.  Use the 'predict' function to get a random effect estimate for 
/// 	every line in the dataset.  
///
///	2.  Unfortunately, this doesn't give us
///		everything we want: any country whose superregion had no data will
/// 	not receive a random-effects estimate.  We fix this by looping through
///		each geography and filling in missing values with mean 0 and SE equal
///		to the global SE.
///
///	3. Keep in mind also that we want to wind up with a thousand draws for
///		each random-effect level that we have.  But since the higher-level geographies
/// 	map to many lower-level geographies, if we were to predict for them all at 
///		once we would wind up with many draw_1's for superregion for each draw_1 
///		for iso3.  To prevent this, while we loop through each random effect level
///		we collapse the dataset down to contain one line for every element of that 
///		geography (i.e. 7 lines for the 'superregion' dataset, 21 for the 'region', etc.)
///	
///4.  We take a thousand draws from each collapsed dataset, and save it in a temp file.
/// 
///////////////////////////////////////////////////////////////////// */

//1. Use 'predict' function
di in red "predicting for random effects"
predict re_* , reffects
predict re_se_* , reses

//2-3: Loop through each geography level 
// local re_idx 2 // EDIT: for testing purposes
forvalues re_idx = 1/`re_count'{
	di in red "predicting for random effect `re_idx' of `re_count'"
	preserve
		//keep only the values corresponding to the random effect of interest
		//and the random effect one level above it (so you can merge on)
		local re_name_`re_idx' : word `re_idx' of `random_effects'
		local past_re_name
		if `re_idx'!=1{
			local past_re_idx = `re_idx'-1
			local past_re_name : word `past_re_idx' of `random_effects'
		}
		
		//reduce down so we have a single row for each geography at this level
		keep `re_name_`re_idx'' `past_re_name' re_*`re_idx'
		bysort `re_name_`re_idx'': gen count=_n
		drop if count!=1
		drop count
		
		//we don't have data for every region, so: fill those in
		// with the global values: mean 0, SE equal to the SE 
		// of the entire regression (from the betas matrix)
		local mat_val = `endbeta' + `re_idx'
		local re_se = exp(betas[1, `mat_val'])
		di in red "using common se `re_se' for missing values"
		replace re_`re_idx' = 0 if re_`re_idx' == .
		replace re_se_`re_idx' = `re_se' if re_se_`re_idx' == .
		
		//4. get 1000 long draws
		expand 1000
		bysort `re_name_`re_idx'': gen sim = _n
		gen g_`re_idx' = rnormal(re_`re_idx', re_se_`re_idx')
		drop re_*
		sort `re_name_`re_idx'' sim
		
		tempfile random_effect_`re_idx'
		save `random_effect_`re_idx'', replace
	restore
	
}

/* /////////////////////////////////////////////////////////////////////
/// Merge, reshape, and calculate final predicted values.
///
/// 1. Merge the fixed effect dataset and each random effect dataset
///		together.
///
///	2. Reshape wide.
///
///	3. 	Merge this new dataset back onto your original dataset with the 
///		covariates and data.
/// 4. For each draw, do the math to generate a predicted value: 
///		y_draw_i = b_0 + B*X + G, where B is the vector of fixed effects,
///		X is the matrix of covariates, and G is the vector of random effects.
///		We transform the draws out of logit space as we go along.
///////////////////////////////////////////////////////////////////// */

//1. Merge fixed/random effects
di in red "merging fixed and random effects"
preserve
	use `fe_sims', clear // `fe_sims' = your fixed effects dataset	
	forvalues re_idx = 1/`re_count'{ // re_count = Number of random effects  EDIT: for testing purposes
		local re_name_`re_idx' : word `re_idx' of `random_effects'
		di in red "merging re `re_name_`re_idx''"
		if `re_idx'==1{
			local merge_on sim
		}
		else{
			local past_re_idx= `re_idx' -1
			local past_re_name: word `past_re_idx' of `random_effects'
			
			local merge_on sim `past_re_name'
		}
		di in red "merging on variables `merge_on'"
		cap drop _merge
		merge 1:m `merge_on' using `random_effect_`re_idx''
		count if _merge!=3
		if `r(N)' > 0{
				di in red "merge on sims not entirely successful!"
				BREAK
			}
	}
	
	drop _merge
	
	//2. Reshape wide
	di in red "reshaping"
	rename b_* b_*_draw_
	rename g_* g_*_draw_
	reshape wide b_* g_*, i(`random_effects') j(sim) 

	tempfile reshaped_covariates
	save `reshaped_covariates', replace
restore

//3. Merge back onto post-regression dataset. Merge should be perfect
di in red "merging covariates onto parent"
drop _merge
merge m:1 `random_effects' using `reshaped_covariates'

count if _merge!=3
if `r(N)' > 0{
	di in red "merge on random effects not entirely successful!"
	BREAK
}
drop _merge

//4. Do arithmetic on draw level, transform from logit to real space.
di in red "calculating predicted value!"
quietly{
	forvalues i=1/1000{
	
		if mod(`i', 100)==0{
			di in red "working on number `i'"
		}
	
		gen lt_hat_draw_`i' = b_0_draw_`i'
		
		forvalues j=1/`cov_count'{
			local cov: word `j' of `covariates'
			replace lt_hat_draw_`i' = lt_hat_draw_`i' + b_`j'_draw_`i' * `cov'
		}
		drop b_*_draw_`i'
		
		forvalues k=1/`re_count'{
			replace lt_hat_draw_`i' = lt_hat_draw_`i' + g_`k'_draw_`i'
		}
		drop g_*_draw_`i'
		
		gen draw_`i' = invlogit(lt_hat_draw_`i')
		drop lt_hat_draw_`i'
	}
}

drop re_* lt_mean

// if you haven't run a sex-specific regression, expand the dataset to include both sexes
local sexval = sex
if `sexval'==3{
	//confirm that all sex values are equal to 3.  If you have mixes of sexes, you have done
	//something very wrong.
	preserve
		//what you collapse on doesn't matter, all that matters is the 'by(sex)'.
		// we're trying to get a dataset with one observation for each sex, that's all
		collapse(mean) year, by(sex)
		count
		if `r(N)'>1{
			di in red "sex-specific and non-specific values"
			BREAK
		}
	restore
	drop sex
	expand 2, gen(sex)
	replace sex=2 if sex==0
}



/* /////////////////////////
///Save everything
///////////////////////// */

//save draws
di in red "saving all draws!"
preserve
	keep location_id year sex draw*
	save "`draws_out_dir'/`acause'_`grouping'_draws.dta", replace
	outsheet using "`draws_out_dir'/`acause'_`grouping'_draws.csv", comma replace
	save "`archive_draws_out_dir'/`acause'_`grouping'_draws_`timestamp'.dta", replace
	outsheet using "`archive_draws_out_dir'/`acause'_`grouping'_draws_`timestamp'.csv", comma replace
restore
	
//save summary stats
rename mean data_val
egen mean = rowmean(draw*)
fastpctile draw*, pct(2.5 97.5) names(lower upper)
drop draw*
	
save "`summary_out_dir'/`acause'_`grouping'_summary.dta", replace
export delimited using "`archive_summary_out_dir'/`acause'_`grouping'_summary_`timestamp'.csv", replace 
export delimited using "`summary_out_dir'/`acause'_`grouping'_summary.csv", replace
save "`archive_summary_out_dir'/`acause'_`grouping'_summary_`timestamp'.dta", replace


di in red "regression complete! Please plot."	


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// CHECK FILES

	// write check file to indicate step has finished
		file open finished using "`out_dir'/finished.txt", replace write
		file close finished
		
	// if step is last step, write finished.txt file
		local i_last_step 0
		foreach i of local last_steps {
			if "`i'" == "`this_step'" local i_last_step 1
		}
		
		// only write this file if this is one of the last steps
		if `i_last_step' {
		
			// account for the fact that last steps may be parallel and don't want to write file before all steps are done
			local num_last_steps = wordcount("`last_steps'")
			
			// if only one last step
			local write_file 1
			
			// if parallel last steps
			if `num_last_steps' > 1 {
				foreach i of local last_steps {
					local dir: dir "`root_j_dir'/03_steps/`date'" dirs "`i'_*", respectcase
					local dir = subinstr(`"`dir'"',`"""',"",.)
					cap confirm file "`root_j_dir'/03_steps/`date'/`dir'/finished.txt"
					if _rc local write_file 0
				}
			}
			
			// write file if all steps finished
			if `write_file' {
				file open all_finished using "`root_j_dir'/03_steps/`date'/finished.txt", replace write
				file close all_finished
			}
		}
		
	// close log if open
		if `close_log' log close
	
