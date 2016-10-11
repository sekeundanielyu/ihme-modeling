// PURPOSE: EXTRACT AND CALCULATE PREVALENCE OF SECONDHAND SMOKE EXPOSURE AMONG NONSMOKERS FROM BRFSS

// NOTES: SHS questions are in module 18 which is an optional module, leading to high missingness.  Optional modules started in 1988.  
** Secondhand smoke question: TOBACCO: "In the past 30 days has anyone, including yourself, smoked cigarettes, cigars, or pipes anywhere inside your home?"  (1="yes", 2 = "no", 7="don't know/not sure", 9 = refused).  In 2008 survey question was "On how many of the past 7 days, did anyone smoke in your home while you were there?"(1-7 = number of days, 55=I was not at home, 88=none)
 
** Smoking status question: SMOKE100: Have you smoked at least 100 cigarettes in your entire life? (1=Yes, 2=No, 7=don't know/not sure, 9=refused).  If yes, (SMOKDAY) Do you now smoke cigarettes everyday, some days or not at all? (1=everyday, 2=some days, c=not at all, 9=refused). 
 
// Set up
	clear all
	set more off
	set mem 2g
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j "J:"
		version 11
	}

// args healthstate iso3 sex
	local us_state "`1'"
	
// add logs
	log using "/snfs3/WORK/05_risk/temp/explore/second_hand_smoke/BRFSS/logs/log_`us_state'.smcl", replace 
	
	di "`us_state'" 
	
// Create locals for relevant files and folders
	local raw_dir = "$j/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/brfss"
	local survey_var_file = "`raw_dir'/brfss_varlist_new.csv"
	local brfss_prepped_dir = "$j/WORK/05_risk/02_models/smoking_shs/01_exp/01_tabulate/data/prepped"
	local years 1998 1999 2000 2008 // Set years of data to use (For now we will only use years that had a smoking in household question (excluding ones that only had a question about rules in the house)
	
