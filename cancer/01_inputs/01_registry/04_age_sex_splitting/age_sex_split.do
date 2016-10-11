
// Purpose:	Splits metric age or sex groups to match GBD cancer estimation groups
/
** **************************************************************************
** CONFIGURATION  (AUTORUN)
** 		Define J drive location. Sets application preferences (memory allocation, variable limits). 
** **************************************************************************
	// Clear memory and set STATA to run without pausing
		clear all
		set more off
		set maxvar 32000

** ****************************************************************
** SET FORMAT FOLDERS and START LOG (if on Unix) (AUTORUN)
** 		Sets output_folder, archive_folder, data_folder
** 
** ****************************************************************
	// Define load_common function depending on operating system. Load common will load common functions and filepaths relevant for registry intake
		if c(os) == "Unix" local load_common = "/ihme/code/cancer/cancer_estimation/01_inputs/_common/set_common_reg_intake.do"
		else if c(os) == "Windows" local load_common = "J:/WORK/07_registry/cancer/01_inputs/_common/set_common_reg_intake.do"

	// Accept Arguments
		args group_folder data_name data_type

	// Create Arguments if Running Manually
	if "`group_folder'" == "" {
		local group_folder = "TUR"
		local data_name = "TUR_provinces_2002_2008"
		local data_type = "inc"
	}

	// Load common settings and default folders. N
		do `load_common' 0 "`group_folder'" "`data_name'" "`data_type'"

	// set folders
		local data_folder = r(data_folder)
		local metric = r(metric)
		local temp_folder = r(temp_folder)

	// set output_filename
		local output_filename = "04_age_sex_split_`data_type'"

	// Cause Map, Age Formats, and Weights
		local cause_map "$cancer_storage/01_inputs/_parameters/mapping/map_cancer_`data_type'.dta"
		local age_format_folder "$s/age_sex_splitting/maps"
		local acause_wgts = "$j/WORK/07_registry/cancer/01_inputs/programs/age_sex_splitting/data/weights/acause_age_weights_`data_type'.dta"

** *******************************************************************
** Check for Data Exception
**		data sources for which some data loss has been determined acceptable 
** *******************************************************************
	local exception_list = "FIJI_NCR_1995_2010"
	local data_exception = 0
	foreach entry in `exception_list' {
		if "`data_name'" == "`entry'" local data_exception = 1
	} 

** ****************************************************************
** Get Additional Resources
** ****************************************************************
// Get age formats
	// Im_frmat
		insheet using "`age_format_folder'/cancer_im_frmat.csv", comma names clear
		tempfile im_frmat_map
		save `im_frmat_map', replace
	
	// Frmat
		insheet using "`age_format_folder'/cancer_frmat.csv", comma names clear
		tempfile frmat_map
		save `frmat_map', replace
	
// Get age-sex restrictions
	use "$j/WORK/00_dimensions/03_causes/causes_all.dta", clear
	// Keep relevant data
		keep if cause_version==2 
		keep cause cause_level acause male female *age_start *age_end
		if "`data_type'" == "mor" {
			drop yld_*
			rename (yll_age_start yll_age_end) (age_start age_end)
		}
		if "`data_type'" == "inc" {
			drop yll_*
			rename (yld_age_start yld_age_end) (age_start age_end)
		}
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

