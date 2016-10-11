// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 			June 4, 2015
// Project:		RISK
// Purpose:		Extract India subnational data from 2005-2006 DHS for second-hand smoke (national-level estimates extracted in large DHS extraction batch)
** **************************************************************************

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

// Create locals for relevant files and folders
	local data_dir  "$j/DATA/MACRO_DHS/IND/2005_2006"
	local out_dir "$j/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped"
	
	
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
		
	// Fix weird symbols that import as question marks 
	rename ihme_loc_id iso3
	drop location_id location_type
	
	keep if regexm(iso3, "IND")
	replace location_name = subinstr(location_name, "?", "a", .) 
	replace location_name = "Chhattisgarh" if location_name == "Chhattasgarh"
	replace location_name = "Chhattisgarh, Rural" if location_name == "Chhattasgarh, Rural" 
	replace location_name = "Chhattisgarh, Urban" if location_name == "Chhattasgarh, Urban" 
	replace location_name = "Jammu and Kashmir" if location_name == "Jammu and Kashmar" 
	replace location_name = "Jammu and Kashmir, Rural" if location_name == "Jammu and Kashmar, Rural"
	replace location_name = "Jammu and Kashmir, Urban" if location_name == "Jammu and Kashmar, Urban" 
	
	rename location_name subnational 
	tempfile countrycodes
	save `countrycodes', replace

// Bring in India couples file for DHS 2005-2006
	use "`data_dir'/IND_DHS5_2005_2006_CUP_Y2010M04D01", clear 
	keep caseid v024 mv001 v005s mv005s spsu mv463z v463z v137 v025 v012 mv012 v024 v025 
	rename spsu psu 
	egen strata = group(v024 v025) // no strata variable but constructed based on state + urban/rural
	rename v024 state
	rename v005s pweight_m // use state-level pweight since making calculations at the state level 
	rename mv005s pweight_w // use state-level pweight since making calculations at the state level 
	rename v463z smoke_female 
	rename mv463z smoke_male 
	rename v137 under_5 
	rename v025 urbanicity 
	rename v012 age_f
	rename mv012 age_m 
	
	
// Definition of SHS from DHS: "Non-smokers who live with a spouse or parent that smokes"
	
	// (1) First create female dataset 
	preserve
	drop age_m pweight_m 
	
		// Female non-smokers whose husband smokes 
			gen shs = 1 if smoke_female == 1 & smoke_male == 0
			replace shs = 0 if smoke_female == 1 & smoke_male == 1 // if neither are smokers
			drop if smoke_female == . | smoke_male == . 
			drop if smoke_female == 0 // only want to include non-smokers
		
		// Clean up dataset 
			drop under_5
			rename pweight_w pweight 
			rename age_f age 
			gen sex = 2 
			
			tempfile shs_women 
			save `shs_women', replace 
	
	// (2) Male dataset 
	restore 
	preserve 
	drop age_f pweight_w 
	
		// Male non-smokers whose wife smokes 
			gen shs = 1 if smoke_female == 0 & smoke_male == 1 
			replace shs = 0 if smoke_male == 1 & smoke_female == 1 // if neither are smokers 
			drop if smoke_female == . | smoke_male == . 
			drop if smoke_male == 0 // only want to include non-smokers
			
		// Clean up dataset 
			drop under_5
			rename pweight_m pweight 
			rename age_m age 
			gen sex = 1 
			
			tempfile shs_men 
			save `shs_men', replace
	
	// (3) Child dataset - want to calculate the prevalence of second-hand smoke exposure for children < 5
	restore
		
		// Drop if households have no children under age 5 and expand observations so that we have one row for each child
			drop if under_5 == 0 
			expand under_5, gen(child)
			drop if smoke_male == . & smoke_female == . 
			drop if smoke_male == 9 | smoke_female == 9 
			
		// Generate SHS indicator variable  
			gen shs = 1 if smoke_female == 0 & smoke_male == 1 // mom smokes, dad doesn't
			replace shs = 1 if smoke_male == 0 & smoke_female == 1 // dad smokes, mom doesn't
			replace shs = 1 if smoke_male == 0 & smoke_female == 0 // both smoke 
			replace shs = 1 if smoke_male == 0 & smoke_female == . // dad smokes, mom unknown 
			replace shs = 1 if smoke_female == 0 & smoke_male == . // mom smokes, dad unknown 
			replace shs = 0 if smoke_female == 1 & smoke_male == 1 // neither smoke 
			replace shs = 0 if smoke_male == 1 & smoke_female == . // dad doesn't smoke, mom unknown 
			replace shs = 0 if smoke_female == 1 & smoke_male == . // mom doesn't smoke, dad unknown
			
		// Clean up dataset (use same pweight as mothers, as the DHS says) 
			drop under_5 pweight_m age_f age_m child
			rename pweight_w pweight 
			gen sex = 3
			gen age = . // Will define GBD age group later for under 5 group 
			
			tempfile shs_children 
			save `shs_children', replace 
			
	append using `shs_women' 
	append using `shs_men' 
	tempfile all 
	save `all', replace