// Country codes
	use "$j/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/countrycodes2015.dta", clear 
	keep if regexm(iso3, "USA") | location_type == "nonsovereign" 
	tempfile countrycodes
	save `countrycodes', replace
	
// Loop  through each survey year and make clean dataset with necessary variables
	foreach year of local years {
		
		// Get variable names for survey processing
			insheet using `survey_var_file', names clear
			tostring nid year, replace
			mata: varlist = st_sdata(.,("nid", "year", "not_smokers", "missing", "daily_var", "hh_shs", "no_hh_shs", "hh_shs_miss"))

			local year_index = `year' - 1997 // This local indexes the correct row in the varlist csv	
			di in red `year_index' 

		// Get logic locals for each year
			mata: st_local("nid", varlist[`year_index', 1])
			mata: st_local("not_smokers", varlist[`year_index', 3])
			mata: st_local("missing", varlist[`year_index', 4])
			mata: st_local("daily_var", varlist[`year_index', 5])
			mata: st_local("hh_shs", varlist[`year_index', 6])
			mata: st_local("no_hh_shs", varlist[`year_index', 7])
			mata: st_local("hh_shs_miss", varlist[`year_index', 8])
		
		// Load data
				use "`raw_dir'/brfss_`year'.dta", clear
				di "`year'"

		// Assign to age groups
			gen age_start = . 
			gen age_end = . 
			forvalues x=15(5)100 {
				local max = `x' + 5
				replace age_start = `x' if age >= `x' & age < `max'
			}
			replace age_start = 80 if age_start >= 80
			replace age_end = age_start + 4

		// Assign daily smokers
			generate smoker = 1 if `daily_var'
			replace smoker = 0 if `not_smokers'
			replace smoker = . if `missing'
	
		// Keep only nonsmokers, since we are interested in household secondhand smoke exposure prevalence among nonsmokers
			keep if smoker == 0
	
		// Define secondhand smoke exposure
			
			generate shs = 1 if `hh_shs' 
			replace shs = 0 if `no_hh_shs'
			replace shs = . if `hh_shs_miss'
			/*
			generate shs = 0
			replace shs = 1 if `hh_shs' 
			replace shs = . if `hh_shs_miss'
			*/

		// Keep only necessary variables so that datasets for each year append properly	
			keep shs age_start age_end sex A_PSU A_STSTR A_FINALWT A_STATE
			
		// Generate year-specific variables to keep track of
			generate year_start = "`year'"
			generate nid = "`nid'"
			destring year_start nid, replace
			
		// Make tempfile for each year
			tempfile `year'data
			save ``year'data'
	}
		
// Append files for each year together to make one master file for all years
	use `1998data', clear
	foreach year in 1999 2000 2008 {
		append using ``year'data'
	}
	
	rename A_STATE state 
	
	tempfile master
	save `master', replace

// Match with state fips codes 
	
	insheet using "`raw_dir'/state_fips_codes.csv", comma names clear 
	
	merge 1:m state using `master', nogen keep(match)
	drop state 
	rename state_name state 
	
	tempfile all 
	save `all', replace 
	
	// Create empty matrix for storing calculated results for each year, sex, age group
	mata
		state = J(1,1,"todrop") 
		nid = J(1,1,999)
		year = J(1,1,999)
		age = J(1,1,999)
		sex = J(1,1,999)
		category = J(1,1, "todrop")
		sample_size = J(1,1,999)
		parameter_value = J(1,1,999)
		standard_error = J(1,1,999)
		lower = J(1,1,999)
		upper = J(1,1,999)
		pctmiss = J(1,1,999)
	end
	
// Specify survey design
	svyset A_PSU [pweight=A_FINALWT], strata(A_STSTR)
	
	save `all', replace

	di in red "`us_state'"

// Compute prevalence, sample size and missigness for each state year sex age group

	foreach year of local years {
		foreach sex in 1 2 {	
			forvalues age=15(5)80 {
							
				di in red "State: `us_state' Year: `year' Age: `age' Sex: `sex'"
				count if state == "`us_state'" & year == `year' & age_start == `age' & sex == `sex' & shs != . 
				local sample_size = r(N)
						
				if `sample_size' > 0 {
				
				svy linearized, subpop(if state == "`us_state'" & year_start == `year' & age_start == `age' & sex == `sex'): mean shs
	
				// preserve
				// keep if year_start == `year' & age_start == `age' & sex == `sex'
				local nid = nid 
				
				mata: nid = nid \ `nid'
				mata: year = year \ `year'
				mata: age = age \ `age'
				mata: sex = sex \ `sex'
				mata: category = category \ "household_cig_smoke"
				mata: state = state \ "`us_state'" 

				mata: sample_size = sample_size \ `e(N_sub)'

				matrix mean_matrix = e(b)
				local mean_scalar = mean_matrix[1,1]
				mata: parameter_value = parameter_value \ `mean_scalar'
				
				matrix variance_matrix = e(V)
				local se_scalar = sqrt(variance_matrix[1,1])
				mata: standard_error = standard_error \ `se_scalar'
				
				local degrees_freedom = `e(df_r)'
				local lower = invlogit(logit(`mean_scalar') - (invttail(`degrees_freedom', .025)*`se_scalar')/(`mean_scalar'*(1-`mean_scalar')))
				mata: lower = lower \ `lower'
				local upper = invlogit(logit(`mean_scalar') + (invttail(`degrees_freedom', .025) * `se_scalar') / (`mean_scalar' * (1 - `mean_scalar')))
				mata: upper = upper \ `upper'
		
				count if year_start == `year' & age_start == `age' & sex == `sex'
				local total_obs = `r(N)'
				count if shs == . & year_start == `year' & age_start == `age' & sex == `sex'
				local missing_count = `r(N)'
				mata: pctmiss = pctmiss \ (`missing_count' / `total_obs')
				// restore
			}
		}
	}
}


// Get stored prevalence calculations from matrix
	clear

	getmata nid state year age sex category sample_size parameter_value standard_error upper lower pctmiss
	drop if _n == 1 // Drop empty top row of matrix
	replace standard_error = . if standard_error == 0 & parameter_value != 0 // Standard error could not be calculated for a few age/age groups so replacing as missing if prevalence is not zero
	
// Create variables that are always tracked
	gen iso3 = "USA"
	gen type = "household_secondhand_smoke"
	gen source = "micro_BRFSS"
	gen ss_level = "age_sex"
	gen national = 1
	gen survey_name = "BRFSS"
	gen case_definition = "Any passive smoke exposure inside the home in the past 30 days among current non-smokers"
	replace case_definition = "any passive smoke exposure at home in the past 7 days among current non-smokers" if year == 2008
	rename year year_start
	gen year_end = year_start
	rename age age_start
	gen age_end = age_start + 4

// Organize
		order iso3 state year_start year_end sex age_start age_end sample_size parameter_value lower upper standard_error, first
		sort sex age_start age_end  year_start
		
// Save survey weighted prevalence estimates 
		save "/snfs3/WORK/05_risk/temp/explore/second_hand_smoke/BRFSS/brfss_`us_state'.dta", replace

