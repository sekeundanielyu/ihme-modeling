// DATE: April 2015
// PURPOSE: CLEAN AND EXTRACT CSA DATA FROM BRFSS AND COMPUTE PREVALENCE IN 5 YEAR AGE-SEX GROUPS FOR EACH YEAR 

// NOTES: 
	// 2009-2012: definition is before age of 18 
	** acetouch: How often did anyone at least 5 years older than you or an adult, ever touch you sexually? (1 Never, 2 Once, 3 More than once, 7 Don’t know / Not sure, 9 Refused)
	** acetthem: How often did anyone at least 5 years older than you or an adult, try to make you touch them sexually? (1 Never, 2 Once, 3 More than once, 7 Don’t know / Not sure, 9 Refused)
	** acehvsex: How often did anyone at least 5 years older than you or an adult, force you to have sex? (1 Never, 2 Once, 3 More than once, 7 Don’t know / Not sure, 9 Refused)
	
	// 2005, 2007
	** svnotch: In the past 12 months, has anyone exposed you to unwanted sexual situations that did not involve physical touching? Examples include things like flashing you, peeping, sexual harassment, or making you look at sexual photos or movies.
	** svsextch: In the past 12 months, has anyone touched sexual parts of your body after you said or showed that you didn't want them to or without your consent? 1=yes, 2=no
	** svnosex: In the past 12 months, has anyone ATTEMPTED to have sex with you after you said or showed that you didn’t want to or without your consent, BUT SEX DID NOT OCCUR?
	** svhadsex: In the past 12 months, has anyone HAD SEX with you after you said or showed that you didn’t want to or without your consent?
	** sveanosx: Has anyone EVER ATTEMPTED to have sex with you after you said or showed that you didn’t want to or without your consent, BUT SEX DID NOT OCCUR?
	** svehdsex: Has anyone EVER had sex with you after you said or showed that you didn’t want them to or without your consent?
	** ipvthrat: Has an intimate partner EVER THREATENED you with physical violence?  This includes threatening to hit, slap, push, kick, or physically hurt you in any way
	** ipvhhrt: Has an intimate partner EVER hit, slapped, pushed, kicked, or physically hurt you in any way?
	** ipvphyvl: “Other than what you have already told me about” Has an intimate partner EVER ATTEMPTED physical violence against you? This  includes times when they tried to hit, slap, push, kick, or otherwise physically hurt you, but they were not able to.
	** ipvuwsex: Have you EVER experienced any unwanted sex by a current or former intimate partner?
	** ipvpvl12: In the past 12 months, have you experienced any physical violence or had unwanted sex with an intimate partner?
	** ipvsxinj: In the past 12 months, have you had any injuries, such as bruises, cuts, scrapes, black eyes, vaginal or anal tears, or broken bones, as a result of this physical violence or unwanted sex?

// Set up
	clear all
	set more off
	set mem 2g
	capture restore not
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j "J:"
	}

// Create locals for relevant files and folders
	local data_dir_ipv "$j/WORK/05_risk/risks/abuse_ipv_exp/data/exp/01_tabulate/raw"
	local data_dir_csa "$j/WORK/05_risk/risks/abuse_csa/data/exp/01_tabulate/raw"
	local prepped_dir_ipv "$j/WORK/05_risk/risks/abuse_ipv_exp/data/exp/01_tabulate/prepped"
	local prepped_dir_csa "$j/WORK/05_risk/risks/abuse_csa/data/exp/01_tabulate/prepped"
	
	local years 2005 2007 2009 2010 2011 2012
	
// Country codes 
 
	adopath + "$j/WORK/10_gbd/00_library/functions"
	get_demographics, gbd_team(epi) make_template clear 
	keep location_name location_id
	collapse (first) location_id, by(location_name)

	tempfile countrycodes
	save `countrycodes', replace 


** *********************************************************************
** 1.) Clean and Compile 
** *********************************************************************
	// Loop through files for each year for IPV
	
	foreach year of local years {
		
		if inlist(`year', 2009, 2010, 2011, 2012) {
			use "`data_dir_csa'/brfss/brfss_`year'.dta", clear
			renvars, lower
			gen year = `year'
			gen file = "J:/DATA/USA/BRFSS/`year'"
			di in red `year'
			
			// Generate a variable for any csa
			recode ace* (7 9 = .) // Don't know/not sure and refusal to missing
			gen any_csa = 1 if acetouch == 2 | acetouch == 3 | acetthem == 2 | acetthem == 3 | acehvsex == 2 | acehvsex == 3 // "yes CSA" if individual had any experience at least once
			recode any_csa (.=0) if acetouch == 1 & acetthem == 1 & acehvsex == 1 // never for all 3 is a "no CSA"
				}
			
		if inlist(`year', 2005, 2007) {
			use "`data_dir_ipv'/BRFSS_`year'.dta", clear
			renvars, lower
			gen year = `year'
			gen file = "J:/DATA/USA/BRFSS/`year'"
			di in red `year'
			
			// Generate variable for ever any IPV
			recode ipv* sv* (7 9 = .)
			cap rename ipvphyv2 ipvphyvl
			gen any_ipv = 1 if (ipvphhrt == 1 |  ipvphyvl == 1 | ipvuwsex == 1)
			recode any_ipv (.=0) if (ipvphhrt ==2 & ipvphyvl == 2 | ipvuwsex == 2)
			}
			
			// Keep only necessary variables
			cap rename a_llcpwt a_finalwt
			tempfile brfss_`year'
			save `brfss_`year'', replace
		}
				
