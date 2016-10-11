// Date: April 22, 2015 (Earth Day!)
// Purpose: Clean and extract Intimate Partner Violence (IPV) and childhood sexual abuse (CSA) data from GENACIS and compute prevalence in 5 year age-sex groups for each year
	
** *********************************************************************
** Set up Stata 
** *********************************************************************
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

** *********************************************************************
** (1.) Clean and compile 
** *********************************************************************
// Prepare countrycodes database 
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
	
	rename ihme_loc_id iso3
	
	// Fix weird symbols that import as question marks 
	replace location_name = subinstr(location_name, "?", "o", .) if regexm(iso3, "JPN")
	replace location_name = subinstr(location_name, "?", "a", .) if regexm(iso3, "IND")
	replace location_name = "Chhattisgarh" if location_name == "Chhattasgarh"
	replace location_name = "Chhattisgarh, Rural" if location_name == "Chhattasgarh, Rural" 
	replace location_name = "Chhattisgarh, Urban" if location_name == "Chhattasgarh, Urban" 
	replace location_name = "Jammu and Kashmir" if location_name == "Jammu and Kashmar" 
	replace location_name = "Jammu and Kashmir, Rural" if location_name == "Jammu and Kashmar, Rural"
	replace location_name = "Jammu and Kashmir, Urban" if location_name == "Jammu and Kashmar, Urban" 
	
	tempfile countrycodes
	save `countrycodes', replace 
	
// Bring in GENACIS data for 1993-2007
	use "`data_dir_ipv'/GENACIS_1993_2007.dta", clear 
	rename country genacis_code 
	
	merge m:1 genacis_code using "`data_dir_ipv'/GENACIS_1993_2007_COUNTRY_CODES.dta", keep(3) 
	drop _m 
	
	order location_name iso3 year_start year_end nid 
	
	tempfile all
	save `all', replace
	
// GENERATE A VARAIBLE FOR IPV IN THE PAST TWO YEARS
		// mostly just use vmpa variable, except for some countries, which have slightly different ways of asking the genacis core question
	
	levelsof iso3, local(countries)
	gen ipv_2yr = . 
	
	// For countries that have slight modifications to the genacis core question, need to individually recode values 
	
		// Spain: didn't explicitly include sexual aggression in the question and also coded as yes or no so might include verbal aggression/threatening
			replace ipv_2yr = 1 if vmpa_05 == 1 & vmpa_05 != . 
			recode ipv_2yr (.= 0) if vmpa_05 == 2
		
		// UK: also focused question on physical aggression; excluded verbal aggression
			replace ipv_2yr = 1 if vmpa_06 != 14 & vmpa_06 != 10 & vmpa_06 != 11 & vmpa_06 != . 
			recode ipv_2yr (.= 0) if inlist(vmpa_06, 14, 10, 11) 
		
		// Czech republic: coded as yes or no so might include verbal aggression
			replace ipv_2yr = 1 if vmpa_14 == 2 & vmpa_14 != . 
			recode ipv_2yr (.= 0) if vmpa_14 == 1 
			
		// Hungary: asks about regular and occasional
			replace ipv_2yr = 1 if (vmpa_15 == 1 | vmpa_15 == 2) & vmpa_15 != . 
			recode ipv_2yr (. = 0) if vmpa_15 == 3
			
		// Sri Lanka: explicitly excluded sexual aggression; excluded verbal aggression
			replace ipv_2yr = 1 if vmpa_20 != 12 & vmpa_20 != 9 & vmpa_20 != 10 & vmpa_20 != . 
			recode ipv_2yr (.= 0) if inlist(vmpa_20, 9, 10, 12) 
	
		// Kazakhstan 
			replace ipv_2yr = 1 if vmpa_22 != 14 & vmpa_22 != . 
			recode ipv_2yr (.= 0) if vmpa_22 == 14
			replace ipv_2yr = . if vmpa_22 == 59 | vmpa_22 == 85
			
		// Argentina
			replace ipv_2yr = 1 if vmpa_23 != 9 & vmpa_23 != 10 & vmpa_23 != . 
			recode ipv_2yr (.= 0) if vmpa_23 == . & iso3 == "ARG"
			
		// Canada
			replace ipv_2yr = 1 if vmpa_24 != 0 & vmpa_24 != 12 & vmpa_24 != 13 & vmpa_24 != 17 & vmpa_24 != . 
			recode ipv_2yr (.= 0) if inlist(vmpa_24, 0, 12, 13, 17) 
			
		// Japan 
			replace ipv_2yr = 1 if vmpa_28 != 10 & vmpa_28 != 11 & vmpa_28 != 14 & vmpa_28 != . 
			recode ipv_2yr (.= 0) if inlist(vmpa_28, 10, 11, 14) 
			
		// Costa Rica 
			replace ipv_2yr = 1 if vmpa_29 != 0 & vmpa_29 != 9 & vmpa_29 != 10 & vmpa_29 != 13 & vmpa_29 != . 
			recode ipv_2yr (. = 0) if inlist(vmpa_29, 0, 9, 10)
			replace ipv_2yr = . if vmpa_29 == 13
			
		// Uruguay 
			replace ipv_2yr = 1 if vmpa_39 != 0 & vmpa_39 != 9 & vmpa_39 != 10 & vmpa_39 != 97 & vmpa_39 != 98 & vmpa_39 != 99 & vmpa_39 != . 
			recode ipv_2yr (. =0) if inlist(vmpa_39, 9, 10, 97)
			replace ipv_2yr = . if vmpa_39 == 0
			
		// Belize 
			replace ipv_2yr = 1 if vmpa_41 != 1 & vmpa_41 != 11 & vmpa_41 != 12 & vmpa_41 != . 
			recode ipv_2yr (.= 0) if inlist(vmpa_41, 1, 11, 12) 
			
		// Nicaragua 
			replace ipv_2yr = 1 if vmpa_42 != 3 & vmpa_42 != 8 & vmpa_42 != 9 & vmpa_42 != 10 & vmpa_42 != 13 & vmpa_42 != . 
			recode ipv_2yr (. = 0) if (vmpa_42 == . & iso3 == "NIC") | inlist(vmpa_42, 3, 8, 9, 10, 13)
		
		// Peru 
			replace ipv_2yr = 1 if vmpa_43 != . 
			recode ipv_2yr (.= 0) if vmpa_43 == . & iso3 == "PER"
			
		// Australia II 
			replace ipv_2yr = 1 if vmpa_44 != 1 & vmpa_44 != 11 & vmpa_44 != 12 & vmpa_44 != 98 & vmpa_44 != 99 & vmpa_44 != . 
			recode ipv_2yr (. = 0) if inlist(vmpa_44, 1, 11, 12) 
			
		// New Zealand
			replace ipv_2yr = 1 if vmpa_46 != 0 & vmpa_46 != 10 & vmpa_46 != 11 & vmpa_46 != . 
			recode ipv_2yr (. = 0) if inlist(vmpa_46, 0, 10, 11) 
		
		// India: has results coded as string variables
		tostring ipv_2yr, replace 
		gen new_vmpa_30 = lower(vmpa_30) 
		
		foreach var in varlist "nothing" "threaten" "verbal" "push, threa" "weapon thr" {
			replace ipv_2yr = "0" if regexm(new_vmpa_30, "`var'") 
			}
		
		replace ipv_2yr = "0" if new_vmpa_30 == "9" | new_vmpa_30 == "0" 
		replace ipv_2yr = "1" if ipv_2yr != "0" & new_vmpa_30 != ""
			
			
	// All other countries that used the main IPV core question 
		gen new_vmpa = lower(vmpa)
	
		foreach var in varlist "no" "none" "nothing" "threat" "NO" "never" "yell" "verbal" "n0ne" "insult" {
			replace ipv_2yr = "0" if regexm(new_vmpa, "`var'") 
		}
	
		replace ipv_2yr = "1" if ipv_2yr != "0" & new_vmpa != "" 
		replace ipv_2yr = "" if new_vmpa == "missing"

		destring ipv_2yr, replace 
		