** ****************************************************************
** If Population Needs to be Split, Split Population
**
** ****************************************************************
	// Get data
		use "`data_folder'/01_standardized_format_`data_type'_pop.dta", clear
		
	// check for missing population. if population is missing, save and exit
		count
		if r(N) == 1 & pop1 == . {
			save "`output_folder'/04_age_sex_split_`data_type'_pop.dta", replace
			if "`data_name'" != "incidence_weights_pop" {
				// SAVE
					compress
					save "`r(output_folder)'/`output_filename'_pop.dta", replace
					save "`r(archive_folder)'/`output_filename'_pop_$today.dta", replace
					save "`r(permanent_copy)'/`output_filename'_pop.dta", replace
			}
		} 
		else {
		
		// if data exists, edit the population data storage type 
			recast double pop*
		
			
		// // Determine if age-splitting is needed on population
			preserve
				local age_split_pop = 0
				keep im_frmat_pop frmat_pop
				duplicates drop
				count if !inlist(frmat_pop, 1, 2, 3, 131) | !inlist(im_frmat_pop, 1, 2, 8, 9) 
				if `r(N)' > 0 local age_split_pop = 1
			restore
			
			// If data are present for "age unknown", then those data needs to be split.
				count if pop26 != 0 & pop26 != .
				if r(N) > 0 local age_split_pop = 1
			
			// If data are present for "sex unknown" or "both sex", then those data needs to be split.
				count if !inlist(sex, 1, 2)
				if r(N) > 0 local age_split_pop = 1
			
			if `age_split_pop' == 1 do "$j/WORK/07_registry/cancer/01_inputs/programs/age_sex_splitting/code/split_population.do" `temp_folder' `data_folder' `data_name' `data_type' "no"
			
			// Save if no split is needed
			else {
				// replace missing data with zeros
				foreach n of numlist 3/6 23/26 91/94{
					capture gen pop`n' = 0
					replace pop`n' = 0 if pop`n' == .
				}
			
				// Collapse remaining under5 and 80+ ages
				gen under5 = pop2 + pop3 + pop4+ pop5+ pop6 + pop91 + pop92 + pop93 + pop94
				gen eightyPlus =  pop22 + pop23 + pop24+ pop25
				replace pop2 = under5
				replace pop22 = eightyPlus
				drop pop3 pop4 pop5 pop6 pop23 pop24 pop25 pop26 pop91 pop92 pop93 pop94
				drop under5 eightyPlus
			
				// update frmat and im_frmat to reflect changes
				replace frmat_pop = 131
				replace im_frmat_pop = 9
				recast float pop*
				
				// Save
				sort source iso3  location_id national gbd_iteration NID sex subdiv registry year_start year_end
			
			// SAVE
				compress
				save "`r(output_folder)'/`output_filename'_pop.dta", replace
				save "`r(archive_folder)'/`output_filename'_pop_$today.dta", replace
				save "`r(permanent_copy)'/`output_filename'_pop.dta", replace
			}
		}	
		