// Match state locations 

	decode state, gen(state_new) 
	decode urbanicity, gen(urban)
	
	replace state_new = regexr(state_new, "\[(.)+\]", "")
	replace state_new = strproper(state_new)
	replace state_new = "Uttarakhand" if regexm(state_new, "Uttaranchal") 
	replace state_new = "Jammu and Kashmir" if regexm(state_new, "Jammu") 
	replace urban = strproper(urban)

	// Concatenate state and urban variable 
	
	egen subnational = concat(state_new urban), punct(", ")
	levelsof subnational, local(subnationals)

// Set age groups
	egen age_start = cut(age), at(15(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	replace age_start = 0 if age_start == . 
	levelsof age_start, local(ages)
	drop age
		
// Set survey weights
	svyset psu [pweight=pweight], strata(strata)
	
	rename shs hh_shs
	
	tempfile all 
	save `all', replace
	
// Create empty matrix for storing calculation results
	mata 
		subnational = J(1,1,"subnational") 
		age_start = J(1,1,999)
		sex = J(1,1,999)
		sample_size = J(1,1,999)
		mean_hh_shs = J(1,1,999)
		se_hh_shs = J(1,1,999)

	end	
	
	
// Loop through subnationals and find mean SHS exposure 


foreach subnational of local subnationals { 
	foreach sex in 1 2 3 {
		foreach age of local ages {
		
	use `all', clear 
	
	di in red  "Subnational `subnational' sex `sex' age `age'"
	count if subnational == "`subnational'" & age_start == `age' & sex == `sex' & hh_shs != .
	local sample_size = r(N)
						
	if `sample_size' > 0 {
	
		svy linearized, subpop(if subnational == "`subnational'" & age_start == `age' & sex == `sex' & hh_shs != .): mean hh_shs
			
			mata: subnational = subnational \ "`subnational'" 
			mata: age_start = age_start \ `age'
			mata: sex = sex \ `sex'
			
			mata: sample_size = sample_size \ `e(N_sub)'	
			matrix mean_matrix = e(b)
			local mean_scalar = mean_matrix[1,1]
			mata: mean_hh_shs = mean_hh_shs \ `mean_scalar'
						
			matrix variance_matrix = e(V)
			local se_scalar = sqrt(variance_matrix[1,1])
			mata: se_hh_shs = se_hh_shs \ `se_scalar'
						
			}
		}
	}
}

// Get stored prevalence calculations from matrix
	clear

	getmata subnational age_start sex sample_size mean_hh_shs se_hh_shs 
	drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
		
	recode se_hh_shs (0=.) // Standard error should not be 0 so we will use sample size to estimate error instead
	tempfile mata_calculations
	save `mata_calculations'

// Merge mean exposures for each subnational-age-sex group with subnational iso3 codes

	merge m:1 subnational using `countrycodes'
	drop if _m == 2 
	
// Reshape so household exposure(gold standard) and household/work (alternative) are long
	reshape long mean_@ se_@, i(iso3 subnational sex age_start) j(case_definition, string)
	replace case_definition = "daily or weekly exposure to tobacco smoke inside the home among current nonsmokers" if case_definition == "hh_shs"
		
// Set variables that are always tracked
	drop _m 
	rename subnational location_name
	rename se_ standard_error
	rename mean_ mean
	gen source = "MACRO_DHS"
	gen national_type_id = 6 // Nationally, subnatoinally and urban/rural representative 
	generate age_end = age_start + 4
	replace age_end = 15 if age_start == 0 
	egen maxage = max(age_start)
	replace age_end = 100 if age_start == maxage
	drop maxage
	gen orig_unit_type = "Rate per capita"
	gen orig_uncertainty_type = "SE" 
	replace orig_uncertainty_type = "ESS" if standard_error == .
	gen year_start = 2005
	gen year_end = 2006
	gen file = "J:/DATA/MACRO_DHS/IND/2005_2006/IND_DHS5_2005_2006_CUP_Y2010M04D01"
	
	// Organize
	order iso3 location_name year_start year_end sex age_start age_end sample_size mean standard_error, first
	sort iso3 location_name sex age_start age_end
		
	// Save survey weighted data
	save "`out_dir'/dhs_ind_subnational.dta", replace
	

	
	
	
	
