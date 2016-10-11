// Purpose: GBD 2015 Soil Transmitted Helminthiasis (STH) Estimates
// Description:	Take GBD 2010 draws, copy to cluster and interpolate for 1990-2010, and extrapolate to 2015. Do this for 
//                      all infection (parent), medium infection (mild abdominal pain), and heavy infection. Wasting and anaemia
//                      are calculated separately elsewhere, given heavy infection and all hookworm infection, respectively.

// LOAD SETTINGS FROM MASTER CODE

	// prep stata
	clear all
	set more off
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

	// base directory on J 
	local root_j_dir `1'
	// base directory on ihme/gbd (formerly clustertmp)
	local root_tmp_dir `2'
	// timestamp of current run (i.e. 2015_11_23)
	local date `3'
	// step number of this step (i.e. 01a)
	local step `4'
	// name of current step (i.e. first_step_name)
	local step_name `5'
	// step numbers of immediately anterior parent step (i.e. first_step_name)
	local hold_steps `6'
	// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
	local last_steps `7'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step'_`step_name'"
	// directory for output on ihme/gbd (formerly clustertmp)
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step'_`step_name'/03_outputs/01_draws"
	// directory for standard code files
	adopath + $prefix/WORK/10_gbd/00_library/functions
	adopath + $prefix/WORK/10_gbd/00_library/functions/utils
	quietly do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"

	di "`out_dir'/02_temp/02_logs/`step'.smcl"
	cap log using "`out_dir'/02_temp/02_logs/`step'.smcl", replace
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


// Specify paths for saving draws
  // Ascariasis
    cap mkdir "`tmp_dir'/ascar_inf_all"
    cap mkdir "`tmp_dir'/ascar_inf_heavy"
    cap mkdir "`tmp_dir'/ascar_inf_med"
  // Trichuriasis
    cap mkdir "`tmp_dir'/trich_inf_all"
    cap mkdir "`tmp_dir'/trich_inf_heavy"
    cap mkdir "`tmp_dir'/trich_inf_med"
  // Hookworm
    cap mkdir "`tmp_dir'/hook_inf_all"
    cap mkdir "`tmp_dir'/hook_inf_heavy"
    cap mkdir "`tmp_dir'/hook_inf_med"

