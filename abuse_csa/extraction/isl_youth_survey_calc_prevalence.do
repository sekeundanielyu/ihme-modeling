// DATE: September 18, 2015
// PURPOSE: CLEAN AND EXTRACT CSA DATA FROM ICELAND YOUTH SURVEY AND COMPUTE PREVALENCE IN 5 YEAR AGE-SEX GROUPS FOR EACH YEAR 

// Notes: 

	// No survey design variables are used for this survey because the survey (according to the described methodology) captures the entire population in those age groups

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
	local data_dir "$j/DATA/ISL/YOUTH_SURVEY"
	local prepped_dir "$j/WORK/05_risk/risks/abuse_csa/data/exp/01_tabulate/prepped"
	local years 2004 2006 2007 2009 2012 2013 2014

** *********************************************************************
** 1.) Clean and create CSA indicator 
** *********************************************************************

	// Loop through surveys

	foreach year of local years {
	
		local surveys: dir "J:/DATA/ISL/YOUTH_SURVEY/`year'" files "*.DTA", respectcase
		cd "J:/DATA/ISL/YOUTH_SURVEY/`year'"
		di `surveys'
	
		foreach file of local surveys {
			use `file', clear 
			gen year = `year'
			gen file = "J:/DATA/ISL/YOUTH_SURVEY/`year'"
			di in red `year'
			di in red `surveys'

			// gen abuse_csa = . 

			if inlist(year, 2004) { 
				egen abuse_csa = rowtotal(sp_154a2 sp_154a3 sp_154a4 sp_154a5 sp_154b2 sp_154b3 sp_154b4 sp_154b5 sp_154c2 sp_154c3 sp_154c4 sp_154c5 /// 
					sp_154d2 sp_154d3 sp_154d4 sp_154d5 sp_154e2 sp_154e3 sp_154e4 sp_154e5), miss
				}

			if inlist(year, 2006) { 
				egen abuse_csa = rowtotal(sp_47q1 sp_47q2 sp_47q3 sp_47r1 sp_47r2 sp_47r3 sp_47s1 sp_47s2 sp_47s3), miss
			}

			if inlist(year, 2007) { 
				egen abuse_csa = rowtotal(sp_54s1 sp_54s2 sp_54s3), miss
			}

			if inlist(year, 2009) { 
				egen abuse_csa = rowtotal(sp_45q1 sp_45q2 sp_45q3 sp_45r1 sp_45r2 sp_45r3 sp_45s1 sp_45s2 sp_45s3), miss
			}


			if inlist(year, 2012) {
				egen abuse_csa = rowtotal(sp_35p1 sp_35p2 sp_35p3), miss
			}

			if inlist(year, 2013) { 
				egen abuse_csa = rowtotal(sp_41s1 sp_41s2 sp_41s3 sp_41t1 sp_41t2 sp_41t3), miss
			}

			if inlist(year, 2014) { 
				egen abuse_csa = rowtotal(sp_30r1 sp_30r2 sp_30r3), miss
			}


			cap replace abuse_csa = 1 if abuse_csa >= 1 & abuse_csa != .

			tempfile isl_`year' 
			save `isl_`year'', replace
		}
	}


	// Append them all together

	use `isl_2004', clear 
	foreach year of local years {
		if `year' != 2004 {
			append using `isl_`year'', force
		}
	}

	tempfile almost
	save `almost', replace

	// Add 2010 separately 

		use "`data_dir'/2010/ISL_YOUTH_SURVEY_2010_AGES_16_20_Y2014M02D24.DTA", clear 
		gen year = 2010
		gen file = "J:/DATA/ISL/YOUTH_SURVEY/2010"
		recode sp_41s1 sp_41s2 sp_41s3 (88 = .)
		egen abuse_csa = rowtotal(sp_41s1 sp_41s2 sp_41s3) 
		replace abuse_csa = 1 if abuse_csa >= 1 & abuse_csa != .

		append using `almost'

	// Generate age variable from year born 
		decode sp_2, gen(year_born) 
		decode sp_02, gen(year_born2) 

		replace year_born = year_born2 if year_born == "" 
		drop if year_born == "Annað"
		destring year_born, replace

		gen age = year - year_born
		// drop if age > 18 // limit to our definitions is 18; gold standard recall age is 15 

		gen sex = sp_1 
		replace sex = sp_01 if sex == . & sp_01 != .

	// Keep only necessary variables
		keep file year abuse_csa age sex 
		order file year age sex abuse_csa

		tempfile all 
		save `all', replace

** ****************************************************************************************
** 2.) Calculate prevalence in each year/age/sex subgroup and save compiled/prepped dataset
** ***********************

	// Create empty matrix 

	use `all', clear

	mata
		file = J(1,1,"todrop") 
		year = J(1,1,-999)
		age_start = J(1,1,-999)
		sex = J(1,1,-999)
		sample_size = J(1,1,-999)
		mean = J(1,1,-999.999)
		standard_error = J(1,1,-999.999)
		lower = J(1,1,-999.999)
		upper = J(1,1,-999.999)
	end

	// Set age groups
	egen age_start = cut(age), at(15(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	levelsof age_start, local(ages)
	drop age

	// Calculate prevalence 

	levelsof file, local(files)

		foreach file of local files { 
			foreach sex in 1 2 {	
				foreach age of local ages {

					count if file == "`file'" & age_start == `age' & sex == `sex'

					if r(N) != 0 {

					di in red "file: `file' sex:`sex' age: `age'"
					mean abuse_csa if file == "`file'" & age_start == `age' & sex == `sex'
					
					matrix mean_matrix = r(table)
					local mean = mean_matrix[1,1]
					mata: mean = mean \ `mean'
					
					local se = mean_matrix[2,1]
					mata: standard_error = standard_error \ `se'


				// Extract other key variables	
					count if file == "`file'" & age_start == `age' & sex == `sex'
					mata: sample_size = sample_size \ `r(N)'
					mata: sex = sex \ `sex'
					mata: age_start = age_start \ `age'
					// mata: year = year \ `yr'
					mata: file = file \ "`file'"

				}
			}
		}
	}
				

