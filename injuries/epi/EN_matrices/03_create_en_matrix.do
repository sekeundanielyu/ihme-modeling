/*
PURPOSE: Imports aggregated inpatient and outpatient EN data by age, sex, income-level. Runs
GNBR regressions on each EN pair with progressively fewer covariates until SE threshold is reached 
for the given pair. 

*/
	
set more off, perm
clear
cap cleartmp
cap restore, not
set seed 0

	local check=99
if `check'==1 {
	local 1 inp
	local 2 "inj_trans_road"
	local 3 "/snfs2/HOME/ngraetz/local/inj/gbd2015"
	local 4 1.5
	local 5 "/snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2016_02_08/03b_EN_matrices/02_temp/03_data/create_en_matrix_check_files"
	local 6 "/snfs1"
	local 7 "/snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015"
	local 8 "/share/injuries/03_steps/2016_02_08/03b_EN_matrices/02_temp/03_data"
	local 9 "/share/injuries/03_steps/2016_02_08/03b_EN_matrices"
	local 10 0 1 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 86 87 88 89
	local 11 "/snfs1/WORK/04_epi/01_database/01_code/00_library/ado"
	local 12 "/snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2016_02_08/03b_EN_matrices/02_temp/04_diagnostics"
	local 13 inp_inj_trans_road
	local 14 4
	local 16 gbd2015
	pause on
}

// Take in arguments from master file
local pf `1'
local e_code `2'
local code_dir `3'
local max_se `4'
local check_file_dir `5'
global prefix `6'
local inj_dir `7'
local in_dir `8'
local step_dir `9'
// Directory of general GBD ado functions
local gbd_ado `10'
// Step diagnostics directory
local diag_dir `11'
// Name for this job
local name `12'
// How many slots are used for this job?
local slots `13'
// GBD version
local gbd `14'

local ages 0 1 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 86 87 88 89

// Import functions
// directory for standard code files
adopath + "$prefix/WORK/04_epi/01_database/01_code/04_models/prod"
adopath + `gbd_ado'
adopath + `code_dir'/ado

// start timer if this is a new job submitted in parallel
start_timer, dir("`diag_dir'") name("`name'") slots(`slots')

// Other filepaths
local pf_dir "`step_dir'/03_outputs/01_draws/`pf'"


// Log
local log_file "`step_dir'/02_temp/02_logs/create_en_matrix_`pf'_`e_code'.smcl"
log using "`log_file'", replace name(create_en_matrix)

// Load params
load_params


// Load EN_data
import delimited using "`in_dir'/02_appended.csv", delimiter(",") clear case(preserve) asdouble
keep if e_code == "`e_code'"
if "`pf'" == "inp" {
	keep if inpatient == 1
	}
else {
	keep if inpatient == 0
	}

// Pick which regressions to run based on what sort of data is available for this platform and e-code
levelsof age, l(this_ages) c
if wordcount("`this_ages'") == wordcount("`ages'") local use_age 1
else local use_age 0
levelsof high_income, l(income_lvls) c
if wordcount("`income_lvls'") == 2 local use_income 1
else local use_income 0
levelsof sex, l(this_sexes) c
if wordcount("`this_sexes'") == 2 local use_sex 1
else local use_sex 0

