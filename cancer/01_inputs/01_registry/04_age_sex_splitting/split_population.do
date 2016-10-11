
// Purpose:	Splits population age groups to match GBD cancer estimation age groups

** **************************************************************************
** CONFIGURATION (autorun)
** 		Sets application preferences (memory allocation, variable limits).
**		Defines the J drive location. (data)
** **************************************************************************

// Set application preferences
	// Clear memory and set memory and variable limits
		clear
		set maxvar 32000
		set more off
	
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" { 
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" global j "J:"

	// Get date
		local today = date(c(current_date), "DMY")
		local today = string(year(`today')) + "_" + string(month(`today'),"%02.0f") + "_" + string(day(`today'),"%02.0f")

** ****************************************************************
** Set Macros
**
** ****************************************************************
	// Accept Arguments
		args temp_folder data_folder data_name data_type runQuery
		
	// Create Arguments when Running Manually
		if "`group_folder'" != "" & "`runQuery'" == "" local runQuery = "no"
		if "`data_type'" == "" {
			local group_folder = "FJI"
			local data_name = "FIJI_NCR_1995_2010"
			local data_type = "inc"
			if "`group_folder'" != "" local data_folder = "$j/WORK/07_registry/cancer/01_inputs/sources/`group_folder'/`data_name'"  // autorun
			else local data_folder = "$j/WORK/07_registry/cancer/01_inputs/sources/`data_name'"  // autorun
		}
	
	// Input Folder (differs if creating weights rather than processing input data)
		if "`data_name'" == "incidence_weights_pop" {
			local data_folder = "$j/WORK/07_registry/cancer/01_inputs/programs/age_sex_splitting/data/weights/inc"
			local input_folder = "`data_folder'"
			local input_file = "`input_folder'/inc_temp_pop_only.dta"
		}
		else {
			local input_folder = "`data_folder'/data/intermediate"
			local input_file = "`input_folder'/01_standardized_format_`data_type'_pop.dta"
		}
	
	// Create temp folder
		if "`temp_folder'" == "" {
			capture mkdir "$j/temp/registry/cancer/01_inputs"
			capture mkdir "$j/temp/registry/cancer/01_inputs/`group_folder'"
			capture mkdir "$j/temp/registry/cancer/01_inputs/`group_folder'/`data_name'"
			local temp_folder = "$j/temp/registry/cancer/01_inputs/`group_folder'/`data_name'/temp_`data_type'"
			capture mkdir "`temp_folder'"
		}
		
	// Other folders
		local output_folder "`input_folder'"
		local archive_folder "`output_folder'/_archive"
		capture mkdir "`output_folder'"
		capture mkdir "`archive_folder'"
	
	// Age Formats and Weights
		local age_format_folder "$j/WORK/07_registry/cancer/01_inputs/programs/age_sex_splitting/maps"
		local weights_file = "$j/WORK/07_registry/cancer/01_inputs/programs/age_sex_splitting/data/weights/acause_age_weights_`data_type'.dta"
	
	// Incidence or mortality
		if "`data_type'" == "inc" local metric_name = "cases"
		if "`data_type'" == "inc" local metric_name_all = "cases*"
		if "`data_type'" == "mor" local metric_name = "deaths"
		if "`data_type'" == "mor" local metric_name_all = "deaths*"

** ****************************************************************
** Create log if running on the cluster
** ****************************************************************
if c(os) == "Unix" {
	// make log folder
	local log_folder "/ihme/gbd/WORK/07_registry/cancer/logs/01_inputs/age_sex_split"
	cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs"
	cap mkdir "/ihme/gbd/WORK/07_registry/cancer/logs/01_inputs"
	cap mkdir "`log_folder'"
	
	// begin log
	capture log close
	capture log using "`log_folder'/population_split_`today'.log", replace
}

** ****************************************************************
** GET ADDITIONAL RESOURCES
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
		