// ADD IN COUNTRIES THAT ASK ABOUT IPV IN THE PAST YEAR
	// Countries where IPV is only asked about in the last 12 months and does not measure in the last 2 years -- will account for this through a covariate in DisMod 
	
	gen ipv_1yr = . 
	
	// USA II 
		replace ipv_1yr = 1 if vmpa_26 != 0 & vmpa_26 != 5 & vmpa_26 != . 
		recode ipv_1yr (.= 0) if inlist(vmpa_26, 0, 5) 
	
	// USA I 
		replace ipv_1yr = 1 if vpal_25 == 1 & vpal_25 != . 
		recode ipv_1yr (. = 0) if vpal_25 == 2 
		
	// Sweden 
		replace ipv_1yr = 1 if vmpa_09 == 1 & vmpa_09 != . 
		recode ipv_1yr (. = 0) if vmpa_09 == 2


// CLEAN UP AND GENERATE PARAMETER VALUE 

	rename gender sex 
	rename year_start year
	drop year_end

	gen parameter_value = ipv_2yr   
	replace parameter_value = ipv_1yr if parameter_value == . & ipv_1yr != .
	gen health_state = "abuse_ipv_phys" 
	
	keep iso3 location_name year nid ident weight sex age parameter_value ipv_2yr ipv_1yr health_state

	tempfile ipv
	save `ipv', replace

// ALSO COMPUTE PARAMETER VALUE FOR LIFETIME SEXUAL IPV 

	use `all', clear 
	gen ipv_lifetime_sex = . 

	// Main question: Since the age of 16, was there a time when someone forced you to have sexual cativity that you really did not want? 
	// This might have been intercourse or other forms of sexual activity, and might have happened with spouses, lovers, or friends as well as with more distant persons and strangers 

	replace ipv_lifetime_sex = 1 if inlist(vast, 1) & inlist(vasp, 1)
	replace ipv_lifetime_sex = 1 if inlist(vast_14, 1) & inlist(vasp_14, 1)
	replace ipv_lifetime_sex = 1 if inlist(vast_25, 1) & inlist(vasp_25, 1) 

	replace ipv_lifetime_sex = 0 if (inlist(vast, 2) | inlist(vasp, 2)) & ipv_lifetime_sex != 1 
	replace ipv_lifetime_sex = 0 if (inlist(vast_14, 2) | inlist(vasp_14, 2)) & ipv_lifetime_sex != 1 
	replace ipv_lifetime_sex = 0 if (inlist(vast_25, 0) | inlist(vasp_25, 0)) & ipv_lifetime_sex != 1 

	keep iso3 location_name year_start year_end nid ident weight gender age ipv_lifetime_sex
	rename gender sex 
	rename year_start year
	drop year_end

	rename ipv_lifetime_sex parameter_value
	gen health_state = "abuse_ipv_sex" 
	// drop if parameter_value == . 

	tempfile ipv_2 
	save `ipv_2', replace 

	append using `ipv'

	tempfile combo 
	save `combo', replace

	// Calculate missingness
	bysort nid health_state: egen sum = sum(parameter_value)
	drop if sum == 0 
	keep if sex == 2 // only females 

	// total observations for each state 
	bysort nid health_state: gen total = _N 

	levelsof nid, local(studies)
	levelsof health_state, local(states)

	foreach study of local studies { 
		foreach state of local states { 

		preserve 
		keep if nid == `study' & health_state == "`state'"
		count if parameter_value == . 
		gen missingness = `r(N)' / total
		tempfile temp_`study'_`state'
		save `temp_`study'_`state'', replace
		restore

		}
	}

	use `temp_169751_abuse_ipv_sex', clear 

	foreach study of local studies { 
		foreach state of local states { 
		
			append using `temp_`study'_`state''
	}
}

	keep nid location_name missingness iso3 health_state
	collapse (first) missingness, by(health_state nid location_name iso3)
 
	tempfile miss_data
	save `miss_data', replace


** *********************************************************************
	** (2a.) Compute IPV prevalence
	** *********************************************************************

	use `combo', clear 

	keep if sex == 2 // only want to calculate for women
	drop if parameter_value == . 

	// Set age groups
	egen age_start = cut(age), at(15(10)120)
	replace age_start = 65 if age_start >= 65 & age_start != .
	levelsof age_start, local(ages)
	drop age

