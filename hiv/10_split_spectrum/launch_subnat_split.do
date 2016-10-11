// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Parallelization to split Spectrum national-level results into child subnationals
//					using CoD death data and populations

** ***************************************************************************
** Set locals and get maps
	// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
		local spec_name = "`1'"
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

	** Set code directory for Git
	local user "`c(username)'"
	local code_dir = "strPath" 
	local prop_out_dir = "/strPath"
	local out_dir = "/strPath"

	// Get locations to parallelize over
	local agg_countries = "IND_minor" // What locations do we need to aggregate from more granular Spectrum output, rather than the other way around?
	adopath + "strPath"
	get_locations, level(lowest)
	drop if parent_id == 6 // Drop HKG, Macau, and CHN mainland since those are all produced already by Spectrum (use CHN mainland as CHN)
	keep if level != 3 // Drop all national countries
    keep if regexm(ihme_loc_id,"KEN") | regexm(ihme_loc_id,"IND") // We now produce lowest-level results for all subnationals except KEN and IND
	levelsof ihme_loc_id, local(subnat_countries) c
	keep ihme_loc_id parent_id level
	tempfile temp
	save `temp'
	
	get_locations
	keep ihme_loc_id location_id
	rename location_id parent_id
	rename ihme_loc_id parent_loc_id
	tempfile parent
	save `parent'
	merge 1:m parent_id using `temp', keep(3) nogen
	replace parent_loc_id = "GBR" if parent_loc_id == "GBR_4749"
	replace parent_loc_id = "IND" if regexm(parent_loc_id,"IND")
	levelsof parent_loc_id, local(parents) c

	

** ***************************************************************************
** Submit parent-country jobs for prepping the proportional splits of Spectrum results

	// set memory (gb) for each job
		local mem 8
	// set mem/slots and create job checks directory
	if `mem' < 2 local mem 2
	local slots = ceil(`mem'/2)
	local mem = `slots' * 2

	// Delete existing files
	! rm `prop_out_dir'/props_*.dta

	// Submit jobs
	// local parents "KEN"
	local n 0
	foreach iso3 of local parents {
			! qsub -N gen_props_`iso3' -pe multi_slot `slots' -l mem_free=`mem' ///
			-e /share/temp/sgeoutput/`user'/errors -o /share/temp/sgeoutput/`user'/output ///
			-P proj_hiv -p -2 "`code_dir'/stata_shell.sh" "`code_dir'/split_gen_props.do" "`iso3'"
			local ++n
	}

	// Wait for all jobs to finish
	local target_total: word count `parents'
	local affirm = 0
	while `affirm' == 0 {
		local total = 0
		foreach iso3 of local parents {
			local draws : dir "`prop_out_dir'" files "props_`iso3'.dta", respectcase
			local count : word count `draws'
			local total = `total' + `count'
		}
		if (`total' == `target_total') local affirm = 1
		else {
			di "Checking `c(current_time)': `total' of `target_total' proportion jobs finished"
			sleep 30000
		}
	}

	di "Done"


** ***************************************************************************
** Submit aggregation jobs for getting IND minor territories parent from the subnational places	
	// set memory (gb) for each job
	local mem 4
	// set mem/slots and create job checks directory
	if `mem' < 2 local mem 2
	local slots = ceil(`mem'/2)
	local mem = `slots' * 2
	
	foreach iso3 of local agg_countries {
		// Delete existing files
			// ! rm "`out_dir'/best/`iso3'_ART_data.csv"
            ! rm "`out_dir'/stage_2/`iso3'_ART_data.csv"
			! rm "`out_dir'/stage_1/`iso3'_ART_data.csv"

		// Submit
			! qsub -N agg_`iso3' -pe multi_slot `slots' -l mem_free=`mem' ///
			-e /share/temp/sgeoutput/`user'/errors -o /share/temp/sgeoutput/`user'/output ///
			-P proj_hiv -p -2 "`code_dir'/stata_shell.sh" "`code_dir'/subnat_aggregate.do" "`iso3' `out_dir'"
			local ++n
	}
	
	local target_total: word count `agg_countries'
	local affirm = 0
	local counter = 0
	while `affirm' == 0 {
		local total = 0
		foreach iso3 in `agg_countries' {
			local draws : dir "`out_dir'/stage_2" files "`iso3'_ART_data.csv", respectcase
			local count1 : word count `draws'
			local draws : dir "`out_dir'/stage_1" files "`iso3'_ART_data.csv", respectcase
			local count2 : word count `draws'
			if `count1' == 0 & `count2' == 0 & `counter' > 10 di "`iso3' is still missing"
			local total = `total' + `count1' + `count2'
		}
		if (`total' == `target_total') local affirm = 1
		else {
			di "Checking `c(current_time)': `total' of `target_total' splitting jobs finished"
			sleep 30000
			local ++counter
		}
	}
	
	sleep 30000 // Sleep to allow csv to write for a bit longer

	sleep 30000 // Add room for IND child to breathe
	
** ***************************************************************************
** Submit child country jobs to apply the proportional splits to the Spectrum results
	
	// set memory (gb) for each job
		local mem 4
	// set mem/slots and create job checks directory
	if `mem' < 2 local mem 2
	local slots = ceil(`mem'/2)
	local mem = `slots' * 2

	// Launch all level 4 countries first
		local n 0
		foreach iso3 of local subnat_countries {
			// Delete existing files
				! rm "`out_dir'/stage_2/`iso3'_ART_data.csv"
				! rm "`out_dir'/stage_1/`iso3'_ART_data.csv"

			// Submit
				! qsub -N hiv_split_`iso3' -pe multi_slot `slots' -l mem_free=`mem' ///
				-e /share/temp/sgeoutput/`user'/errors -o /share/temp/sgeoutput/`user'/output ///
				-P proj_hiv -p -2 "`code_dir'/stata_shell.sh" "`code_dir'/split_subnationals.do" "`iso3' `out_dir'"
				local ++n
		}
		
		local target_total: word count `subnat_countries'
		local affirm = 0
		local counter = 0
		while `affirm' == 0 {
			local total = 0
			local iso_list = ""
			foreach iso3 in `subnat_countries' {
				local draws : dir "`out_dir'/stage_2" files "`iso3'_ART_data.csv", respectcase
				local count1 : word count `draws'
				local draws : dir "`out_dir'/stage_1" files "`iso3'_ART_data.csv", respectcase
				local count2 : word count `draws'
				local total = `total' + `count1' + `count2'
				if `count1' == 0 & `count2' == 0 local iso_list = "`iso_list' `iso3'"
			}
			if (`total' == `target_total') local affirm = 1
			else {
				di "Checking `c(current_time)': `total' of `target_total' splitting jobs finished"
				if `total' > 60 di "`iso_list' is still missing"
				sleep 30000
				local ++counter
			}
		}
	


	di "Done"