// Create draw file with zeroes for countries without file in GBD 2010 (i.e. assuming no burden in those countries)
  clear
  quietly set obs 18
  quietly generate double age = .
  quietly format age %16.0g
  quietly replace age = _n * 5
  quietly replace age = 0.1 if age == 85
  quietly replace age = 1 if age == 90
  sort age

  generate double age_group_id = .
  format %16.0g age_group_id
  replace age_group_id = _n + 3

  forvalues i = 0/999 {
    quietly generate draw_`i' = 0
  }

  quietly format draw* %16.0g

  tempfile zeroes
  save `zeroes', replace
  
// Produce draws from GBD 2010 source files
// NB: the code for this part was from "create_final_custom_model.do" in the folder
// "$prefix/Project/GBD/Causes/Parasitic and Vector Borne Diseases/Hookworm". Adaptations were made
// so that the code would run in the GBD 2013 framework. This code produces figures for all infection,
// medium infection, and heavy infection. No disability is attributed to light infection.
  quietly {
    local get_data "$prefix/Project/GBD/Causes/Parasitic and Vector Borne Diseases/Hookworm"
  // use total data and merge on new china data
    insheet using "`get_data'/china_update.csv", double names clear	//has 2005 CHN data (mapvar2)
    tempfile china_data
    save `china_data', replace
    
    use "`get_data'/ALL_DATA_reshaped.dta", clear	//has all data including CHN 2005 (mapvar); these get replaced with the new CHN data (mapvar2)
    merge 1:1 iso3 year age intensity helminth_type using "`china_data'", keep(master match) nogen
    //update mapvar with mapvar2
	replace mapvar = mapvar2 if mapvar2 != .
    replace lower = lower2 if lower2 != .
    replace upper = upper2 if upper2 != .
    sort iso3 age intensity helminth_type year
    bysort iso3 age intensity helminth_type : replace mapvar2 = mapvar2[_n-1] if missing(mapvar2)
    bysort iso3 age intensity helminth_type : replace lower2 = lower2[_n-1] if missing(lower2)
    bysort iso3 age intensity helminth_type : replace upper2 = upper2[_n-1] if missing(upper2)
    replace lower = lower2 if mapvar2 < mapvar & helminth_type == "hk"
    replace upper = upper2 if mapvar2 < mapvar & helminth_type == "hk"
    replace mapvar = mapvar2 if mapvar2 < mapvar & helminth_type == "hk"
    replace lower = lower2 if mapvar2 < mapvar & helminth_type == "tt"
    replace upper = upper2 if mapvar2 < mapvar & helminth_type == "tt"
    replace mapvar = mapvar2 if mapvar2 < mapvar & helminth_type == "tt"
    drop *2
	
	//add these changes for GBD 2015
	replace countryname = "Virgin Islands, U.S." if countryname == "British Virgin Islands"
	replace countryname = "Guinea-Bissau" if countryname == "Guinea Bissau"
	replace countryname = "North Korea" if countryname == "Korea, North"
	replace countryname = "Libya" if countryname == "Libyan Arab Jamahiriya"
	replace countryname = "Federated States of Micronesia" if countryname == "Micronesia (Federated States of)"
	replace countryname = "Saint Vincent and the Grenadines" if countryname == "St Vincent"
	replace countryname = "Syria" if countryname == "Syrian Arab Republic"
	replace countryname = "Timor-Leste" if countryname == "Timor Leste"
	replace countryname = "United Arab Emirates" if countryname == "United Arab Emerates"
	replace countryname = "Tanzania" if countryname == "United Republic of Tanzania"
	replace countryname = "Vietnam" if countryname == "Viet Nam"
	
    tempfile all_data
    save `all_data'
	
    
    use "`get_data'/data/Africa_2010.dta", clear
    drop ttprev
    sort iso3 age intensity helminth_type year
    expand 3
    bysort iso3 age intensity helminth_type: gen x=_n
    replace year = 1990 if x == 1
    replace year = 2005 if x == 2
    replace year = 2010 if x == 3
	
	//add these changes for GBD 2015
	replace countryname = "The Gambia" if countryname == "Gambia"
	replace countryname = "Guinea-Bissau" if countryname == "Guinea Bissau"
	replace countryname = "Tanzania" if countryname == "United Republic of Tanzania"
	
    tempfile africa
    save `africa', replace

        insheet using "`get_data'/STH_reductions.csv", double names clear
      
    rename country countryname
    rename *_2005_2010 *
    reshape long asc_ tt_ hk_, i(countryname coverage) j(age) string
    rename *_ *
    rename asc helminth_type_asc
    rename hk helminth_type_hk
    rename tt helminth_type_tt
    reshape long helminth_type_, i(countryname coverage age) j(helminth_type) string
    rename helminth_type_ adjustment_factor
    expand 2
    bysort countryname helminth_type age: gen x = _n
    replace age = "0to4" if age == "rest" & x == 1
    replace age = "15plus" if age == "rest" & x == 2
    replace age = "5to9" if age == "sac" & x == 1
    replace age = "10to14" if age == "sac" & x == 2
    gen year = 2010
    drop x
    sort countryname age helminth_type
	
	//add these changes for GBD 2015
	replace countryname = "Cote d'Ivoire" if countryname == "Côte d'Ivoire"
	replace countryname = "North Korea" if countryname == "Democratic People's Republic of Korea"
	replace countryname = "Guinea-Bissau" if countryname == "Guinea Bissau"
	replace countryname = "Laos" if countryname == "Lao People's Democratic Republic"
	replace countryname = "Venezuela" if countryname == "Venezuela (Bolivarian Republic of)"
	replace countryname = "Vietnam" if countryname == "Viet Nam"

    tempfile adjust
    save `adjust', replace
    //`adjust' has vars countryname coverage(community/sch), age, helminth_type, adjustment_factor, year
	
    use "`africa'", clear
    merge m:1 countryname age helminth_type year using "`adjust'"
    keep if _m == 1 | _m == 3
    drop _m
    gen new_2005_mapvar = mapvar * (1 + adjustment_factor) if year == 2010
    gen new_2005_lower = lower * (1 +  adjustment_factor) if year == 2010
    gen new_2005_upper = upper * (1 +  adjustment_factor) if year == 2010
    sort iso3 age intensity helminth_type year
    gsort iso3 age intensity helminth_type -year
      bysort iso3 age intensity helminth_type: replace new_2005_mapvar = new_2005_mapvar[_n-1] if missing(new_2005_mapvar)
      bysort iso3 age intensity helminth_type: replace new_2005_lower = new_2005_lower[_n-1] if missing(new_2005_lower)
      bysort iso3 age intensity helminth_type: replace new_2005_upper = new_2005_upper[_n-1] if missing(new_2005_upper)
    replace mapvar = new_2005_mapvar if new_2005_mapvar != . & (year == 2005 | year == 1990)
    replace lower = new_2005_lower if new_2005_lower != . & (year == 2005 | year == 1990)
    replace upper = new_2005_upper if new_2005_upper != . & (year == 2005 | year == 1990)
    sort iso3 age intensity helminth_type year
    drop new_* x coverage adjustment_factor
    order year, after(iso3)
    rename mapvar mapvar2 
    rename lower lower2
    rename upper upper2
    tempfile africa_fixed
    save `africa_fixed', replace
   
    use "`all_data'", clear
    merge 1:1 iso3 year age helminth_type intensity using "`africa_fixed'"
    replace mapvar = mapvar2 if _m == 2 //only COM, LSO, STP, & SWZ changed mapvar, lower & upper
    replace lower = lower2 if _m == 2
    replace upper = upper2 if _m == 2
    drop _m
	//replacing for Central Sub-Saharan Africa (gbd_super_region 3): 46 locations | SYC
    replace mapvar = mapvar2 if mapvar2 != . & gbd_super_region == 3 | iso3 == "SYC"
    replace lower = lower2 if lower2 != . & gbd_super_region == 3 | iso3 == "SYC"
    replace upper = upper2 if upper2 != . & gbd_super_region == 3 | iso3 == "SYC"
    drop if iso3 == "MYT" //Mayotte dropped, not a gbd location
    keep if inlist(intensity,"prev","med", "heavy")
    drop *2
    replace helminth_type = "ascar" if helminth_type == "asc"
    replace helminth_type = "trich" if helminth_type == "tt"
    replace helminth_type = "hook" if helminth_type == "hk"
    replace intensity = "inf_all" if intensity == "prev"
    replace intensity = "inf_med" if intensity == "med"
    replace intensity = "inf_heavy" if intensity == "heavy"
     
    tempfile data
    save `data', replace
    
  // Load and save geographical names
   //DisMod and Epi Data 2015
   clear
   get_location_metadata, location_set_id(9)
 
  // Prep country codes file
  duplicates drop location_id, force
  tempfile country_codes
  save `country_codes', replace
  
// Prepare envelope and population data
// Get connection string
create_connection_string, server(modeling-mortality-db) database(mortality) 
local conn_string = r(conn_string)

  //gbd2015 version:
 odbc load, exec("SELECT a.age_group_id, a.age_group_name_short AS age, a.age_group_name, o.sex_id AS sex, o.year_id AS year, o.location_id, o.mean_env_hivdeleted AS envelope, o.pop_scaled AS pop FROM output o JOIN output_version USING (output_version_id) JOIN shared.age_group a USING (age_group_id) WHERE is_best=1") `conn_string' clear
  
  tempfile demo
  save `demo', replace
  
  use "`country_codes'", clear
  merge 1:m location_id using "`demo'", nogen
  keep age age_group_id sex year ihme_loc_id parent location_name location_id location_type region_name envelope pop
  keep if inlist(location_type, "admin0","admin1","admin2","nonsovereign", "subnational", "urbanicity")

   replace age = "0" if age=="EN"
   replace age = "0.01" if age=="LN"
   replace age = "0.1" if age=="PN"
   drop if age=="All" | age == "<5"
   keep if age_group_id <= 22
   destring age, replace
  
  sort ihme_loc_id year sex age
  tempfile pop_env
  save `pop_env', replace
    
    use "`data'", clear
	rename countryname location_name
	rename iso3 ihme_loc_id
    merge m:1 ihme_loc_id using "`country_codes'"
    keep if _m == 1 | _m == 3 //subnational locations excluded here
    drop _m
    drop ihme_country
	compress location_name
    replace mapvar = 0 if lower == 0 & upper == 0
  
  // Zero means and confidence intervals that break the code due to numerical instability,
  // and aren't relevant in terms of magnitude anyway.
    replace mapvar = 0 if mapvar < 1.0e-10 | upper < 1.0e-10
    replace lower = 0 if mapvar < 1.0e-10
    replace upper = 0 if mapvar < 1.0e-10
  
  // create 1000 draws
    generate avg_sd = abs(ln(upper)-ln(lower))/(invnormal(0.975)*2)
    generate sd_half = abs(ln(upper)-ln(mapvar))/invnormal(0.975) if missing(avg_sd) & upper > 0
    replace sd_half = abs(ln(lower)-ln(mapvar))/invnormal(0.975) if missing(avg_sd) & lower > 0
    forvalues x=0/999 {
      quietly generate double draw_`x'= mapvar * exp(rnormal()*avg_sd)
      quietly replace draw_`x' = 1 if draw_`x' > 1 & !missing(draw_`x')
      quietly replace draw_`x' = 0 if upper == 0 & lower == 0 & missing(draw_`x')
      quietly replace draw_`x'= mapvar * exp(rnormal()*sd_half) if missing(draw_`x')
    }

  // Expand to all age categories and sexes considered in GBD 2015
    replace age = "1" if age == "0to4"
    replace age = "5" if age == "5to9"
    replace age = "10" if age == "10to14"
    replace age = "15" if age == "15plus"
    destring age, replace
    recast double age
    format %16.0g age
    expand 2 if age == 1 //to get post neonatal (28-364 days) and 1-4 i.e. age 0.1-4
    expand 14 if age == 15 //to get the 14 gbd age groups from 15-19, 20-24, ..., 80+
    bysort ihme_loc_id year age helminth_type intensity: gen x = _n
    replace age = 0.1 if age == 1 & x == 1
    forvalues x = 1/14 {
      replace age = 10 + `x' * 5 if age == 15 & x == `x'
    }
    drop x
    expand 2 //for each sex
    bysort ihme_loc_id year age helminth_type intensity: gen x=_n
    gen sex = ""
	replace sex = "M" if x == 1
    replace sex = "F" if x == 2
    drop x
	
  // make it into custom model
    rename helminth_type cause
	
	generate double age_group_id = .
	format %16.0g age_group_id
	replace age_group_id = 4 if age == 0.1 //PN
	replace age_group_id = 5 if age == 1 //1to4
	replace age_group_id = age/5 + 5 if age > 1

    keep cause year ihme_loc_id location_id sex intensity age age_group_id mapvar lower upper draw_*
    sort cause ihme_loc_id year sex intensity age
    order cause year ihme_loc_id location_id sex intensity age age_group_id mapvar lower upper
  
  // clean up
    format %16.0g age draw*
    tempfile all_inf_draws
    save `all_inf_draws', replace //draws assume same prevalence in males and females
  }

  //merge with pop_env data to fill in subnational geographies with national figures where necessary
  use `pop_env', clear
  tostring sex, replace
  replace sex = "M" if sex == "1"
  replace sex = "F" if sex == "2"
  keep ihme_loc_id location_id year sex age age_group_id pop envelope
  keep if inlist(year,1990,2005,2010)
  replace ihme_loc_id = substr(ihme_loc_id, 1, 3)
  joinby ihme_loc_id year age_group_id sex using "`all_inf_draws'", unmatched(none)
  
  tempfile all_inf_draws_filled
  save `all_inf_draws_filled', replace
 
// Prep data for looping
  use `pop_env', clear
  levelsof location_id, local(isos)
	
// Loop through sex, location_id, and year, keep only the relevant data, and outsheet the .csv of interest: prevalence (measue id 5)	
    foreach cause in ascar trich hook {
    foreach intensity in inf_all inf_med inf_heavy {
    // Set location where draws are saved
      local save_dir "`tmp_dir'/`cause'_`intensity'"
	  
	  use `all_inf_draws_filled' if cause == "`cause'" & intensity == "`intensity'", clear
	  
	  tempfile `cause'_draws
      quietly save ``cause'_draws', replace
	  
	  foreach i of local isos {
		// adopt Sudan (522) figures for South Sudan(435)
		local iso "`i'"
		if "`iso'" == "435"{
          local iso = "522"
        }
		
		use ``cause'_draws', clear
        quietly keep if location_id == `iso'
		
	  foreach year in 1990 2005 2010 {
      forvalues s = 1/2 {
        
        if `s' == 1 {
          local sex "1"
		  local sex_old "M"
        }
        else {
          local sex "2"
		  local sex_old "F"
        }

        display in red "`cause' `intensity' `i' `year' `sex'"
        
      // Verify that there is a drawfile available from GBD 2010. If not, assume zero prevalence.
        preserve
          quietly keep if sex == "`sex_old'" & year == `year'
          quietly count
          if r(N) > 0 {
			quietly keep age_group_id draw*
          }
          else {
            use `zeroes', clear
          }
          
          //keep age draw_*
		  keep age_group_id draw*
          
          quietly outsheet using "`save_dir'/5_`i'_`year'_`sex'.csv", comma replace
          
        restore
	  
	  }
	  }
	  }
	}
	}

  