// No psu or strata variables, so set psu equal to the observation number and strata equal to 0 
	gen strata = 0 
	gen psu = _n 
	replace weight = 1 if weight == .
	
// Specify survey design
	svyset psu [pweight=weight], strata(strata) singleunit(centered) 

// Compute prevalence, sample size and missigness for each year sex age group
	
	levelsof iso3, local(countries)
	levelsof year, local(years)
	levelsof location_name, local(names)
	levelsof health_state, local(ipv_types)
	
	// Create empty matrix for storing calculated results for each year, sex, age group
	mata
		iso3 = J(1,1,"todrop")
		location_name = J(1,1,"todrop")
		health_state = J(1,1,"todrop")
		year = J(1,1,999)
		age = J(1,1,-999)
		sex = J(1,1,-999)
		sample_size = J(1,1,-999)
		mean = J(1,1,-999.999)
		standard_error = J(1,1,-999.999)
		lower = J(1,1,-999.999)
		upper = J(1,1,-999.999)
		nid = J(1,1,999)
	
	end

	save `combo', replace
	
		foreach country of local countries {
			foreach year of local years {
			
			use `combo', clear 
			keep if iso3 == "`country'" & year == `year'
				
			foreach ipv_type of local ipv_types {
					foreach age of local ages {

				
				capture noisily svy, subpop(if health_state == "`ipv_type'" & iso3 == "`country'" & year == `year' & age_start == `age'): mean parameter_value
				di in red "Type: `ipv_type' Country: `country' Year: `year' Age: `age'"
				qui: count if health_state == "`ipv_type'" & iso3 == "`country'" & year == `year' & age_start == `age'
				
				if r(N) != 0 {
					preserve
					keep if health_state == "`ipv_type'" & iso3 == "`country'" & year == `year' & age_start == `age'
					mata: iso3 = iso3 \ "`country'" 
					levelsof location_name, local(location_name) 
					mata: location_name = location_name \ `location_name'
					mata: health_state = health_state \ "`ipv_type'" 
					mata: year = year \ `year'
					mata: age = age \ `age'

					mata: sample_size = sample_size \ `e(N_sub)'
					levelsof nid, local(nid)
					mata: nid = nid \ `nid'
					
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
					restore
					
					}
				}
			}
		}
	}


