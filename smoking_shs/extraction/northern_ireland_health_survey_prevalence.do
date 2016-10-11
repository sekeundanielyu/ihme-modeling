// Date: March 5, 2013
// Purpose: Extract secondhand smoke exposure prevalence from the Northern Ireland Health Survey 

// Set up
	clear all
	set more off
	set mem 2g
	capture log close
	
	local outdir "J:/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped"
	
	use "J:/DATA/GBR/NORTHERN_IRELAND_HEALTH_SURVEY/1997/GBR_NIHSWS_1997_DATA_Y2013M10D15.DTA", clear
				
// Make age groups
	egen age_start = cut(age), at(15(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	levelsof age_start, local(ages)
	
// Keep only nonsmokers, since we are interested in hh_shs exposure prevalence among nonsmokers
	keep if smkstat == 1
	
// Make household secondhand smoke variable
	gen hh_shs = 1 if passmok1 == 1 
	replace hh_shs = 0 if passmok1 == 0 | passsm == 2
	
// Create empty matrix for storing prevalence of household smoke exposure among nonsmokers for each age/sex subpopulation
	mata 
		year = J(1,1,"todrop")
		age_start = J(1,1,999)
		sex = J(1,1,999)
		sample_size = J(1,1,999)
		mean = J(1,1,999)
		standard_error = J(1,1,999)
	end	
	
//  Compute prevalence
	foreach sex in 1 2 {
		foreach age of local ages {
			
			di in red  "sex:`sex' age:`age'"
			mean hh_shs if age_start == `age' & sex == `sex'
			
			matrix mean_matrix = r(table)
			local mean = mean_matrix[1,1]
			mata: mean = mean \ `mean'
			
			local se = mean_matrix[2,1]
			mata: standard_error = standard_error \ `se'
	
		// Extract other key variables	
			count if age_start == `age' & sex == `sex'
			mata: sample_size = sample_size \ `r(N)'
			mata: sex = sex \ `sex'
			mata: age_start = age_start \ `age'
		}
	}

	// Get stored prevalence calculations from matrix
		clear
		getmata age_start sex sample_size mean standard_error
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
	
	// Create variables that are always tracked	
		gen year_start = 1997
		gen year_end = year_start
		gen file = "J:\DATA\GBR\NORTHERN_IRELAND_HEALTH_SURVEY\1997\GBR_NIHSWS_1997_DATA_Y2013M10D15.DTA"	
		generate age_end = age_start + 4
		egen maxage = max(age_start)
		replace age_end = 100 if age_start == maxage
		drop maxage
		gen national_type =  2 // subnationally representative
		gen urbanicity_type = 1 // representative
		gen survey_name = "Northern Ireland Health Survey"
		gen iso3 = "GBR_433" // Northern Ireland code
		gen site = "Northern Ireland"
		gen acause = "_none"
		gen grouping = "risks"
		gen healthstate = "smoking_shs"
		gen sequela_name = "Second-hand smoke"
		gen description = "GBD 2013: smoking_shs"
		gen study_status = "active"
		gen parameter_type = "Prevalence"
		gen orig_unit_type = "Rate per capita"
		gen orig_uncertainty_type = "SE"
		gen case_definition = "nonsmokers exposed to tobacco smoke inside their home on a daily or weekly basis"
	
	//  Organize
		order iso3 year_start year_end sex age_start age_end sample_size mean standard_error, first
		sort sex age_start age_end		
	
	// Save survey weighted prevalence estimates 
		save "`outdir'/nihs_prepped.dta", replace
