
// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		set mem 12g
		set maxvar 32000
	// Set to run all selected code without pausing
		set more off
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}
		

// TEST ARGUMENTS 
	
	/*
	local 1 C
	local 2 102
	local 3 2 
	local 4 99
	*/

// Pass in arguments from launch script	
	local virus `1'
	local iso3 `2'
	local sex `3' 
	local draw_num `4'
	local version `5'

// Locals 
	local code_dir "/snfs2/HOME/strUser/strUser_dismod_risks/drug_use/04_paf"
	local rr_dir "/share/epi/risk/temp/drug_use_pafs/hepatitis_`virus'"
	local data_dir "/share/epi/risk/temp/drug_use_pafs"

	local startyr 1960
	local endyr 2015

	local years "1990 1995 2000 2005 2010 2015"

// Run central functions 
	run "$prefix/WORK/10_gbd/00_library/functions/get_ids.ado" 
	run "$prefix/WORK/10_gbd/00_library/functions/get_best_model_versions.ado" 
	run "$prefix/WORK/10_gbd/00_library/functions/get_draws.ado" 

// Set up log file 
	cap mkdir "`data_dir'/logs/`iso3'"
	log using "`data_dir'/logs/`iso3'/log_virus`virus'_`iso3'_`sex'_`draw_num'.smcl", replace 
	
// 1) Prep IDU exposure draws 
		clear
		get_ids, table(modelable_entity) clear 
		keep if regexm(modelable_entity_name, "Intravenous drug use")
		local exp_sequela_id = modelable_entity_id

		di `exp_sequela_id'
		
	 // Get model version id
		clear 
		get_best_model_versions, gbd_team(epi) id_list(`exp_sequela_id')
		local exp_model_version_id = model_version_id 
		di `exp_model_version_id'
	
	// Use get draws function to pull location-sex specific draws from the drug use exposure model 				
		
		// temporary use flat file for testing purposes 
		//use "$j\WORK\05_risk\risks\drug_use\products\pafs\hepatitis_C\drug_use_draws.dta", clear

		get_draws, gbd_id_field(modelable_entity_id) gbd_id(`exp_sequela_id') location_ids(`iso3') sex_ids(`sex') status(latest) source(epi) clear

		tempfile idu_draws 
		save `idu_draws', replace 

		insheet using "`data_dir'/convert_to_new_age_ids.csv", comma names clear 
		merge 1:m age_group_id using `idu_draws', keep(3) nogen

		rename age_start age 
		keep if age >= 15 & age <=80
		keep age year draw_*	

	// Expand to make observations for years 1960(5)1990
		local yeardif = (1990 - `startyr')/5 + 1
		expand `yeardif' if year == 1990, gen(dup)
		sort year age dup
		bysort year age: gen x = _n if year == 1990
		replace x = x * 5 // 5 year intervals
		levelsof x, local(yrs)
		foreach yr of local yrs {
			replace year = `startyr' + `yr' - 5 if x == `yr'
		}
		drop dup x
		
	// Expand again to make observations for each year between GBD 5 year intervals
		expand 5, gen(dup)
	
	// Replace duplicate with proper year
		bysort year age dup: gen y = _n
		forvalues x = 1/4 {
			replace year = year - y if y == `x' & dup == 1 & year != `startyr'
		}
		
		duplicates drop age year, force
		drop dup y
		
	// Save prepped IDU exposure draws
		tempfile `iso3'_`sex'_exposure
		save ``iso3'_`sex'_exposure', replace
		
