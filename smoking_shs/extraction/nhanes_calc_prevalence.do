// Date: October, 2013
// Purpose: Calculate nationally representative secondhand smoke exposure prevalence among nonsmokers from NHANES data

// Notes: 
	** Household secondhand smoke question: "Does anyone who lives here smoke cigarettes, cigars, or pipes anywhere inside this home?" 1= Yes, 2= No, 7 = Refused, 9= Don't know
	** Smoking status question: Have you smoked at least 100 cigarettes in your lifetime? (1-Yes, 2=No, 7= refused, 9=don't know).  If respondent answers yes, they get the question: Do you now somke... 1= everyday, 2= some days, 3 = not at all, 7 = refused, 9=don't know


// Set up
	clear all
	set more off
	set mem 2g
	capture log close
	capture restore not
	
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	
	else if c(os) == "Windows" {
		global j "J:"
	}
	
	
// Create locals for relevant files and folders
	local datadir "$j/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate"

// Use NHANES file that has compiled data for all years to present that have smoking status and secondhand smoke exposure questions
	use `datadir'/raw/nhanes/nhanes_compiled.dta, clear

		
// Rename key variables for consistency with prevalence estimates from other surveys
	rename sdmvpsu  psu 
	rename sdmvstra strata
	rename wtint2yr wt 
	
	rename ridageyr age
	rename riagendr sex
	
// Set age groups
	egen age_start = cut(age), at(10(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	levelsof age_start, local(ages)
	drop age

// Generate indicator variables for smoking status and secondhand smoke exposure in the household
	generate smoker = smq040 // 1= respondent is a daily smoker
	replace smoker = 0 if age_start < 20 | smoker == 2 | smoker == 3 | smq020 == 2 // Assume individuals under age 20 do not smoke (aren't asked smoking status question) and if respondent smokes "some days" or "not at all", or has not smoked more than 100 cigarettes in lifetime they are considered a nonsmoker
	
	generate shs = .
	replace shs = 1 if smd410 == 1 // 1= smoking in respondent home
	replace shs = 0 if smd410 == 2 // no smoking in respondent home
	
// Calculate year-sex-age specific prevalence of secondhand smoke exposure among nonsmokers in U	// Create empty matrix for storing results
		mata 
			year = J(1,1,999)
			age_start = J(1,1,-999)
			sex = J(1,1,-999)
			category = J(1,1,"todrop")
			sample_size = J(1,1,-999)
			parameter_value = J(1,1,-999.999)
			standard_error = J(1,1,-999.999)
			upper = J(1,1,-999.999)
			lower = J(1,1,-999.999)
		end

	
	// Set survey weights
		svyset psu [pweight=wt], strata(strata)
	
	// Keep only known nonsmokers, since we are interested in shs exposure prevalence among nonsmokers
		keep if smoker == 0 

	// Tempfile dataset containing only nonsmokers for use in loop below that calculates prevalence
		tempfile allyears
		save `allyears'

	// Loop through each year, sex, and age to calculate secondhand smoke exposure among nonsmokers using survey weights
	levelsof year_end, local(years)
	foreach year of local years  {
	
		use `allyears', clear
		keep if year_end == `year'
			
		// Compute prevalence
			foreach sex in 1 2 {	
				foreach age of local ages {
					
					di in red "Year: `year' Age: `age' Sex: `sex'"
						svy linearized, subpop(if age_start ==`age' & sex == `sex'): mean shs
		
						mata: year = year \ `year'
						mata: age_start = age_start \ `age'
						mata: sex = sex \ `sex'
						mata: category = category \ "household_cig_smoke"
						mata: sample_size = sample_size \ `e(N_sub)'
						matrix mean_matrix = e(b)
						local mean_scalar = mean_matrix[1,1]
						mata: parameter_value = parameter_value \ `mean_scalar'
						
						matrix variance_matrix = e(V)
						local se_scalar = sqrt(variance_matrix[1,1])
						mata: standard_error = standard_error \ `se_scalar'
						
					// Calculate upper and lower 95% confidence intervals
						local degrees_freedom = `e(df_r)'
						local lower = invlogit(logit(`mean_scalar') - (invttail(`degrees_freedom', .025)*`se_scalar')/(`mean_scalar'*(1-`mean_scalar')))
						mata: lower = lower \ `lower'
						local upper = invlogit(logit(`mean_scalar') + (invttail(`degrees_freedom', .025) * `se_scalar') / (`mean_scalar' * (1 - `mean_scalar')))
						mata: upper = upper \ `upper'	
				}
			}
	}

	// Get stored prevalence calculations from matrix
		clear

		getmata year age_start sex category sample_size parameter_value standard_error lower upper
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
	
	// Set variables that are always tracked
		gen GBD_cause = "smoking_shs"
		gen iso3 = "USA"
		gen case_name = "any_houshold_secondhand_smoke"
		gen source = "micro_NHANES"
		gen ss_level = "age_sex"
		gen national = 1
		gen survey_name = "NHANES"
		gen age_end = age_start + 4
		rename year year_end
		gen year_start = year_end - 1
		
	// Enter NIDs
		gen nid = .
		replace nid = 110300 if year_end == 2012
		replace nid = 48332 if year_end == 2010
		replace nid = 25914 if year_end == 2008
		replace nid = 47478 if year_end == 2006
		replace nid = 47962 if year_end == 2004
		replace nid = 49205 if year_end == 2002
		replace nid = 52110 if year_end == 2000

	// Organize
		order year_start year_end sex age_start age_end sample_size parameter_value lower upper standard_error, first
		sort sex age_start age_end year_start
		

save `datadir'/prepped/nhanes_prepped.dta, replace


