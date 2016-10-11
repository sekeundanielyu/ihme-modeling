
// Purpose:	Disaggregates observations for which multiple gbd cause (acause) are assigned (generally only garbage codes). Redistributes the aggregate number of cases/deaths among those separated observations.
 
** **************************************************************************
** CONFIGURATION (autorun)
** 		Sets application preferences (memory allocation, variable limits) 
** 		Accepts/Sets Arguments. Defines the J drive location.
** **************************************************************************
// Clear memory and set memory and variable limits
	clear all
	set mem 5G
	set maxvar 32000
	set more off

// Accept Arguments
	args group_folder data_name data_type 	
	
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"	
	
// Create Arguments when Running Manually
	local troubleshooting = 0
	if "`group_folder'" == "" {
		local group_folder = "USA"
		local data_name = "USA_NPCR_1999_2011"
		local data_type = "inc"
		local troubleshooting = 1
		pause on
	}
		
	if "`group_folder'" != "" & "`group_folder'" != "none" local data_folder = "$j/WORK/07_registry/cancer/01_inputs/sources/`group_folder'/`data_name'"  // autorun
	else local data_folder = "$j/WORK/07_registry/cancer/01_inputs/sources/`data_name'"  // autorun

** ****************************************************************
** Set Macros
**	Data Types, Folder and Script Locations
** ****************************************************************
// Metric Name (cases or deaths)
	if "`data_type'" == "inc" local metric_name = "cases"
	if "`data_type'" == "mor" local metric_name = "deaths"

// Input Folder
	local input_folder = "`data_folder'/data/intermediate"

// Output folder
	local output_folder "`data_folder'/data/intermediate"
	local archive_folder "`output_folder'/_archive"
	capture mkdir "`output_folder'"
	capture mkdir "`archive_folder'"

// Age Format Folder
	local age_format_folder "$j/WORK/07_registry/cancer/01_inputs/programs/age_sex_splitting/maps"
	local acause_rates = "$j/WORK/07_registry/cancer/01_inputs/programs/age_sex_splitting/data/weights/acause_age_weights_`data_type'.dta"

// SCC/BCC Proportions	
	local scc_bcc_proportions = "$j/WORK/07_registry/cancer/01_inputs/programs/acause_disaggregation/maps/scc_bcc_proportions.dta"
	
// GBD Cancer Map
	local full_cancer_map = "$j/WORK/07_registry/cancer/01_inputs/programs/mapping/data/map_cancer_`data_type'.dta"

** ****************************************************************
** Get Additional Resources
** ****************************************************************
// Add GBD codes as ICD codes in the cause map
	use `full_cancer_map', clear
	keep if coding_system == "GBD"
	replace cause = cause_name
	replace coding_system = "ICD10"
	tempfile GBD_codes
	save `GBD_codes', replace
	replace coding_system = "ICD9_detail"
	append using `GBD_codes'
	save `GBD_codes', replace
	use `full_cancer_map', clear
	keep if regexm(coding_system, "ICD")
	append using `GBD_codes'
	tempfile cancer_map
	save `cancer_map', replace

// Get cause map. Note: all alternate causes should be gbd_causes or ICD10 codes
	use `cancer_map', clear
	keep cause coding_system gbd_cause acause1 acause2
	tempfile cause_map
	save `cause_map', replace

// Get wgt_cause map
	use `cancer_map', clear
	keep cause gbd_cause coding_system
	rename (cause gbd_cause) (wgt_cause mapped_cause)
	tempfile wgt_cause_map
	save `wgt_cause_map', replace
	
// Get cause weights
	use `acause_rates', clear
	if "`data_type'" == "inc" rename inc_rate* rate*
	else rename death_rate* rate*
	rename acause wgt_cause
	tempfile cause_rates
	save `cause_rates', replace

// Get Kaposi sarcoma proportions
	use "$j/WORK/03_cod/01_database/02_programs/hiv_correction/rdp_proportions/data/hiv_rdp_props.dta", clear
	keep if p_reg == 1 // global proportions
	keep if regexm(cause, "C46")
	rename (target prop3) (gbd_cause prop2)
	replace cause = substr(cause, 1, 3) + "." + substr(cause, 4, .) if strlen(cause) >3
	gen start_year_range = substr(year_range, 1, 4)
	gen end_year_range = substr(year_range, -4, .)
	destring start end, replace
	keep sex cause gbd_cause start end prop*
	duplicates drop
	tempfile kaposi_proportions
	save `kaposi_proportions', replace
		
