// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Purpose:		Submit death/cases draws for age-sex splitting



	** ****************************************************************
		// Set application preferences
			// Clear memory and set memory and variable limits
				clear all
				set mem 5G
				set maxvar 32000

			// Set to run all selected code without pausing
				set more off

			// Set graph output color scheme
				set scheme s1color

			// Define J drive (data) for cluster (UNIX) and Windows (Windows)
				if c(os) == "Unix" {
					global prefix "/home/j"
					set odbcmgr unixodbc
				}
				else if c(os) == "Windows" {
					global prefix "J:"
				}
			
			// Get timestamp
				local date = c(current_date)
				local today = date("`date'", "DMY")
				local year = year(`today')
				local month = month(`today')
				local day = day(`today')
				local time = c(current_time)
				local time : subinstr local time ":" "", all
				local length : length local month
				if `length' == 1 local month = "0`month'"	
				local length : length local day
				if `length' == 1 local day = "0`day'"
				global date = "`year'_`month'_`day'"
				global timestamp = "${date}_`time'"


	
			// username
				global username "`1'"
			
			
			// gbd cause (acause)
				local acause "`2'"
			
			
			// Deaths or cases
				local metric "`3'"
				if "`metric'" == "death" local metric_folder "COD_prep"
				if "`metric'" == "cases" local metric_folder "EPI_prep"
				
			// iso3 code
				local ihme_loc_id "`4'"
				
				 
			// Temp folder
				capture mkdir "/ihme/scratch/users/${username}"
				capture mkdir "/ihme/scratch/users/${username}/`metric_folder'"
				capture mkdir "/ihme/scratch/users/${username}/`metric_folder'/`acause'"
				capture mkdir "/ihme/scratch/users/${username}/`metric_folder'/`acause'/02_agesex_split"
				capture mkdir "/ihme/scratch/users/${username}/`metric_folder'/`acause'/02_agesex_split/`ihme_loc_id'"
				capture mkdir "/ihme/scratch/users/${username}/`metric_folder'/`acause'/99_final_format"
				local clustertmp_folder "/ihme/scratch/users/${username}/`metric_folder'/`acause'/02_agesex_split/`ihme_loc_id'"
			
			// Log folder
				local log_folder "/ihme/scratch/users/${username}/`metric_folder'/`acause'/02_agesex_split/_logs"
				capture mkdir "`log_folder'"

		** ****************************************************************
		** CREATE LOG
		** ****************************************************************
			capture log close
			log using "`log_folder'/agesex_split_`ihme_loc_id'_${timestamp}.log", replace


		** ****************************************************************
		** GET GBD RESOURCES
		** ****************************************************************
			// Location information
				// Get data
					strConnection
				// Remake dev_status into the CoD format
					replace developed = "0" if inlist(substr(ihme_loc_id, 1, 3), "IND", "KEN", "SAU") 
					drop if developed == ""
					tostring developed, replace
					replace developed = "D" + developed if substr(developed, 1, 1)!="G"
				// Rename variables to match CoD format
					rename developed dev_status
					rename region_id region
				duplicates drop
				tempfile gbd_geography
				save `gbd_geography', replace
		
** **************************************************************************
** RUN PROGRAGM
** **************************************************************************
	// Get data
		use "/ihme/scratch/users/${username}/`metric_folder'/`acause'/01_initial_data/`ihme_loc_id'_input.dta", clear
		
	// Reshape all draws long
		gen obs = _n
		reshape long ensemble_@, i(obs ihme_loc_id location_id year) j(subdiv) string
		drop obs
	
	// Create variables used for age-sex splitting
		// Deaths
			rename ensemble_ deaths26
			foreach i of numlist 1/26 91/94 {
				capture gen deaths`i' = 0
			}
			replace deaths1 = deaths26
		// Formats
			gen frmat = 9
			gen im_frmat = 8
		// Sex
			gen sex = 9
		// National
			gen national = 1
		// Source
			gen source = string(location_id)
		// Source_label
			gen source_label = "Codem prep `acause'"
		// Souce_type
			gen source_type = "VR"
		// Location information
			drop ihme_loc_id
			merge m:1 location_id using `gbd_geography', keep(1 3) assert(2 3) keepusing(ihme_loc_id dev_status region) nogen
			split(ihme_loc_id), p("_")
			drop location_id
			rename ihme_loc_id1 iso3
			capture gen ihme_loc_id2 = ""
			rename ihme_loc_id2 location_id
			destring(location_id), replace
		// NID
			gen NID = 999999999
		// List
			gen list = "GBD"
		// Cause
			gen cause = "`acause'"
			gen cause_name = "`acause'"
			gen acause = "`acause'"
			
		// Format
			keep iso3 location_id year sex acause cause cause_name NID source source_label source_type list national subdiv region dev_status im_frmat frmat deaths*
			
		// Save
			save "`clustertmp_folder'/ready_for_agesex_split.dta", replace
		
	
	** **************************************************************************
	** AGE-SEX SPLIT
	** **************************************************************************
		global data_name "`metric'_`acause'"
		global tmpdir "`clustertmp_folder'"
		global source_dir "`clustertmp_folder'"
	// Make the temp directory for this particular dataset
		capture mkdir "$tmpdir/02_agesexsplit"	
		capture mkdir "$tmpdir/02_agesexsplit/${data_name}"	
		global temp_dir "$tmpdir/02_agesexsplit/${data_name}"
		
	 // Make the temp directory for this particular dataset
		capture mkdir "$tmpdir/02_agesexsplit"	
		capture mkdir "$tmpdir/02_agesexsplit/${data_name}"	
		global temp_dir "$tmpdir/02_agesexsplit/${data_name}"
		
	 // Other macros to make the code work
		global wtsrc acause
		global codmod_level acause
		global weight_dir "$prefix/WORK/03_cod/01_database/02_programs/age_sex_splitting/data/weights"

	// Prep the pop_file
		do "$prefix/WORK/03_cod/01_database/02_programs/prep/code/env_wide.do"
		
		keep if location_id == .
		
		drop env*
		
		if strmatch("$data_name","_Australia*") | "$data_name" == "ICD7A" | "$data_name" == "ICD8A" {
			forval y = 1907/1969 {
				expand 2 if year == 1970, gen(exp)
				replace year = `y' if exp == 1
				drop exp
			}
		}
		save "$temp_dir/pop_prepped.dta", replace

	 // Bring in the data
		use "`clustertmp_folder'/ready_for_agesex_split.dta", clear

	 // Do the thing
		count if frmat!=2 | im_frmat>2 | sex==9 | sex==. | sex==3
		if `r(N)'>0 {
		
	// collapse 80-84 with 85+
			egen double oldest = rowtotal(deaths22 deaths23)
			replace deaths22 = oldest
			replace deaths23 = 0
			drop oldest	

		// "do" the ado-files for age splitting, agesex splitting, and storing summary statistics ///
		
		quietly do "$prefix/WORK/03_cod/01_database/02_programs/age_sex_splitting/code/agesexsplit.ado"
		quietly do "$prefix/WORK/03_cod/01_database/02_programs/age_sex_splitting/code/agesplit.ado"
		quietly do "$prefix/WORK/03_cod/01_database/02_programs/age_sex_splitting/code/summary_store.ado"


		// erase any old agesplit and agesexsplit files so that are not appended with the new age and sex split files
			
			local split_files: dir "$temp_dir" files "${data_name}_ages*", respectcase 

			** loop through the old split files and erase 
			foreach i of local split_files {
				capture erase "$temp_dir/`i'"
			}

			
		// create vectors to store checks along the way
		local maxobs 10000
		global currobs 1
		mata: stage = J(`maxobs', 1, "")
		mata: sex = J(`maxobs', 1, .)
		mata: sex_orig = J(`maxobs', 1, .)
		mata: frmat = J(`maxobs', 1, .)
		mata: frmat_orig = J(`maxobs', 1, .)
		mata: im_frmat = J(`maxobs', 1, .)
		mata: im_frmat_orig = J(`maxobs', 1, .)
		mata: deaths_sum = J(`maxobs', 1, .)
		mata: deaths1 = J(`maxobs', 1, .)
				
		// recalculate deaths1 so the first set of summary statistics will be accurate
		capture drop deaths1
		aorder 
		egen deaths1 = rowtotal(deaths3-deaths94)
		
		
		** // store preliminary values for deaths_sum and deaths1 before making any other changes to the dataset
		preserve
			aorder
			egen deaths_sum = rowtotal(deaths3-deaths94)
			summary_store, stage("beginning") currobs(${currobs}) storevars("deaths_sum deaths1") ///
				sexvar("sex") frmatvar("frmat") im_frmatvar("im_frmat")
		restore
			
			
			egen tmp = rowtotal(deaths91 deaths92)
			replace deaths91 = tmp
			replace deaths92 = 0
			drop tmp
			replace im_frmat = 2 if im_frmat == 1
	
			replace deaths2 = deaths91 if deaths2==0 & im_frmat==8
			replace deaths91 = deaths2 if im_frmat == 8
			foreach var of varlist deaths92 deaths93 deaths94 {
				replace `var' = 0 if im_frmat == 8
			}

			
			replace deaths91 = deaths2 + deaths3 if im_frmat == 9
			
			
			drop deaths1
			aorder 
			egen deaths1 = rowtotal(deaths3-deaths94)
			
			replace deaths26 = deaths1 if frmat == 9
					
			drop deaths2
			
			aorder
			capture drop tmp
			egen tmp = rowtotal(deaths*) 
			drop if tmp == 0 
			drop tmp
			
			replace sex=9 if sex==3 | sex==.

		// check that frmat and im_frmat are designated for all observations
		count if frmat == .
		if `r(N)' != 0 {
			di in red "WARNING: frmat variable is missing values.  Splitting will not work."
			pause
		}
		count if im_frmat == .
		if `r(N)' != 0 {
			di in red "WARNING: im_frmat variable is missing values.  Splitting will not work."
			pause
		}
			
		// check that we actually need to do agesexsplitting; only run the rest of the code if there are observations that need to be split
		
		count if (sex != 1 & sex != 2) | frmat != 2 | im_frmat != 2 
		if `r(N)' != 0 { 
			// record the total number of deaths in original, un-split file
				capture drop deathsorig_all
				egen deathsorig_all = rowtotal(deaths3-deaths94)

					
				// make a tempfile of the entire dataset so far
				noisily display "Saving allfrmats tempfile"
				tempfile allfrmats
				save `allfrmats', replace

			// store a summary of the deaths_sum and deaths1 at this stage
			egen deaths_sum = rowtotal(deaths3-deaths94)
			summary_store, stage("allfrmats") currobs(${currobs}) storevars("deaths_sum deaths1") ///
				sexvar("sex") frmatvar("frmat") im_frmatvar("im_frmat")
			drop deaths_sum

				
			// prepare data for splitting
				** rename deaths variables to be deaths_1, deaths_5, deaths_10, etc
				rename deaths3 deaths_1
				rename deaths26 deaths_99
				rename deaths91 deaths_91
				rename deaths93 deaths_93
				rename deaths94 deaths_94
				replace deaths22 = 0 if deaths22 == .
				replace deaths23 = 0 if deaths23 == .
				replace deaths22 = deaths22 + deaths23
				replace deaths23 = 0
				forvalues i = 7/22 {
					local j = (`i'-6)*5
					rename deaths`i' deaths_`j'
				}
				
			
				rename cause cause_orig
				
				** Map to splitting cause (level 3)
					preserve
						use "$prefix/WORK/00_dimensions/03_causes/gbd2015_causes_all.dta", clear
						** keep if cause_version==2 
						keep cause_id path_to_top_parent level acause yld_only yll_age_start yll_age_end male female
						** make sure age restriction variables are doubles, not floats
						foreach var of varlist yll_age_start yll_age_end {
							recast double `var'
							replace `var' = 0.01 if `var' > 0.009 & `var' < 0.011
							replace `var' = 0.1 if `var' > 0.09 & `var' < 0.11
						}
						** drop the parent "all_cause"
						levelsof cause_id if level == 0, local(top_cause)
						drop if path_to_top_parent =="`top_cause'"
						replace path_to_top_parent = subinstr(path_to_top_parent,"`top_cause',", "", .)	
						** make cause parents for each level
						rename path_to_top_parent agg_
						split agg_, p(",")
						** take the cause itself out of the path to parent, also map the acause for each agg
						rename acause acause_orig
						rename cause_id cause_id_orig
						forvalues i = 1/5 {
							rename agg_`i' cause_id
							destring cause_id, replace
							merge m:1 cause_id using "$prefix/WORK/00_dimensions/03_causes/gbd2015_causes_all.dta", keepusing(acause) keep(1 3) nogen
							rename acause acause_`i'
							rename cause_id agg_`i'
							tostring agg_`i', replace
							replace agg_`i' = "" if level == `i' | agg_`i' == "."
							replace acause_`i' = "" if level == `i'
							order acause_`i', after(agg_`i')
						}
						rename acause_orig acause
						rename cause_id_orig cause_id
						compress
						tempfile all
						save `all', replace
					restore
					
				**	make an acause which is the level 3 version of acause if acause is 4 or 5
					merge m:1 acause using `all', keep(1 3) keepusing(level acause_3) nogen
					gen cause = acause
					forvalues i = 4/5 {
						replace cause = acause_3 if level == `i'
					}
					drop level acause_*
					
				** there are too many variables that could possibly be identifying variables in these datasets so generate an 'id' 
				** variable for use in reshapes
				gen id_variable = iso3 + string(location_id) + string(year) + string(region) + dev_status + string(sex) + cause + cause_orig + acause + source + source_label + source_type ///
					+ string(national) + subdiv + string(im_frmat) + string(frmat) + string(NID)
				capture replace id_variable = id_variable + string(subnational)
				
				** load in frmat keys containing information about whether the frmat/age combination needs to be split
					// im_frmats
					preserve
						insheet using "$prefix/WORK/03_cod/01_database/02_programs/age_sex_splitting/maps/frmat_im_key.csv", comma clear
						tempfile frmat_im_key
						save `frmat_im_key', replace
					restore
					
					// other frmats
					preserve
						insheet using "$prefix/WORK/03_cod/01_database/02_programs/age_sex_splitting/maps/frmat_key.csv", comma clear
						tempfile frmat_key
						save `frmat_key', replace
					restore
					
					// frmat 9
					preserve
						insheet using "$prefix/WORK/03_cod/01_database/02_programs/age_sex_splitting/maps/frmat_9_key.csv", comma clear
						tempfile frmat_9_key
						save `frmat_9_key', replace
					restore
				
				** save all data, post-prep
				noisily display "Saving allfrmats_prepped tempfile"
				tempfile allfrmats_prepped
				save `allfrmats_prepped', replace

				** make a tempfile of the observations that need to be **age-split only**, with age long
					
					keep if ((frmat > 2 & frmat != .) | (im_frmat > 2 & im_frmat != .)) & sex != 9

					// drop the age groups we don't need
					capture drop deaths4 deaths5 deaths6 deaths23 deaths24 deaths25 deaths1 deaths92
					
					// reshape to get age long for infants, adults, and frmat 9 separately because it takes too long to do it all at once
						** reshape im_frmats
						preserve
							// reduce to non-standard im_frmats, excluding them if frmat == 9 (deaths_99 == 0 | deaths_99 == .), 
							// because we'll deal with these later
							keep if (im_frmat > 2) & (deaths_99 == 0 | deaths_99 == .) & frmat != 9
							
							// we only care about infant deaths, not the other ages or frmat 9
							aorder
							drop deaths_1-deaths_80 deaths_99
							
							// make age long	
							reshape long deaths_, i(id_variable) j(age)
							
							// merge with key from above to keep only the frmats and age groups that need to be split
							merge m:1 im_frmat age using `frmat_im_key', keep(3) nogenerate
							keep if needs_split == 1
							
							// save for later
							tempfile ims_age
							save `ims_age', replace
						restore
						
						** now reshape the bad adult frmats
						preserve
							// reduce to non-standard frmats, excluding them if frmat == 9 (deaths_99 == 0  deaths_99 == .), 
							keep if (frmat > 2) & (deaths_99 == 0 | deaths_99 == .)
							
							rop deaths_91 deaths_93 deaths_94 deaths_99
							
							// make age long
							reshape long deaths_, i(id_variable) j(age)
							
							// merge with key from above to keep only the frmats and age groups that need to be split
							merge m:1 frmat age using `frmat_key', keep(3) nogenerate
							keep if needs_split == 1
							
							// save for later
							tempfile adults_age
							save `adults_age', replace
						restore
						
						** lastly, reshape frmat = 9
						preserve
							// reduce to frmat 9 deaths
							keep if (deaths_99 != 0 & deaths_99 != .)
							
							// we only care about frmat 9 deaths (deaths_99)
							aorder
							drop deaths_1-deaths_94
							
							// make age long
							reshape long deaths_, i(id_variable) j(age)
							
							// ensure that the frmat is properly labeled
							replace frmat = 9
							
							// merge with key from above to keep only the frmats and age groups that need to be split
							merge m:1 frmat age using `frmat_9_key', keep(3) nogenerate
							keep if needs_split == 1
							
							// save for later
							tempfile frmat9_age
							save `frmat9_age', replace
						restore
								
						// append these tempfiles together - now we have a reshaped dataset with age long
						clear
						use `ims_age'
						append using `adults_age'
						append using `frmat9_age'
						rename deaths_ deaths
							
						
						noisily display "Saving $temp_dir/temp_to_agesplit.dta"
						save "$temp_dir/temp_to_agesplit.dta", replace
						
						// store a summary of the deaths_sum at this stage
						rename deaths deaths_sum
						summary_store, stage("temp_to_agesplit") currobs(${currobs}) storevars("deaths_sum") ///
							sexvar("sex") frmatvar("frmat") im_frmatvar("im_frmat")
						rename deaths_sum deaths

							
					// open file with all data, after prepping
					use `allfrmats_prepped', clear

					// keep only the observations that need age-sex-splitting or sex-splitting
					keep if sex == 9

					// drop the age groups we don't need
					capture drop deaths4 deaths5 deaths6 deaths23 deaths24 deaths25 deaths1 deaths92
					
					// reshape to get age long for infants, adults, and frmat 9 separately because it takes too long to do it all 
					// at once
						** reshape im_frmats
						preserve
							// exclude observations if frmat == 9 (deaths_99 == 0 | deaths_99 == .), because we'll deal with 
							// these later
							keep if (deaths_99 == 0 | deaths_99 == .) & frmat != 9
							
							
							aorder
							drop deaths_1-deaths_80 deaths_99
							
							// make age long			
							reshape long deaths_, i(id_variable) j(age)
							
							// merge with key from above to get values for age_start and age_end
							merge m:1 im_frmat age using `frmat_im_key', keep(3) nogenerate
							
							// save for later
							tempfile ims_agesex
							save `ims_agesex', replace
						restore
								
						** now reshape the bad adult frmats
						preserve
							// exclude observations if frmat == 9 (deaths_99 == 0  deaths_99 == .), because we'll 
							// deal with these later
							keep if (deaths_99 == 0 | deaths_99 == .) & frmat != 9
							
							
							drop deaths_91 deaths_93 deaths_94 deaths_99
							
							// make age long
							reshape long deaths_, i(id_variable) j(age)
							
							// merge with key from above to get values for age_start and age_end
							merge m:1 frmat age using `frmat_key', keep(3) nogenerate
							
							// save for later
							tempfile adults_agesex
							save `adults_agesex', replace
						restore
						
						** lastly, reshape frmat = 9
						preserve
							// reduce to frmat 9 deaths
							keep if (deaths_99 != 0 & deaths_99 != .)
							
							aorder
							drop deaths_1-deaths_91
							
							// make age long
							reshape long deaths_, i(id_variable) j(age)
							
							// ensure that the frmat is properly labeled
							replace frmat = 9
							
							// merge with key from above to keep only the frmats and age groups that need to be split
							merge m:1 frmat age using `frmat_9_key', keep(3) nogenerate
							
							// save for later
							tempfile frmat9_agesex
							save `frmat9_agesex', replace
						restore
							
					// append these tempfiles together - now we have a reshaped dataset with age long
					clear
					use `ims_agesex'
					append using `adults_agesex'
					append using `frmat9_agesex'
					rename deaths_ deaths
					
					// save what we have so far - this will be the file that gets age-sex-split
					noisily display "Saving $temp_dir/temp_to_agesexsplit.dta"
					save "$temp_dir/temp_to_agesexsplit.dta", replace
					
					// store a summary of the deaths_sum at this stage
					rename deaths deaths_sum
					
					// Make isopop iso3
					gen isopop = iso3
					
					summary_store, stage("temp_to_agesexsplit") currobs(${currobs}) storevars("deaths_sum") ///
						sexvar("sex") frmatvar("frmat") im_frmatvar("im_frmat")
					rename deaths_sum deaths

							
			// run the actual splitting code!
				** age-splitting only
				noisily display _newline "Beginning agesplitting"
				
					
					// open file for age-splitting
					use "$temp_dir//temp_to_agesplit.dta", clear
					
					// create a local to hold the $codmod_level causes in this dataset
					capture levelsof cause, local(causes)
					
									
					// IF there are observations in this dataset, loop through each cause and split the ages for that cause
					if ! _rc {
						foreach c of local causes {
							noisily di in red "Splitting cause `c'"
								agesplit, splitvar("deaths") splitfil("$temp_dir/temp_to_agesplit.dta") ///
								outdir("$temp_dir") weightdir("$weight_dir") mapfil("$iso3_dir/countrycodes_official.dta") ///
								dataname("$data_name") cause("`c'") wtsrc("$wtsrc")
							
						}
					}
					
									
				
				** age-sex-splitting and sex-splitting only
				noisily display _newline "Beginning agesexsplitting"
				
					// open file for age-sex-splitting
					use "$temp_dir/temp_to_agesexsplit.dta", clear
					
					// create a local to hold the $codmod_level causes in this dataset
					capture levelsof cause, local(causes)
					
					// IF there are observations in this dataset, loop through each cause and split the ages for that cause 
					
					if ! _rc {
						foreach c of local causes {
							noisily di in red "Splitting cause `c'" 
							agesexsplit, splitvar("deaths") splitfil("$temp_dir/temp_to_agesexsplit.dta") ///
								outdir("$temp_dir") weightdir("$weight_dir") mapfil("$iso3_dir/countrycodes_official.dta") ///
								dataname("$data_name") cause("`c'") wtsrc("$wtsrc")
								}
					}
				
				
			// compile the split files!
				** prepare a dataset for appending
				clear
				set obs 1
				gen split = ""

				** store the names of the age-split files
				local files: dir "$temp_dir" files "${data_name}_agesplit*", respectcase

				** loop through the age-split files to combine them
				foreach f of local files {
					append using "$temp_dir/`f'"
				}
				
				** mark that these observations have come from the age-splitting code
				replace split = "age"
				
				** store the names of the age-sex-split files
				local files: dir "$temp_dir" files "${data_name}_agesexsplit*", respectcase
				
				** loop through the age-sex-split files to combine them
				foreach f of local files {
					append using "$temp_dir/`f'"
				}
				
				** mark that these observations have come from the age-sex-splitting code
				replace split = "age-sex" if split == ""
				
				** mark observations with missing population
				gen nopop_adult = (nopop_10 == 1)
				gen nopop_im = (nopop_1 == 1)
				gen nopop_frmat9 = ((nopop_adult == 1 | nopop_im == 1) & frmat == 9)
				drop nopop_1-nopop_80
				
				** rename the deaths variables 
				rename deaths deaths_orig_split
				rename deaths_1 deaths3
				forvalues i = 5(5)80 {
					local j = (`i'/5) + 6
					rename deaths_`i' deaths`j'
				}
				renpfix deaths_ deaths
				
				** record original frmats 
				gen frmat_orig = frmat
				gen im_frmat_orig = im_frmat

				** reset frmat for successfully split observations
				replace frmat = 2 if (needs_split == 1 | sex_orig == 9) & nopop_adult != 1 & nopop_frmat9 != 1 	
					// population exists, so adults have been split
				replace im_frmat = 2 if (needs_split == 1 | sex_orig == 9) & nopop_im != 1 & nopop_frmat9 != 1 
					// population exists, so infants have been split
				
				** rename cause and cause_orig back to their original names
				drop cause
				rename cause_orig cause
				
				** generate a deaths92, deaths4-6, and deaths23-26 since we have those in the pre-age split file `allfrmats'
				generate deaths92 = 0
				forvalues i = 4/6 {
					generate deaths`i' = 0
				}
				forvalues i = 23/26 {
					generate deaths`i' = 0
				}
				
				** cleanup
				drop if cause == "" & year == .

				** save compiled split files
				tempfile splits
				save `splits', replace
				noisily display _newline "Saving splits tempfile"
				
				** store a summary of the deaths_sum at this stage
				preserve
				aorder
				egen deaths_sum = rowtotal(deaths3-deaths94)
				summary_store, stage("splits") currobs(${currobs}) storevars("deaths_sum") sexvar("sex_orig") frmatvar("frmat_orig") im_frmatvar("im_frmat_orig")
				restore
				
				
			// combine split data with frmats and age groups that did not need to be split
					// during the merge.  Also create a copy for use in frmats that cross the adult/infant divide
					foreach var of varlist deaths* {
						replace `var' = 0 if `var' == .
						gen `var'_tmp = `var'
					}
					
					// number each observation within each group, so we know which entry to replace later on
					bysort iso3 region dev_status location_id NID subdiv source *national ///
							*frmat* subdiv list sex year cause acause split: egen obsnum = seq()
					
					// fix deathsorig_all
					
					replace deathsorig_all = 0 if obsnum != 1
					
							preserve
							insheet using "$prefix/WORK/03_cod/01_database/02_programs/age_sex_splitting/maps/frmat_replacement_key.csv", comma clear
							tempfile replacement_key
							save `replacement_key', replace
						restore
						
						preserve
							insheet using "$prefix/WORK/03_cod/01_database/02_programs/age_sex_splitting/maps/frmat_im_replacement_key.csv", comma clear
							tempfile replacement_im_key
							save `replacement_im_key', replace
						restore

						
						merge m:1 frmat_orig split obsnum using `replacement_key', update replace
						drop if _m == 2
						drop _m
						
						merge m:1 im_frmat_orig split obsnum using `replacement_im_key', update replace
						drop if _m == 2
						drop _m
						
						** FIX FRMATS AND IM_FRMATS THAT CROSS THE ADULT/INFANT DIVIDE
							// fix deaths3 if im_frmat is 9
							replace deaths3 = deaths3_tmp if im_frmat_orig == 9
							
							// fix infant deaths if frmat is 9
							forvalues i = 91/94 {
								replace deaths`i' = deaths`i'_tmp if frmat_orig == 9
							}
							
							// fix infant deaths if im_frmat is 10
							local adult_deaths 3 7 8
							foreach i of local adult_deaths {
								replace deaths`i' = deaths`i'_tmp if im_frmat_orig == 10
							}

							// fix infant deaths if im_frmat is 11
							local adult_deaths 3 7 8 9 10 11 12 13 14 15 16 17
							foreach i of local adult_deaths {
								replace deaths`i' = deaths`i'_tmp if im_frmat_orig == 11
							}
							
							// fix infant formats if im_frmat is 05
							local adult_deaths 3
							foreach i of local adult_deaths {
								replace deaths`i' = deaths`i'_tmp if im_frmat_orig == 5
							}						
							// fix infant formats if im_frmat is 06
							local adult_deaths 3
							foreach i of local adult_deaths {
								replace deaths`i' = deaths`i'_tmp if im_frmat_orig == 6
							}						
							// fix infant formats if im_frmat is 12
							local adult_deaths 3 4
							foreach i of local adult_deaths {
								replace deaths`i' = deaths`i'_tmp if im_frmat_orig == 12
							}						
							// fix infant formats if im_frmat is 13
							local adult_deaths 3
							foreach i of local adult_deaths {
								replace deaths`i' = deaths`i'_tmp if im_frmat_orig == 13
							}						
							// fix infant formats if im_frmat is 14
							local adult_deaths 3
							foreach i of local adult_deaths {
								replace deaths`i' = deaths`i'_tmp if im_frmat_orig == 14
							}						
							// fix infant formats if im_frmat is 15
							local adult_deaths 3 4
							foreach i of local adult_deaths {
								replace deaths`i' = deaths`i'_tmp if im_frmat_orig == 15
							}

							// get rid of temporary deaths variables now that we've finished fixing frmats that 
							// cross the infant/adult divide
							foreach var of varlist deaths*tmp {
								drop `var'
							}
						
						** change marked observations to be missing
						foreach var of varlist deaths* {
							replace `var' = . if `var' == 9999
						}
						
					
					foreach var of varlist deaths91-deaths3 {
						replace `var' = . if nopop_im == 1 & obsnum == 1
					}
					
					foreach var of varlist deaths7-deaths22 {
						replace `var' = . if nopop_adult == 1 & obsnum == 1
					}
					
					foreach var of varlist deaths91-deaths22 {
						replace `var' = . if nopop_frmat9 == 1 & obsnum == 1
					}
					
					
							preserve
							// prepared data
							use `allfrmats', clear
							drop if sex == 9
							
												
							gen frmat_orig = frmat
							gen im_frmat_orig = im_frmat
							** *************************************************************************************************
							
							noisily display "Saving allfrmats_ageonly tempfile"
							tempfile allfrmats_ageonly
							save `allfrmats_ageonly', replace
							
							// store a summary of the deaths_sum and deaths1 at this stage
							aorder
							egen deaths_sum = rowtotal(deaths3-deaths94)
							summary_store, stage("allfrmats_ageonly") currobs(${currobs}) storevars("deaths_sum deaths1") sexvar("sex") frmatvar("frmat_orig") im_frmatvar("im_frmat_orig")
						restore
						
						** merge with age-split observations
						preserve
							
							drop if sex_orig == 9
							
							merge m:1 iso3 year sex cause acause *frmat_orig subdiv location_id NID source* using `allfrmats_ageonly', update
							
							noisily display "Saving postsplit_ageonly tempfile"
							tempfile postsplit_ageonly
							save `postsplit_ageonly', replace
							
							// store a summary of the deaths_sum and deaths1 at this stage
							aorder
							egen deaths_sum = rowtotal(deaths3-deaths94)
							summary_store, stage("postsplit_ageonly") currobs(${currobs}) storevars("deaths_sum deaths1") sexvar("sex") frmatvar("frmat_orig") im_frmatvar("im_frmat_orig")
						restore
					
						// age-sex-split and sex-split observations
							** prepare `allfrmats' to only include those observations which should have been age-sex-split
							preserve
								// prepare data
								use `allfrmats', clear
								keep if sex == 9
								
							
								gen frmat_orig = frmat
								gen im_frmat_orig = im_frmat
								
								
								noisily display "Saving allfrmats_agesexonly tempfile"
								tempfile allfrmats_agesexonly
								save `allfrmats_agesexonly', replace
								
								// store a summary of the deaths_sum and deaths1 at this stage
								aorder
								egen deaths_sum = rowtotal(deaths3-deaths94)
								summary_store, stage("allfrmats_agesexonly") currobs(${currobs}) storevars("deaths_sum deaths1") ///
									sexvar("sex") frmatvar("frmat_orig") im_frmatvar("im_frmat_orig")
								rename deaths_sum deaths
							restore
								
						
							// nopop_im
							preserve
								** determine which obs from the splitfiles weren't split because of nopop_im (we'll deal with nopop for frmat 9 later)
								keep if sex_orig == 9
								keep if nopop_im == 1 & nopop_frmat9 != 1
								
								** for these iso3/year/causes, merge with pre-split data so we can recover the deaths
								keep iso3 location_id NID source source_label source_type year cause cause_name list nopop* national subdiv dev_status region
								capture duplicates drop
								merge 1:m iso3 location_id NID source source_label source_type year cause cause_name list national subdiv dev_status region using `allfrmats_agesexonly', keep(3) nogenerate
								
								** zero out everything except the infant deaths that couldn't be split
								aorder
								foreach var of varlist deaths1-deaths26 {
									replace `var' = 0
								}
								
								** save file
								tempfile nopop_im
								save `nopop_im', replace
							restore
							
							// nopop_adult
							preserve
								** determine which obs from the splitfiles weren't split because of nopop_adult (we'll deal 
								** with nopop for frmat 9 later)
								keep if sex_orig == 9
								keep if nopop_adult == 1 & nopop_frmat9 != 1
								
								** for these iso3/year/causes, merge with pre-split data so we can recover the deaths
								keep iso3 location_id NID source source_label source_type year cause cause_name list nopop* national subdiv dev_status region
								capture duplicates drop
								merge 1:m iso3 location_id NID source source_label source_type year cause cause_name list national subdiv dev_status region using `allfrmats_agesexonly', keep(3) nogenerate
								
								** zero out everything except the adult deaths that couldn't be split
								aorder
								foreach var of varlist deaths91-deaths94 {
									replace `var' = 0
								}
								
								** save file
								tempfile nopop_adult
								save `nopop_adult', replace
							restore
							
							// nopop_frmat9
							preserve
								** determine which split data wasn't split because of either nopop_im or nopop_adult in frmat 9
								keep if sex_orig == 9
								keep if nopop_frmat9 == 1
								
								** for these iso3/year/causes, merge with pre-split data so we can recover the deaths
								keep iso3 location_id NID source source_label source_type year cause cause_name nopop*
								capture duplicates drop
								merge 1:m iso3 location_id NID source source_label source_type year cause cause_name using `allfrmats_agesexonly', keep(3) nogenerate
								
								** nothing was split successfully, so don't zero out any deaths in this case
								aorder
								
								** save file
								tempfile nopop_frmat9
								save `nopop_frmat9', replace
							restore
							
							// append these files together so we maintain all the deaths for sex-split observations
							keep if sex_orig == 9
							append using `nopop_im'
							append using `nopop_adult'
							append using `nopop_frmat9'
							noisily display "Saving postsplit_agesexonly tempfile"
							tempfile postsplit_agesexonly
							save `postsplit_agesexonly', replace
							
							// store a summary of the deaths_sum and deaths1 at this stage
							aorder
							egen deaths_sum = rowtotal(deaths3-deaths94)
							summary_store, stage("postsplit_agesexonly") currobs(${currobs}) storevars("deaths_sum deaths1") ///
								sexvar("sex") frmatvar("frmat_orig") im_frmatvar("im_frmat_orig")
									
					// combine both age-split and age-sex-split observations
					use `postsplit_ageonly', clear
					append using `postsplit_agesexonly'

				** since we have multiple observations per group, collapse to get a total count
					// first make sure that the proper things are set to missing; if the original im_frmat was 3, we 
					// don't have any information about deaths94; set it missing
					replace deaths94 = . if im_frmat_orig == 3 & frmat_orig != 9
				
					// collapse sums up missing entries to make 0, so we need to mark the groups where all the observations
					// for a variable are missing
						** create a group variable rather than always sorting on all these variables
						egen group = group(iso3 region dev_status location_id NID subdiv source* *national ///
							frmat im_frmat subdiv list sex year cause acause), missing
						
						** loop through variables, creating a miss_`var' variable that records whether all the observations within
						** the group have missing for the variable `var'
						foreach var of varlist deaths* {
							bysort group (`var'): gen miss_`var' = mi(`var'[1])
						}
					
					// do the collapse, retaining the value for miss_`var'
					collapse (sum) deaths* (mean) miss* nopop*, by(iso3 location_id ///
						subdiv source* NID *national frmat im_frmat list sex year cause cause_name acause region dev_status)
					
					// use miss_`var' to inform which variables need to be reverted back to missing
					foreach var of varlist deaths* {
						di "`var'"
						replace `var' = . if miss_`var' != 0
					}
					drop miss*
				
				
			// final adjustments and formatting
				
				capture drop tmp
				egen tmp = rowtotal(deaths91-deaths22 deaths26), missing
				drop if tmp == .
				drop tmp

				
					// first create country-year-sex-age proportions by codmod cause
					aorder
					capture drop deaths_known
					
					// temporarily generate a deaths23 that incorporates deaths23-deaths25 (we correct restriction violations 
					// after age splitting and we need deaths24 and 25)
					gen deaths23_tmp = deaths23
					capture drop tmp
					egen tmp = rowtotal(deaths23 deaths24 deaths25)
					replace deaths23 = tmp if frmat != 9
					drop tmp

					// find out how many deaths we've ended up with after splitting
					egen deaths_known = rowtotal(deaths3-deaths23 deaths91-deaths94)
					

					capture drop totdeaths
					bysort iso3 location_id year sex $codmod_level source* NID: egen totdeaths = total(deaths_known)
					
					foreach i of numlist 3/23 91/94 {
						bysort iso3 location_id year sex $codmod_level source* NID: egen num`i' = total(deaths`i')
						generate codmodprop`i' = num`i'/totdeaths
					
						** now redistribute the remaining deaths26
						generate new_deaths`i' = deaths`i' + (deaths26*codmodprop`i')
					
						** replace deaths = newdeaths where frmat is still 9
						replace deaths`i' = new_deaths`i' if frmat == 9
					}
					
				
					aorder
					egen numtot = rowtotal(num*)
						
				
					foreach i of numlist 3/23 91/94 {
						replace deaths`i' = 0 if deaths`i' == .
					}
					
					bysort $codmod_level: egen totknown = total(deaths_known)
					foreach i of numlist 3/23 91/94 {
						bysort $codmod_level: egen totnum`i' = total(deaths`i')
						generate totprop`i' = totnum`i'/totknown
						generate othernew`i' = deaths`i' + (deaths26*totprop`i')
						replace deaths`i' = othernew`i' if frmat == 9 & numtot == 0
					}
					
					// do some final cleanup
					replace deaths23 = deaths23_tmp if frmat != 9
					drop deaths23_tmp
					replace frmat = 2 if frmat == 9
					replace deaths26 = 0	
				
				** recalculate deaths1
				aorder
				capture drop tmp
				egen tmp = rowtotal(deaths3-deaths94)
				replace deaths1 = tmp
				drop tmp
				
				
			// warn user if nopop
			count if nopop_adult != 0 & nopop_adult != .
			if r(N) > 0 {
				preserve
				local numobs = r(N)
				egen totadult = rowtotal(deaths3-deaths25)
				summ totadult if nopop_adult != 0 & nopop_adult != .
				noisily di in red "WARNING: Missing adult population numbers.  " ///
					"`numobs' observations and `r(sum)' deaths not split for adults.  "
				keep if nopop_adult != 0 & nopop_adult != .
				keep iso3 location_id year
				duplicates drop
				sort iso3 year
				noisily di in red "The following country-years are missing adult population numbers:"
				noisily list
				restore
			}

			count if nopop_im != 0 & nopop_im != .
			if r(N) > 0 {
				preserve
				local numobs = r(N)
				summ deaths91 if nopop_im != 0 & nopop_im != .
				noisily di in red "WARNING: Missing infant population numbers.  " ///
					"`numobs' observations and `r(sum)' deaths not split for infants.  "
				keep if nopop_im != 0 & nopop_im != .
				keep iso3 location_id year
				duplicates drop
				sort iso3 year
				noisily di in red "The following country-years are missing infant population numbers:"
				noisily list
				restore
			}

			count if nopop_frmat9 != 0 & nopop_frmat9 != .
			if r(N) > 0 {
				preserve
				keep if nopop_frmat9 != 0 & nopop_frmat9 != .
				keep iso3 location_id year
				duplicates drop
				sort iso3 year
				noisily di in red "WARNING: Missing population numbers AND frmat 9.  Big problems.  " ///
					"(Deaths in deaths26 have been lost.)  The following country-years are problematic:"
				noisily list
				restore
			}


			// drop variables we don't need
			drop nopop* *orig* codmodprop* num* new_deaths* tot* other* deaths_known

			// store a summary of the deaths_sum and deaths1 and export to .csv
			preserve
				egen deaths_sum = rowtotal(deaths3-deaths94)
				summary_store, stage("end") currobs(${currobs}) storevars("deaths_sum deaths1") sexvar("sex") ///
					frmatvar("frmat") im_frmatvar("im_frmat")

				** export to Stata dataset
				clear
				getmata stage sex sex_orig deaths_sum deaths1 frmat frmat_orig im_frmat im_frmat_orig
				drop if stage == ""
				
				** calculate useful comparisons
					// difference between stage-specific deaths_sum and deaths1 (not expected to be correct for postsplit 
					// files, so make these missing).  NOTE: these should match!
					gen stage_diff = deaths_sum - deaths1
					replace stage_diff = . if regexm(stage, "postsplit")
					
					// calculate death differences
					local deaths_diff = $allfrmats_deaths_sum - $end_deaths_sum
					local deaths_to_split = $temp_to_agesplit_deaths_sum + $temp_to_agesexsplit_deaths_sum
					local split_diff = `deaths_to_split' - $splits_deaths_sum
					local ageonly_diff = $allfrmats_ageonly_deaths_sum - $postsplit_ageonly_deaths_sum
					local agesexonly_diff = $allfrmats_agesexonly_deaths_sum - $postsplit_agesexonly_deaths_sum
								
				** report important comparisons
					// total deaths
					noisily di in red _newline "Total deaths"
					noisily di "# of deaths at start: ${allfrmats_deaths_sum}" _newline ///
						"# of deaths at end: ${end_deaths_sum}" _newline ///
						"Total deaths lost during splitting: `deaths_diff'"
					if `deaths_diff' > 0.01 {
						noisily di in red "***WARNING: More than 0.01 deaths lost during the agesexsplitting process!***"
					}
							
					// deaths that should have been split
					noisily di in red _newline "Deaths that should have been split (includes both agesplit and sexsplit)"
					noisily di "# of deaths to be split: `deaths_to_split'" _newline ///
						"# of deaths after splitting: ${splits_deaths_sum}" _newline ///
						"Deaths lost during splitting stage: `split_diff'"
					
					// observations to have been agesplit only		
					noisily di in red _newline "Observations to have been agesplit only"
					noisily di "# of deaths in original file to be agesplit: ${allfrmats_ageonly_deaths_sum}" _newline ///
						"# of deaths in postsplit file that were agesplit: ${postsplit_ageonly_deaths_sum}" _newline ///
						"Deaths lost during age-splitting: `ageonly_diff'"
					
					// observations to have been agesexsplit only
					noisily di in red _newline "Observations to have been agesexsplit only"
					noisily di "# of deaths in original file to be agesexsplit: ${allfrmats_agesexonly_deaths_sum}" _newline ///
						"# of deaths in postsplit file that were agesexsplit: ${postsplit_agesexonly_deaths_sum}" _newline ///
						"Deaths lost during agesex-splitting: `agesexonly_diff'"
					
				
				
			restore
		}
		else {
			noisily display "All observations are in the desired age and sex formats.  No splitting required."
		}
		
				** recalculate deaths2
				egen imtot = rowtotal(deaths91 deaths92 deaths93 deaths94)
				capture gen deaths2 = 0
				replace deaths2 = imtot
				drop imtot	
	}		
	
	// Save dataset
		compress
		collapse(sum) deaths*, by(iso3 location_id year sex acause cause cause_name NID source source_label source_type list national subdiv region dev_status im_frmat frmat) fast
		save "$source_dir/02_agesexsplit.dta", replace
		save "$source_dir/02_agesexsplit_${timestamp}.dta", replace

	// Check sex
		count if sex != 1 & sex != 2
		if `r(N)' > 0 {
			display in red "ERROR: THERE ARE SEXES THAT ARE NOT MALES OR FEMALES IN HERE!"
			BREAK
		}
	
	// Reformat
		// Bring location ID out of source variable
			drop location_id
			rename source location_id
			destring location_id, replace
		// Merge on ihme_loc_id based on location_id	
			merge m:1 location_id using `gbd_geography', keep(1 3) assert(2 3) keepusing(ihme_loc_id) nogen
		
	// Keep only what we need
		keep deaths* ihme_loc_id location_id year sex acause subdiv
		
	// Collapse
		collapse (sum) deaths*, by(ihme_loc_id location_id year sex acause subdiv) fast
		
	// Reshape ages long
		gen obs = _n
		reshape long deaths@, i(obs ihme_loc_id location_id year sex acause subdiv) j(gbd_age)
		drop obs
		gen age = .
		replace age = 0 if gbd_age == 91
		replace age = .01 if gbd_age == 93
		replace age = .1 if gbd_age == 94
		replace age = 1 if gbd_age == 3
		foreach i of numlist 7/22 {
			local j = (`i'-6)*5
			replace age = `j' if gbd_age == `i'
		}
		drop if age == .
		drop gbd_age
				
	// Reshape draws wide
		collapse (sum) deaths, by(ihme_loc_id location_id year sex acause subdiv age) fast
		rename deaths draw_
		replace subdiv = subinstr(subdiv,"d","",.)
		destring(subdiv), replace
		reshape wide draw_, i(ihme_loc_id location_id year sex age acause) j(subdiv)
	// Save
		compress
		save "/ihme/scratch/users/${username}/`metric_folder'/`acause'/99_final_format/`ihme_loc_id'_formatted.dta", replace
	
	capture log close


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