// *************************************************************************************  
// Perform exponential interpolation for years 1995 and 2000, based on predictions for 1990 and 2005
  use `pop_env', clear
  levelsof location_id, local(isos)

  foreach cause in hook ascar trich {
  foreach intensity in inf_all inf_heavy inf_med {
  foreach i of local isos {
  foreach sex in 1 2 {
	
    ! qsub -N int_`cause'_`intensity'_`i'_`sex' -pe multi_slot 4 -l mem_free=8 -P proj_custom_models "$prefix/WORK/10_gbd/00_library/functions/utils/stata_shell.sh" "$prefix/WORK/04_epi/01_database/02_data/ntd_nema/04_models/gbd2015/01_code/interpolate_parallel.do" "`tmp_dir' `tmp_dir' `cause' `intensity' `i' `sex'"	
  }
    sleep 500
  }
  }
  }

// Check whether interpolation has finished; if not, wait for files to be written
  foreach cause in hook ascar trich {
  foreach intensity in inf_all inf_heavy inf_med {
  
    display as error "Checking draw files for `cause' `intensity'"
    
  foreach i of local isos {
  foreach year in 1990 1995 2000 2005 2010 {
  foreach sex in 1 2 {
  
    ** display as error "Looking for `cause' `intensity' prevalence_`i'_`year'_`sex'.csv"
    capture confirm file "`tmp_dir'/`cause'_`intensity'/5_`i'_`year'_`sex'.csv"
    while _rc {
      sleep 300000  // 5 minutes
      display as error "WAITING FOR `cause' `intensity' 5_`i'_`year'_`sex'.csv"
      capture confirm file "`tmp_dir'/`cause'_`intensity'/5_`i'_`year'_`sex'.csv"                
    }
    ** di as error "FOUND: `cause' `intensity' prevalence_`i'_`year'_`sex'.csv"
    
  }
  }
  }
  }
  }