if `use_age' + `use_income' +`use_sex' == 3 local regressions all age_sex age_income sex_income age sex income none
else if `use_age' + `use_income' == 2 local regressions age_income age income none
else if `use_age' + `use_sex' == 2 local regressions age_sex age sex none
else if `use_sex' + `use_income' == 2 local regressions sex_income sex income none
else if `use_sex' local regressions sex none
else if `use_age' local regressions age none
else if `use_income' local regressions income none
else local regressions none
				
// Create template for EN draws
preserve
clear
local total_obs = wordcount("`ages'") * wordcount("$sexes") * wordcount("${income_levels}")
set obs `total_obs'
gen age = 0
gen sex = 1
gen high_income = 0
local i 1
foreach a of local ages {
	foreach s of global sexes {
		foreach n of global income_levels {
			replace age = `a' in `i'
			replace sex = `s' in `i'
			replace high_income = `n' in `i'
			local ++i
		}
	}
}
tempfile demogs
save `demogs'
restore

	
** ***************************************
// Create Generalized Negative Binomial Model to estimate percent of cases of each GBD cause that results in particular ncodes
** ***************************************


// Loop through all E-N combinations and determine which model in the hierarchy to use.  Places each E-N into
// one of 5 locals, representing the different model possibilities.

local skip_list
local model_failed

foreach model of local regressions {
	local model_`model'
	if "`model'" == "all" 			local regtext = "i.high_income i.sex i.age"
	if "`model'" == "age_sex" 		local regtext = "i.sex i.age"
	if "`model'" == "age_income" 	local regtext = "i.high_income i.age"
	if "`model'" == "sex_income" 	local regtext = "i.high_income i.sex"
	if "`model'" == "sex"			local regtext = "i.sex"
	if "`model'" == "age"			local regtext = "i.age"
	if "`model'" == "income"		local regtext = "i.high_income"
	if "`model'" == "none" 			local regtext = ""
	
	foreach n of global n_codes {
		di in red "N-code: `n'"
		
		// Skip if EN combination is in skip_list
		local skip 0
		foreach item of local skip_list {
			if "`item'" == "`n'" {
				local skip 1
			}
		}
		
		if `skip' di in red "Skipped because of successful higher rank model."
		else {
			di "Model `model': `model_`model''"
			
			** check for models with 0 observations
			egen temp = total(`n')
			local n_count = temp[1]
			drop temp
			if !`n_count' {
				local failed 0
				local zero_model 1
			}
			else {
				** mark this as a non-zero model
				local zero_model 0
				
				capture noisily {
					poisson `n' `regtext', exposure(totals) iterate(30)
					mat ini = e(b)
					gnbreg `n' `regtext', from(ini) exposure(totals) iterate(30)
				}

				// Test standard errors
				if !_rc {
					** Mark failed as 1 if the model fails to converge, which leads to an error in offset reporting
					if !e(converged) local failed 1
					else {
						** Create matrix C from regression covariance matrix
						matrix C = e(V)

						** don't care about the lnalpha SE so don't measure last variance
						local cols = colsof(C) - 1

						local se 1000
						local failed 0
						** if any SE's are higher than our max allowed, mark as failed
						** unless this is the no-covariate model, in which case we are
						** forced to accept the model even w/ higher SE's.
						** NOTE: Will still fail if regression doesn't converge
						if "`model'" != "none" {
							local names: rownames(C)
							forvalues i = 1/`cols' {
								local se = sqrt(`=C[`i',`i']')
								** report model as failed if SE exceeds the arbitrary maximum or if the SE for 
								** a variable (that is not a reference category) has a 0 SE
								if (`se' > `max_se' | (`se' == 0 & !regexm(word("`names'",`i'),"b."))) local failed 1
							}
						}
					}
				}
				else local failed 1
			}
			
			if `failed' == 0 {
				// Generate draws
				preserve
				
				** Mark this as model that succeeded at a given level
				local model_`model' `model_`model'' `n'
	
				** if model had 0 cases
				if `zero_model' {
					** Mark this as model as a zero model
					local model_zero `model_zero' `n'
					clear
					set obs 1
					forvalues i = 0/999 {
						gen draw`i' = 0
					}
					local vars
				}
				
				else {
					** pull in template that has all age-sex-income groups
					use `demogs', clear
					** Hack: For some reason, the predictnl command needs the independent var to exist
					** but its value doesn't affect the prediction
					gen `n' = .
					** TODO 17 Jan 2014: The predicted values aren't actually normally distributed. Need to get draws of beta's and then use those coefficient draws to come up with draws for the predicted value
					cap noisily predictnl double mean = predict(ir), se(se)
					** hack to get around cases with small parameter estimates that causes model to fail. Set exposure to 1 and
					** instead of predicting incidence rate predict expected cases. Increment the exposure var
					** up by 1 every time until the prediction succeeds and then divide by fake exposure numbers
					** to get incidence rate
					if _rc {
						gen totals = 1
						local i 1
						while _rc {
							local ++i
							replace totals = `i'
							di "`i'"
							cap predictnl double mean = predict(), se(se)
						}
						foreach var in mean se {
							replace `var' = `var' / totals
						}
						drop totals
					}
					forvalues i = 0/999 {
						gen double draw`i' = rnormal(mean,se)
					}
					
					** keep only 1 set of draws for each permutation of the demographic vars used in regression
					local vars = subinstr("`regtext'","i.","",.)
					if "`regtext'" == "" {
						keep in 1
						keep draw*
					}
					else {
						duplicates drop `vars', force
						keep `vars' draw*
					}
					
					** prevent negative percentages
					foreach var of varlist draw* {
						replace `var' = 0 if `var' < 0
					}
				}
				

					
				** save
				cap mkdir "`in_dir'/03_modeled/`pf'"
				cap mkdir "`in_dir'/03_modeled/`pf'/`e_code'"
				keep `vars' draw*
				format draw* %16.0g
				export delimited using "`in_dir'/03_modeled/`pf'/`e_code'/`n'", delimit(",") replace
				restore
			}
			** make list of totally failed models
			else if "`model'" == "none" local model_failed `model_failed' `n'
		}
	}
	local skip_list `skip_list' `model_`model''
}

foreach i of local regressions {
	di "`i': `model_`i''"
}
di "Zeros: `model_zero'"
di "Model failed: `model_failed'"
cap assert "`model_failed'" == ""



// redo regression as Poisson if model failed completely
if _rc {
	local skip_list
	local pois_model_failed

	foreach model of local regressions {
		local pois_model_`model'
		if "`model'" == "all" 			local regtext = "i.high_income i.sex i.age"
		if "`model'" == "age_sex" 		local regtext = "i.sex i.age"
		if "`model'" == "age_income" 	local regtext = "i.high_income i.age"
		if "`model'" == "sex_income" 	local regtext = "i.high_income i.sex"
		if "`model'" == "sex"			local regtext = "i.sex"
		if "`model'" == "age"			local regtext = "i.age"
		if "`model'" == "income"		local regtext = "i.high_income"
		if "`model'" == "none" 			local regtext = ""
		
		foreach n of local model_failed {
			di in red "N-code: `n'"
			
			// Skip if EN combination is in skip_list
			local skip 0
			foreach item of local skip_list {
				if "`item'" == "`n'" {
					local skip 1
				}
			}
			
			if `skip' di in red "Skipped because of successful higher rank model."
			else {
				di "Model `model': `pois_model_`model''"
				
				capture noisily {
					poisson `n' `regtext', exposure(totals) iterate(30)
				}

				// Test standard errors
				if !_rc {
					** Mark failed as 1 if the model fails to converge, which leads to an error in offset reporting
					if !e(converged) local failed 1
					else {
						** Create matrix C from regression covariance matrix
						matrix C = e(V)
						local cols = colsof(C)
						

						local se 1000
						local failed 0
						** if any SE's are higher than our max allowed, mark as failed
						** unless this is the no-covariate model, in which case we are
						** forced to accept the model even w/ higher SE's.
						** NOTE: Will still fail if regression doesn't converge
						if "`model'" != "none" {
							forvalues i = 1/`cols' {
								local se = sqrt(`=C[`i',`i']')
								if (`se' > `max_se' | `se' == 0) local failed 1
							}
						}
					}
				}
				else local failed 1
				
				if `failed' == 0 {
					// Generate draws
					preserve
					
					** Mark this as model that succeeded at a given level
					local model_`model' `model_`model'' `n'
						

					if `zero_model' {
						** Mark this as model as a zero model
						local model_zero `model_zero' `n'
						clear
						set obs 1
						forvalues i = 0/999 {
							gen draw`i' = 0
						}
						local vars
					}
					
					else {
						** pull in template that has all age-sex-income groups
						use `demogs', clear
						** Hack: For some reason, the predictnl command needs the independent var to exist
						** but its value doesn't affect the prediction
						gen `n' = .
						** TODO 17 Jan 2014: The predicted values aren't actually normally distributed. Need to get draws of beta's and then use those coefficient draws to come up with draws for the predicted value
						cap noisily predictnl double mean = predict(ir), se(se)
						** hack to get around cases with small parameter estimates that causes model to fail. Set exposure to 1 and
						** instead of predicting incidence rate predict expected cases. Increment the exposure var
						** up by 1 every time until the prediction succeeds and then divide by fake exposure numbers
						** to get incidence rate
						if _rc {
							gen totals = 1
							local i 1
							while _rc {
								local ++i
								replace totals = `i'
								di "`i'"
								cap predictnl double mean = predict(), se(se)
							}
							foreach var in mean se {
								replace `var' = `var' / totals
							}
							drop totals
						}
						forvalues i = 0/999 {
							gen double draw`i' = rnormal(mean,se)
						}
						** keep only 1 set of draws for each permutation of the demographic vars used in regression
						local vars = subinstr("`regtext'","i.","",.)
						if "`regtext'" == "" {
							keep in 1
							keep draw*
						}
						else {
							duplicates drop `vars', force
							keep `vars' draw*
						}
						
						** prevent negative percentages
						foreach var of varlist draw* {
							replace `var' = 0 if `var' < 0
						}
					}
					
					** save
					cap mkdir "`in_dir'/03_modeled/`pf'"
					cap mkdir "`in_dir'/03_modeled/`pf'/`e_code'"
					keep `vars' draw*
					format draw* %16.0g
					export delimited using "`in_dir'/03_modeled/`pf'/`e_code'/`n'", delimit(",") replace
					restore
				}
				** make list of totally failed models
				else if "`model'" == "none" local pois_model_failed `pois_model_failed' `n'
			}
		}
		local skip_list `skip_list' `pois_model_`model''
	}	
}

foreach i of local regressions {
	di "Poisson `i': `pois_model_`i''"
}
di "Poisson failed: `pois_model_failed'"
assert "`pois_model_failed'" == ""


