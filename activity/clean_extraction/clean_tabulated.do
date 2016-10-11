// Date: February 27, 2013
// Purpose: Compile, format and clean all tabulated physical activity data extractions (i.e. everything that was extracted from reports rather than microdata). Note that report tabulations were extracted in both wide and long formats.

// Set up
	clear all
	set more off
	set mem 2g
	capture log close
	
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	
	else if c(os) == "Windows" {
		global j "J:"
	}
	

// Make locals for relevant folders
	local data_dir "$j/WORK/05_risk/risks/activity/data/exp"
	
** **************************************************************************************************
** 1.) Clean and format data that was extracted in "long" format  (i.e. only one mean/proportion variable and one row per healthstate)	
** **************************************************************************************************
// Bring in data	
	insheet using "`data_dir'/raw/report_extraction_longformat_revised.csv", comma clear

// Append using CHINA SUBNATIONAL DATA 2013
	append using "J:/WORK/05_risk/risks/activity/data/exp/raw/china_subnational_tabulated.dta" 

	tempfile 2013 
	save `2013', replace

// Append using new STEPS surveys
	insheet using "J:/WORK/05_risk/risks/activity/data/exp/raw/STEPS_survey_additions_2015.csv", comma clear

	tostring site*, replace
	tostring age_start, replace
	tostring citation, replace 
	
	append using `2013', force

// Rename and re-format for consistency with other extraction dataset
	rename proportion mean
	tostring page_num, replace
	
// Can only use tabulations that encompass activity performed across all domains
	drop if inlist(domain, "recreational", "exercise", "walking and moderate and vigorous recreational activity")
	replace questionnaire = "GPAQ" if regexm(file, "STEPS") & questionnaire == "" // STEPS always use GPAQ
	replace questionnaire = "GPAQ" if regexm(file, "VIGITEL") & questionnaire == "" // modeled off of GPAQ
	
// Convert extracted percentages to proportions
	foreach var in mean lower upper {
		replace `var' = `var' / 100 if upper > 1 & upper != .
	}
	replace standard_error = standard_error / 100 if mean > 1 // catch the ones that have standard error instead of a 95% CI
	replace mean = mean / 100 if mean > 1
	
// site 
	replace site = site_new if site == "" 


// Format age ranges
	rename age_start agegrp
	gen age_start = substr(agegrp, 1, 2) if age_end == .
	replace age_start = agegrp if age_start == ""
	replace age_end = 100 if age_end == 999 | age_end == 99
	tostring age_end, replace
	replace age_end = substr(agegrp, 4, 2) if age_end == "."
	replace age_end = "100" if agegrp == "80+"
	destring age_start age_end, replace
	drop agegrp

// Formatting things 
	tostring survey_admin, replace
	tostring notes, replace 

// Save so that dataset can be appended to other extraction dataset
	tempfile tabulated_long
	save `tabulated_long'

** **************************************************************************************************************
** 2.) Clean and format data that was extracted in "wide" format  (i.e. separate mean/proportion variables for every activity healthstate)
** **************************************************************************************************************
// Bring in tabulated data that was extracted in a wide format and append
	insheet using "`data_dir'/raw/report_extraction_wideformat.csv", comma clear

// Drop unusable data (i.e. doesn't include all domains or in terms of minutes with no intensity metric
	keep if inlist(domain, "all", "recreation, occupation, transport", "outside or work")
	drop if inlist(units, "daily physical activity", "min activity", "min of activity", "hours/day")
	
// Rename variables and address duplicate information
	replace mod_def = moderate_def if mod_def == "" & mod_def != ""
	replace high_def = vig_def if high_def == "" & vig_def != ""
	rename vigorous_mean high_mean
	rename vigorous_ss high_ss
	rename vigorous_ci high_ci
	
// Extract site and urban/rural designation from notes text field
	split notes, parse(";")
	gen site = notes1 if regexm(notes, "ONLY")
	replace site = notes2 if notes2 == " data from N'Djamena ONLY"
	replace site = notes if notes == "data collected from centers in Ballabgarh, Chennai, Delhi, Dibrugarh, Nagpur, and Trivandrum"
	drop notes1 notes2 notes3 notes4 notes5 moderate_def vig_def country_name *_mean_dpw *_mean_min se_or_ci grouping // *_ss
	
	replace representation = "urban" if regexm(notes, "city|urban|capital|Capital|City") & representation == "" & !regexm(notes,"urban and rural split also available")
	replace representation = "rural" if regexm(notes, "rural") & representation == "" & !regexm(notes,"urban and rural split also available")
	replace representation = "mixed" if national == 0 & representation == "" & site != ""
	
