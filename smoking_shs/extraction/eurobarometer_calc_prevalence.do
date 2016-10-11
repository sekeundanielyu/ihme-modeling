** Date: October, 2013
** Purpose: Calculate secondhand smoke exposure prevalence among nonsmokers in eurobarometer data

// Key to variable definitions (extracted variable names are saved in eurobarometer_varlist.csv)
	** shs_hhrules: "Which statement best describes smoking situation inside your house?" 1=smoking is not allowed at all inside the house, 2=smoking is allowed only in certain rooms, 3=smoking is allowed everywhere inside the house, 4= don't know)
	** smok_curr: Regarding smoking cigarettes, cigars or a pipe, which of the following applies to you?" 1=you smoke at the present time, 2= you used to smoke but you have stopped, 3=you have never smoked, 4=DK
	** smok_curr_man: "Do you smoke manufactured tobacco products every day, occasionally or not at all?" (1=yes, every day, 2=yes, occasionally, 3=No, not at all)
	** smok_curr_unman: "Do you smoke hand-rolled tobacco products every day, occasionally or not at all?" (1=yes, every day, 2=yes, occasionally, 3=No, not at all)
	** cigs_daily: "On average, how many cigarettes do you smoke each day?" (text field to enter number/day, 98=refusal, 99=dk)
	** smok_reg: "Do you smoke regularly or ocassionally?" (1=regularly, 2=ocassionally, 3= DK)
	** shs_freq: How long are you exposed to tobacco smoke at home on a daily basis? (1=never or almost never, 2= less than one hour a day, 3=1-5 hours a day, 4=more than 5 hours a day, 5=DK) *this question is only asked if the respondent answered that smoking is not allowed in the house but sometimes exceptions are made, it is allowed in certain rooms only, allowed only outside.  
	** shs_hh: "Are there smokers or not...at home?" (1=Yes, 2=No, 3= DK)

** Set up: 
	clear all
	set mem 700m
	set maxvar 30000
	set more off
	capture restore not
	cap log close
	
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
		set mem 3g
	}
	else if c(os) == "Windows" {
		global j "J:"
		set mem 800m
	}
	
	
** Set directory, make locals for relevant files and folders, use csv with variable names/definitions
	local nids "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/eurobarometer_SHS.csv"
	local data_dir "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate"
	
** Prep Eurobarometer NID dataset (In spring of 2014 Eurobarometer series was assigned country-specific NIDs)
	insheet using "`nids'", comma clear
	gen year_start= substr(timeperiodcovered, -4, 4)
	destring year_start, replace
	rename suggestedcitation citation
	tempfile eurobarometer_nids
	save `eurobarometer_nids'	
	
** Prepare countrycodes database
	use "$j/Usable/Common Indicators/Country Codes/countrycodes_official.dta", clear
	keep if countryname == countryname_ihme
	drop if iso3 == ""
	tempfile countrycodes
	save `countrycodes', replace
	
** Bring in Eurobarometer varlist
	insheet using "`data_dir'/raw/eurobarometer_varlist.csv", names clear
	tostring nid, replace 
	
** Get variable names for survey processing
	mata: datasets = st_sdata(.,("nid", "country", "start_year", "filepath", "pweight_uk", "pweight_germ", "pweight", "sex", "age", "shs_hhrules", "shs_freq","shs_hh", "smok_curr", "smok_curr_man", "smok_curr_unman", "cigs_daily", "smok_reg", "notes", "pweight_nor"))

	local num_surveys = _N