// Append all years together
	use `brfss_2005', clear
	foreach year of local years {
		if `year' != 2005 {
			append using `brfss_`year'', force
		}
	}


tempfile all 
save `all', replace

// Check for missingness in IPV for the 12 states that have the Intimate Partner Violence module 
	keep if year == 2005 | year == 2007 
	keep if sex == 2 
	bysort a_state year: egen sum = sum(any_ipv)
	drop if sum == 0 

	// total observations for each state 
	bysort a_state year: gen total = _N 

	levelsof a_state, local(states)
	levelsof year, local(years) 

	foreach state of local states { 
		foreach year of local years { 

		preserve 
		keep if a_state == `state' & year == `year' 
		count if any_ipv == . 
		gen missingness = `r(N)' / total
		tempfile temp_`year'_`state'
		save `temp_`year'_`state'', replace
		restore
		}
	}

	use `temp_2005_4', clear 

	foreach state of local states { 
		foreach year of local years { 
		if `state' != 4 { 
			append using `temp_`year'_`state''
			}
		}
	}

	keep a_state year missingness
	collapse (first) missingness, by(a_state year)
	tempfile missing 

	rename a_state state 
	tempfile miss_data
	save `miss_data', replace

	insheet using "$j/WORK/05_risk/risks/abuse_ipv_exp/data/exp/01_tabulate/raw/state_fips_codes.csv", comma names clear 
	
	merge 1:m state using `miss_data', nogen keep(match)
	rename state_name location_name
	replace location_name = "Virgin Islands, U.S." if location_name == "Virgin Islands"
	merge m:m location_name using `countrycodes', nogen keep(match) 
	drop state
	rename year year_start

	save `miss_data', replace

	// Merge back on file so we have a missigness variable
	
	use `all', clear 

	keep a_state any_csa any_ipv age sex acetouch acehvsex acetthem a_psu a_finalwt year file 
	gen parameter_value = any_csa
	replace parameter_value = any_ipv if parameter_value == . & any_ipv != .
	drop if parameter_value == .
	
	// Match with state fips codes 
	
	rename a_state state 
	
	tempfile all 	
	save `all', replace 
	
	insheet using "$j/WORK/05_risk/risks/abuse_ipv_exp/data/exp/01_tabulate/raw/state_fips_codes.csv", comma names clear 
	
	merge 1:m state using `all', nogen keep(match)
	drop state 
	rename state_name state 
	
** *******************************************************************************************
** 2.) Calculate Prevalence in each year/age/sex subgroup and save compiled/prepped dataset
** *******************************************************************************************		
// Create empty matrix for storing calculated results for each year, sex, age group
	mata
		state = J(1,1,"todrop") 
		year = J(1,1,999)
		age = J(1,1,-999)
		sex = J(1,1,-999)
		sample_size = J(1,1,-999)
		mean = J(1,1,-999.999)
		standard_error = J(1,1,-999.999)
		lower = J(1,1,-999.999)
		upper = J(1,1,-999.999)
		file = J(1,1,"to drop")
	end

// Set age groups
	egen age_start = cut(age), at(15(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	levelsof age_start, local(ages)
	drop age
	
// Specify survey design
	svyset a_psu [pweight=a_finalwt], strata(a_finalwt)

// Compute prevalence, sample size and missigness for each year sex age group

	levelsof year, local(years) clean
	levelsof state, local(states) 
	
foreach state of local states {
	foreach year of local years {
		foreach sex in 1 2 {	
			forvalues age=15(5)80 {
				
				di in red "State: `state' Year: `year' Age: `age' Sex: `sex'"
				count if state == "`state'" & year == `year' & age_start == `age' & sex == `sex' & parameter_value != . 
				if r(N) != 0 {
				
				svy linearized, subpop(if state == "`state'" & year == `year' & age_start == `age' & sex == `sex'): mean parameter_value

					matrix mean_matrix = e(b)
					local mean_scalar = mean_matrix[1,1]
					mata: mean = mean \ `mean_scalar'
					
					matrix variance_matrix = e(V)
					local se_scalar = sqrt(variance_matrix[1,1])
					mata: standard_error = standard_error \ `se_scalar'
					
					local degrees_freedom = `e(df_r)'
					local lower = invlogit(logit(`mean_scalar') - (invttail(`degrees_freedom', .025)*`se_scalar')/(`mean_scalar'*(1-`mean_scalar')))
					mata: lower = lower \ `lower'
					local upper = invlogit(logit(`mean_scalar') + (invttail(`degrees_freedom', .025) * `se_scalar') / (`mean_scalar' * (1 - `mean_scalar')))
					mata: upper = upper \ `upper'
					
					mata: state = state \ "`state'" 
					mata: year = year \ `year'
					mata: age = age \ `age'
					mata: sex = sex \ `sex'
					// levelsof file, local(file)
					// mata: file = file \ "`file'"
					
					mata: sample_size = sample_size \ `e(N_sub)'
				
				}
			}
		}
	}
}

// Get stored prevalence calculations from matrix
	clear

	getmata state year age sex sample_size mean standard_error upper lower file, replace
	drop if _n == 1 // Drop empty top row of matrix
	replace standard_error = (3.6/sample_size)/(2*1.96) if standard_error == 0 // Greg's standard error fix for binomial outcomes
	
	tostring year, replace
	replace file = "J:/DATA/BRFSS/" + year
	destring year, replace
	
// Create variables that are always tracked
	gen iso3 = "USA"
	gen healthstate = "abuse_csa" if inlist(year, 2009, 2010, 2011, 2012)
	replace healthstate = "abuse_ipv" if inlist(year, 2005, 2007)
	gen survey_name = "Behavioral Risk Factor Surveillance System"
	rename year year_start
	gen year_end = year_start
	rename age age_start
	gen age_end = age_start + 4
	egen maxage = max(age_start)
	replace age_end = 100 if age_start == maxage
	drop maxage
	gen data_type = "Survey: unspecified"
	gen source_type = 2
	label define source_type 2 "Survey"
	label values source_type source_type
	gen orig_uncertainty_type = "SE" 
	gen national_type = 1 // Nationally representative
	gen urbanicity_type = "representative" // Representative
	gen units = 1
	gen nid = 104825 if year_start == 2012
	replace nid = 83633 if year_start == 2011
	replace nid = 83627 if year_start == 2010
	replace nid = 30018 if year_start == 2009
	replace nid = 30000 if year_start == 2007
	replace nid = 29983 if year_start == 2005 
	
	replace state = "Virgin Islands, U.S." if state == "Virgin Islands"
	tempfile all 
	save `all', replace 
	