// Produce draws for 2015, based on 2010 estimates corrected for PCT control activities between 2010
// and 2014, based on PCT coverage 2010-2014, observed trend in mean of draws 2005-2010, and
// PCT coverage 2005-2010.
  use `pop_env', clear
  levelsof location_id, local(isos)
  
  // Append all draw files for 2005 and 2010 from GBD 2010 (only needs to be done once)
	
    foreach cause in ascar trich hook  {
    foreach intensity in inf_all inf_med inf_heavy {
    
      local n = 0
      
      foreach iso of local isos {
        
        display in red "`cause' `intensity' `iso'"
        
      foreach sex in 1 2 {
      foreach year in 2005 2010 {
      
        quietly insheet using "`tmp_dir'/`cause'_`intensity'/5_`iso'_`year'_`sex'.csv", clear double
        quietly keep age_group_id draw*
        
        generate location_id = "`iso'"
        generate sex = "`sex'"
        generate year = `year'
        
        local ++n
        tempfile `n'
        quietly save ``n'', replace
        
      }
      }
      }
      
      clear
      forvalues i = 1/`n' {
        append using ``i''
      }
      
      save "`tmp_dir'/`cause'_`intensity'/prevalence_draws_2005_2010.dta", replace
      
    }
    }
    
  // Load and prep PCT coverage figures
    insheet using "`in_dir'/who_pct_databank_coverage_STH_2015.csv", clear double
      rename populationrequiringpcforsthpresa popPreSAC
      rename numberofpresactargeted targetPreSAC
      rename reportednumberofpresactreated treatPreSAC
      rename drugusedpresac drugPreSAC
      rename programmecoveragepresac progCovPreSAC
      rename nationalcoveragepresac natCovPreSAC
      rename populationrequiringpcforsthsac popSAC
      rename numberofsactargeted targetSAC
      rename reportednumberofsactreated treatSAC
      rename drugusedsac drugSAC
      rename programmecoveragesac progCovSAC
      rename nationalcoveragesac natCovSAC
      rename iso3 ihme_loc_id
	  
    replace natCovPreSAC = 0 if missing(natCovPreSAC)
    replace natCovSAC = 0 if missing(natCovSAC)
    
    // Calculate cumulative number of treatments per person in population requiring PCT
      preserve
        keep if year >= 2005 & year < 2010
        collapse (sum) natCovPreSAC natCovSAC, by (ihme_loc_id)
        rename natCovPreSAC cumPreSAC2005
        rename natCovSAC cumSAC2005
        rename ihme_loc_id iso_short
        tempfile cum2005
        save `cum2005', replace
      restore
      preserve
        keep if year >= 2010 //changed this to include 2010 - gbd2013 excluded the year 2010
        collapse (sum) natCovPreSAC natCovSAC, by (ihme_loc_id)
        rename natCovPreSAC cumPreSAC2010
        rename natCovSAC cumSAC2010
        tempfile cum2010
        rename ihme_loc_id iso_short
        save `cum2010', replace
      restore
 
  // Extrapolate trend 2005-2010 to 2015, given cumulative number of treatments per person, applying
  // trend in infection to all intensities.
    foreach cause in ascar trich hook {
		foreach intensity in inf_all inf_heavy inf_med {
		  
		// Fit model to trend 2005-2010 for all infections and apply trend to all sub-intensities of infection
		  if "`intensity'" == "inf_all" {
			
			use "`tmp_dir'/`cause'_`intensity'/prevalence_draws_2005_2010.dta", replace
			
			egen double mean = rowmean(draw*)
			drop draw*
			tempfile prevd
			save `prevd', replace
			use `pop_env', clear
			keep if inlist(year, 2005,2010) & sex !=3 & age_group_id >=4
			keep ihme_loc_id location_id age_group_id sex year
			tostring location_id, replace
			tostring sex, replace
			joinby location_id age_group_id sex year using "`prevd'", unmatched(none)
			
			reshape wide mean, i(age_group_id ihme_loc_id sex) j(year)
			
			// Fix Vanuatu (VUT): 2010 >>>>>> 2005
			  replace mean2005 = mean2010 if ihme_loc_id == "VUT"
		//FOR GBD 2015, also fix GRD, LCA & VCT:
          replace mean2005 = mean2010 if ihme_loc_id == "GRD"
          replace mean2005 = mean2010 if ihme_loc_id == "LCA"
          replace mean2005 = mean2010 if ihme_loc_id == "VCT"
		  
		// Generate annual rate of change based on the means of all draws
			  generate double ann_rate = (mean2010/mean2005)^(1/5)
			
		// Merge cumulative treatment numbers and prep for regression
		  generate iso_short = substr(ihme_loc_id, 1, 3)
			  
			  
			  merge m:1 iso_short using `cum2005', keepusing(cumPreSAC2005 cumSAC2005) keep (master match) nogen
				generate cumTreat2005 = cumSAC2005 if age_group_id < 8 //age < 15
				quietly replace cumTreat2005 = cumPreSAC2005 if age_group_id < 6 //age < 5
				quietly replace cumTreat2005 = 0 if age_group_id < 8 & missing(cumTreat2005)
				drop cumPreSAC2005 cumSAC2005
			  merge m:1 iso_short using `cum2010', keepusing(cumPreSAC2010 cumSAC2010) keep (master match) nogen
				generate cumTreat2010 = cumSAC2010 if age_group_id < 8
				quietly replace cumTreat2010 = cumPreSAC2010 if age_group_id < 6
				quietly replace cumTreat2010 = 0 if age_group_id < 8 & missing(cumTreat2010)
				drop cumPreSAC2010 cumSAC2010
				
			  drop iso_short
			
			// Regress annual rate of change against average number of treatments per person at risk per year
			  generate treatPerYear2005 = cumTreat2005 / 5
			  generate treatPerYear2010 = cumTreat2010 / 5
			 
			  meglm ann_rate treatPerYear2005, link(log) || ihme_loc_id: , startgrid(0.001, 0.01)
			
			// Predict annual rate of change for 2010-2015
			  predict rfx if !missing(treatPerYear2010), remeans
			  
			  // Substitute treatments per person per year 2010-2015 for 2005-2010
				drop treatPerYear2005
				rename treatPerYear2010 treatPerYear2005
			  
			  predict ann_rate_pred if !missing(treatPerYear2005), xb fixedonly
			  replace ann_rate_pred = exp(ann_rate_pred + rfx)
			  
			  // Fix increasing annual rates of change > 1
				replace ann_rate_pred = 1 if ann_rate_pred > 1 & !missing(ann_rate_pred)
			  
			// For all other ages, assume that the rate of change is the average of what is predicted for pre-SAC and SAC
			  bysort ihme_loc_id sex (age_group_id): egen mean_rate = mean(ann_rate_pred)
			  replace ann_rate_pred = mean_rate if missing(ann_rate_pred)
			  replace ann_rate_pred = 1 if missing(ann_rate_pred)
			  
			  tempfile `cause'_rate
			  save ``cause'_rate', replace
		  }
		
		// Load 2010 draws, predict 2015, and save csv-files
		  use "`tmp_dir'/`cause'_`intensity'/prevalence_draws_2005_2010.dta", replace
		  keep if year == 2010
		  drop year
		  
		// Use rate of change in prevalence of all infection for all sub-intensities
		  merge 1:1 location_id sex age_group_id using ``cause'_rate', keepusing(ann_rate_pred) nogen
		  
		  replace ann_rate_pred = ann_rate_pred^5
		  
		  forvalues i = 0/999 {
			quietly replace draw_`i' = draw_`i' * ann_rate_pred
		  }
		  
		  tempfile `cause'_`intensity'_2015
		  save ``cause'_`intensity'_2015', replace
		  
		  // Export csv by country and sex for 2015
			foreach iso of local isos {
				foreach sex in 1 2 {
				  display in red "`cause' `intensity' `iso' `sex' 2015"
				  
				  use ``cause'_`intensity'_2015', replace
				  
				  quietly keep if location_id == "`iso'"
				  quietly keep if sex == "`sex'"
				  
				  keep age_group_id draw_*
				  
				  quietly outsheet using "`tmp_dir'/`cause'_`intensity'/5_`iso'_2015_`sex'.csv", comma replace
				  
				}
			}
		}
    }


  // Append all STH draw files for all six Dismod years and save
  use `pop_env', clear
  levelsof location_id, local(isos)
  
    foreach cause in ascar hook trich {
    foreach intensity in inf_all {
    
      local n = 0
      
      foreach iso of local isos {
        
        display in red "`cause' `intensity' `iso'"
        
      foreach sex in 1 2 {
      foreach year in 1990 1995 2000 2005 2010 2015 {
      
        quietly insheet using "`tmp_dir'/`cause'_`intensity'/5_`iso'_`year'_`sex'.csv", clear double
        quietly keep age_group_id draw*
        
        generate location_id = "`iso'"
        generate sex = "`sex'"
        generate year = `year'
        
        local ++n
        tempfile `n'
        quietly save ``n'', replace
        
      }
      }
      }
      
      clear
      forvalues i = 1/`n' {
        append using ``i''
      }      
    }
    }

  
*********************************************************************
// Send results to central database
  save_results, modelable_entity_id(2999) description("Ascariasis infestation: Extrapolation GBD 2010 (2015 = f(PCT)*2010)") in_dir("`tmp_dir'/ascar_inf_all") metrics(prevalence) mark_best(yes)
  
  save_results, modelable_entity_id(3001) description("Trichuriasis infestation: Extrapolation GBD 2010 (2015 = f(PCT)*2010)") in_dir("`tmp_dir'/trich_inf_all") metrics(prevalence) mark_best(yes)
 
  save_results, modelable_entity_id(3000) description("Hookworm infestation: Extrapolation GBD 2010 (2015 = f(PCT)*2010)") in_dir("`tmp_dir'/hook_inf_all") metrics(prevalence) mark_best(yes)

 //heavy infestation
  save_results, modelable_entity_id(1513) description("Heavy ascariasis infestation: Extrapolation GBD 2010 (2015 = f(PCT)*2010)") in_dir("`tmp_dir'/ascar_inf_heavy") metrics(prevalence) mark_best(yes)
  
  save_results, modelable_entity_id(1516) description("Heavy trichuriasis infestation: Extrapolation GBD 2010 (2015 = f(PCT)*2010)") in_dir("`tmp_dir'/trich_inf_heavy") metrics(prevalence) mark_best(yes)
 
  save_results, modelable_entity_id(1519) description("Heavy hookworm infestation: Extrapolation GBD 2010 (2015 = f(PCT)*2010)") in_dir("`tmp_dir'/hook_inf_heavy") metrics(prevalence) mark_best(yes)
  
 //Medium infestation
  save_results, modelable_entity_id(1514) description("Mild abdominal pain due to asciariasis: Extrapolation GBD 2010 (2015 = f(PCT)*2010)") in_dir("`tmp_dir'/ascar_inf_med") metrics(prevalence) mark_best(yes)
  
  save_results, modelable_entity_id(1517) description("Mild abdominal pain due to trichuriasis: Extrapolation GBD 2010 (2015 = f(PCT)*2010)") in_dir("`tmp_dir'/trich_inf_med") metrics(prevalence) mark_best(yes) 
 
  save_results, modelable_entity_id(1520) description("Mild abdominal pain due to hookworm: Extrapolation GBD 2010 (2015 = f(PCT)*2010)") in_dir("`tmp_dir'/hook_inf_med") metrics(prevalence) mark_best(yes)

 *********************************************************************************************************************************************************************
// CHECK FILES

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
				local dir: dir "root_j_dir/03_steps/`date'" dirs "`i'_*", respectcase
				local dir = subinstr(`"`dir'"',`"""',"",.)
				cap confirm file "root_j_dir/03_steps/`date'/`dir'/finished.txt"
				if _rc local write_file 0
			}
		}
		
		// write file if all steps finished
		if `write_file' {
			file open all_finished using "root_j_dir/03_steps/`date'/finished.txt", replace write
			file close all_finished
		}
	}
	
// close log if open
	if `close_log' log close