// Get stored prevalence calculations from matrix
		clear
		getmata file age_start sex sample_size mean standard_error lower upper
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
		drop if sample_size < 10
		drop lower upper

	// Create variables that are always tracked	

		split(file), p("/")
		rename file5 year
		drop file*
		gen year_start = year
		gen year_end = year_start
		gen age_end = age_start + 4
		gen national_type = 1
		gen urbanicity_type = "representative"
		gen iso3 = "ISL"
		gen acause = "_none"
		gen grouping = "risks"
		gen health_state = "abuse_csa"
		gen sequela_name = "Childhood Sexual Abuse"
		gen description = "GBD 2015: abuse_csa"
		gen study_status = "active"
		gen parameter_type = "Prevalence"
		gen orig_unit_type = "Rate per capita"
		gen orig_uncertainty_type = "SE"
		

// NIDS 
	// 2004 2006 2007 2009 2010 2012 2013 2014
		gen nid = 166284 if year == "2014"
		replace nid = 166283 if year == "2013" 
		replace nid = 166282 if year == "2012" 
		replace nid = 166280 if year == "2010"
		replace nid = 166279 if year == "2009"
		replace nid = 166277 if year == "2007"
		replace nid = 166276 if year == "2006" 
		replace nid = 166274 if year == "2004"

// Epi covariates
	
		gen contact = 0 
		gen noncontact = 0
		gen intercourse = 0 
		gen child_16_17 = 1 if inlist(year, "2014", "2012", "2009", "2006")
		gen child_18 = 1
		gen child_18plus = 1 if inlist(year, "2013", "2007", "2010")
		gen child_over_15 = 1 
		gen child_under_15 = 0
		gen nointrain = 0
		gen perp3 = 0
		gen notviostudy1 = 1
		gen parental_report = 0
		gen school = 0
		gen anym_quest = 0

		drop year
		destring year_start, replace 
		destring year_end, replace


//  Organize
		order iso3 year_start year_end sex age_start age_end sample_size mean standard_error, first
		sort sex age_start age_end	

// Save file 
	
		save "`prepped_dir'/isl_youth_survey_prepped.dta", replace	





