// March 17, 2014
// Clean and prep CSA extraction for Australia

// Set data directory
	local data_dir "J:/WORK/05_risk/risks/abuse_csa/data/exp/01_tabulate"
	
// Prep raw data file	
	import excel using "`data_dir'/raw/CSA_Norman_new citations.xlsx", firstrow sheet("Australia CSA") clear
	renvars, lower
	gen sex = 1 if mf == "M"
	replace sex = 2 if mf == "F"
	replace sex = 3 if mf == "M/F"

// Drop if definition of childhood is unclear
	drop if inlist(definition, "childhood", "N/A")
	
// Drop studies among subpopulations or are self-selected
	keep if inlist(sample, "High School Students") | regexm(sample, "Represent")   

// Make GBD age variables
	split age, parse("-") gen(age)
	replace age2 = "100" if regexm(age1, ">") & age2 == ""
	replace age1 = substr(age1,-8, 2) if regexm(age1, "years") 
	replace age2 = substr(age2,-8, 2) if regexm(age2, "years")
	replace age2 = age1 if age2 == ""
	rename age1 age_start
	rename age2 age_end
	destring age_start age_end, replace
	drop age mf
	
// Specify representation
	gen iso3 = "AUS"
	gen national_type = location == "all States and Territories"
	replace national_type = 2 if regexm(sample, "Representative") & national_type == 0
	label define national 0 "Unknown"  1 "Nationally representative" 2 "Subnationally representative" 3 "Not representative"
	label values national_type national
	drop if study == "MUSP Birth Cohort" // Participants accrued at 2 obstetric hospitals - not representative

// Specify Epi covariates
	gen cv_contact = regexm(measureofabuse, "Sexually assaulted or raped|6 items: With contact")
	gen cv_noncontact = regexm(measureofabuse, "6 items: Without Contact")
	gen cv_intercourse = regexm(measureofabuse, "Sexual pentration")
	gen cv_child_16_17 = regexm(definition, "16") | regexm(definition, "17")
	gen cv_child_18 = regexm(definition, "18")
	gen cv_child_18plus = 0
	gen cv_child_over_15 = 0
	gen cv_child_under_15 = 0
	gen cv_nointrain = 1
	gen cv_perp3 = 0
	gen cv_notviostudy1 = !regexm(study, "Violence|VIOLENCE|violence")
	gen cv_parental_report = 0
	gen cv_school = 0
	gen cv_anym_quest = 0
	gen parental_report = 0
	
// Rename variables for consistency with Epi template
	rename fullreference citation
	rename study source_name
	rename location site
	rename n sample_size
	rename measureofabuse case_definition
	rename prevalence mean 
	gen source_type = "Survey" if regexm(citation, "urvey")
	replace source_type = "Literature" if source_type == ""
	gen recall_type = "Lifetime"
	
	keep nid iso3 sample_size site source_name citation cv_* national_type year_start year_end age_start age_end mean sex case_definition source_type recall_type
	order nid source_name citation iso3 site case_definition national_type year_start year_end sex age_start age_end sex mean sample_size 
	sort source_name

	outsheet using "`data_dir'/prepped/aus_potential_sources.csv", comma replace
	
