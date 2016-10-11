// PURPOSE: CLEAN AND EXTRACT SECONDHAND SMOKE PREVALENCE AMONG NONSMOKERS FROM THE Brazil Household Survey on Risk Factors, Morbidity, and NCDs

// NOTES: Use weight2 variable as sample weight since not every respondent in the sample completed the physical activity module

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

// Make locals for relevant files and folders
	local data_dir "$j/DATA/BRA/RISK_FACTOR_MORBIDITY_NCD_SURVEY/2002_2005"
	local codebook "$j/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw"
	local outdir "/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate"

// Bring in location names from database for GBD 2015 hierarchy 
	
	clear
	#delim ;
	odbc load, exec("SELECT ihme_loc_id, location_name, location_id, location_type
	FROM shared.location_hierarchy_history 
	WHERE (location_type = 'admin0' OR location_type = 'admin1' OR location_type = 'admin2')
	AND location_set_version_id = (
	SELECT location_set_version_id FROM shared.location_set_version WHERE 
	location_set_id = 9
	and end_date IS NULL)") dsn(epi) clear;
	#delim cr
	
	keep if regexm(ihme_loc_id, "BRA") 
	rename location_name subnational
	
	tempfile countrycodes
	save `countrycodes', replace
	
// Bring in dataset
	use "`data_dir'/BRA_RISK_FACTOR_MORBIDITY_NCD_SURVEY_2002_2005_SMOKING.DTA", clear
	drop if tabsitu == -4 
		
// Rename variables for clarity and consistency
	rename idade age
	rename sexo sex
	recode sex (0=2) 
	
// 1 is regular smoker
	rename fumareg smoker 
	
// Keep only nonsmokers, since we are interested in hh_shs exposure prevalence among nonsmokers
	keep if smoker == 0

// 1 is at least one person smokes inside house
	gen hh_shs = 0 if numpessf == 0 | pessfumd == 0 // if no smokers in HH or no one smokes indoors
	replace hh_shs = 1 if pessfumd > 0 

// Define subnationals 
	decode uf, gen(rfncd_name)
	tempfile all 
	save `all', replace
	
	import excel using "`codebook'/RFNCD_brazil_codebook.xlsx", firstrow clear 
	duplicates tag rfncd_name, gen(dup)
	drop if dup == 1
	drop dup
	merge 1:m rfncd_name using `all' 
	drop _m 
	
// Clean up: Keep only necessary variables
	keep subnational age sex hh_shs hh_shs smoker psu weight2

// Set age groups
	egen age_start = cut(age), at(15(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	levelsof age_start, local(ages)
	drop age

// Set survey weights
	svyset psu [pweight=weight2]
	
	tempfile all 
	save `all', replace
	
// Create empty matrix for storing proportion of a country/age/sex subpopulation 
	mata 
		age_start = J(1,1,999)
		sex = J(1,1,999)
		sample_size = J(1,1,999)
		mean = J(1,1,999)
		standard_error = J(1,1,999)
	end
	
	foreach sex in 1 2 {	
			foreach age of local ages {
			
		use `all', clear
		count if age_start == `age' & sex == `sex' & hh_shs != .
		local sample_size = r(N)
			
		if `sample_size' > 0 {
			
			di in red "Age: `age' Sex: `sex'"
				svy linearized, subpop(if age_start ==`age' & sex == `sex' & hh_shs != .): mean hh_shs
				// Extract proportion  of nonsmokers exposed at home
					matrix mean_matrix = e(b)
					local mean_scalar = mean_matrix[1,1]
					mata: mean = mean \ `mean_scalar'
					
					matrix variance_matrix = e(V)
					local se_scalar = sqrt(variance_matrix[1,1])
					mata: standard_error = standard_error \ `se_scalar'
						
				// Extract other key variables	
					mata: age_start = age_start \ `age'
					mata: sex = sex \ `sex'
					mata: sample_size = sample_size \ `e(N_sub)'
	
				}
			}
		}
	
// Get stored prevalence calculations from matrix
	clear
	getmata age_start sex sample_size mean standard_error 
	drop if _n == 1 // drop top row which was a placehcolder for the matrix created to store results
	
	gen iso3 = "BRA"
	
	tempfile national
	save `national', replace 
	
	
	
// Create empty matrix for storing proportion of a country/age/sex subpopulation 
	mata 
		subnational = J(1,1,"subnational") 
		age_start = J(1,1,999)
		sex = J(1,1,999)
		sample_size = J(1,1,999)
		mean = J(1,1,999)
		standard_error = J(1,1,999)
	end

use `all', clear

levelsof subnational, local(subnationals)

foreach subnational of local subnationals { 
	foreach sex in 1 2 {	
			foreach age of local ages {
			
		use `all', clear
		count if subnational == "`subnational'" & age_start == `age' & sex == `sex' & hh_shs != .
		local sample_size = r(N)
			
		if `sample_size' > 0 {
			
			di in red "Subnational: `subnational' Age: `age' Sex: `sex'"
				svy linearized, subpop(if subnational == "`subnational'" & age_start ==`age' & sex == `sex' & hh_shs != .): mean hh_shs
				// Extract proportion  of nonsmokers exposed at home
					matrix mean_matrix = e(b)
					local mean_scalar = mean_matrix[1,1]
					mata: mean = mean \ `mean_scalar'
					
					matrix variance_matrix = e(V)
					local se_scalar = sqrt(variance_matrix[1,1])
					mata: standard_error = standard_error \ `se_scalar'
						
				// Extract other key variables	
					mata: subnational = subnational \ "`subnational'"
					mata: age_start = age_start \ `age'
					mata: sex = sex \ `sex'
					mata: sample_size = sample_size \ `e(N_sub)'
	
				}
			}
		}
	}

// Get stored prevalence calculations from matrix
	clear
	getmata subnational age_start sex sample_size mean standard_error 
	drop if _n == 1 // drop top row which was a placehcolder for the matrix created to store results
	
	
	merge m:1 subnational using `countrycodes'
	drop if _m == 2
	drop _m 
	
	rename ihme_loc_id iso3
	
	drop location_id location_type
	
	append using `national' 
	
// Create variables that are always tracked
	generate file = "`data_dir'/BRA_RISK_FACTOR_MORBIDITY_NCD_SURVEY_2002_2005_SMOKING.DTA"
	generate year_start = 2002
	generate year_end = 2005
	generate age_end = age_start + 4
	egen maxage = max(age_start)
	replace age_end = 100 if age_start == maxage
	drop maxage
	gen risk = "smoking_shs"
	gen parameter_type = "Prevalence"
	gen survey_name = "Brazil Household Survey on Risk Factors, Morbidity, and NCDs"
	gen source = "micro"
	gen data_type = 10
	gen orig_unit_type = 2 // Rate per 100 (percent)
	gen orig_uncertainty_type = "SE" 
	gen national_type_id = 2 // Representative for subnational location only 
	gen case_definition = "Living with at least one smoker who smokes indoors, among current non-smokers"
	rename subnational location_name
	
	
//  Organize
	order iso3 location_name year_start year_end sex age_start age_end sample_size mean standard_error, first
	sort sex age_start age_end
	
// Save survey weighted prevalence estimates 
	save "`outdir'/prepped/bra_rfncd_subnationals.dta", replace			
	