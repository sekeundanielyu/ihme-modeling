// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Date: 			4 June 2014
// Project:		RISK
// Purpose:		launch script do file - parallelize calculation of population attributable fraction of HIV prevalence due to intimate partner violence, by groups of 10 draws
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
// Set seed for random draws
	set seed 963066483
	
// Set repo local 
	local repo `1'

// Create macros for settings, files and filepaths
	local version 2 // increase by 1 for every run
	local healthstate "abuse_ipv"
	//local risk "abuse_ipv_hiv" 
	local acause = "hiv"
	local integrand "incidence" // actually want prevalence, but results are stored as incidence for prevalence only models
	local sex "female"
	local years "1990 1995 2000 2005 2010 2015"
	
	local rr_dir "$prefix/WORK/05_risk/risks/abuse_ipv_hiv/data/rr"
	local code_dir "`repo'/abuse_ipv/04_paf/hiv"
	local data_dir "$prefix/WORK/05_risk/risks/abuse_ipv_hiv/data"
	local out_dir "/share/epi/risk/temp/ipv_hiv_pafs/v`version'"

// Make a directory for storing intermediate PAF files & for versioning
	cap mkdir "`out_dir'"

// Get ISO3 with subnational location ids
	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & most_detailed == 1 

	keep ihme_loc_id location_id location_ascii_name super_region_name super_region_id region_name region_id 
	
	rename ihme_loc_id iso3 
	tempfile country_codes
	save `country_codes', replace

	levelsof location_id, local(locations)
		
// Prepare relative risk for HIV due to IPV [note that relative risks are actually incidence rate ratios (i.e. for HIV incidence, not prevalence)]
	// Meta-analysis 	
		ssc install metan 

		import excel using "`rr_dir'/raw/rr_component_studies.xlsx", firstrow clear
		keep if RelativeRisk == "IPV-HIV"
		metan EffectSize Lower Upper, random
		local rr r(ES) // 1.59 (1.27, 1.91)
		local upper = r(ci_upp)
		local lower = r(ci_low) 
		
	// 1,000 draws from normal distribution
		local sd = ((ln(`upper')) - (ln(`lower'))) / (2*invnormal(.975))
		clear
		set obs 1
		forvalues d = 0/999 {
			gen rr_`d' = exp(rnormal(ln(`rr'), `sd'))
		}
		
	// Make identifier for merge with Dismod model
		gen x = 1
	
	// Save relative risk draws for PAF calculation
		save "`rr_dir'/prepped/`acause'_rr_draws.dta", replace 
	
// 3.) Parellize by 10 groups of 100 draws
	**  Make local to be filled with the list of each job that must finish before the compilation/formatting code can be launched
		local holdlist ""
	
	** Loop through draws and launch jobs
		//cd "`out_dir'"

	// test locations 
	//local locations 482 483 484 485 486 487 488 489 490

	foreach iso3 of local locations { 
		forvalues i = 99(100)999 {
			local draw_num = `i'
			!qsub -N "ipv_hiv`iso3'_`i'" -P proj_custom_models -l mem_free=20G -pe multi_slot 4 ///
			"`code_dir'/stata_shell.sh" ///
			"`code_dir'/02_hiv_paf.do" ///
			"`version' `draw_num' `iso3'"
			
			/*
			** Add each unique job name to the hold list
			if "`holdlist'" == "" {
				local holdlist ipv_`acause'`i'
			}
			else {
				local holdlist `holdlist',ipv_`acause'`i'
			}
			*/
		}
	}	

/*
// 4.) Launch job that gets the PAFs in the correct format for the DALYnator, once all parallel jobs have finished 
	!/usr/local/bin/SGE/bin/lx24-amd64/qsub -N format_ipv_hiv -hold_jid `holdlist' -l mem_free=4G ///
	"`code_dir'/stata_shell.sh" ///
	"`code_dir'/03_format_paf.do" ///
	"sex(`sex') version(`version') data_dir(`data_dir') outdir(`outdir') acause(`acause') years(`years') risk(`risk')" 
	
	