// Merge with iso3 codes for U.S. states

	use `countrycodes', clear 
	rename location_name state 
	
	merge 1:m state using `all', nogen keep(match)
	
	
// Save CSA dataset
	preserve
	keep if healthstate == "abuse_csa"
	
	// Specify Epi covariates
		gen contact = 0 
		gen noncontact = 0
		gen intercourse = 0 
		gen child_16_17 = 0
		gen child_18 = 1
		gen child_18plus = 0
		gen child_over_15 = 0
		gen child_under_15 = 0
		gen nointrain = 1
		gen perp3 = 0
		gen notviostudy1 = 1
		gen parental_report = 0
		gen school = 0
		gen anym_quest = 0
	
	// Organize
		order iso3 year_start year_end sex age_start age_end sample_size mean lower upper standard_error, first
		sort sex age_start age_end  year_start
		tostring location_id, replace
	save "`prepped_dir_csa'/brfss_states_prepped.dta", replace
	restore
	
// Save IPV dataset
	preserve
	keep if healthstate == "abuse_ipv" & sex == 2
	rename mean parameter_value // to be consistent with other IPV datasets
	
	// Specify Epi covariates
		gen subnational = 0
		gen urban = 0
		gen rural = 0
		gen mixed = 0
		gen nointrain = 1
		gen notviostudy1 = 1
		gen sexvio = 0
		gen physvio = 0
		gen spouseonly = 0
		gen pstatall = 0
		gen pstatcurr = 0
		gen pastyr = 0
		gen past2yr = 0
		gen severe = 0
		gen currpart = 0

	// Merge on missigness
		merge m:1 location_id year_start using `miss_data'
		drop _m
		
	// Organize
		order iso3 location_id year_start year_end sex age_start age_end sample_size parameter_value lower upper standard_error missingness, first
		sort sex age_start age_end  year_start
		tostring location_id, replace
	save "`prepped_dir_ipv'/brfss_states_prepped.dta", replace
	restore
