// Purpose:	Create incidence rates that will be used to generate weights in age age/sex splitting and acause disaggregation

** **************************************************************************
** Set Preferences
** **************************************************************************
// Clear memory and set memory and variable limits
	clear all
	set more off

// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"

// Get date
	local today = date(c(current_date), "DMY")
	local today = string(year(`today')) + "_" + string(month(`today'),"%02.0f") + "_" + string(day(`today'),"%02.0f")

** ****************************************************************
** Set Macros
**
** ****************************************************************
	// Input folder
		local sources_folder "$j/WORK/07_registry/cancer/01_inputs/sources"
		local program_folder = "$j/WORK/07_registry/cancer/01_inputs/programs/age_sex_splitting"
		
	// Output folders
		local temp_folder "$j/WORK/07_registry/cancer/01_inputs/programs/age_sex_splitting/data/weights/inc"
		local output_folder "$j/WORK/07_registry/cancer/01_inputs/programs/age_sex_splitting/data/weights"
		capture mkdir "`temp_folder'"
		capture mkdir "`output_folder'"
	
** ****************************************************************
** GET ADDITIONAL RESOURCES
** ****************************************************************
// Get age-sex restrictions
	use "$j/WORK/00_dimensions/03_causes/causes_all.dta", clear
	// Keep relevant data
		keep if cause_version==2 
		keep cause cause_level acause male female yll_age_start yll_age_end
		rename (yll_age_start yll_age_end) (age_start age_end)
		drop if substr(cause, 1,1)=="D" | substr(cause,1,1)=="E"
		drop if cause_level == 0
	// edit age formats
		foreach var in age_start age_end {
			replace `var' = floor(`var'/5) + 6 if `var' >= 5
			replace `var' = 0 if `var' < 5
		}
		keep acause male female age*
	// save
		tempfile age_sex_restrictions
		save `age_sex_restrictions', replace
	
** ********************
** Get Data
** ********************
// // Pool all incidence datasets: Get list of sources in cancer prep folder and append all sets together
	local loopnum = 1 
	foreach folder in "CI5" "USA" "NORDCAN" {
		local subfolders: dir "`sources_folder'/`folder'" dirs "*", respectcase
		foreach subFolder in `subfolders' {
			di "`subFolder'"
			if substr("`subFolder'", 1, 1) == "_" | substr("`subFolder'", 1, 1) == "0" continue
			if regexm(upper("`subFolder'"), "APPENDIX") continue
			if "`folder'" == "USA" & (!regexm(upper("`subFolder'"), "SEER") | "`subFolder'" == "USA_SEER_threeYearGrouped_1973_2012") continue  // only use one-year SEER incidence data, not NPCR
			
			local checkoutput "`sources_folder'/`folder'/`subFolder'/data/intermediate/03_mapped_inc.dta"
			capture confirm file "`checkoutput'"
			if !_rc {
				use "`sources_folder'/`folder'/`subFolder'/data/intermediate/03_mapped_inc.dta", clear
				merge m:1 source iso3 registry subdiv location_id sex year* using "`sources_folder'/`folder'/`subFolder'/data/intermediate/01_standardized_format_inc_pop.dta", keep(3) assert(1 3)
				drop _merge
				if `loopnum' != 1 append using "`temp_folder'/all_mapped_inc_data.dta"
				else local loopnum = 0
				save "`temp_folder'/all_mapped_inc_data.dta", replace
			}
			else display "MISSING: `subFolder'_inc"
		}
	}
		save "`temp_folder'/all_mapped_inc_data.dta", replace

** ********************
** Keep data of interest
** ********************		
// // Keep only "gold standard" data

	// generate an average year to be used for dropping data
		gen year = floor((year_start+year_end)/2)
		gen year_span = 1 + year_end - year_start
	
	// drop USA data that is not from SEER, since SEER is the most trustworthy
		drop if iso3 == "USA" & !regexm(upper(source), "SEER")
	
	// drop NORDCAN data except for special causes with little data
		drop if regexm(lower(source), "nordcan") & gbd_cause != "neo_meso"
		
	// more known data than unknown data
		drop cases1 pop1
		egen cases1 = rowtotal(cases*), missing
		egen pop1 = rowtotal(pop*), missing
		drop if cases1 == .
		drop if cases26 != 0
	
	// drop non-CI5 data if it can be obtained from CI5
		duplicates tag location_id gbd_cause sex year*, gen(tag)
		drop if tag != 0 & !regexm(upper(source), "CI5")
		drop tag
	
	// Drop within-source duplications due to multiple year spans
		sort source iso3 location_id subdiv sex registry gbd_cause year
		egen uid = concat(source location_id sex registry gbd_cause year), punct("_")
		duplicates tag uid, gen(duplicate)
		bysort uid: egen smallestSpan = min(year_span)
		drop if duplicate != 0 & year_span != smallestSpan
		drop year year_span
	
	// keep only data in the correct format
		keep if inlist(frmat_inc, 0, 1, 2, 131)
	
	// save
		save "`temp_folder'/good_format", replace

