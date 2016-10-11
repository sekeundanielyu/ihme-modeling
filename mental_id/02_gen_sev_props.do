// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global

// Description: IN 2013, the Intellectual Disability Splits were done in Meta-excel and Ersatz.
	//Here, I pull the 2013 severity specific data, add 2015 severity-specific data, run meta-analyses for the proportions, then save 1000 draws for ID custom code 


* do "/home/j/WORK/04_epi/01_database/02_data/imp_id/04_models/02_inputs/updating_splits.do"


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

//Running interactively on cluster 
** do "/ihme/code/epi/struser/id/gen_sev_props.do"
	local cluster_check 0
	if `cluster_check' == 1 {
		local 1		"/home/j/temp/struser/imp_id"
		local 2		"/share/scratch/users/struser/id/tmp_dir"
		local 3		"2015_12_29"
		local 4		"02"
		local 5		"gen_sev_props"
		local 6		""
		local 7		""
		local 8		"/ihme/code/epi/struser/id"
		}

// LOAD SETTINGS FROM MASTER CODE (NO NEED TO EDIT THIS SECTION)

	clear all
	set more off
	set mem 2g
	set maxvar 32000
	set type double, perm
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
		local cluster 1 
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local cluster 0
	}
	// directory for standard code files
		adopath + "$prefix/WORK/10_gbd/00_library/functions"
		adopath +  "$prefix/WORK/10_gbd/00_library/functions/get_outputs_helpers"

	//If running locally, manually set locals 
	if `cluster' == 0 {

		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
        local date = subinstr("`date'", " " , "_", .)
		local step_num "02"
		local step_name "obtain_secondary_causes"
		local hold_steps ""
		local code_dir "C:/Users/struser/Documents/Git/id"
		local in_dir "$prefix/WORK/04_epi/01_database/02_data/imp_id/04_models/02_inputs"
		local root_j_dir "$prefix/temp/struser/imp_id"
		local root_tmp_dir "$prefix/temp/struser/imp_id/tmp_dir"
		
		}


	//If running on cluster, use locals passed in by model_custom's qsub
	else if `cluster' == 1 {
		// base directory on J 
		local root_j_dir `1'
		// base directory on clustertmp
		local root_tmp_dir `2'
		// timestamp of current run (i.e. 2014_01_17) 
		local date `3'
		// step number of this step (i.e. 01a)
		local step_num `4'
		// name of current step (i.e. first_step_name)
		local step_name `5'
		// step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
		local hold_steps `6'
		// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
		local last_steps `7'
		// directory for steps code
		local code_dir `8'
		}
	
	**Define directories 
		// directory for external inputs 
		local in_dir "$prefix/WORK/04_epi/01_database/02_data/imp_id/04_models/02_inputs"
		// directory for output on the J drive
		local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
		// directory for output on clustertmp
		local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"


		

	// write log if running in parallel and log is not already open
	cap log using "`out_dir'/02_temp/02_logs/`step_num'.smcl", replace
	if !_rc local close_log 1
	else local close_log 0
	
	// check for finished.txt produced by previous step
	if "`hold_steps'" != "" {
		foreach step of local hold_steps {
			local dir: dir "`root_j_dir'/03_steps/`date'" dirs "`step'_*", respectcase
			// remove extra quotation marks
			local dir = subinstr(`"`dir'"',`"""',"",.)
			capture confirm file "`root_j_dir'/03_steps/`date'/`dir'/finished.txt"
			if _rc {
				di "`dir' failed"
				BREAK
			}
		}
	}	


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE

*****************************************************************************
***	Load and prep 2013 data
*****************************************************************************

	import excel "`in_dir'/ID_master_file_2013_incl_sev_split.xlsx", clear firstrow sheet("Data")

	//There's some calculations at bottom of this sheet, I just want to keep data 
		keep if level != . 
		destring n n_cases sex, replace 
		//studyid 54 has both CHN and GBR study. The GBR one isn't used (only has 50 threshold) so I'll drop 
		drop if studyid == 54 & isocode == "GBR"

	//need to map iso3 to location_id
	preserve 
	get_location_metadata, location_set_id(9) clear 
	rename ihme_loc_id iso3
	gen HIC = 0 
	replace HIC = 1 if super_region_name == "High-income"
	keep location_id iso3 location_name developed HIC
	tempfile location_data 
	save `location_data'
	restore 

	rename isocode iso3
	merge m:1 iso3 using `location_data'
		count if _merge == 1
		if `r(N)' > 0 di in red "not all iso3s merged" BREAK
		else keep if _merge == 3
		drop _merge 

drop if n_cases == .
*isid location_id studyid level sex age1 mid_birth_year

	//Some studies only have certain thresholds be sex-specific, in which cases we will aggregate sexes 
	preserve 
	collapse (mean) sex = sex, by(studyid level)
	bysort studyid : egen max = max(sex)
	bysort studyid : egen min = min(sex)
	levelsof studyid if max == 3 & min != 3, local(aggs) sep(",")
	restore 
	replace sex = 3 if inlist(studyid, `aggs')

