/// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 			8 July 2014
// Project:		RISK
// Purpose:		Format PAFs for central machinery. 
** **************************************************************************
** RUNTIME CONFIGURATION
** **************************************************************************
// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		set mem 12g
		set maxvar 32000
	// Set to run all selected code without pausing
		set more off
	// Set graph output color scheme
		set scheme s1color
	// Remove previous restores
		cap restore, not
	// Reset timer (?)
		timer clear	
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}
	// Close previous logs
		cap log close


// TEST ARGUMENTS 
/*
	local 1 4758
	local 2 2 
	local 3 1
*/

// Pass in arguments from launch script	
	local iso3 `1'
	local sex `2' 
	local version `3'

	local code_dir "/snfs2/HOME/strUser/strUser_dismod_risks/drug_use/04_paf"
	local data_dir "/share/epi/risk/temp/drug_use_pafs"
	local rr_dir "$prefix/WORK/05_risk/risks/drug_use/data/rr/prepped"
	local out_dir "/share/epi/risk/temp/drug_use_pafs/finalized_pafs"
	local years "1990 1995 2000 2005 2010 2015"

	run "$prefix/WORK/10_gbd/00_library/functions/get_ids.ado" 
	run "$prefix/WORK/10_gbd/00_library/functions/get_draws.ado"
// Log 

// Loop over each country, sex and draw "chunk", saving PAF draws for each cause attributable to IV drug use 

	** Merge draw files to make master PAF file for each country and sex

		local viruses "C B"
		//local viruses "B"

		foreach virus of local viruses { 

			di in red "VIRUS: `virus'"
			use "`data_dir'/hepatitis_`virus'/v`version'_new/`iso3'/paf_`iso3'_`sex'_draw_0.dta", clear
			//use "C:/Users/strUser/Desktop/`iso3'/paf_`iso3'_`sex'_draw_0.dta", clear 

			forvalues d = 100(100)900 {
				merge 1:1 iso3 year age sex using "`data_dir'/hepatitis_`virus'/v`version'_new/`iso3'/paf_`iso3'_`sex'_draw_`d'.dta", nogen
				//merge 1:1 iso3 year age sex using "C:/Users/strUser/Desktop/`iso3'/paf_`iso3'_`sex'_draw_`d'.dta", nogen
			}	
			
			rename age age_start 

			tempfile hep`virus'
			save `hep`virus'', replace 
	
		}

		use `hepB', clear 
		append using `hepC'
		
		tempfile all 
		save `all', replace 


			insheet using "`data_dir'/convert_to_new_age_ids.csv", comma names clear 
			//insheet using "C:/Users/strUser/Desktop/convert_to_new_age_ids.csv", comma names clear
			merge 1:m age_start using `all', keep(3) nogen
			drop age_start 

			rename iso3 location_id 
			rename year year_id 
			rename sex sex_id

			levelsof year_id, local(years)

			save `all', replace 

