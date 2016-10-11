
// Purpose:	Standardizing cause codes & mapping

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
	args group_folder data_name data_type resubmit

// Create Arguments if Running Manually
if "`group_folder'" == "" {
	local group_folder = "TUR"
	local data_name = "TUR_provinces_2002_2008"
	local data_type = "inc"
	local resubmit = 1
}

// toggle resubmission, if not set
	if "`resubmit'" == "" local resubmit = 0

// Load common settings and default folders
	do `load_common' 0 "`group_folder'" "`data_name'" "`data_type'"

// set folders
	local data_folder = r(data_folder)
	local metric = r(metric)
	local temp_folder = r(temp_folder) + "/subtotal_recalculation"
	make_directory_tree, path("`temp_folder'")

// set output_filename
	local output_filename = "02_subtotals_disaggregated_`data_type'"

// set location of subroutines
	local subroutines_folder = "$registry_intake_code/02_subtotal_recalculation/subroutines"
	local subcause_detection_script = "`subroutines_folder'/subcause_detection.py"
	local code_components_script = "`subroutines_folder'/code_components.py"
	local sd_parallel_script = "`subroutines_folder'/subcause_detection_parallel.py"

** *******************************************************************
** Check for Data Exception
**     Sources for which there are known rounding errors (See Part 6)
** ********************************************************************
// Define Source Exceptions
	#delimit ;
	local source_exceptions "grd_1996_2000_inc SVN_2008_2009 deu_north_rhine_2003_inc gin_1992_1995_inc GBR_England_Wales_1990_2010 jam_1988_1992_inc aus_qld_1982_2003_2006_2007_mor 
		ita_modena_2003_2007_inc deu_brandenburg_2005_2006_mor wsm_1980_1988_inc ukr_2002_2007_inc bgr_2006_mor ury_national_2002_2006_inc HRV_2009_2010 DEU_common_2007_2008 
		jam_1978_1982_inc EST_2000_2008 CZE_2008_2010  JPN_NationalCIS_1958_2013 AUS_1968_2007 DEU_NationalRegistry_2000_2010 UKR_2009_2011 usa_seer_1973_2008_mor usa_seer_1973_2008_inc";
	#delimit cr

// Set Variable if dataset is "known offender"
	local data_exception = 0 
	foreach s of local source_exceptions {
		if "`data_name'" == "`s'" local data_exception = 1
	}

