// Date: July 22, 2015 (original date: January 27 2015)
// Purpose: Approximate sample sizes for subnational IPV data provided by Mexican GBD collaborators because only national level sample sizes are provided and we need some sort of variance metric to incorporate this data into Dismod models

// Make locals for relevant files and folders 
	local population_envelope 		"J:/WORK/02_mortality/04_outputs/02_results/envelope.dta"
	local data_dir 					"J:/WORK/05_risk/risks/abuse_ipv_exp/data/exp/01_tabulate"
	local country_codes 				"J:/DATA/IHME_COUNTRY_CODES/IHME_COUNTRY_CODES_Y2013M07D26.DTA"

// 1st calculate sample sizes
	// Prep subnational population numbers 
		use iso3 year age sex mean_pop location_type using "`population_envelope'" if inlist(location_type, "subnational", "country") & regexm(iso3, "MEX") & inlist(year, 2003, 2006) & age >= 15 & age <=80 & sex == 2, clear
		
	// Make 10 year age groups instead of 5 year ones (except for 15-19 year age group), to be consistent with age groups presented in Mexico tabulations
		tostring age, replace
		replace age = substr(age, 1, 1) if age != "15"
		replace age = age + "0" if age != "15"
		destring age, replace
		collapse (sum) mean_pop, by(iso3 location_type year age sex)
		
	// Calculate proportion of each national agegrp in subnational location
		bysort year sex age: egen agegrp_pop = total(mean_pop)
		gen weight = mean_pop / agegrp_pop
		rename age age_start
		
		tempfile population
		save `population', replace
		
	// Prep Mexico
		import excel using "`data_dir'/raw/mexico_subnational_data.xlsx", sheet("study population") firstrow clear
		
	// Merge with population envelope
		merge 1:m year age_start using `population', nogen keep(match)
		
	// Calculate estimated sample size for each age group
		gen sample_size = round(weight * envelope)
		
	// Calculate total sample size for all ages combined since the tabulated data only presents age aggregated prevalence
		collapse (sum) sample_size, by(year iso3 sex)

	// Make variable names match extracted data sheet in preparation for merge
		rename year year_start
		gen year_end = year_start
		
	// Tempfile sample size dataset
		tempfile sample_size
		save `sample_size', replace
	
// Get ISO3 with subnational location ids
	use "`country_codes'" if indic_epi == 1, clear
	keep location_id location_name iso3 gbd_country_iso3
	replace gbd_country_iso3 = iso3 if gbd_country_iso3 == ""
	rename gbd_country_iso3 parent_iso3
	gen real_iso3 = parent_iso3
	replace real_iso3 = parent_iso3 + "_" + string(location_id) if iso3 != parent_iso3
	keep if parent_iso3 == "MEX"
	keep location_id location_name real_iso3
	rename real_iso3 iso3
	
	tempfile country_codes
	save `country_codes', replace
	
// Bring in subnational prevalence data and fill in ISO3 codes
	import excel using "`data_dir'/raw/mexico_subnational_data.xlsx", sheet("data") firstrow clear
	merge m:1 location_name using `country_codes', update nogen
	
// Merge with estimated sample sizes
	merge m:1 iso3 year_start year_end sex using `sample_size', update nogen
	
	tostring interview_type notes, replace
	tostring location_id, replace 

// Add missingness from the study (value from report on the Encuesta Nacional sobre Violencia contra las Mujeres (ENVIM, 2006) pg. 21)
	gen missingness= 0.06
	
save "`data_dir'/prepped/mexico_subnational.dta", replace