// Get stored prevalence calculations from matrix 
	clear

	getmata iso3 location_name nid health_state year age sex sample_size mean standard_error upper lower
	drop if _n == 1 // Drop empty top row of matrix
	replace standard_error = (3.6/sample_size)/(2*1.96) if standard_error == 0 
	
	drop if sample_size < 10 // These means are too unstable
	replace sex = 2 // Only calculate IPV for women 
	rename mean parameter_value // to be consistent with other IPV datasets
	replace location_name = "USA" if location_name == "USA (II)" | location_name == "USA (I)" 
	
	tempfile mata_calculations 
	save `mata_calculations', replace 

	
	// Variables that are always tracked 
	gen survey_name = "GENACIS"
	gen citation = "GENACIS"
	rename year year_start
	gen year_end = year_start
	rename age age_start
	gen age_end = age_start + 9
	egen maxage = max(age_start)
	replace age_end = 100 if age_start == maxage
	drop maxage
	gen data_type = "Survey: unspecified"
	gen source_type = 2
	label define source_type 2 "Survey"
	label values source_type source_type
	gen orig_uncertainty_type = "SE" 
	gen national_type = 1 if inlist(iso3, "BLZ", "CAN", "CRI", "CZE", "GBR", "NZL", "AUS") 
	replace national_type = 1 if inlist(iso3, "URY", "USA", "JPN", "HUN", "SWE") // Nationally representative
	replace national_type = 2 if inlist(iso3, "ARG", "BRA", "ESP", "IND", "KAZ")
	replace national_type = 2 if inlist(iso3, "LKA", "NGA", "NIC", "PER", "UGA") // Subnationally representative 
	label define national 0 "Unknown"  1 "Nationally representative" 2 "Subnationally representative" 3 "Not representative"
	label values national_type national
	gen urbanicity_type = "representative" if national_type == 1 // Representative
	replace urbanicity_type = "rural" if inlist(iso3, "IND", "KAZ", "UGA") 
	replace urbanicity_type = "urban" if inlist(iso3, "ARG", "BRA", "ESP", "PER", "NIC")
	replace urbanicity_type = "unknown" if inlist(iso3, "LKA", "NGA") 
	gen units = 1
	
	// Specify Epi covariates
		gen subnational = 0 if national_type == 1 
		replace subnational = 1 if subnational == . 
		gen urban = 0 
		replace urban = 1 if urbanicity_type == "urban"
		gen rural = 0 
		replace rural = 1 if urbanicity_type == "rural"
		gen mixed = 0
		gen nointrain = 1
		gen notviostudy1 = 1
		gen sexvio = 1 if health_state == "abuse_ipv_sex" 
		replace sexvio = 0 if sexvio == . 
		gen physvio = 1 if health_state == "abuse_ipv_phys" 
		replace physvio = 0 if physvio == . 
		gen spouseonly = 0
		gen pstatall = 0
		gen pstatcurr = 0
		gen pastyr = 0 
		replace pastyr = 1 if iso3 == "SWE" 
		gen past2yr = 1
		replace past2yr = 0  if iso3 == "SWE" | health_state == "abuse_ipv_sex" // Sweden asked about IPV in the last year 
		gen severe = 0
		gen currpart = 0
	
	// For countries that have subnationals, replace iso3 with code of state where survey or study was conducted 
	
		replace location_name = "São Paulo" if location_name == "Brazil" 
		expand 2 if location_name == "India", gen(dup) 
		replace location_name = "Karnataka, Urban" if dup == 0 & location_name == "India"
		replace location_name = "Karnataka, Rural" if dup == 1 & location_name == "India"
		drop dup
		replace location_name = "United States" if iso3 == "USA" 
		replace location_name = "United Kingdom" if iso3 == "GBR" 
		
	// Merge with missingness 
		merge m:1 health_state nid using `miss_data'

		replace health_state = "abuse_ipv"
		save `ipv', replace
		
	// Merge with location_id 
		
		use `countrycodes', clear 
		duplicates drop location_name, force
		
		merge m:m location_name using `ipv', keep(3) nogen
		drop _m
		
		// Organize
		
		order iso3 location_name location_id nid year_start year_end sex age_start age_end sample_size parameter_value lower upper standard_error, first
		tostring location_id, replace
		sort iso3 sex age_start age_end  year_start
		save "`prepped_dir_ipv'/genacis_prepped.dta", replace
		
	
	** *********************************************************************
	** (2a.) Compute CSA prevalence
	** *********************************************************************
	
	// GENERATE VARIABLE FOR CSA 
	// Combined questions asking about about whether a family member AND someone outside the family tried to make respondent do/watch sexual things 
	
	use `all', clear 
	gen any_csa = . 
	
	// CSA question about family members 
	replace any_csa = 1 if inlist(vstf, 2, 3, 4, 5) | inlist(vstf_14, 2, 3, 4, 5) | vstf_24 == 1 | vstf_25 == 1 | inlist(vstf_27, 2, 3, 4, 5) 
	replace any_csa = 0 if (vstf == 1 | vstf_14 == 1  | vstf_24 == 2 | vstf_25 == 0 | vstf_27 == 1)
	
	// CSA question about non-family members
	replace any_csa = 1 if inlist(vsto, 2, 3, 4, 5) | inlist(vsto_14, 2, 3, 4, 5) | vsto_24 == 1 | vsto_25 == 1 
	replace any_csa = 0 if any_csa != 1 & (vsto == 1 | vsto_14 == 1 | vsto_24 == 2 | vsto_25 == 0)

	
// CLEAN UP AND GENERATE PARAMETER VALUE 

	keep iso3 location_name year_start year_end nid ident weight gender age  any_csa 
	rename gender sex 
	rename year_start year
	drop year_end

	gen parameter_value = any_csa
	gen health_state = "abuse_csa"
	drop if parameter_value == .  

// Set age groups
	egen age_start = cut(age), at(15(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	levelsof age_start, local(ages)
	drop age

// No psu or strata variables, so set psu equal to the observation number and strata equal to 0 
	gen strata = 0 
	gen psu = _n 
	replace weight = 1 if weight == .
	
// Specify survey design
	svyset psu [pweight=weight], strata(strata) singleunit(centered) 

// Compute prevalence, sample size and missigness for each year sex age group

	levelsof iso3, local(countries)
	levelsof year, local(years)
	levelsof health_state, local(healthstates)
	
// Create empty matrix for storing calculated results for each year, sex, age group
	mata
		iso3 = J(1,1,"todrop")
		location_name = J(1,1,"todrop") 
		health_state = J(1,1,"todrop")
		year = J(1,1,999)
		age = J(1,1,-999)
		sex = J(1,1,-999)
		sample_size = J(1,1,-999)
		mean = J(1,1,-999.999)
		standard_error = J(1,1,-999.999)
		lower = J(1,1,-999.999)
		upper = J(1,1,-999.999)
		nid = J(1,1,999)
	
	end
	
	tempfile csa
	save `csa', replace 
	
	
	foreach country of local countries {
		foreach year of local years {
			
			use `csa', clear
			keep if iso3 == "`country'" & year == `year' // want to use subpop command on country-year surveys 
			
				foreach sex in 1 2 {	
					forvalues age=15(5)80 {
				
				capture noisily svy, subpop(if iso3 == "`country'" & year == `year' & age_start == `age' & sex == `sex'): mean parameter_value
				di in red "Country: `country' Year: `year' Age: `age' Sex: `sex'"
				qui: count if iso3 == "`country'" & year == `year' & age_start == `age' & sex == `sex'
				
				if r(N) != 0 {
					preserve
					// keep if iso3 == "`country'" & year == `year' & age_start == `age' & sex == `sex' 
					mata: iso3 = iso3 \ "`country'" 
					levelsof location_name, local(location_name) 
					mata: location_name = location_name \ `location_name' 
					mata: health_state = health_state \ "abuse_csa"
					mata: year = year \ `year'
					mata: age = age \ `age'
					mata: sex = sex \ `sex'
					mata: sample_size = sample_size \ `e(N_sub)'
					levelsof nid, local(nid)
					mata: nid = nid \ `nid' 
			
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
					restore
					
					}
				}
			}
		}
	}
	