// Save on clustertmp as country, year and sex specific files
	local causes "hepatitis_B hepatitis_C hiv mental_drug_opioids mental_drug_cocaine mental_drug_amphet mental_drug_cannabis mental_drug_other"
		
	foreach year of local years {
		foreach acause of local causes { 
			di "YEAR = `year', CAUSE = `acause'"

			// Hepatitis B & C have calculated PAFs using a cumulative risk method
				if "`acause'" == "hepatitis_C" | "`acause'" == "hepatitis_B" {
					** Make a dataset that contains PAF draws equal to zero for age groups for which we do not attribute YLLS or YLDs to IDU (i.e. < 15)
					clear 
					local ages 2 3 4 5 6 7 
					local n_obs: word count `ages'
					set obs `n_obs'
					
					** Make variables
					gen age_group_id = .
					forvalues i = 1/`n_obs' {
						local value: word `i' of `ages'
						replace age_group_id = `value' in `i'
						
					}
					forvalues d = 0/999 {
						gen draw_`d' = 0
					}
					
					gen location_id = `iso3'
					gen year_id = `year'
					gen sex_id = `sex'
					gen acause = "`acause'"

					tempfile extra_ages
					save `extra_ages', replace
					
					** Bring in calculated PAF draws for ages 15+
					//local vtype = substr("`acause'", -1, 1)
					use `all', clear
					keep if year == `year' & acause == "`acause'"
					//rename iso3 location_id 
					//rename year year_id 
					//rename sex sex_id 

					append using `extra_ages'
					order location_id year_id sex_id age_group_id acause
					sort age_group_id
				
					** Expand to make identical PAFs for cirrhosis and liver cancer
					expand 3, gen(dup)
					bysort acause location_id year_id sex_id age_group_id dup: gen count = _n if dup == 1
					local virus = substr("`acause'", -1, .)
					replace acause = "neo_liver_hep`virus'" if count == 1
					replace acause = "cirrhosis_hep`virus'" if count == 2
					drop dup count 
					
					if "`acause'" == "hepatitis_C" {
						gen cause_id = 523 if acause == "neo_liver_hepC"
						replace cause_id = 419 if acause == "cirrhosis_hepC"
						replace cause_id = 403 if acause == "hepatitis_C"

					}
					
					if "`acause'" == "hepatitis_B" { 
						gen cause_id = 522 if acause == "neo_liver_hepB"
						replace cause_id = 418 if acause == "cirrhosis_hepB"
						replace cause_id = 402 if acause == "hepatitis_B"
					}
					
					tempfile `acause'
					save ``acause'', replace
				}
				
			// HIV was modeled as a direct proportion due to IV drug use in Dismod
				if "`acause'" == "hiv" {
					** Make a dataset that contains PAF draws equal to zero for age groups for which we do not attribute YLLS or YLDs to IDU (i.e. < 15)
					clear 
					local ages 2 3 4 5 6 7 
					local n_obs: word count `ages'
					set obs `n_obs'
					
					** Make variables
					gen age_group_id = .
					forvalues i = 1/`n_obs' {
						local value: word `i' of `ages'
						replace age_group_id = `value' in `i'
						
					}
					forvalues d = 0/999 {
						gen draw_`d' = 0
					}

					gen location_id = `iso3'
					gen year_id = `year'
					gen sex_id = `sex'
					gen cause_id = 298

					tempfile extra_ages
					save `extra_ages', replace
							
					** Bring in PAF draws from Dismod for ages 15+
						** Pull sequelae_id from epi database
						clear
						get_ids, table(modelable_entity) clear 
						keep if regexm(modelable_entity_name, "HIV") & regexm(modelable_entity_name, "intravenous")
						local exp_sequela_id = modelable_entity_id

						di `exp_sequela_id'

						
						** Bring in data points for relevant country, sex and year  
						get_draws, gbd_id_field(modelable_entity_id) gbd_id(`exp_sequela_id') location_ids(`iso3') sex_ids(`sex') status(latest) source(epi) clear
						//use "H:/hiv_idu_draws.dta", clear 

						tempfile idu_hiv_draws 
						save `idu_hiv_draws', replace 

						keep if inrange(age_group_id, 8, 21)
						//keep age draw_*	
						keep if year_id == `year'
						gen cause_id = 298
							
						append using `extra_ages'
						order location_id year_id sex_id age_group_id cause_id
						sort age_group_id	
						
						tempfile `acause'
						save ``acause'', replace
				}
				
			// Make a dataset that contains PAF draws equal to 1 for drug use disorders because this is a 100% attributable cause(i.e. all of drug use disorders are due to drugs)
				if regexm("`acause'", "mental") {
					clear 
					local ages 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21
					local n_obs: word count `ages'
					set obs `n_obs'
					
					** Make variables
					gen age_group_id = .
					forvalues i = 1/`n_obs' {
						local value: word `i' of `ages'
						replace age_group_id = `value' in `i'
						
					}
					forvalues d = 0/999 {
						gen draw_`d' = 1
					}
					gen location_id = `iso3'
					gen year_id = `year'
					gen sex_id = `sex'
					
					if "`acause'" == "mental_drug_opioids" { 
						gen cause_id = 562
					}

					if "`acause'" == "mental_drug_cocaine" { 
						gen cause_id = 563
					}

					if "`acause'" == "mental_drug_amphet" {
						gen cause_id = 564
					}

					if "`acause'" == "mental_drug_cannabis" { 
						gen cause_id = 565
					}

					if "`acause'" == "mental_drug_other" {
						gen cause_id = 566 
					}
					
					tempfile `acause'
					save ``acause'', replace
				}
			}
	

		// Combine all causes 
		clear
		foreach acause of local causes  {
			append using ``acause''
		}

		//keep age acause draw*
		drop measure_id model_version_id
	
		gen rei_id = 103 
		replace modelable_entity_id = 8798

		drop acause 
		
		tempfile ready 
		save `ready', replace

		// Apply same PAF to both YLLs and YLDs, but must save separate files for central machinery
		foreach mortype in yll yld {

			use `ready', clear 
			keep if year_id == `year'
			renpfix draw paf
			order age_group_id rei_id location_id sex_id cause_id modelable_entity_id paf_* 
			sort age_group_id rei_id location_id sex_id cause_id modelable_entity_id paf_*

			outsheet using "`out_dir'/paf_`mortype'_`iso3'_`year'_`sex'.csv", comma replace
		}
	}
	
		