** *********************************************************************
** Disaggregate Subtotals
**
**
** *********************************************************************
	** *********************************************************************
	** Part 1: Drop "All" cause data and Check for Aggregate Codes
	**
	** *********************************************************************
	// GET DATA
		use "`data_folder'/01_standardized_format_`data_type'.dta", clear

	// Collapse after standardization
		collapse (sum) `metric'*, by(location_id registry_id source_id year_start year_end frmat im_frmat sex coding_system cause cause_name) fast
		
	// Drop "All" codes
		gen all = 1 if regexm(cause,  "C00-C43,C45-C97") | regexm(cause, "C00-43,C45-97") | regexm(cause, "C00-C80") | regexm(cause, "C00-C94") | regexm(cause, "C00-C96") | regexm(cause, "C00-C97")
		drop if all == 1
		drop all

	// Generate uniqid, unique to each country/subdiv/location_id/registry, year, and sex
		egen uniqid=group(location_id registry_id source_id year_start year_end sex frmat im_frmat), missing
		sort cause cause_name uniqid
		
	// save a version of the file before the check
		tempfile preCheck
		save `preCheck', replace

	// Keep just the cause and the unique id
		keep cause uniqid coding_system
		duplicates drop
		
	// Determine if Aggregates Exist (denoted by comma or dash in cause variable)
		local aggregate_code_exist = 0
		count if regexm(cause,",")==1 | regexm(cause,"-")==1 & inlist(coding_system, "ICD10") 
		if `r(N)' > 0 local aggregate_code_exist = 1
		
	** *********************************************************************
	** Part 2: If No Aggregate Codes Exist, Finalize and End Script
	** *********************************************************************
	if !`aggregate_code_exist'{
		
		// Use presplit data 
		use `preCheck', clear
		
		// add variables to indicate that no disaggregation was needed
			gen orig_cause = cause
			gen codes_removed = ""
			
		// Keep only variables of interest
			keep location_id registry_id source_id year_start year_end sex frmat im_frmat coding_system cause cause_name orig_cause codes_removed `metric'* 
			order location_id registry_id source_id year_start year_end sex frmat im_frmat coding_system cause cause_name orig_cause codes_removed `metric'* 
			sort location_id registry_id source_id year_start year_end sex frmat im_frmat coding_system cause cause_name orig_cause codes_removed `metric'* 

		// Save
			compress
			save "`r(output_folder)'/`output_filename'.dta", replace
			save "`r(archive_folder)'/`output_filename'_$today.dta", replace
			save "`r(permanent_copy)'/`output_filename'.dta", replace

		// Close Log
			capture log close
		
		// Exit Current *.do file
			noisily di "No disaggregation needed. Script complete."
			 exit, clear
	}
	else {
			
		// Create Temp folders
			// remove any files present in the temp_folder
			local old_files: dir "`temp_folder'" files "*.dta", respectcase
			foreach old_file of local old_files {
				display "`old_file'"
				capture rm "`temp_folder'/`old_file'"
			}
			capture mkdir "`temp_folder'/inputs"
			capture mkdir "`temp_folder'/outputs"

		// separately save copies of data by whether they can be disaggregated
			use `preCheck', clear
			drop `metric'1
			rename `metric'* metric*
			save `preCheck', replace
			
			// data that cannot be disaggregated
			keep if coding_system != "ICD10"
			count
			if r(N) > 0 {
				local has_non_icd10 = 1
				capture rm "`temp_folder'/02_coding_system_not_split.dta"
				save "`temp_folder'/02_coding_system_not_split.dta", replace
			}
			else local has_non_icd10 = 0
			
			// data that can be disaggregated
			use `preCheck', clear
			keep if coding_system == "ICD10"
			tempfile presplit
			save `presplit', replace
	}

	** *********************************************************************
	** Part 3: Determine Possible Components of Aggregate Codes 
	**		(if the script has not ended, then aggregate must codes exist).
	** *********************************************************************
	// Save raw cause input
		rename cause orig
		drop metric*
		compress
		tempfile code_components_raw
		save `code_components_raw', replace
		save "`temp_folder'/02_code_components_raw.dta", replace
		capture saveold "`temp_folder'/02_code_components_raw.dta", replace
		
	// Run python script to separate all codes into their component codes (example: C01-02 becomes C01 and C02)
		!python "`code_components_script'" "`temp_folder'" "`data_type'"
		
	// Check for completed code separation (code_components_split.dta) and 
		clear
		// Check for file
			local numAttempts = 1
			local checkfile "`temp_folder'/02_code_components_split.dta"
			capture confirm file "`checkfile'"
			if _rc == 0 {
				noisily display "code components FOUND!"
			}
			else {
				noisily di in red "Could not find completed code components file"
				BREAK
			}
		use "`temp_folder'/02_code_components_split.dta"
		compress
		save "`temp_folder'/02_code_components_split.dta", replace
		capture saveold "`temp_folder'/02_code_components_split.dta", replace
		
	// Re-attach uniquid and verify that no data were lost by merging separated code components with list of original codes
		joinby orig coding_system using `code_components_raw', unmatched(both) nolabel
		count if _merge != 3
		if `r(N)' > 0 {
			noisily display in red "ERROR: Unable to merge raw code components with split code components. Check code_components_split.dta for problems."
			BREAK
		}
		drop _merge

	// Save List of Original Codes for 
		keep cause orig uniqid
		duplicates drop
		tempfile original_code_list
		save `original_code_list', replace
		save "`temp_folder'/original_code_list.dta", replace
		capture saveold "`temp_folder'/original_code_list.dta", replace
		
	** ***********************************************************************
	** Part 4: Submit and then compile results of disaggregation ("subcause_detection")
	** ***********************************************************************		
	// find the largest uid
		capture levelsof(uniqid), local(uids) clean
		summ uniqid
		local max_uid = `r(max)'
		
	// For each uid, save input data then submit disaggregation script. Paralellize the process if there are many uids
		// Prepare input data to save for each uid
		use `presplit', clear
		keep uniqid metric* cause
		
		save "`temp_folder'/inputs/input_data.dta", replace

		// if there are many uids, parallelize the script submission 
		if `max_uid' > 500 & c(os) != "Windows" & !`resubmit'{ 
			forvalues uid = 1/`max_uid' {
				!/usr/local/bin/SGE/bin/lx24-amd64/qsub -P proj_cancer_prep -pe multi_slot 4 -l mem_free=8g -N "SD_`data_name'_`data_type'_`uid'" "$py_shell" "`sd_parallel_script'" "`temp_folder' `data_type' `uid' `data_exception'"
			}
		}
		else {
			!python "`subcause_detection_script'" `temp_folder' `data_type' `data_exception'
		}
		
		
	// Append all cause hierarchies together. Check every 15 seconds for completed step. If a long wait has passed, attempt to run the program again
		clear	
		sleep 15000
		local numAttempts = 0
		foreach uid of local uids {
			local numAttempts = 0
			// Check for file
				local checkfile "`temp_folder'/outputs/uid_`uid'_output.dta"
				capture confirm file "`checkfile'"
				if _rc == 0 {
					noisily display "uid `uid' output FOUND!"
				}
				while _rc != 0 {
					noisily display "`checkfile' not found, checking again in 15 seconds"
					sleep 15000
					local numAttempts = `numAttempts' + 1
					if `numAttempts' == 10 {
						!python "`code_folder'/subcause_detection_parallel.py" `temp_folder' `data_type' `uid' `data_exception'
					}
					if `numAttempts' == 12 {	
						noisily di in red "Could not find completed cause hierarchy `uid' file"
						BREAK
					}
					capture confirm file "`checkfile'"
					if _rc == 0 {
						noisily display "uid `uid' output FOUND!"
					}
				}
				append using "`checkfile'"
		}
		
	// Save the compiled outputs
		compress
		save "`temp_folder'/temp_disaggregation_output.dta", replace
		capture saveold "`temp_folder'/temp_disaggregation_output.dta", replace

	** ***********************************************************************
	** Part 5: Format results of disaggregation 
	** ***********************************************************************
	// get uid data
		use `presplit', clear
		drop metric*
		tempfile uid_values
		save `uid_values', replace
		 
	// merge disaggregation output with uid data
		use "`temp_folder'/temp_disaggregation_output.dta", clear
		replace age = subinstr(age, "metric", "", .)
		drop orig_metric
		reshape wide metric, i(cause codes_removed codes_remaining uniqid) j(age) string
		merge m:1 uniqid cause using `uid_values', keep(1 3) assert(2 3) nogen
		rename (cause codes_remaining) (orig_cause cause)
		save "`temp_folder'/final_disaggregation_output.dta", replace

	//	replace blank causes with the original aggregate. drop causes that were zeroed in subtotal disaggregation 
		egen metric1 = rowtotal(metric*)
		drop if metric1 == 0	
		replace cause = orig_cause if cause == "" & metric1 != 0
		drop metric1	
		
	** *********************************************************************
	** Finalize: Keep Variables of Interest, Save New and Archive Old
	** *********************************************************************	
	// Append data from coding systems that are not split
		if `has_non_icd10' == 1 append using "`temp_folder'/02_coding_system_not_split.dta"	
		
	// rename metric data
		rename metric* `metric'* 		
		
	// Keep only variables of interest
		keep location_id registry_id source_id year_start year_end sex frmat im_frmat coding_system cause cause_name orig_cause codes_removed `metric'* 
		order location_id registry_id source_id year_start year_end sex frmat im_frmat coding_system cause cause_name orig_cause codes_removed `metric'* 
		sort location_id registry_id source_id year_start year_end sex frmat im_frmat coding_system cause cause_name orig_cause codes_removed `metric'* 
		
	// Save
		compress
		compress
		save "`r(output_folder)'/`output_filename'.dta", replace
		save "`r(archive_folder)'/`output_filename'_$today.dta", replace
		save "`r(permanent_copy)'/`output_filename'.dta", replace

	// Close Log
		capture log close

** *********************************************************************
** END subtotal_recalculation.do
** *********************************************************************

