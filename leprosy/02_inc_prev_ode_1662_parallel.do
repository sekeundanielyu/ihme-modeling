// **********************************************************************
// Purpose:        This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global
// Description:   Calculate incidence of leprosy by country-year-age-sex, using cases reported to WHO and
//                      age-patterns from dismod. Produce incidence for every year in 1890-2015, and sweep forward
//                      with ODE to arrive at prevalence predictions.
// /home/j/WORK/04_epi/01_database/02_data/leprosy/1662/04_models/gbd2015/01_code/dev/02_inc_prev_ode_1662_parallel.do

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

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
	
	// Define arguments
	if "`1'" != "" {
		local location_id `1'
		local min_year `2'
		local tmp_dir `3'	
	}
	else if "`1'" == "" {
		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
		local date = subinstr("`date'"," ","_",.)
		local location_id 43911
		local min_year 1987
		local tmp_dir "/ihme/gbd/WORK/04_epi/01_database/02_data/leprosy/1662/04_models/gbd2015/03_steps/`date'/02_inc_prev_ode"
	}

// *********************************************************************************************************************************************************************
// Import functions
	run "$prefix/WORK/10_gbd/00_library/functions/get_draws.ado"
	run "$prefix/WORK/10_gbd/00_library/functions/get_demographics.ado"
	run "$prefix/WORK/10_gbd/00_library/functions/fastcollapse.ado"
	run "$prefix/WORK/10_gbd/00_library/functions/fastrowmean.ado"
	
// Load universal needs
	get_demographics, gbd_team(cod) clear
	use "`tmp_dir'/loc_iso3.dta" if location_id == `location_id', clear
	levelsof iso3, local(iso) c
	local sex_1 "male"
	local sex_2 "female"
	
// *********************************************************************************************************************************************************************
// Merge incidence pattern with annually reported total incidence and population envelope and calculate year-specific incidences by scaling
// by [absolute reported numbers per year] / [sum of mean of all draws by country-year]. Save files for 1987-2015   
   local n = 0

    foreach sex_id of global sex_ids {
      
      forvalues year_id = 1987/2015 {
      
        quietly insheet using "`tmp_dir'/draws/cases/age_pattern_interpolated/interpolated/6_`location_id'_`year_id'_`sex_id'.csv", clear double
        quietly keep if age_group_id <= 21
        
        forvalues i = 0/999 {
          quietly replace draw_`i' = 0 if age_group_id < 5
        }
        
        local ++n
        tempfile `n'
        quietly save ``n'', replace
      
      }
      
    }
    
  // Append all ages, sexes, and years for a given country, add total numbers of reported cases and population envelope, and save
    clear
    forvalues i = 1/`n' {
      append using ``i''
    }
    
    quietly merge m:1 location_id year_id using "`tmp_dir'/data_filled.dta", keepusing(mean total_pop) keep(match) nogen
    quietly merge 1:1 location_id year_id age_group_id sex_id using "`tmp_dir'/pops.dta", keep(match) nogen
    
  // Generate scaling factor [absolute reported numbers per year] / [sum of mean of all draws by country-year] and
  // scale dismod incidences to have mean equal to the annually reported number of cases.
    generate double cases = mean * total_pop
    fastrowmean draw_*, mean_var_name(mu_cases_draw)
      quietly replace mu_cases_draw = mu_cases_draw * mean_pop
    bysort year: egen double total_cases_draw = total(mu_cases_draw)
    generate double scale = cases / total_cases_draw
    
    forvalues i = 0/999 {
      quietly replace draw_`i' = draw_`i' * scale
    }
    
    drop cases mu_cases_draw total_cases_draw scale mean total_pop mean_pop
    
  // Write year-specific incidence files by country (using ISO-3) and sex for 1987-2015, then calculate prevalent cases that have ever had leprosy for first year of data
	quietly merge m:1 age_group_id using "`tmp_dir'/age_map.dta", keep(match) nogen
	tempfile bs
	save `bs', replace
    foreach sex_id of global sex_ids {
	 // INCIDENCE
	  use `bs' if sex_id == `sex_id', clear
      forvalues year = 1987/2015 {
        preserve
          display in red "`year' `sex_id'"
          
          quietly keep if year_id == `year'
          		  
		  keep age draw_*
		  sort age
          quietly outsheet using "`tmp_dir'/draws/cases/inc_annual/incidence_`iso'_`year'_`sex_`sex_id''.csv", comma replace
        restore
      }
        
	// PREVALENCE
        quietly insheet using "`tmp_dir'/draws/cases/inc_annual/incidence_`iso'_`min_year'_`sex_`sex_id''.csv", clear double
        
        forvalues x = 0/999 {
          // Prevalence at start of each age category
            quietly generate double prev_start_`x' = 0 if age == 0 
            quietly replace prev_start_`x' = prev_start_`x'[_n-1] + (1 - prev_start_`x'[_n-1]) * (1 - exp(-(age - age[_n-1]) * draw_`x'[_n-1])) if age > 0
            
          // Prevalence halfway each age category (half-year correction)
            quietly replace prev_start_`x' = prev_start_`x' + (1 - prev_start_`x') * (1 - exp(-(age[_n+1] - age)/2 * draw_`x')) if age < 80
            quietly replace prev_start_`x' = prev_start_`x' + (1 - prev_start_`x') * (1 - exp(-(85 - age)/2 * draw_`x')) if age == 80
            quietly drop draw_`x'
            quietly rename prev_start_`x' draw_`x'
        }
        
        keep draw_* age
        format %16.0g draw_* age
        quietly outsheet using "`tmp_dir'/draws/cases/prev_initial/prevalence_`iso'_`min_year'_`sex_`sex_id''.csv", comma replace
    }

// *********************************************************************************************************************************************************************