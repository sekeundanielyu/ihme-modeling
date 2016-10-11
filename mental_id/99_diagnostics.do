
//Purpose: Graph important outputs from each step file, append into one pdf 

//Running interactively on cluster 
** do "/ihme/code/epi/struser/id/99_diagnostics.do"
	local cluster_check 0
	if `cluster_check' == 1 {
		local 1		"/home/j/temp/struser/imp_id"
		local 2		"/ihme/scratch/users/struser/id/tmp_dir" 
		local 3		"2016_04_27"
		local 4		"99"
		local 5		"diagnostics"
		local 7		"58"
		}

// LOAD SETTINGS FROM STEP CODE (NO NEED TO EDIT THIS SECTION)
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

		local location_id `7'

**Define directories 
		// directory for external inputs 
		local in_dir "$prefix/WORK/04_epi/01_database/02_data/imp_id/04_models/02_inputs"
		// directory for output on the J drive
		local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
		// directory for output on clustertmp
		local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

	//Define useful gbd codes (ie age_group_id)
			get_location_metadata, location_set_id(9) clear 
			keep location_id location_name super_region_id super_region_name
			drop if super_region_id == . 
			duplicates drop location_id, force
			tempfile gbd_locations
			save `gbd_locations', replace 

			query_table, table_name(age_group) clear 
			keep age_group_id age_group_years_start age_group_years_end
			keep if age_group_id <= 21 //5yr ranges 
			drop if age_group_id == 1 //for now, let's ignore 0-5 and instead use smaller ranges 
			gen age_mid = (age_group_years_start + age_group_years_end) / 2
			gen age = round(age_group_years_start, 1) //just for easy graphing (age_mid is ugly)
			tempfile gbd_ages
			save `gbd_ages', replace 



	local location_ids "18 89 97 128 214 62" // "18 89 97 128 214 62" Thailand Netherlands Argentina Guatemala Nigeria Russia
	local years 2000
	local sexes "1 2"
	

	*local location_id 58
	local year_id 2000
	local sex_id 1
	foreach location_id of local location_ids {
	** foreach sex of local sexes {
	** foreach year of local years {

	use `gbd_locations' if location_id == `location_id', clear 
		local location_name = location_name
		if `sex_id' == 1 local sex = "Male" 
		if `sex_id' == 2 local sex = "Female" 

do "$prefix/Usable/Tools/ADO/pdfmaker_Acrobat11.do"
pdfstart using "`out_dir'/diagnostic_graphs_`location_name'_`year_id'_`sex'.pdf"
	
	**************************
	*** STEP 02
	**************************

	//SEE FOREST PLOTS THAT ARE CREATED WITHIN STEP 2 CODE 

	**************************
	*** STEP 03_split_sev_env
	**************************
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/03_split_sev_env"

	use "`tmp_dir'/03_outputs/01_draws/id_sev_envelopes_loc`location_id'" if year_id == `year_id' & sex_id == `sex_id', clear 
	merge m:1 age_group_id using `gbd_ages', nogen keep(3)
	merge m:1 location_id using `gbd_locations', nogen keep(3)
	
		local location_name = location_name
		if `sex_id' == 1 local sex = "Male" 
		if `sex_id' == 2 local sex = "Female" 


	levelsof healthstate, local(states)
	foreach state in `states' {
		egen `state' = rowmean(draw*) if healthstate == "`state'"
		}

	graph bar id_under70, over(age) title("`location_name' `year_id' `sex' Intellectual Disability") subtitle("IQ <70 envelope")
	pdfappend
	graph bar id_prof id_sev id_mod id_mild, over(age) stack title("`location_name' `year_id' `sex' Intellectual Disability") subtitle("By severity")
	pdfappend
	graph bar id_prof id_sev id_mod id_mild id_bord, over(age) stack title("`location_name' `year_id' `sex' Intellectual Disability") subtitle("By severity - Borderline included")
	pdfappend

pdffinish


* } // next year 
* } // next sex
} // next location_id


di in red "DIAGNOSTICS SAVED AT" _new "`out_dir'/diagnostic_graphs_loc`location_id'_year`year_id'_sex`sex_id'.pdf"
