// *********************************************************************************************************************************************************************


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
		// directory for steps code
		local code_dir `6'
		local location_id `7'

		}
	
	
	//Assign income status
	get_location_metadata, location_set_id(9) clear 
	levelsof location_id if super_region_name == "High-income", local(locs_hic) sep(,)
	local hic = 0
	if inlist(`location_id', `locs_hic') local hic = 1
		di "High Income Status = `hic'"

	//Load gbd ages 
	query_table, table_name(age_group) clear 
			keep if age_group_id <= 21 //5yr ranges 
			drop if age_group_id == 1 
			gen n = 1 
			keep n age_group_id
			tempfile gbd_ages
			save `gbd_ages', replace 



	********************************************************************
	*** Generate severity-specific ID envelopes 
	********************************************************************

	// Load severity proportions from last step 
	use "`root_j_dir'/03_steps/`date'/02_gen_sev_props/sev_props" if HIC == `hic', clear 
	tempfile props
	save `props', replace 

	// pull in the IQ <70 envelope (DisMod)
	else get_draws, source(epi) gbd_id_field(modelable_entity_id) gbd_id(2420) measure_ids(5) location_ids(`location_id') year_ids(1990 1995 2000 2005 2010 2015) sex_ids(1 2) clear
		keep if age_group_id <= 21
		tempfile draws
		save `draws', replace
		
	// define severity healthstates
	local severities "id_mild id_mod id_sev id_prof id_bord"

	//APPLY SPLITS 
	local i 0
	foreach severity of local severities {
		use `draws', clear 
		gen healthstate = "`severity'"
		merge m:1 healthstate using `props', keep(3) nogen
		
		forvalues num = 0/999 {
			qui replace draw_`num' = draw_`num' * v`num' 
			}
		
		drop v*
		if `i' == 0 tempfile envelopes
		else append using `envelopes'
		save `envelopes', replace 
		local ++ i 
	}
	
	//SAVE 	
	drop income HIC x2 x3 _varname 
	order measure_id location_id year_id age_group_id sex_id healthstate draw_*
	sort healthstate measure_id location_id year_id age_group_id sex_id
	save `envelopes', replace 

	//Save for diagnostics 
	append using `draws'
	replace healthstate = "id_under70" if healthstate == ""
	save "`tmp_dir'/03_outputs/01_draws/id_sev_envelopes_loc`location_id'", replace 


******* Format for save_results: need one csv for each loc-year-sex
//Loop over every year and sex for given location 
	//year_ids
		local year_ids "1990 1995 2000 2005 2010 2015"
	//sex_ids
		local sex_ids "1 2"

	foreach year_id in `year_ids' {
		foreach sex_id in `sex_ids' {

			
			*** SAVE ENVELOPES (PREVALENCE)
				foreach severity of local severities {
					* 9423	Borderline intellectual disability impairment envelope
					if "`severity'" == "id_bord" local meid 9423
					* 9424	Mild intellectual disability impairment envelope
					if "`severity'" == "id_mild" local meid 9424
					* 9425	Moderate intellectual disability impairment envelope
					if "`severity'" == "id_mod" local meid 9425
					* 9426	Severe intellectual disability impairment envelope
					if "`severity'" == "id_sev" local meid 9426
					* 9427	Profound intellectual disability impairment envelope
					if "`severity'" == "id_prof" local meid 9427

				use `envelopes' if healthstate == "`severity'" & year_id == `year_id' & sex_id == `sex_id', clear 
					drop healthstate
					capture mkdir "`out_dir'/03_outputs/01_draws/`meid'"
				outsheet using "`out_dir'/03_outputs/01_draws/`meid'/5_`location_id'_`year_id'_`sex_id'.csv", c replace
				} //Next severity 

		//Next sex	
		}
	//Next year 
	}

// *********************************************************************************************************************************************************************