// Squeeze to sum to 1
cap mkdir "`pf_dir'"
** expand each file so that it contains draws for every age-sex-income group, even if not all vars were used in regression
clear
tempfile appended
foreach n of global n_codes {
	import delimited using "`in_dir'/03_modeled/`pf'/`e_code'/`n'.csv", delim(",") clear asdouble
	expand_draws, a("`ages'") s("$sexes") h("${income_levels}")
	gen n_code = "`n'"
	cap confirm file `appended'
	if !_rc append using `appended'
	save `appended', replace
}

** get sum across N-codes to squeeze each result to
collapse (sum) draw*, by(sex age high_income)
rename draw* total*
merge 1:m sex age high_income using `appended', assert(match) nogen
forvalues x = 0/999 {
	replace draw`x' = draw`x' / total`x'
	drop total`x'
}

** save squeezed data
order n_code age sex high_income, first
sort age sex high_income
sort_by_ncode n_code
format draw* %16.0g
export delimited using "`pf_dir'/`e_code'.csv", delim(",") replace

** save summary data
fastrowmean draw*, mean_var_name("mean")
fastpctile draw*, pct(2.5 97.5) names(ll ul)
drop draw*
capture mkdir "`step_dir'/03_outputs/02_summary/`pf'"
export delimited using "`step_dir'/03_outputs/02_summary/`pf'/`e_code'.csv", delim(",") replace


// if this is last 
local files_left : dir "`check_file_dir'" files "*.txt"
local files_left = subinstr(`"`files_left'"',`"""',"",.)
if "`files_left'" == "" {
	rmdir "`check_file_dir'"
	file open finished using "`step_dir'/finished.txt", replace write
	file close finished
}

// End timer
end_timer, dir("`diag_dir'") name("`name'")

log close create_en_matrix
if !`debug' erase "`log_file'"