** **************************************************************************
** Disaggregate 
** **************************************************************************	
	// Get Data
		use "`input_folder'/04_age_sex_split_`data_type'.dta", clear
		
	// Change coding system
		replace coding_system = "ICD10" if coding_system != "ICD9_detail"
		
	// Alert if unmapped causes exist
		count if gbd_cause == "" | acause1 == ""
		if r(N) > 0 {
			di "ERROR: Missing map for causes present in the dataset"
			BREAK
		}
	
	// Calculate total metrics for later comparison
		capture drop cases_total
		capture drop deaths_total
		capture drop `metric_name'1
		egen `metric_name'1 = rowtotal(`metric_name'*)
		capture sum(`metric_name'1)
		local pre_disagg_total = r(sum)
		
	// Preserve unique identifiers (UIDs) and metric data
		// create dummy variable to enable later merge
		gen obs = _n
		preserve
			keep iso3 subdiv location_id national source NID registry gbd_iteration year_start year_end sex coding_system cause cause_name obs
			gen orig_cause = cause + cause_name
			drop cause*
			tempfile UIDs
			save `UIDs', replace
		restore
		// preserve metric data
		preserve
			keep obs `metric_name'*
			rename `metric_name'1 obs_total
			tempfile metric_data
			save `metric_data', replace
		restore
	
	// reshape data to determine the number of alternate causes. tag data with multiple acauses
		keep obs location_id iso3 registry year* sex cause acause* coding_system
		reshape long acause, i(obs sex location_id iso3 registry year* coding_system) j(acause_num)
		capture _strip_labels*
		gen wgt_cause = acause
		replace wgt_cause = cause if acause == ""
		drop if acause == ""
	
	// Merge ICD10 garbage codes with cause map
		merge m:1 wgt_cause coding_system using `wgt_cause_map', keep(1 3)
		replace wgt_cause = mapped_cause if _merge == 3
		replace wgt_cause = "average_cancer" if substr(wgt_cause, 1, 4) != "neo_"
		replace wgt_cause = "neo_leukemia" if regexm(acause, "leukemia")
		drop if mapped_cause == "_none"
		drop mapped_cause _merge
	
	// Merge rates file with remaining dataset, rename any acause entries that failed to merge as the conglomerate garbage code "average_cancer", and rename entries for which the weight total is 0. Drop the rates
		merge m:1 sex wgt_cause using `cause_rates', keep(1 3)
		egen wgt_tot = rowtotal(rate*)
		replace wgt_cause = "average_cancer" if wgt_tot == 0 & wgt_cause != "_none"
		drop _merge wgt_tot rate*
	
	// drop data that are mapped to "_none"
		drop if wgt_cause == "_none"

	// Save a copy of the data for later use
		tempfile prepared_for_merge
		save `prepared_for_merge', replace

	// // merge data with rates before merging with population data (will multiply by pop by rate to create weights)
		merge m:1 sex wgt_cause using `cause_rates', keep(1 3) assert(2 3) nogen
		merge m:1 location_id iso3 registry sex year* using "`output_folder'/04_age_sex_split_`data_type'_pop.dta", keep(1 3)
		keep location_id iso3 registry sex wgt_cause year* rate* pop* _merge
		drop pop1
		egen pop1 = rowtotal(pop*)
		duplicates drop
		
		// add use envelope population to create weights if population data is not provided
		count if _merge == 1 | pop1 == 0
		if r(N) > 0 {
			tempfile all_data
			save `all_data', replace
			
				keep if _merge == 1 | inlist(pop1, 0, .)
				drop _merge pop*
				// create an average year variable with which envelope population can be merged. If data spans more than one year, population for the year average will be used
				gen year = floor((year_start+year_end)/2)
				tempfile no_pop
				save `no_pop', replace
				
				// Get  population by location_id
				if "`runQuery'" == "yes" do "$j/WORK/07_registry/cancer/00_common/code/get_pop_and_env_data.do"
				else use "$j/WORK/07_registry/cancer/00_common/data/all_populations_data.dta", clear 
				keep location_id iso3 year sex pop age 
				reshape wide pop, i(location_id iso3 year sex) j(age)
				tempfile pop_data
				save `pop_data', replace
				
				// merge 
				use `no_pop', clear
				merge m:1 location_id year sex using `pop_data', keep(1 3) 
				
				// In the event that subnational populations have not yet been added to the database, use national population. Alert user if data still doesn't merge
				count if _merge == 1
				if r(N) > 0 {
					preserve
						use `pop_data', clear
						keep if location_id < 300
						tempfile national_only
						save `national_only', replace
					restore
					preserve
						keep if _merge == 1
						drop _merge
						merge m:1 iso3 year sex using `national_only', keep(1 3)
						count if _merge == 1 & sex != 9 & iso3 != "FRO"
						drop _merge
						if r(N) > 0 {
							di in red "Error during population merge."
							BREAK
						}
						tempfile iso3_merge
						save `iso3_merge', replace
					restore
				}
				drop if _merge == 1
				capture append using `iso3_merge'
				drop year _merge
				
				// save tempfile
				tempfile added_pop
				save `added_pop', replace
				
			use `all_data', clear
			drop if _merge == 1 | pop1 == 0
			append using `added_pop'
		}		
		drop _merge
	
	// make weights
		foreach n of numlist 2 7/22 {
			gen wgt`n' = rate`n'*pop`n'
			replace wgt`n' = 0 if wgt`n' == .
		}
		drop rate* pop*
		tempfile cause_wgts
		save `cause_wgts', replace
		
	// use weights to distribute aggregate totals among the alternate causes for each observation
		use `prepared_for_merge', clear
		sort obs
		merge m:1 obs using `metric_data', assert(3) nogen
		duplicates tag obs, gen(need_split)
		replace need_split = 1 if need_split > 0
		merge m:1 location_id year* sex registry wgt_cause using `cause_wgts', keep(1 3) nogen
		foreach i of numlist 2 7/22 {
			gen orig_`metric_name'`i' = `metric_name'`i'
			egen wgt_tot`i' = total(wgt`i'), by(obs)
			replace wgt`i' = 1 if need_split == 1 & wgt_tot`i' == 0
			egen wgt_scaled`i' = pc(wgt`i'), by(obs) prop
			replace `metric_name'`i' = `metric_name'`i' * wgt_scaled`i' if need_split == 1
		}
		// verify calculations
		egen double row_total = rowtotal(`metric_name'*)
		bysort obs: egen new_obs_total = total(row_total)
		gen diff = new_obs_total - obs_total
		count if abs(diff) > 1
		if r(N){
			noisily di "ERROR: New observation total does not equal original at full disaggregation step"
			aorder
			if `troubleshooting' pause
			else BREAK
		}
		
		// drop extra variables
		drop wgt* need_split row_total new_obs_total orig_`metric_name'* diff
		
	// Specially Handle Kaposi Sarcoma Data
		// merge with kaposi sarcoma weights. this will create multiple copies of each obs (location, year, sex, cause...)
			joinby sex cause using `kaposi_proportions', unmatched(master)
		// keep the obs copies with data years that match the proportion years (if no data matches the proportion years, keep one copy and do nothing)
			gen year = floor((year_start+ year_end)/2)
			bysort obs: gen any_match = 1 if _merge == 3 & inrange(year, start, end)
			bysort obs: egen has_match = total(any_match) if _merge == 3
			bysort obs: gen single_entry = _n == 1 if _merge == 3 & has_match == 0
			drop if _merge == 3 & (has_match > 0 & !inrange(year, start, end) ) | (has_match == 0 & single_entry == 0)
			foreach i of numlist 2 7/22 {
				gen orig_`metric_name'`i' = `metric_name'`i'
				replace prop`i' = . if has_match == 0
				replace `metric_name'`i' = `metric_name'`i' * prop`i' if _merge == 3 & has_match > 0
			}
		// replace redistributed causes
		replace acause = gbd_cause if _merge == 3 & has_match > 0
		replace acause = "C46" if substr(acause, 1, 3) == "C46" & strlen(acause) <= 6
		
		// verify calculations
		egen double row_total = rowtotal(`metric_name'*)
		bysort obs: egen new_obs_total = total(row_total)
		gen diff = new_obs_total - obs_total
		count if abs(diff) > 1
		if r(N){
			noisily di "ERROR: New observation total does not equal original at Kaposi disaggregation step"
			aorder
			if `troubleshooting' pause
			else BREAK
		}
		
		// drop extra variables
		drop _merge prop* any_match has_match gbd_cause row_total new_obs_total orig_`metric_name'* diff
		
	// If incidence data only, specially handle NMSC garbage 
		if "`data_type'" == "inc" {
			// adjust bcc_scc map
			preserve	
				use `scc_bcc_proportions', clear
				rename (acause cause) (mapped_cause acause)
				tempfile sb_props
				save `sb_props', replace 
			restore

			// merge with bcc_scc map
				joinby sex acause using `sb_props', unmatched(master)
			// multiply by proportions
				foreach i of numlist 2 7/22 {
					gen orig_`metric_name'`i' = `metric_name'`i'
					replace `metric_name'`i' = `metric_name'`i' * prop`i' if _merge ==3
				}
				
			// verify calculations
				egen double row_total = rowtotal(`metric_name'*)
				bysort obs: egen new_obs_total = total(row_total)
				gen diff = new_obs_total - obs_total
				count if abs(diff) > 1
				if r(N){
					noisily di "ERROR: New observation total does not equal original at NMSC disaggregation step"
					aorder
					if `troubleshooting' pause
					else BREAK
				}
		
			// replace redistributed causes
				replace acause = mapped_cause if _merge == 3
				
			// drop extra variables
				drop mapped_cause _merge prop* row_total new_obs_total orig_`metric_name'* diff
		}
		
	// Map disaggregated causes to gbd causes. Preserve any ICD codes that are associated with garbage codes
		// Preserve any ICD codes that are associated with garbage codes.
			rename acause disag_cause
			replace cause = disag_cause if disag_cause != "_gc" // replaces disaggregat
			
		// prepare for merge with map
			replace cause = "zzz" if cause == "ZZZ"
			replace coding_system = "ICD10" if inlist(substr(cause, 1, 1), "C", "D") 
		
		// merge with cause map
			capture merge m:1 cause coding_system using `cause_map', keep(1 3) assert(2 3)
			if _rc {
				di "ERROR: Not all causes could be mapped"
				BREAK
			}
			
		// Verify that newly mapped codes are mapped to only one cause
		capture count if trim(acause2) != "" & | (acause1 != gbd_cause & gbd_cause != "_gc")
		if r(N) > 0 {
			keep if acause2 != "" & | acause1 != gbd_cause
			di "ERROR: Some disaggregated causes are mapped to more than one code. Please correct the map for `data_type'."
			di "(Note: only two alternate causes are currently shown. For all alternate causes, see the full map.)"
			BREAK
		}

		// rename gbd_cause and remove irrelevant variables
		rename gbd_cause acause
		drop _merge acause1 acause2

	// Recalculate totals 
		keep obs acause cause disag_cause `metric_name'*
		capture drop `metric_name'1
		egen `metric_name'1 = rowtotal(`metric_name'*)
	
	// Merge with UIDs
		merge m:1 obs using `UIDs', assert(3) nogen
			
	// Check for calculation errors
		capture sum(`metric_name'1)
		local delta = r(sum) - `pre_disagg_total'
		if `delta' > 0.00001 * `pre_disagg_total' {
			noisily di in red "ERROR: Total `metric_name' before disaggregation does not equal total after (difference = `delta' `metric_name')."
			BREAK
		}
			
	// Check for missing cause information
		capture count if cause == "" | acause == ""
		if r(N) > 0 {
			noisily di in red "ERROR: Cannot continue with missing cause information. Error in acause_disaggregation suspected."
			BREAK
		}
	
	// Collapse
		collapse (sum) `metric_name'*, by(iso3 subdiv location_id national source NID registry gbd_iteration year_start year_end sex coding_system acause cause orig_cause disag_cause) fast
		order iso3 subdiv location_id sex year_start year_end acause cause disag_cause orig_cause registry `metric_name'* gbd_iteration coding_system national source NID  
	
	// SAVE
		compress
		save "`output_folder'/05_acause_disaggregated_`data_type'.dta", replace
		capture saveold "`output_folder'/05_acause_disaggregated_`data_type'.dta", replace
		save "`output_folder'/_archive/05_acause_disaggregated_`data_type'_`today'.dta", replace
		capture saveold "`output_folder'/_archive/05_acause_disaggregated_`data_type'_`today'.dta", replace
		

	capture log close
	if `troubleshooting' pause off
	
** **************************************************************************
** END acause_disaggregation.do
** **************************************************************************