** ****************************************************************
** If Cases/Deaths Need to be Split, Split Cases/Deaths
** 
**
** ****************************************************************
	** ****************************************************************
	** Part 1: Determine if split is necessary
	** ****************************************************************
		// Get data
			use "`input_folder'/03_mapped_`data_type'.dta", clear
			recast double `metric'* 
		
		// Add missing age categories	
			foreach n of numlist 3/6 23/26 91/94{
				capture gen double `metric'`n' = 0
			}
			
		// // DETERMINE IF AGE-SPLITTING IS NEEDED on metrics		
			// Determine if non-standard age formats are present. Frmat 9 is handled by "age unknown" section, hence is not considered in "non-standard".
				local nonStandard_ageFormat = 0
				count if  !inlist(frmat_`data_type', 1, 2, 9, 131) | (!inlist(im_frmat_`data_type', 1, 2, 8, 9) & frmat_`data_type' != 9)
				if r(N) > 0 local nonStandard_ageFormat = 1
				
			// Determine if data are present for "age unknown"
				local age_unknown_data = 0
				count if !inlist(`metric'26, 0, .)
				if r(N) local age_unknown_data = 1
				
			// Determine if data are present for aggregate sex
				local aggregate_sex = 0
				// drop "both sex" data if data for individual sexes are present
				bysort location* registry NID cause* year* coding frmat im_frmat: egen has_dif_sex = count(sex) if sex == 1 | sex == 2
				drop if sex == 3 & !inlist(has_dif_sex, 0 , .)
				drop has_dif_sex
				// count
				count if sex == 3 | sex == 9
				if r(N) > 0 local aggregate_sex = 1
				
		// // Save if no split is needed
		if !`nonStandard_ageFormat' & !`age_unknown_data' & !`aggregate_sex' {
			// replace missing data with zeros
			foreach n of numlist 3/6 23/26 91/94{
				replace `metric'`n' = 0 if `metric'`n' == .
			}
			
			// recalculate metric totals
			drop `metric'1
			egen `metric'1 = rowtotal(`metric'*)
			
			// Collapse remaining under5 and 80+ ages
			gen under5 = `metric'2 + `metric'3 + `metric'4+ `metric'5+ `metric'6 +`metric'91 + `metric'92 +`metric'93 + `metric'94
			gen eightyPlus =  `metric'22 + `metric'23 + `metric'24+ `metric'25
			replace `metric'2 = under5
			replace `metric'22 = eightyPlus
			drop `metric'3 `metric'4 `metric'5 `metric'6 `metric'23 `metric'24 `metric'25 `metric'26 `metric'91 `metric'92 `metric'93 `metric'94
			drop under5 eightyPlus
			
			// update frmat and im_frmat to reflect changes
			replace frmat_`data_type' = 131
			replace im_frmat_`data_type' = 9
			
		// SAVE
			compress
			save "`r(output_folder)'/`output_filename'.dta", replace
			save "`r(archive_folder)'/`output_filename'_$today.dta", replace
			save "`r(permanent_copy)'/`output_filename'.dta", replace

			capture log close
			exit, clear
		}
		
	** ****************************************************************
	** Part 2: Create Custom Weights if necessary
	** ****************************************************************	
	// // Replace blank cause entries: used to merge data, removed at end of script
		replace cause = cause_name if cause == ""
		replace gbd_cause = "_gc" if gbd_cause == ""
		
		// Save unique identifiers and cases1/deaths1 for later
			gen obs = _n
			preserve
				keep iso3 subdiv location_id national source NID registry gbd_iteration year_start year_end coding_system cause cause_name gbd_cause obs acause* `metric'1
				rename `metric'1 preSplit_`metric'1
				tempfile UIDs
				save `UIDs', replace
			restore
			
			keep obs cause gbd_cause acause* location_id iso3 registry year* sex frmat_`data_type' im_frmat_`data_type' `metric'*
			
		// Save a copy of the data to be used later
			tempfile beforeCustom
			save `beforeCustom', replace

	// // // Make custom weights by multiplying the global cancer rate by the population of the data
		// Keep only data used in creating weights. Preserve the mapped cause and other datum information to be re-attached later
			replace acause1 = gbd_cause if acause1 == "." | acause1 == ""
			keep obs location_id iso3 registry year* sex cause acause* gbd_cause
			duplicates drop
		
		// Reshape so that weights will merge with all associated causes. Drop associated causes that are blank
			replace acause1 = gbd_cause if acause1 == ""
			reshape long acause@, i(obs location_id iso3 registry year* sex cause) j(seq)
			capture _strip_labels*
			replace acause = "" if acause == "."
			drop if acause == ""
		
		// for sex=3 data, add sex =1 and sex =2  so that weights can be created
		if `aggregate_sex' == 1 {
			preserve
				keep if sex == 3
				tempfile unknown_sex
				save `unknown_sex', replace
			restore
			replace sex = 2 if sex == 3
			append using `unknown_sex'
			replace sex = 1 if sex == 3
			append using `unknown_sex'
		}
		
		// Create a special map so that garbage codes with alternate causes might be merged with weights
			preserve 
				use `cause_map', clear
				keep if regexm(coding_system, "ICD")
				keep cause gbd_cause 
				rename (cause gbd_cause) (acause mapped_cause)
				tempfile map_extra_acauses
				save `map_extra_acauses', replace
			restore
		
		// Adjust the temporary acause based on the map to enable merge with weights
			merge m:1 acause using `map_extra_acauses', keep(1 3)
			replace acause = mapped_cause if _merge == 3 & !regexm(acause, "neo_")
			replace acause = "neo_leukemia" if regexm(acause, "neo_leukemia")
			drop mapped_cause _merge
		
		// Merge weights file with remaining dataset. Replace any acause entries that failed to merge with "average_cancer"
			merge m:1 sex acause using `acause_wgts', keep(1 3)
			egen rate_tot = rowtotal(*rate*)
			replace acause = "average_cancer" if rate_tot == 0 | _merge == 1
			drop *rate* _merge rate_tot
			duplicates drop
			merge m:1 sex acause using `acause_wgts', keep(1 3) nogen
			if "`data_type'" == "inc" rename inc_rate* rate*
			else rename death_rate* rate*
					
		// Replace empty entries with "0", multiply  and collapse weigths to be cause & sex specific
			foreach var of varlist rate* {
				replace `var' = 0 if `var' == .	
			}
				
		// // merge with population data
			merge m:1 location_id iso3 registry sex year* using "`output_folder'/04_age_sex_split_`data_type'_pop.dta", keep(1 3)
			keep obs location_id iso3 registry sex cause year* rate* pop* _merge
			drop pop1
			egen pop1 = rowtotal(pop*)
			
			// use envelope population to create weights if population data is not provided
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
					use "$j/WORK/07_registry/cancer/00_common/data/all_populations_data.dta", clear
					keep location_id iso3 year sex pop age 
					reshape wide pop, i(location_id iso3 year sex) j(age)
				
					// ensure that sex = 3 population is present if aggregate sex is present
					if `aggregate_sex' == 1 {	
						preserve
							drop if sex == 3
							replace sex = 3
							collapse(sum) pop*, by(location_id iso3 year sex)
							tempfile both_sex_pop
							save `both_sex_pop'
						restore
						append using `both_sex_pop'
					}
					// save pop data
					tempfile pop_data
					save `pop_data', replace
					
					// merge 
					use `no_pop', clear
					gen orig_sex = sex
					replace sex = 3 if sex == 9
					merge m:1 location_id year sex using `pop_data', keep(1 3) 
					replace sex = orig_sex
					drop orig_sex
					
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
							assert !r(N) 
							drop _merge
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
		
		// make weights (weights = the expected number of deaths = rate*pop)
			foreach n of numlist 2 7/22 {
				gen double wgt`n' = rate`n'*pop`n'
			}	
		
		// Collapse the weights for each case to equal the sum of the weights. 
			collapse (mean) wgt*, by(obs location_id iso3 registry sex year* cause) fast
		
		// keep only the necessary variables
			keep obs sex cause wgt*
			duplicates tag obs sex cause, gen(tag)
			count if tag >1
			if r(N) > 0 {
				pause on
				di "error. duplicates exist when they should not"
				pause
				pause off
			}
			drop tag
		
		// reshape
			reshape long wgt@, i(obs sex cause) j(gbd_age)		
		
		// Save
			tempfile cause_wgts
			save `cause_wgts', replace
			
		// // Add weights for additional sexes if sex=3 data exists, since weights may have only merged onto sex=3 data for a given obs 
		if `aggregate_sex' == 1 {			
			// reshape to facilitate recalculation	
			reshape wide wgt@, i(cause obs gbd_age) j(sex)
			
			// if there is no sex = 3 data for a given cause, then there is no need to calculate sex split weights for that cause. 
			capture rename wgt9 wgt3
			drop if wgt3 == .
			collapse wgt*, by(cause gbd_age)
			
			// regenerate wgt for sex = 3. 
			drop wgt3
			gen wgt3 = wgt1 + wgt2
			
			// recalculate weights for sex=1 and sex =2 as their proportions of the total number of deaths (weight for sex =3)
			replace wgt1 = wgt1/wgt3
			replace wgt2 = wgt2/wgt3
			replace wgt1 = 0 if wgt1 == .
			replace wgt2 = 0  if wgt2 == .
			
			// drop weights for sex =3. save the data so that they can be joined with sex = 3 data and split it into two sexes
			drop wgt3
			reshape long wgt@, i(cause gbd_age) j(sex)
			rename sex new_sex
			gen sex = 3
			
			// save
				tempfile sex_split_wgts
				save `sex_split_wgts', replace	
		}
		
	** ****************************************************************
	** Part 3: Split age and sex
	** ****************************************************************
		// restore pre-custom data
			use `beforeCustom', clear
			
		// preserve total deaths for testing
			capture summ(`metric'1)
			local pre_split_total = r(sum)
		
		// prepare data for editing
			keep obs cause sex frmat_`data_type' im_frmat_`data_type' `metric'* 
			rename `metric'1 metric_total
			reshape long `metric', i(obs cause sex frmat_`data_type' im_frmat_`data_type' metric_total) j(age)
			capture _strip_labels*
			
		// // Split	
		if `nonStandard_ageFormat' == 1 {
			// rename age formats to enable merge
				rename (im_frmat_`data_type' frmat_`data_type') (im_frmat frmat)
			
			// mark those entries that need to be split. Do not split if frmat == 9 (unknown age)
				gen need_split = 1 if  !inlist(frmat, 1, 2, 9, 131) | (!inlist(im_frmat, 1, 2, 8, 9) & frmat != 9)
				replace need_split = 0 if need_split != 1
			
			// for each format type, mark which age categories need to be split per the corresponding format map. split only those categories. can split multiple age formats at once 
			foreach format_type in im_frmat frmat {
				// preserve a copy in case split cannot be performed
				preserve
				
				// merge with map and reshape
					if "`format_type'" == "im_frmat" merge m:1 im_frmat age using `im_frmat_map', keep(1 3)
					if "`format_type'" == "frmat" merge m:1 frmat age using `frmat_map', keep(1 3)
					reshape long age_specific@, i(obs cause sex frmat im_frmat age `metric' need_split _merge) j(age_split_num)
				
				// keep one copy of each entry (for totals) and keep one copy each for the new categories created in the split
					keep if (_merge == 1 & age_split_num == 1) | (_merge == 3 & age_specific != .)
				
				// mark those data that need to be split. skip to next format if no split can occur
					replace need_split = 0 if _merge == 1
					count if need_split == 1
					if `r(N)' == 0 {
						restore
						continue
					}
					else restore, not
					
				
				// edit age formats and rename to enable merge with weights
					gen gbd_age = (age_specific / 5) + 6 if _merge == 3 & age_specific >= 5
					replace gbd_age = 2 if _merge == 3 & age_specific < 5
					rename _merge _merge_`format_type'
				
				// add weights
					merge m:1 obs sex cause gbd_age using `cause_wgts', keep(1 3) nogen
					egen double wgt_tot = total(wgt), by(obs cause sex `format_type' age)
					replace wgt = 1 if wgt_tot == 0 | wgt_tot == . & need_split == 1
					replace wgt = 0 if wgt == . & need_split == 1
					egen double wgt_scaled = pc(wgt), by(obs cause sex `format_type' age) prop
				
				
				// replace only those weights that are marked to be split	
					replace `metric' = wgt_scaled * `metric' if need_split == 1
					replace age = gbd_age if need_split == 1
				
				// collapse, then update format types of split data
					keep `metric' obs cause sex frmat im_frmat age
					collapse (sum) `metric', by(obs cause sex frmat im_frmat age) fast
			}
			
			// rname age formats to original name
				rename (im_frmat frmat) (im_frmat_`data_type' frmat_`data_type') 
				replace im_frmat_`data_type' = 9 
				replace frmat_`data_type' = 131 if frmat_`data_type' != 9
			
			// save copy in case of troubleshooting		
				tempfile afterFrmat
				save `afterFrmat', replace
		}
		
		// Ensure that remaining under5 and 80+ ages are collapsed
			// Alert user if data remains in under1 age groups
				foreach n of numlist 91/94 {
					count if age == `n' & `metric' != 0
					if r(N) > 0 {
						noisily di in red "Error in im_frmat. `metric' data still exist in `metric'`n' after age/sex split"
						BREAK
					}
				}
			
			// combine under5 and 80+
			bysort obs cause sex: egen under5 = total(`metric') if inlist(age, 2, 3, 4, 5, 6, 91, 92, 93, 94)
			replace `metric' = under5 if age == 2
			bysort obs cause sex: egen eightyPlus = total(`metric') if inrange(age, 22, 25)
			replace `metric' = eightyPlus if age == 22
			drop if inlist(age, 3, 4, 5, 6, 23, 24, 25, 91, 92, 93, 94)
			drop under5 eightyPlus
		
		// // // Redistribute "unknown age" data according to the current distribution of cases/deaths
		if `age_unknown_data' == 1 {
			// Remove age-category indication for "unknown age" data
			preserve
				keep obs cause sex im_frmat_`data_type' frmat_`data_type' age `metric'
				keep if age == 26
				rename `metric' unknown_age_`metric'
				drop age
				tempfile unknown_age_data
				save `unknown_age_data', replace
			restore
			
			// // Recombine data with "unknown age" data
				// Merge with custom weights, calculate weights according to the percent composition of cases/deaths by age category, and redistribute "unknown age" data by weight type (custom or percent composition)
				drop if inlist(age, 1, 26)
				merge m:1 obs sex im_frmat_`data_type' frmat_`data_type' using `unknown_age_data', assert(3) nogen
				
				// add custom weights where indicated. for datasets with `sex_unknown' data, ignore sex = 1 or sex = 2 data from unknown_age_wgts (hence assert(2 3) below)
				rename age gbd_age
				merge m:1 obs sex cause gbd_age using `cause_wgts', keep(1 3) assert(2 3) nogen
				rename gbd_age age
				
				// calculate redistributed values and replace cases/deaths with that value
				egen double total_wgt = total(wgt), by(obs sex im_frmat frmat)
				egen double wgt_pc = pc(wgt), by(obs sex im_frmat frmat) prop
				replace wgt = 1 if total_wgt == 0 | total_wgt == .
				gen double distributed_unknown = unknown_age_`metric' * wgt_pc
				replace distributed_unknown = 0 if distributed_unknown == .
				
				// add redistributed data to the rest of the data
				replace `metric' = `metric' + distributed_unknown
				keep obs cause sex im_frmat_`data_type' frmat_`data_type' age `metric'
				replace frmat_`data_type' = 131
				tempfile redistributed_unknown_metric
				save `redistributed_unknown_metric', replace
		}
		
		// // Split Sex = 3 and sex = 9 data
		local percentage_sex_split = 0
		if `aggregate_sex' == 1 {
			tempfile full_dataset
			save `full_dataset', replace
			
			local firstLoop = 1
			foreach sexNum of numlist 3 9 {
				use `full_dataset', clear
				
				// keep only the sex of interest. exit loop if the sex is not present
					count if sex == `sexNum'
					if !r(N) continue
					local percentage_sex_split = r(N)/_N
					keep if sex == `sexNum'
					
				// reformat sex = 9 data to enable merge
					replace sex = 3 if sex == `sexNum'
				
				// merge with weights
					rename age gbd_age
					joinby gbd_age sex cause using `sex_split_wgts'
					rename gbd_age age
				
				// if/where sex = 3 remains, replace values
					replace `metric' = wgt * `metric' if sex == 3 
					replace sex = `sexNum'
					keep obs cause sex new_sex im_frmat_`data_type' frmat_`data_type' age `metric'
					
				// reshape to enable later merge
					reshape wide `metric', i(obs cause sex new_sex im_frmat_`data_type' frmat_`data_type') j(age)
				
				// append and/or save
					if `firstLoop' == 1 {
						tempfile sex_disaggregated
						local firstLoop = 0
					}
					else append using `sex_disaggregated'
					save `sex_disaggregated', replace
			}
			// restore the full dataset
					use `full_dataset', clear
		}
		
		// save a copy for troubleshooting
		tempfile redistributed
		save `redistributed', replace
		
		
	** ****************************************************************
	** Part 4: Finalize
	** ****************************************************************		
		// Reshape
			reshape wide `metric', i(obs cause sex) j(age)
			merge m:1 obs using `UIDs', assert(3) nogen
			
			// add disaggregated sex
			if `aggregate_sex' == 1 {
				foreach m of varlist `metric'* {
					replace `m' = . if inlist(sex, 3, 9)
				}
				merge 1:m obs using `sex_disaggregated', update keep(1 3 4) assert(1 3 4) nogen				
				replace sex = new_sex if !inlist(sex, 1, 2)
				drop new_sex
				drop if sex == .
			}
		
		// Check for errors. If more than 3 metric totals are greater than .0001% different from the original number, alert the user
			// check rowtotals
			egen postSplit_`metric'1 = rowtotal(`metric'2-`metric'22)
			capture count if abs(postSplit_`metric'1 - preSplit_`metric'1) > .000001*preSplit_`metric'1 if inlist(sex, 1, 2)
			if r(N) > 3 & `data_exception' != 1 {
				pause on
				display in red "Error: total `metric' are not equivalent in all rows before and after split" 
				gen diff_pre_post = abs(postSplit - preSplit)
				gsort -diff_pre_post
				pause
				drop diff_pre_post
				pause off
			}	
			drop preSplit_`metric'1 postSplit_`metric'1
			
			// test sum of all deaths/cases
			egen `metric'1 = rowtotal(`metric'*)
			capture summ(`metric'1)
			local delta = abs(r(sum) - `pre_split_total')
			if (`delta' > 0.00005 * `pre_split_total' & `percentage_sex_split' < .75) | (`delta' > 0.005 * `pre_split_total' & `percentage_sex_split' >= .75)  {
				noisily di in red "ERROR: Total `metric' before disaggregation does not equal total after (`delta' `metric')."
				BREAK
			}
			
		// Remove causes that were added earlier in the script 
			replace cause = "" if cause == cause_name	
		
		// collapse dataset
			collapse (sum) `metric'* , by(location iso3 subdiv registry national gbd* source NID year* coding cause* acause* sex)
			
		// Replace frmat and im_frmat variables to reflect current status
			capture drop `metric'26
			gen frmat_`data_type' = 131
			gen im_frmat_`data_type' = 9
			recast float `metric'* 
			aorder
		
		// SAVE
			compress
			save "`r(output_folder)'/`output_filename'.dta", replace
			save "`r(archive_folder)'/`output_filename'_$today.dta", replace
			save "`r(permanent_copy)'/`output_filename'.dta", replace
					

	capture log close

** **************************************************************************
** END age_sex_split.do
** **************************************************************************