// Reshape from wide to long to be consistent with other physical activity data
	foreach cat in inactive mod high {
		foreach stub in def mean ci ss {
			rename `cat'_`stub' `stub'_`cat'
		}
	}

	reshape long def_@ mean_@ ci_@ ss_@, i(file source_name iso3 site year_start year_end sex age_start age_end) j(category, string)
	rename mean_ mean
	rename ci_ ci
	rename def_ category_definition
	rename ss_ sample_size_new

	replace sample_size = sample_size_new if sample_size == . 
	
// Confidence intervals are in inconsistent formats 
	split ci, parse("-")
	gen lower = ci1 if regexm(ci, "-") | regexm(ci, ",")
	gen upper = ci2 if regexm(ci, "-") | regexm(ci, ",")
	
	gen ci_numeric = ci if ci1 != "" & ci2 == "" & !regexm(ci,"-")
	destring upper lower ci_numeric, replace
	
// Convert CI from percentage to proportion to match mean	
	foreach var in ci_numeric upper lower {
		replace `var' = `var' / 100 
	}
	replace lower = mean - ci_numeric if (!regexm(ci,"-") & ci != "")
	replace upper = mean + ci_numeric if !regexm(ci, "-") & ci != ""
	drop ci* 	
	
// Fill in missing category definitions assuming standard STEPS/GPAQ categories (need to do this so that data will be categorized correctly and not dropped)
	replace category_definition = "<600" if category_definition == "" & category == "inactive" 
	replace category_definition = "600-1500/3000" if category_definition == "" & category == "mod" 
	replace category_definition = ">3000/1500" if category_definition == "" & category == "high"

** **************************************************************************************************************
** 3.) Format compiled dataset
** **************************************************************************************************************	
// Combine data that was extracted in wide format with data that was extracted in long format
	append using `tabulated_long'

// Drop tabulated data if we have since extracted microdata
	 drop if regexm(file, "VIGITEL") 
	
// Drop if no error/variance metric available in tabulations or if proportion was not extracted
	drop if mean == . | (upper == . & lower == . & sample_size == . & standard_error == .)
	replace orig_uncertainty_type = "CI" if upper != . & lower != .
	replace orig_uncertainty_type = "SE" if standard_error != . & orig_uncertainty_type == ""
	replace orig_uncertainty_type = "ESS" if sample_size != . & orig_uncertainty_type == ""
	
// Fill in epi variables
	rename data_type source_type
	replace source_type = "Literature" if regexm(citation, "#") & source_type == "" // # identifies IHME zotero citations
	replace source_type = "Survey" if source_name != "" & source_type == ""
	gen data_type = "Survey: unspecified" if source_type == "Survey"
	replace data_type = "Study: unspecified" if source_type == "Literature" 
				
	** Make representativeness epi variable
	replace national_type = 3 if representation == "Aboriginal and Torres Strait Islanders only" | regexm(notes, "indigenous")
	replace national_type = 1 if national_type == . & national == 1
	replace national_type = 2 if national_type == . & national == 0 & site != ""
	replace national_type = 3 if (site == "" & national == 0) & national_type == .
	replace national_type = 1 if national_type == .
	label define national 0 "Unknown" 1 "Nationally representative" 2 "Subnationally representative" 3 "Not representative", replace
	label values national_type national
	
	** Make urbanicity epi variable
	gen urbanicity_type = 1 if national_type == 1 | national_type == 2
	replace urbanicity_type = 2 if representation == "urban" | regexm(site, "City")
	replace urbanicity_type = 3 if representation == "rural"
	replace urbanicity_type = 0 if urbanicity_type == . & (national_type == 3 | national_type == 0)
	label define urban 0 "Unknown" 1 "Representative" 2 "Urban" 3 "Rural" 4 "Suburban" 5 "Peri-urban", replace
	label values urbanicity_type urban

// Identify proper healthstate category for each extracted figure	
	// 1.) Inactive (<600 MET-min/week)
		preserve
		keep if regexm(category,"inactive|insufficient|low|sedentary|physical activity")
		keep if regexm(units, "min/week|min/day|categories|""")
		
		replace standard_error = ((upper - lower)/2)/1.96 if standard_error == . 
		replace sample_size = mean *(1 - mean)/(standard_error ^2) if sample_size == . // binomial approximation of sample size since these are proportions
		
		by file iso3 year_start year_end sex age_start age_end, sort: egen inactive_mean = total(mean) if units == "min/week" | iso3 == "JAM"
		by file iso3 national_type urbanicity_type site year_start year_end sex age_start age_end, sort: egen ss = mean(sample_size)
		
		replace category = "inactive aggregated" if mean != inactive_mean & inactive_mean != .
		replace sample_size = round(ss) if category == "inactive aggregated"
		replace category_definition = "<150" if category == "inactive aggregated"
		replace units = "MET-min/week" if category == "inactive aggregated".
		replace mean = inactive_mean if category == "inactive aggregated"
		recode standard_error (0=.) if sample_size != .
		duplicates drop file iso3 year_start year_end sex age_start age_end mean, force
		drop inactive_mean ss
		
		// Remove inaccurate variance metrics from aggregation above
		foreach var in standard_error upper lower {
			replace `var' = . if category == "inactive aggregated"
		}

		gen healthstate = "activity_inactive"
		tempfile inactive
		save `inactive', replace
		restore
		
	// 2.) Active (>600 MET-min/week)
		replace units = "MET-min/week" if inlist(units, "MET-minutes/week", "METmin/week")
		keep if regexm(category, "high|medium|mod|physically active 30|regular activity|adequate activity") | inlist(category, "sufficiently active", "sufficient activity", "sufficiently active (moderate or high)", "active", "vigorous", "sufficient", "physical activity")
		keep if regexm(units, "MET-min/week|min/day|min/week|minutes of physical activity in previous week|""")
		drop if source_name == "Australia National Health Survey 2007-2008"
		
		replace standard_error = ((upper - lower)/2)/1.96 if standard_error == . 
		replace sample_size = mean *(1 - mean)/(standard_error ^2) if sample_size == . // binomial approximation of sample size since these are proportions
		
		by file iso3 national_type urbanicity_type site year_start year_end sex age_start age_end, sort: egen active_mean = total(mean)
		by file iso3 national_type urbanicity_type site year_start year_end sex age_start age_end, sort: egen ss = mean(sample_size)
		
		replace category = "active aggregated" if mean != active_mean & active_mean != .
		replace sample_size = round(ss) if category == "active aggregated"
		replace category_definition = ">600" if category == "active aggregated"
		replace units = "MET-min/week" if category == "active aggregated"
		replace mean = active_mean if category == "active aggregated"
		recode standard_error (0=.) if sample_size != .
		duplicates drop file iso3 national_type urbanicity_type site year_start year_end sex age_start age_end mean, force
		drop active_mean ss
		
		keep if category_definition == ">600" &  units == "MET-min/week" | (regexm(category_definition, "30") & regexm(units, "min/day")) | (category_definition == ">150" & regexm(units, "min/week|minutes"))
		
		// Remove inaccurate variance metrics from aggregation above
		foreach var in upper lower {
			replace `var' = . if category == "active aggregated" & standard_error != .
		}
		
		gen healthstate = "activity_lowmodhigh"
		
	// Combine
		append using `inactive'
	
	// 3.) If only have proportion with ">600" MET-min/week or proportion with "<600" MET-min/week, calculate the proportion in the opposite category (1-mean)
		duplicates tag nid file source_name iso3 site national_type urbanicity_type year_start year_end sex age_start age_end, gen(dup)
		sort iso3 site national_type urbanicity_type year* sex* age*
		expand 2 if dup == 0, gen(opposite)
		replace mean = round(1 - mean, .001) if opposite == 1
		replace healthstate = "activity_lowmodhigh" if inlist(category, "inactive", "inactive or irregularly active", "low") & opposite == 1
		replace healthstate = "activity_inactive" if regexm(category, "sufficient|physically active 30|active aggregated") & opposite == 1
			
		replace orig_uncertainty_type = "ESS" if (opposite == 1 | regexm(category, "aggregated")) & sample_size != .
		replace sample_size = . if orig_uncertainty_type != "ESS" // these sample sizes were back-calculated
		replace standard_error = . if sample_size != . & orig_uncertainty_type != "SE"
		
	// Drop unnecessary variables
		rename category case_name
		drop timeperiodcovered domain category_definition units notes redundancy met_threshold national specificity representation denominator dup opposite
		
	// Validation checks
		replace lower = . if mean < lower   
		replace upper = . if upper < mean
		replace lower = . if upper == .
		replace upper = . if lower == .
		drop if sample_size == . & upper == . & lower == . & standard_error == . // Can't use if no mean or  variance metric
		duplicates tag nid file source_name iso3 site national_type urbanicity_type year_start year_end age_start age_end healthstate, gen(dups)
		drop if sex == 3 & dups > 1
		drop dups
		tabmiss iso3 year_start year_end sex age_start age_end orig_uncertainty_type national_type urbanicity_type
	
		foreach var in mean lower upper standard_error {
			replace `var' = round(`var', 0.0001)
		}
		replace sample_size = round(sample_size)
		
	tostring location_id, replace 
	
	// Save
		save "`data_dir'/prepped/tabulated_prepped.dta", replace
		