// Get location population
	if "`runQuery'" == "" do "$j/WORK/07_registry/cancer/00_common/code/get_pop_and_env_data.do"
	else use "$j/WORK/07_registry/cancer/00_common/data/all_populations_data.dta", clear
	
	// Make compatible age groups
	rename (pop age) (wgt gbd_age)
	keep location_id year sex wgt gbd_age
	tempfile pop_wgts
	save `pop_wgts', replace

** ****************************************************************
** SPLIT POPULATION IF NEEDED
**
** ****************************************************************
	// Get data
		use "`input_file'", clear
		
		// drop if missing population for an entire row (if there are no people then there can't be any cancer)
		drop pop1 
		egen pop1 = rowtotal(pop*), missing
		drop if pop1 == 0 | pop1 == .
		count
		if r(N) ==0 {
			save "`output_folder'/04_age_sex_split_`data_type'_pop.dta", replace
			if "`data_name'" != "incidence_weights_pop" {
				capture saveold "`output_folder'/04_age_sex_split_`data_type'_pop.dta", replace
				save "`output_folder'/_archive/04_age_sex_split_`data_type'_pop_`today'.dta", replace
				capture saveold "`output_folder'/_archive/04_age_sex_split_`data_type'_pop_`today'.dta", replace
			}
			exit, clear
		}
		
		// if data exists, edit the population data storage type 
		recast double pop*
		
		// save the dataset total for later comparison
			summ(pop1)
			local pre_split_pop = r(sum)
			
		// determine if datset contains unknown sex
			count if inlist(sex, 3, 9)
			if r(N) > 0 local split_sex = 1
			else local split_sex = 0
		
		// replace missing data with zeros
		foreach n of numlist 3/6 23/26 91/94{
			capture gen pop`n' = 0
			replace pop`n' = 0 if pop`n' == .
		}
		
	// Save UIDs (unique IDs) for later
		gen obs = _n
		preserve
			keep obs iso3 subdiv location_id national source NID registry gbd_iteration year_start year_end pop1
			rename pop1 preSplit_pop1
			tempfile uids
			save `uids', replace
		restore
		keep obs location_id year_start year_end sex frmat_pop im_frmat_pop pop*
		gen year = floor((year_start + year_end) / 2)
		drop year_start year_end

** ******************
** Split Age
** *******************		
	// Split
		reshape long pop, i(obs location_id sex year frmat_pop im_frmat_pop) j(age)
		// 
		rename (im_frmat_pop frmat_pop) (im_frmat frmat)
		foreach frmat_type in "im_frmat" "frmat" {
			// preserve a copy in case split cannot be performed
			preserve
			
			// merge with map and reshape
			if "`frmat_type'" == "im_frmat" merge m:1 `frmat_type' age using `im_frmat_map', keep(1 3) 
			else if "`frmat_type'" == "frmat" merge m:1 `frmat_type' age using `frmat_map', keep(1 3) 
			reshape long age_specific@, i(obs location_id year sex frmat im_frmat age pop need_split _merge) j(age_split_num)
			keep if (_merge == 1 & age_split_num == 1) | (_merge == 3 & age_specific != .)
			
			// mark those data that need to be split. skip to next format if no split is needed
			replace need_split = 0 if _merge == 1
			count if need_split == 1
			if `r(N)' == 0 {
				restore
				continue
			}
			else restore, not
			
			// prepare age for merge
			gen gbd_age = (age_specific / 5) + 6 if _merge == 3
			replace gbd_age = 2 if _merge == 3 & age_specific == 0
			
			// Merge with population data
			rename _merge _merge1
			merge m:1 location_id year sex gbd_age using `pop_wgts', keep(1 3)
			egen wgt_tot = total(wgt), by(obs location_id year sex frmat im_frmat age)
			replace wgt = 1 if wgt_tot == 0
			egen wgt_scaled = pc(wgt), by(obs location_id year sex frmat im_frmat age) prop
			replace pop = wgt_scaled * pop if need_split == 1
			replace age = gbd_age if need_split == 1
			//
			keep pop obs location_id year sex frmat im_frmat age
			collapse (sum) pop, by(obs location_id year sex frmat im_frmat age) fast	
		}
		drop im_frmat frmat

	// Ensure that remaining under5 and 80+ ages are collapsed
		// Alert user if data remains in under1 age groups
			foreach n of numlist 91/94 {
				count if age == `n' & pop != 0
				if r(N) > 0 {
					noisily di in red "Error in im_frmat. `metric_name' data still exist in `metric_name'`n' after age/sex split"
					BREAK
				}
			}
		
		// combine under5 and 80+
		bysort obs sex: egen under5 = total(pop) if inlist(age, 2, 3, 4, 5, 6, 91, 92, 93, 94)
		replace pop = under5 if age == 2
		bysort obs sex: egen eightyPlus = total(pop) if inrange(age, 22, 25)
		replace pop = eightyPlus if age == 22
		drop if inlist(age, 3, 4, 5, 6, 23, 24, 25, 91, 92, 93, 94)
		drop under5 eightyPlus	
		
	// // Split Age Unknown
		// mark if age unknown
			capture count if age == 26 & !inlist(pop, 0, .)
			if r(N) > 0 local age_unknown_data = 1
			else local age_unknown_data = 0
			preserve
				keep obs location_id year sex age pop
				keep if age == 26
				drop age
				rename pop unknown_age 
				tempfile unknown_metric
				save `unknown_metric', replace
			restore
		
		// Redistribute if age unknown
			drop if inlist(age, 1, 26)
			if `age_unknown_data' {
				merge m:1 obs location_id year sex using `unknown_metric', assert(3) nogen
				rename age gbd_age
				merge m:1 location_id year sex gbd_age using `pop_wgts', keep(1 3)
				rename gbd_age age
				egen total_wgt = total(wgt), by(obs location_id year sex)
				egen wgt_pc = pc(wgt), by(obs location_id year sex) prop
				replace wgt_pc = 1 if total_wgt == 0
				replace pop = pop + unknown_age * wgt_pc
				keep obs location_id year sex age pop
				tempfile redistributed_unknown_metric
				save `redistributed_unknown_metric', replace
			}

** ***************
** Verify Split
** ***************
	// // Verify Split
		preserve
		// Reshape wide and merge back with uids
			reshape wide pop, i(obs location_id year sex) j(age)
			drop year
			
			merge 1:1 obs using `uids', assert(3) nogen
			drop obs
			
		// Check for errors. If more than 3 population totals are greater than .0001% different from the original number, alert the user. (Below this fraction errors are likely due to rounding)
			egen postSplit_pop1 = rowtotal(pop2 - pop22)
			gen test_diff = abs(postSplit_pop1 - preSplit_pop1)
			capture count if test_diff > .000005*preSplit_pop1
			if r(N) > 3 {
				pause on
				display in red "Error: total population is not equivalent in all rows before and after split" 
				pause
				pause off
			}
			drop preSplit_pop1 postSplit_pop1 test_diff
		
		// restore data if splitting sex
			if `split_sex' restore
			else restore, not
		
** ******************
** Split Sex Unknown
** *******************
	if `split_sex' {
	// save a copy of the data with no combined sex
		local has_unique_sex = 0
		count if !inlist(sex, 3, 9)
		if r(N) > 0 {
			local has_unique_sex = 1
			preserve
				keep if !inlist(sex, 3, 9)
				tempfile unique_sex
				save `unique_sex', replace
			restore
			keep if inlist(sex, 3, 9)
		}
		
	// format population weights
		preserve
			use `pop_wgts', clear
			reshape wide wgt, i(year location_id gbd_age) j(sex)
			gen wgt3 = wgt1 + wgt2
			gen w1 = wgt1/wgt3
			gen w2 = 1 - w1
			drop wgt*
			rename gbd_age age
			tempfile split_sex_wgts
			save `split_sex_wgts', replace
		restore
		keep obs location_id year age pop
		merge m:1 year location_id age using `split_sex_wgts', keep(1 3) nogen
		replace w1 = .5 if w1 == .
		replace w2 = .5 if w2 == . 
		gen pop1 = pop * w1
		gen pop2 = pop * w2
		drop pop w*
		reshape long pop, i(obs location_id year age) j(sex)
		
	// merge with data for which sex was not split	
		if `has_unique_sex' append using `unique_sex'
		
	// Reshape wide and merge back with uids
		reshape wide pop, i(obs location_id year sex) j(age)
		drop year
		
		merge m:1 obs using `uids', assert(3) nogen
		drop obs
	}
	
** ******************
** Finalize and Save
** *******************	
	// Verify totals
		egen pop1 = rowtotal(pop*)
		summ(pop1)
		local post_split_pop = r(sum)
		if abs(`post_split_pop'-`pre_split_pop') > .0005*`pre_split_pop' {
			noisily di "ERROR: post-split total does not match pre-split total"
			BREAK
		}
		
	// update frmat and im_frmat to reflect changes
		capture drop frmat_pop im_frmat_pop 
		recast float pop*
		
	// Save
		compress
		save "`output_folder'/04_age_sex_split_`data_type'_pop.dta", replace
		if "`data_name'" != "incidence_weights_pop" {
			capture saveold "`output_folder'/04_age_sex_split_`data_type'_pop.dta", replace
			save "`output_folder'/_archive/04_age_sex_split_`data_type'_pop_`today'.dta", replace
			capture saveold "`output_folder'/_archive/04_age_sex_split_`data_type'_pop_`today'.dta", replace
		}

capture log close
** *************
** Split Pop Finished
** *************