tempfile data_2013
save `data_2013', replace 


*****************************************************************************
	***	Load and prep 2015 data
*****************************************************************************


//This was extracted in GBD database format
	import excel "`in_dir'/ID_sev_2015_data.xlsx", clear firstrow 
		//make variables to match 2013 
		rename nid 			studyid 
		rename sample_size 	N
		rename cases		n_cases

		merge m:1 location_id using `location_data', keep(3) nogen 
		append using `data_2013'

	tempfile data 
	save `data', replace 

*****************************************************************************
	***	Calculate fractions and do meta-analysis 
*****************************************************************************


	use `data', clear 

	//Get reference category, aka threshold 70
	foreach thresh_denom in 50 70 {
		preserve
		levelsof studyid if level == `thresh_denom', local(ids_at_thresh) sep(",")
		keep if level <= `thresh_denom'
		keep if inlist(studyid, `ids_at_thresh') //Only want studies with threshold of interest 
		collapse (sum) N = n_cases, by(studyid sex iso3 HIC)
		tempfile denominator_`thresh_denom'
		save `denominator_`thresh_denom'', replace 
		restore 
		}
	
* local thresh_num 85
foreach thresh_num in 20 35 50 85 {

		use `data', clear 

		if inlist(`thresh_num', 50, 85) local thresh_denom 70
		if inlist(`thresh_num', 20, 35) local thresh_denom 50

		levelsof studyid if level == `thresh_num', local(ids_at_thresh) sep(",")

		//<50 is done as threshold, others are discrete 
		if inlist(`thresh_num', 20, 35, 85) keep if level == `thresh_num' 
		else if `thresh_num' == 50 keep if level <= 50

		keep if inlist(studyid, `ids_at_thresh') //Only want study with threshold of interest (relevant to <50)
		collapse (sum) cases = n_cases, by(studyid sex iso3 HIC)
		tempfile numerator 
		save `numerator', replace 

		merge 1:1 studyid sex using `denominator_`thresh_denom'', nogen keep(3)
		sort studyid

		gen mean = cases / N 
		gen sd = sqrt(mean * (1 - mean) / N)
		if `thresh_num' replace sd = 0.02 if sd == . 
		gen uci = mean + 1.96*sd 
		gen lci = mean - 1.96*sd


		//meta-analysis: for all but borderline do by high-income status 
			do "$prefix/Usable/Tools/ADO/pdfmaker_Acrobat11.do"
			pdfstart using "`in_dir'/sev_splits_forest_plots/ALL_sev.pdf"
		if `thresh_num' == 85 {
			metan mean lci uci, random lcols(iso3) rcols(cases) textsize(90) title("70-85 as proportion of <70") saving("`in_dir'/sev_splits_forest_plots/sev_`thresh_num'", replace)
			pdfappend
			local mean_`thresh_num' = `r(ES)'
			local uci_`thresh_num' = `r(ci_upp)'
			local lci_`thresh_num' = `r(ci_low)'
			local se_`thresh_num' = `r(seES)'
			}
		else {
			metan mean lci uci if HIC == 1 , random lcols(iso3) rcols(cases) textsize(90) title("%<`thresh_num' of <`thresh_denom', High-income") saving("`in_dir'/sev_splits_forest_plots/sev_`thresh_num'_HIC", replace)
			pdfappend
			local mean_HIC_`thresh_num' = `r(ES)'
			local uci_HIC_`thresh_num' = `r(ci_upp)'
			local lci_HIC_`thresh_num' = `r(ci_low)'
			local se_HIC_`thresh_num' = `r(seES)'
			metan mean lci uci if HIC == 0 , random lcols(iso3) rcols(cases) textsize(90) title("%<`thresh_num' of <`thresh_denom', LMIC") saving("`in_dir'/sev_splits_forest_plots/sev_`thresh_num'_LMIC", replace)	
			pdfappend
			local mean_LMIC_`thresh_num' = `r(ES)'
			local uci_LMIC_`thresh_num' = `r(ci_upp)'
			local lci_LMIC_`thresh_num' = `r(ci_low)'
			local se_LMIC_`thresh_num' = `r(seES)'
			}

		}


*****************************************************************************
	***	Create 1000 draws from mean + 95%CI calculated by meta-analysis
*****************************************************************************

	clear 
	set obs 1000
	foreach sev in 85 HIC_20 LMIC_20 HIC_35 LMIC_35 HIC_50 LMIC_50 {
		gen prop_`sev' = rnormal(`mean_`sev'', `se_`sev'') 
		}

*****************************************************************************
	***	Calculate discrete categories as proportion of <70 envelope. 
*****************************************************************************

		//Since <20 and 20-34 were calculated as proportion of <50, we should adjust 
		gen LMIC_id_prof =  prop_LMIC_20 *  prop_LMIC_50
		gen LMIC_id_sev =  prop_LMIC_35 *  prop_LMIC_50
		gen HIC_id_prof =  prop_HIC_20 *  prop_HIC_50
		gen HIC_id_sev =  prop_HIC_35 *  prop_HIC_50

		//50-70 is inverse of <50 
		gen HIC_id_mild = 1 - prop_HIC_50
		gen LMIC_id_mild = 1 - prop_LMIC_50

		//35-50 is <50 minus <20 and 20-34
		gen HIC_id_mod = prop_HIC_50 - HIC_id_prof - HIC_id_sev
		gen LMIC_id_mod = prop_LMIC_50 - LMIC_id_prof -LMIC_id_sev

				
			//QC: discrete categories within <70 (not incl borderline) should add to one 
				egen test_HIC = rowtotal(HIC*)
				egen test_LMIC = rowtotal(LMIC*)

				count if !inrange(test_HIC, 0.99, 1.01) | !inrange(test_LMIC, 0.99, 1.01) 
				if `r(N)' > 0 di in red "CHECK SUM OF DISCRETE SEVERITY PROPS" BREAK 

		//70-85 is same for HIC and LMIC 
		gen HIC_id_bord = prop_85
		gen LMIC_id_bord = prop_85


	keep *id*

	//Diagnostics
	preserve
		collapse (mean) *id*
		graph bar LMIC_id_prof LMIC_id_sev LMIC_id_mod LMIC_id_mild LMIC_id_bord, stack title("Intellectual Disability Severity Distribution - LMIC") subtitle("As proportion of <70 Envelope")
		pdfappend
		graph bar HIC_id_prof HIC_id_sev HIC_id_mod HIC_id_mild HIC_id_bord , stack title("Intellectual Disability Severity Distribution - HIC") subtitle("As proportion of <70 Envelope")
		pdfappend
		pdffinish
	restore 

	//Transform into format for step 03

	xpose, varname clear 

	//Rename from 1-1000 to 0-999 
	forval i = 0/999 {
		local j = `i' + 1 
		rename v`j' v`i'
		}

	split _varname, parse("_") limit(3) gen(x)
	rename x1 income 
	gen HIC = .
		replace HIC = 1 if income == "HIC"
		else replace HIC = 0 if income == "LMIC"
	egen healthstate = concat(x2 x3), punct("_")

	order income healthstate 

	save "`out_dir'/sev_props", replace


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// CHECK FILES (NO NEED TO EDIT THIS SECTION)

	// write check file to indicate step has finished
		file open finished using "`out_dir'/finished.txt", replace write
		file close finished
		
	// if step is last step, write finished.txt file
		local i_last_step 0
		foreach i of local last_steps {
			if "`i'" == "`this_step'" local i_last_step 1
		}
		
		// only write this file if this is one of the last steps
		if `i_last_step' {
		
			// account for the fact that last steps may be parallel and don't want to write file before all steps are done
			local num_last_steps = wordcount("`last_steps'")
			
			// if only one last step
			local write_file 1
			
			// if parallel last steps
			if `num_last_steps' > 1 {
				foreach i of local last_steps {
					local dir: dir "`root_j_dir'/03_steps/`date'" dirs "`i'_*", respectcase
					local dir = subinstr(`"`dir'"',`"""',"",.)
					cap confirm file "`root_j_dir'/03_steps/`date'/`dir'/finished.txt"
					if _rc local write_file 0
				}
			}
			
			// write file if all steps finished
			if `write_file' {
				file open all_finished using "`root_j_dir'/03_steps/`date'/finished.txt", replace write
				file close all_finished
			}
		}
		
	// close log if open
		if `close_log' log close
	