// Get stored prevalence calculations from matrix 
	clear

	getmata iso3 location_name nid health_state year age sex sample_size mean standard_error upper lower
	drop if _n == 1 // Drop empty top row of matrix
	replace standard_error = (3.6/sample_size)/(2*1.96) if standard_error == 0 // Greg's standard error fix for binomial outcomes
	
	drop if iso3 == "IMN" // don't include Isle of Man 
	drop if sample_size < 10 // These means are too unstable
	replace location_name = "USA" if location_name == "USA (I)"
	
	tempfile mata_calculations 
	save `mata_calculations', replace 
	
	// Variables that are always tracked 
	gen survey_name = "GENACIS"
	gen citation = "GENACIS"
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
	gen national_type = 1 if inlist(iso3, "BLZ", "CAN", "CRI", "CZE", "GBR", "NZL", "URY", "USA") // Nationally representative
	replace national_type = 2 if inlist(iso3, "ARG", "BRA", "ESP", "IND", "KAZ")
	replace national_type = 2 if inlist(iso3, "LKA", "NGA", "NIC", "PER", "UGA") // Subnationally representative 
	label define national 0 "Unknown"  1 "Nationally representative" 2 "Subnationally representative" 3 "Not representative"
	label values national_type national
	gen urbanicity_type = "representative" if national_type == 1 // Representative
	replace urbanicity_type = "rural" if inlist(iso3, "IND", "KAZ", "UGA") 
	replace urbanicity_type = "urban" if inlist(iso3, "ARG", "BRA", "ESP", "PER", "NIC")
	replace urbanicity_type = "unknown" if inlist(iso3, "LKA", "NGA") 
	gen units = 1
	
	// Specify Epi covariates
		gen contact = 0 
		gen noncontact = 0
		gen intercourse = 0 
		gen child_16_17 = 0
		gen child_18 = 0 
		replace child_18 = 1 if iso3 == "UGA" // Ugandan survey asks about sexual assult before 18 
		gen child_18plus = 0
		gen child_over_15 = 0
		gen child_under_15 = 0
		replace child_under_15 = 1 if iso3 == "CZE" // Czech Republic survey asks about under 15 sexual assault 
		gen nointrain = 1
		gen perp3 = 0
		gen notviostudy1 = 1
		gen parental_report = 0
		gen school = 0
		gen anym_quest = 0
		
	// For countries that have subnationals, replace iso3 with code of state where survey or study was conducted 
	
		replace location_name = "São Paulo" if location_name == "Brazil" 
		expand 2 if location_name == "India", gen(dup) 
		replace location_name = "Karnataka, Urban" if dup == 0 & location_name == "India"
		replace location_name = "Karnataka, Rural" if dup == 1 & location_name == "India"
		drop dup
		replace location_name = "United States" if iso3 == "USA" 
		replace location_name = "United Kingdom" if iso3 == "GBR" 
		
		tempfile csa 
		save `csa', replace
		
	// Merge with location_id 
		
		use `countrycodes', clear 
		duplicates drop location_name, force
		
		merge m:m location_name using `csa', keep(3) nogen
		
	
	// Organize
		order iso3 location_name location_id year_start year_end sex age_start age_end sample_size mean lower upper standard_error, first
		sort iso3 sex age_start age_end  year_start
		
		save "`prepped_dir_csa'/genacis_10_yr_age_groups_prepped.dta", replace
	
	
	
		