// 2.) Prep Hepatitis incidence draws by summing incidence for each of the three "acute" healthstates (moderate, acute and asymptomatic infections)
	// Pull sequelae_ids and model version ids for best marked models from epi database

		clear
		get_ids, table(modelable_entity) clear 
		keep if regexm(modelable_entity_name, "acute hepatitis") & !regexm(modelable_entity_name, "hepatitis A|hepatitis E") 
		keep if regexm(modelable_entity_name, "`virus'") 
		// just keep whichever hepatitis outcome currently running PAFs for; global set in master script
	
	levelsof modelable_entity_id, local(outcome_healthstates)		

	local counter 0
	foreach seq of local outcome_healthstates {
	di "SEQUELA = `seq', ACAUSE = hepatitis_`virus'"
		
		local counter = `counter' + 1

		get_draws, gbd_id_field(modelable_entity_id) gbd_id(`seq') location_ids(`iso3') sex_ids(`sex') measure_ids(6) status(latest) source(epi) clear
		
		//save "`data_dir'/hep_`seq'_draws.dta", replace 
		//use "`data_dir'/hep_`seq'_draws.dta", clear 

		tempfile hep_draws 
		save `hep_draws', replace

		insheet using "`data_dir'/convert_to_new_age_ids.csv", comma names clear 
		merge 1:m age_group_id using `hep_draws', keep(3) nogen

		rename age_start age 
		keep if age >= 15 & age <=80
		keep age year draw_*	
			
		tempfile outcome_`counter'
		save `outcome_`counter'', replace
		
	}
		
		// Append all files
		clear
		forvalues x = 1/`counter' {
			append using `outcome_`x''
		}

		// Total incidence is the sum of incidence from each acute sequelae
		collapse (sum) draw_*, by(year age) fast
		
	// Rename so that exposure and outcome draws do not have the same variable name
		forvalues d = 0/999 {
			rename draw_`d' incidence`d'
		}
		
	// Expand to make observations for years 1960(5)1990
		local yeardif = (1990 - `startyr')/5 + 1
		expand `yeardif' if year == 1990, gen(dup)
		sort year age dup
		bysort year age: gen x = _n if year == 1990
		replace x = x * 5 // 5 year intervals
		levelsof x, local(yrs)
		foreach yr of local yrs {
			replace year = `startyr' + `yr' - 5 if x == `yr'
		}
		drop dup x
		
	// Expand again to make observations for each year between GBD 5 year intervals
		expand 5, gen(dup)
	
	// Fill in proper years
		bysort year age dup: gen y = _n
		forvalues x = 1/4 {
			replace year = year - y if y == `x' & dup == 1 & year != `startyr'
		}
		
		duplicates drop age year, force
		drop dup y
		
	// Save prepped outcome draws of incidence 
		tempfile `iso3'_`sex'_hepatitis_`virus'
		save ``iso3'_`sex'_hepatitis_`virus'', replace
		
// Draw_num represents the final draw number, make local for first draw in group of 100 draws
	local draw_start = `draw_num' - 99

// Loop through draws from best IDU DisMod model for relevant country and sex and calculate PAF for Hepatitis incidence  

	forvalues d = `draw_start'/`draw_num' {
		di "ISO3 = `iso3', Sex = `sex', draw `d'/`draw_num'"
		quietly {
				// Open exposure dataset and pull only the current working draw	
					use year age draw_`d' using ``iso3'_`sex'_exposure', clear 
				
				// Merge exposure with hepatitis incidence dataset
					merge 1:1 year age using ``iso3'_`sex'_hepatitis_`virus'', nogen keep(match) keepusing(incidence`d')
					rename incidence`d' incidence	
					
				// Linearly interpolate exposure between  year intervals
					reshape wide draw_`d' incidence, i(age) j(year)
					
					// Merge with working draw of year coefficient
						gen x = 1
						merge m:1 x using "`data_dir'/year_coef_draws.dta", keepusing(beta_`d') nogen
		
						foreach y1 in `startyr' 1990 1995 2000 2005 2010 {
							// Use coefficient on year covariate from DisMod model to project prevalence backward for years prior to 1990 (assume hepatitis incidence is the same as it was in 1990)
							if inlist(`y1', `startyr') {
								local dif = 1990 - `startyr' - 1
								forvalues x = 0/`dif' {
									local ynow = `y1' + `x'
									local ydif = 1990 - `ynow'
									replace draw_`d'`ynow' = draw_`d'1990*exp(-beta_`d'*`ydif')
								}
							}
							// Use linear trend between 5 year GBD intervals for both IDU prevalence and hepatitis incidence
							if inlist(`y1', 1990, 1995, 2000, 2005, 2010) {
								forvalues x = 1/4 {
									local y2 = `y1' + 5
									local ynow = `y1' + `x'
									replace draw_`d'`ynow' = exp(ln(draw_`d'`y1') + (ln(draw_`d'`y2') - ln(draw_`d'`y1'))*(`ynow'-`y1')/(`y2'-`y1'))
									replace incidence`ynow' = exp(ln(incidence`y1') + (ln(incidence`y2') - ln(incidence`y1'))*(`ynow'-`y1')/(`y2'-`y1'))
								}
							}
							
						}
					

					drop x beta_`d'
					reshape long
				
				// Rename IV drug use prevalence draw as "exposure" for clarity
					rename draw_`d' exposure
					gen x = 1
					
				// Merge IDU exposure with absolute risk
					merge m:1 x using "`rr_dir'/hepatitis_`virus'_risk_draws.dta", keepusing(risk`d')  keep(match) nogen
					rename risk`d' risk
					
				// Only keep necessary variables
					keep year risk exposure age incidence
					
				// Expand again to get 1 year age groups
					expand 5, gen(dup)
					bysort year age dup: gen y = _n
					forvalues x = 1/4 {
						replace age = age + y if y == `x' & dup == 1
					}
					drop dup y	
				
				// Reshape wide	

					rename year_id year 
					gen iso3 = `iso3'
					gen sex = `sex'

					reshape wide incidence exposure, i(year) j(age)

					tostring year, replace 
					replace year = "_" + year 

					reshape wide incidence* exposure*, i(iso3 sex) j(year, string)	
				
				tempfile prepped
				save `prepped', replace
				

			// 1.) Denominator: Cumulative incidence of Hepatitis (after age start = 15, since 15 is our start age for estimating attributable IV drug use burden). Assume risk from IV drug use began accumulating in 1960. 
				// Extract cumulative Hepatitis incidence
				gen double prob1 = .
				gen double prob2 = .
					forvalues year = `startyr'/`endyr' {
						forvalues age_then = 15(1)84 {
							//  Calculate the year each cohort was 15 years old
							local age15yr = `year' - (`age_then' - 15) 
							// Scenerio 1: If year that cohort was 15 years old is before 1960 then they start accumulating risk at whatever age they were in 1960 rather than at age 15
							if `age15yr' < `startyr' {
								local agein`startyr' = `startyr' - (`age15yr'-15)
								replace prob1 = 1 - incidence`agein`startyr''_`startyr'
								local agein1961 = `agein`startyr'' + 1
								if `agein1961' < 84 {
									forvalues age = `agein1961'(1)`age_then' {
										local year = `age15yr' + (`age'-15)
										replace prob2 = prob1 * (1 - incidence`age'_`year')
										replace prob1 = prob2
									}
								}
							}
							// Scenerio 2: If the year the cohort was 15 years old is after 1960 then they start accumulating risk at age 15
							if `age15yr' >= `startyr' {
								replace prob1 = 1 - incidence15_`age15yr'
								if `age15yr' < `year' {
									forvalues age = 16(1)`age_then' {
										local year = `age15yr' + (`age'-15)
										replace prob2 = prob1 * (1 - incidence`age'_`year')
										replace prob1 = prob2
									}
								}
							}
								
							// Extract
								gen double prob_denominator`age_then'_`year' = prob1
						}
					}
						
				// Reshape long (twice) for later merge with the numerator cumulative probability
					drop incidence* risk* exposure* prob1 prob2
					// Reshape year long
						// save stubs in local
						if `d' == `draw_start' {
							unab varlist1 : prob_denominator*_`startyr'
							foreach var of local varlist1 {
								local stub1 = substr("`var'",1,length("`var'")-4)
								local stublist1 `stublist1' `stub1'
							}
						}
						reshape long "`stublist1'", i(iso3 sex) j(year)
				
					// Reshape age long
						reshape long prob_denominator, i(iso3 year sex) j(age, string)
						replace age = substr(age, 1, 2)
						destring age, replace
					
				// Cumulative incidence is 1 - probability of not getting Hepatitis
					gen double denominator = 1 - prob_denominator	
					drop prob_denominator
					
				tempfile denominator
				save `denominator', replace
				

			// 2.) Numerator: Cumulative incidence of Hepatitis due to IV drug use
				use `prepped', clear
				gen double prob1 = .
				gen double prob2 = .
				// Extract cumulative Hepatitis incidence
					forvalues year = `startyr'/`endyr' {
						forvalues age_then = 15(1)84 {
							local age15yr = `year' - (`age_then' - 15)
							// Scenerio 1: If year that cohort was 15 years old is before 1960 then they start accumulating risk at whatever age they were in 1960 rather than at age 15
							if `age15yr' < `startyr' {
								local agein`startyr' = `startyr' - (`age15yr'-15)
								gen product = exposure`agein`startyr''_`startyr' * risk
								replace product = .99 if product > 1
								replace prob1 = 1 - product
								local agein1961 = `agein`startyr'' + 1
								if `agein1961' < 84 {
									forvalues age = `agein1961'(1)`age_then' {
										local year = `age15yr' + (`age'-15)
										replace product = exposure`age'_`year' * risk
										replace product = .99 if product > 1
										replace prob2 = prob1 * (1 - product)
										replace prob1 = prob2
									}
								}
								drop product
							}
							// Scenerio 2: If the year the cohort was 15 years old is after 1960 then they start accumulating risk at age 15
							if `age15yr' >= `startyr' {
								gen product = exposure15_`age15yr' * risk
								replace product = .99 if product > 1
								replace prob1 = 1 - product
								if `age15yr' < `year' {
									forvalues age = 16(1)`age_then' {
										local year = `age15yr' + (`age'-15)
										replace product = exposure`age'_`year' * risk
										replace product = .99 if product > 1
										replace prob2 = prob1 * (1 - product)
										replace prob1 = prob2
									}
								}
								drop product
							}
								
							// Extract
								gen double prob_numerator`age_then'_`year' = prob1
						}
					}
					
				// Reshape long (twice) for merge with denominator cumulative probability
					drop incidence* risk* exposure* prob1 prob2
					// Reshape year long
						// save stubs in local
						if `d' == `draw_start' {
							unab varlist2 : prob_numerator*_`startyr'
							foreach var of local varlist2 {
								local stub2 = substr("`var'",1,length("`var'")-4)
								local stublist2 `stublist2' `stub2'
							}
						}
						reshape long "`stublist2'", i(iso3 sex) j(year)
				
					// Reshape age long
						reshape long prob_numerator, i(iso3 year sex) j(age, string)
						replace age = substr(age, 1, 2)
						destring age, replace		
						
				// Cumulative incidence is 1 - probability of not getting Hepatitis
					gen double numerator = 1 - prob_numerator
					drop prob_numerator
					
				// Merge with prob_denominator
					merge 1:1 iso3 year age using `denominator', nogen
					
				// Calculate PAF on prevalence of Hepatitis due to IDU
					gen double draw_`d' = numerator / denominator
					recode draw_`d' (.=0) if numerator == 0 & denominator == 0
				
				// Keep only GBD years
					keep if inlist(year, 1990, 1995, 2000, 2005, 2010, 2015)
					drop numerator* denominator*
					
				// Take average of ages in each age group to get 5 year age group 
					forvalues gbdage = 15(5)80 {
						forvalues x = 1/4 {
							di `gbdage' + `x'
							replace age = age - `x' if age == (`gbdage' + `x')
						}
					}
					collapse (mean) draw_*, by(iso3 year age sex) fast
					
				// Cap PAF at 0.9
					replace draw_`d' = 0.9 if draw_`d' > 0.9 & draw_`d' != .
					
				// Save each draw as a tempfile to be appended at the end
					tempfile draw`d'_`iso3'_`sex'
					save `draw`d'_`iso3'_`sex'', replace			

		}
	}
		
		// Merge 100 PAF draws for this paralellized "chunk"
			use `draw`draw_start'_`iso3'_`sex'', clear
			local s = `draw_start' + 1
			forvalues d=`s'/`draw_num' {
				qui: merge 1:1 year age using `draw`d'_`iso3'_`sex'', nogen
			}
			
		// Fill in identifying variables
			gen acause = "hepatitis_`virus'"
			
		// Save in intermediate directory as country and sex specific files
		cap mkdir "`data_dir'/hepatitis_`virus'/v`version'_new"
		cap mkdir "`data_dir'/hepatitis_`virus'/v`version'_new/`iso3'"
		save "`data_dir'/hepatitis_`virus'/v`version'_new/`iso3'/paf_`iso3'_`sex'_draw_`draw_start'.dta", replace
			