** ********************
** Correct formatting
** ********************
	// Correct population
		count if (frmat_pop != 2 & frmat_pop != 8 & frmat_pop != 9) | (im_frmat_pop != 2 & im_frmat_pop != 8 & im_frmat_pop != 9)
		if r(N) != 0 {
			preserve
				drop pop*
				save "`temp_folder'/inc_data_without_pop.dta", replace
			restore
			
			keep source iso3 subdiv location_id national NID registry gbd_iteration frmat_pop im_frmat_pop year_start year_end sex pop*
			keep if inlist(frmat_pop, 0, 1, 2, 131)
			duplicates drop
			save "`temp_folder'/inc_temp_pop_only.dta", replace
			
			do "$j/WORK/07_registry/cancer/01_inputs/programs/age_sex_splitting/code/split_population.do" `temp_folder' "incidence_weights_pop" "incidence_weights_pop" "inc"
			
			use "`temp_folder'/inc_data_without_pop.dta", clear
			merge m:1 source source iso3 registry subdiv location_id sex year* using "`temp_folder'/04_age_sex_split_inc_pop.dta", keep(3) nogen
		}
		
	// Combine all 80+ deaths to one age category, if  80+ categories exist
		foreach n of numlist 23/25 {
			capture confirm variable cases`n'
			if !_rc {
				replace cases22 = cases22 + cases`n'
				drop cases`n'
			}
		}

** ********************
** Create dataset for "average cancer"
** ********************
	// Create "average_cancer" 
		preserve
			keep location_id registry source year* sex pop*
			duplicates drop
			collapse (sum) pop*, by (sex)
			tempfile average_cancer_pop
			save `average_cancer_pop', replace
		restore
		preserve 
			collapse (mean) cases*, by(sex)
			merge 1:1 sex using `average_cancer_pop', nogen
			gen gbd_cause = "average_cancer"
			tempfile average_cancer
			save `average_cancer', replace
		restore
		
	// Make weights for other cancers
		preserve 
			keep location_id registry source year* sex pop*
			collapse (mean) pop*, by(location_id registry source year* sex)
			tempfile pop_bySourceYear
			save `pop_bySourceYear', replace
		restore
			drop pop*
			merge m:1 location_id registry source year* sex using `pop_bySourceYear', nogen
		append using `average_cancer'
		drop if gbd_cause == "_gc"
	
	// Append, rename, and save
		collapse cases* pop*, by(sex gbd_cause) fast
		rename gbd_cause acause
		
	// save 
		save "`temp_folder'/gold_standard_mapped_inc_data.dta", replace
		** use "`temp_folder'/gold_standard_mapped_inc_data.dta", clear

** ********************
** Create Rates
** ********************		
// Rename and format variables
	drop if acause == ""
	aorder
	keep acause sex cases2 cases7-cases22 pop2 pop7-pop22
	gen obs = _n
	reshape long cases@ pop@, i(sex acause obs) j(gbd_age)
	gen age = (gbd_age - 6)*5
	replace age = 0 if gbd_age == 2
	_strip_labels*
	drop age
	rename gbd_age age

// Apply sex restrictions
	merge m:1 acause using `age_sex_restrictions', keep(1 3)
	replace cases = 0 if _merge == 3 & sex == 1 & male == 0 
	replace cases = 0 if _merge == 3 & sex == 2 & female == 0 
	drop male female

// Apply age restrictions
	replace cases = 0 if _merge == 3 & age_start > age
	replace cases = 0 if _merge == 3 & age_end < age
	drop age_start age_end _merge
	
// Generate sex = 3 data
	tempfile split_sex
	save `split_sex', replace
	collapse (sum) cases* pop*, by(age acause)
	gen sex = 3
	append using `split_sex'

// ensure non-zero data if data should not be zero
	egen uid = concat(acause sex), p("_")
	sort uid age
	replace cases = ((cases[_n-1]+cases[_n+1])/2) if cases == 0 &  cases[_n-1] > 0 & cases[_n+1] > 0 & uid[_n-1] == uid & uid[_n+1] == uid 
	drop uid
	
// Create Rate
	gen double inc_rate = cases/pop
	drop cases pop obs
	replace inc_rate = 0 if inc_rate == . | inc_rate < 0
	reshape wide inc_rate, i(sex acause) j(age)
	
// // Finalize and Save
	keep sex acause inc_rate*
	order sex acause
	sort acause sex
	compress
	save "`output_folder'/acause_age_weights_inc", replace
	capture saveold "`output_folder'/_archive/acause_age_weights_inc_`today'", replace
	
	 

** ****
** END
** ****