** This loop will run through all of the data files for this country-gender.  Begin by making stata locals from the mata vector datasets.			
	local counter = 1
		forvalues filenum=1(1)`num_surveys' {
				mata: st_local ("nid", datasets[`filenum', 1])
				mata: st_local ("country", datasets[`filenum', 2])
				mata: st_local ("start_year", datasets[`filenum', 3])
				mata: st_local ("filepath", datasets[`filenum', 4])
				mata: st_local ("pweight_uk", datasets[`filenum', 5])
				mata: st_local ("pweight_germ", datasets[`filenum', 6])
				mata: st_local ("pweight", datasets[`filenum', 7])
				mata: st_local ("sex", datasets [`filenum', 8])
				mata: st_local ("age", datasets [`filenum', 9])
				mata: st_local ("shs_hhrules", datasets [`filenum', 10])
				mata: st_local ("shs_freq", datasets [`filenum', 11])
				mata: st_local ("shs_hh", datasets [`filenum', 12])
				mata: st_local ("smok_curr", datasets [`filenum', 13])
				mata: st_local ("smok_curr_man", datasets [`filenum', 14])
				mata: st_local ("smok_curr_unman", datasets [`filenum', 15])
				mata: st_local ("cigs_daily", datasets [`filenum', 16])
				mata: st_local ("smok_reg", datasets [`filenum', 17])
				mata: st_local ("notes", datasets [`filenum', 18])
				mata: st_local ("pweight_nor", datasets [`filenum', 19])
		
			display in red _newline _newline "filename: `filepath'"

			** Use the file referenced by filename.
				use "`filepath'", clear 
			
			** Generate variables that we want to keep track of
				gen filepath = "`filepath'"
				gen nid = `nid'
				
				gen year_start = "`start_year'"
				replace year_start = substr(year_start, 2,4)
				destring year_start, replace
				
				generate sex = `sex'
			
			** generate iso3 var
				decode `country', g(country_name)
				g iso3 = ""
				replace iso3 = "FRA" if country_name== "FRANCE" | country_name == "France"
				replace iso3 = "BEL" if country_name == "BELGIUM" | country_name == "Belgium"
				replace iso3 = "NLD" if country_name == "NETHERLANDS" | country_name == "Netherlands" | country_name == "The Netherlands"
				replace iso3 = "DEU" if country_name == "GERMANY" | country_name  == "Germany" | country_name == "EAST GERMANY" | country_name == "WEST GERMANY" | country_name == "Germany - West" | country_name == "Germany - East" | country_name == "Germany (West+East)" | country_name == "Germany West" | country_name == "Germany East" | country_name == "GERMANY WEST" | country_name == "GERMANY EAST"
				replace iso3 = "ITA" if country_name == "ITALY" | country_name == "Italy"
				replace iso3 = "LUX" if country_name == "LUXEMBOURG" | country_name == "Luxembourg"
				replace iso3 = "DNK" if country_name == "DENMARK" | country_name == "Denmark"
				replace iso3 = "IRL" if country_name == "IRELAND" | country_name == "Ireland"
				replace iso3 = "GBR" if country_name == "UNITED KINGDOM" | country_name == "United Kingdom" | country_name == "Great Britain" | country_name == "Northern Ireland" | country_name == "GREAT BRITAIN" | country_name == "NORTHERN IRELAND"
				replace iso3 = "GRC" if country_name == "GREECE" | country_name == "Greece"
				replace iso3 = "ESP" if country_name == "SPAIN" | country_name == "Spain"
				replace iso3 = "PRT" if country_name == "PORTUGAL" | country_name == "Portugal"
				replace iso3 = "NOR" if country_name == "NORWAY" | country_name == "Norway"
				replace iso3 = "FIN" if country_name == "FINLAND" | country_name == "Finland"
				replace iso3 = "SWE" if country_name == "SWEDEN" | country_name == "Sweden"
				replace iso3 = "AUT" if country_name == "AUSTRIA" | country_name == "Austria"
				replace iso3 = "BGR" if country_name == "BULGARIA" | country_name == "Bulgaria"
				replace iso3 = "CYP" if country_name == "Cyprus (Republic)" | country_name == "Cyprus (TCC)" | country_name == "CYPRUS (REPUBLIC)" | country_name == "CYPRUS TCC"
				replace iso3 = "CZE" if country_name == "Czech Republic" | country_name == "CZECH REPUBLIC"
				replace iso3 = "EST" if country_name == "Estonia"  | country_name == "ESTONIA"
				replace iso3 = "HUN" if country_name == "Hungary" | country_name == "HUNGARY"
				replace iso3 = "LVA" if country_name == "Latvia" | country_name == "LATVIA"
				replace iso3 = "LTU" if country_name == "Lithuania" | country_name == "LITUANIA"
				replace iso3 = "MLT" if country_name == "Malta" | country_name == "MALTA"
				replace iso3 = "POL" if country_name == "Poland" | country_name == "POLAND"
				replace iso3 = "ROU" if country_name == "Romania" | country_name == "ROMANIA"
				replace iso3 = "SVK" if country_name == "Slovakia" | country_name == "SLOVAKIA"
				replace iso3 = "SVN" if country_name == "Slovenia" | country_name == "SLOVENIA"
				replace iso3 = "TUR" if country_name == "Turkey" | country_name == "TURKEY"
				replace iso3 = "HRV" if country_name == "Croatia" | country_name == "CROATIA"
				replace iso3 = "MKD" if country_name == "MAKEDONIA"

		** Fix the weights that are split by britain/germany subregions
			g pweight = .
			if "`pweight_uk'" != "" {  
				replace pweight = `pweight'
				replace pweight = `pweight_uk' if iso3 == "GBR"
				replace pweight = `pweight_germ' if iso3 == "DEU"
			}
			if "`pweight_uk'" == "" {  
				replace pweight = `pweight'
			}
			if "`pweight_nor'" != "" {
				replace pweight = `pweight_nor' if iso3 == "NOR"
			}

		** Set age groups
			gen age_start = . 
			gen age_end = . 
			keep if `age' >= 15
			forvalues x=15(5)100 {
				local max = `x' + 5
				replace age_start = `x' if `age'>=`x' & `age'<`max'
			}
			replace age_start = 80 if age_start>=80
			replace age_end = age_start + 4
			

		** Create smoking status indicator variable
			g smok_curr_all_cigs = .
			replace smok_curr_all_cigs = `smok_curr_man' + `smok_curr_unman'
				
			g smoker = .
			replace smoker = 0 if smok_curr_all_cigs != . // gets denominator based on who answered the smoking question
			cap replace smoker = 1 if smok_curr_all_cigs > 0 & smok_curr_all_cigs != .
		
		** Keep only nonsmokers, since we are interested in shs exposure prevalence among nonsmokers
			keep if smoker == 0

		** Definining secondhand smoke exposure as any daily passive smoke exposure at home
				g shs = .
				// Surveys asking about hours/day of passive smoking at home
				if year_start == 2006 { 
					replace shs = 0 if `shs_freq' == 1 | `shs_freq' > 4 &(`shs_hhrules' == 1 | `shs_hhrules' == 5 | `shs_hhrules' == 6) // never or almost never, or smoking is never allowed in house, people voluntarily do not smoke in house or no smoking norms\no smokers\do not need rules
					replace shs = 1 if `shs_freq' > 1 & `shs_freq' < 5 // any daily passive smoke exposure counts
				}
		
				// 1992 & 1995 surveys ask a yes or no question about smokers at home
				if year_start == 1992 | year_start == 1995 {
					replace shs = 0 if `shs_hh' == 2 // "no" smokers at home
					replace shs = 1 if `shs_hh' == 1 // "yes" smokers at home
				}
			
			
			** Keep only necessary variables so that datasets for each year append properly
				keep year_start country_name iso3 pweight age_start age_end sex shs filepath nid
				

			** Tempfile the data
				tempfile curr`counter'
				save `curr`counter'', replace 
				local counter = `counter' + 1
	}
	
				** Append all data	
	clear
	local max = `counter' -1
	use `curr1', clear
	forvalues x = 2/`max' {
		append using `curr`x''
	}		
	
	tempfile master
	save `master', replace
	
			// Create empty matrix for storing results
			mata 
				iso3 = J(1,1,"999")
				year = J(1,1,999)
				age = J(1,1,-999)
				sex = J(1,1,-999)
				category = J(1,1,"todrop")
				sample_size = J(1,1,-999)
				parameter_value = J(1,1,-999.999)
				standard_error = J(1,1,-999.999)
				filepath = J(1,1,"filepath")
				nid = J(1,1, -9999999)
				upper = J(1,1, -9999999)
				lower = J(1,1, -9999999)
			end
		
			// set survey weights
				svyset _n [pweight=pweight]
				
				** Loop through sexes and ages and calculate smoking prevalence using survey weights
				levelsof iso3, local(countries) clean
				levelsof year_start, local(years)
				levelsof age_start, local(ages)
				
				foreach year of local years {
					local filepath filepath
					foreach country of local countries {
						foreach sex in 1 2 {
							foreach age of local ages {
								di in red  "year:`year' country:`country' sex:`sex' age:`age'"
								
								count if year_start == `year' & iso3 == "`country'" & age_start == `age' & sex == `sex'
								local sub_observations `r(N)'
								
								if `sub_observations' > 0 {
									di "`country'"  "`year'"
									
									sum nid if year_start == `year' & iso3 == "`country'" & age_start == `age' & sex == `sex'
									local nid = `r(mean)'
									
									levelsof filepath if year_start == `year' & iso3 == "`country'" & age_start == `age' & sex == `sex', local(filepath) clean
									
									
									svy linearized, subpop(if year_start == `year' & iso3 == "`country'" & age_start == `age' & sex == `sex'): mean shs

		
									** Extract identifiers
									mata: iso3 = iso3 \ "`country'"
									mata: year = year \ `year'
									mata: age = age \ `age'
									mata: sex = sex \ `sex'
									mata: category = category \ "household_cig_smoke"
									mata: sample_size = sample_size \ `e(N_sub)'	
									mata: filepath = filepath \ "`filepath'"
									mata: nid = nid \ `nid'
		
									** Extract calculated prevalence and standard error from the matrix
									matrix mean_matrix=e(b)
									local mean_scalar = mean_matrix[1,1]
									mata: parameter_value = parameter_value \ `mean_scalar'
		
									matrix variance_matrix=e(V)
									local se_scalar = sqrt(variance_matrix[1,1])
									mata: standard_error = standard_error \ `se_scalar'
									
									local degrees_freedom = `e(df_r)'
									local lower = invlogit(logit(`mean_scalar') - (invttail(`degrees_freedom', .025)*`se_scalar')/(`mean_scalar'*(1-`mean_scalar')))
									mata: lower = lower \ `lower'
									local upper = invlogit(logit(`mean_scalar') + (invttail(`degrees_freedom', .025) * `se_scalar') / (`mean_scalar' * (1 - `mean_scalar')))
									mata: upper = upper \ `upper'
								}
							}
						}
					}
				}	
	
// Get stored prevalence calculations from matrix
		clear

		getmata iso3 year age sex category sample_size parameter_value standard_error lower upper filepath nid
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
		
	
// Merge on country names
		merge m:1 iso3 using `countrycodes', keepusing(countryname)
		drop if _merge == 2
		drop _merge

// Create variables that are always tracked		
	rename year year_start
	generate year_end = year_start	
	rename age age_start
	generate age_end = age_start + 9
	gen GBD_cause = "smoking_shs"
	gen case_definition = "any daily passive smoke exposure at home among current nonsmokers" if year_start == 2006
	replace case_definition = "current nonsmokers living with a smoker" if inlist(year_start, 1992, 1995)
	gen national = 1
	gen survey_name = "Eurobarometer"
	gen source = "micro_eurobarometer"
	gen ss_level = "age_sex"
	
//  organize
	order iso3 year_start year_end sex age_start age_end sample_size parameter_value lower upper standard_error, first
	sort countryname sex age_start age_end
	
// Fill in proper NIDs
	replace nid = .
	merge m:1 iso3 year_start using `eurobarometer_nids', nogen keepusing(nid iso3 year_start citation) update
	
// Save survey weighted prevalence estimates 
	save "`data_dir'/prepped/eurobarometer_prepped.dta", replace


