// Purpose: GBD 2015 Schistosomiasis Estimates
// Description:	Calculate prevalence of schistosomiasis infection and sequelae by country-year-age-sex

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
	
	di "`out_dir'/02_temp/02_logs/`step'.smcl""
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

// **********************************************************************
// Set constants for calculations
  // Bounds for standard deviation of dispersion of logit prevalence of infection within countries
    local inf_sd_lo = 0.6
    local inf_sd_hi = 0.8
    
  // Set number of villages to simulate per country
    local n_vill = 1000
  
  // Parameters for translating infection (x) to morbidity (y): y = (a + bx^c)/(1 + bx^c) - a
    //	Diarrhea (S. mansoni and/or japonicum) - van der Werf 2002
      local a_dia = 0.222
      local b_dia = 0.272
      local c_dia = 7.702
    // Moderate/severe hepatic disease (S. mansoni and/or japonicum) - van der Werf 2002
      local a_hep = 0.183
      local b_hep = 0.217
      local c_hep = 1.555
    // Dysuria during last two weeks (S. haematobium) - van der Werf 2003
      local a_dys = 0.30
      local b_dys = 1.94
      local c_dys = 4.23
    // Major hydronephrosis (S. haematobium) - van der Werf 2003
      local a_hyd = 0
      local b_hyd = 0.11
      local c_hyd = 1.23
    // Hematemesis "ever" (S. mansoni and/or japonicum) - van der Werf 2002
    // "Ongom et al. showed that reported history of haematemesis ‘ever’ was only twice as frequent as reported
    // history of haematemesis ‘this year’ (Ongom and Bradley, 1972)."
      local a_hem = 0
      local b_hem = 0.0133
      local c_hem = 1.027
    // Ascites (S. mansoni and/or japonicum) - van der Werf 2002
      local a_asc = 0
      local b_asc = 0.00249
      local c_asc = 1.005
    // Bladder pathology on ultrasound (S. haematobium) - van der Werf 2004
      local a_bla = 0.033
      local b_bla = 1.35
      local c_bla = 1.78
  
  // Effects of c
    // Schistosoma haematobium - Cochrane 2008
      // Reduction in risk of parasitological failure 1 year after treatment
        local pzq_sh_y_mu = 0.23
        local pzq_sh_y_lo = 0.14
        local pzq_sh_y_hi = 0.39
      // Reduction in risk of parasitological failure 1 month after treatment
        local pzq_sh_m_mu = 0.39
        local pzq_sh_m_lo = 0.27
        local pzq_sh_m_hi = 0.55
    // Schistosoma mansoni (apply this to japonicum as well) - Cochrane 2013
      // Reduction in risk of parasitological failure 1 months after treatment
        local pzq_sm_m_mu = 0.32
        local pzq_sm_m_lo = 0.10
        local pzq_sm_m_hi = 0.97

// *********************************************************************
  // Load and save geographical names
   //DisMod and Epi Data 2015
   clear
   get_location_metadata, location_set_id(9)
 
  // Prep country codes file
  duplicates drop location_id, force
  tempfile country_codes
  save `country_codes', replace

    keep ihme_loc_id location_id location_name
	tempfile iso3s
    save `iso3s', replace
  
// **********************************************************************
// Calculate conversion factor for splitting species-specific infection in North Africa and Middle East
  
  // Load data
    import excel using "`in_dir'/literature_data.xlsx", sheet("split_species_egypt") firstrow clear

  // Format data
    local d_factor = 2.5  // assumed design factor (data are based on household survey)
    
    replace n_mansoni = n_mansoni / `d_factor'
    replace n_haematobium = n_haematobium / `d_factor'
    
    generate pos_mansoni = n_mansoni * prev_mansoni
    generate neg_mansoni = n_mansoni - pos_mansoni
    
    generate pos_haematobium = n_haematobium * prev_haematobium
    generate neg_haematobium = n_haematobium - pos_haematobium
    
    foreach var of varlist pos* n_* neg* {
      replace `var' = round(`var',1)
      recast int `var'
    }
    
  // Meta-analysis for ratio of prevalence of S. mansoni versus S. haematobium infection in
  // Egypt, taking into account heterogeneity between sites within a country. Later use this to
  // split overall infection prevalence into S. mansoni prevalence fraction 1/(1+RR^-1) and
  // S. haematobium prevalence fraction 1/(1+RR).
  ssc install metan
    metan pos_mansoni neg_mansoni pos_haematobium neg_haematobium, rr randomi label(namevar = site) counts log nokeep nograph notable
    
    local log_rr_mansoni_egypt_mu = `r(ES)'
    local log_rr_mansoni_egypt_se = `r(seES)'

// **********************************************************************   
// Calculate transformation factors for converting prevalence in individuals under 20 years of age
// to total population, and for converting total infection prevalence to species-specific prevalence in sub-Sahara Africa

  // Load data
    import excel using "`in_dir'/literature_data.xlsx", sheet("data") firstrow clear
    keep if citation == "Schur 2013 Acta Trop"

  // Transform data to logit scale
    foreach var in p20_hae p20_hae_lo p20_hae_hi p_hae p_hae_lo p_hae_hi p20_man p20_man_lo p20_man_hi p_man p_man_lo p_man_hi p20_tot p20_tot_lo p20_tot_hi p_tot p_tot_lo p_tot_hi {
      replace `var' = ln(`var'/(1-`var'))
    }
    
  // Calculate standard errors
    foreach var in p20_hae p_hae p20_man p_man p20_tot p_tot {
      generate `var'_se1 = (`var' - `var'_lo)/invnormal(0.975)
      generate `var'_se2 = (`var'_hi - `var')/invnormal(0.975)
      generate `var'_se = (`var'_se1 + `var'_se2)/2
        quietly replace `var'_se = `var'_se2 if missing(`var'_se1)  
      generate `var'_w = 1/`var'_se^2
      drop `var'_se1 `var'_se2 `var'_lo `var'_hi
    }

  // Stata has no meta-analysis function that can do pair-wise comparisons of point-estimates
  // for which only standard errors are supplied (ie no sample sizes). Therefore, here we use a
  // rough method where we perform a paired T-test with observations weighted by their inverse variance.
        
  // Prepare and reshape data for meta-analysis of prevalence in <20yrs and total population
    rename p20_hae    p_hae1
    rename p_hae      p_hae2
    rename p20_man    p_man1
    rename p_man      p_man2
    rename p20_tot    p_tot1
    rename p_tot      p_tot2
    
    rename p20_hae_se se_hae1
    rename p_hae_se   se_hae2
    rename p20_man_se se_man1
    rename p_man_se   se_man2
    rename p20_tot_se se_tot1
    rename p_tot_se   se_tot2
    
    rename p20_hae_w  w_hae1
    rename p_hae_w    w_hae2
    rename p20_man_w  w_man1
    rename p_man_w    w_man2
    rename p20_tot_w  w_tot1
    rename p_tot_w    w_tot2
    
    reshape long p_hae p_man p_tot se_hae se_man se_tot w_hae w_man w_tot, i(nid citation file table super_region region country year notes) j(agegroup)
  
  // Odds-ratio of prevalence of infection in individuals under 20 years of age [1] and the general population [2]
    foreach species in hae man tot {
      svyset country [iweight=w_`species']
      svy: mean p_`species', over(agegroup)
      lincom [p_`species']2 - [p_`species']1
      
    // Log-odds ratio of infection in total population vs age<20
      local log_or_total_`species'_mu = `r(estimate)'
      
    // Standard error of log-odds ratio of infection in total population vs age<20
      local log_or_total_`species'_se = `r(se)'
    }
    
  // Prepare and reshape data for meta-analysis of species-specific prevalence vs total prevalence
    keep if agegroup == 2  // keep total population estimates only
    drop agegroup
    
    rename p_hae  p1
    rename p_man  p2
    rename p_tot  p3
    rename se_hae se1
    rename se_man se2
    rename se_tot se3
    rename w_hae  w1
    rename w_man  w2
    rename w_tot  w3
    
    reshape long p se w, i(country) j(species)
  
  // Odds-ratio of species-specific infection and all-species infection in the general population
    svyset country [iweight=w]
    svy: mean p, over(species)
   
  // Log-odds ratio of all-species infection [3] and species-specific infection [1,2] in total population
    lincom [p]1 - [p]3
    local log_or_hae_ssa_mu = `r(estimate)'
    local log_or_hae_ssa_se = `r(se)'
    
    lincom [p]2 - [p]3
    local log_or_man_ssa_mu = `r(estimate)'
    local log_or_man_ssa_se = `r(se)'
     
// ********************************************************************** 
// Prep infection data
  // load data with Brazil national from literature data split into subnational using data from PCE (reported schisto in endemic states) and GBD 2015 population estimates (see schisto_expl.do for how data was split)	
	insheet using "`in_dir'/prev_data_BRA_split.csv", clear double 
    
    merge 1:m location_name using `iso3s', keepusing(location_id ihme_loc_id) keep(master match) nogen
    
    // DUPLICATE DATA POINT FOR SUDAN AND ASSIGN TO SOUTH SUDAN.
      expand 2 if location_name == "Sudan", generate(copy)
      replace location_name = "South Sudan" if copy == 1
      replace location_id = 435 if copy == 1
      replace ihme_loc_id = "SSD" if copy == 1
      drop copy

    keep if !missing(ihme_loc_id)
    
    tempfile inf_prev_data
    save `inf_prev_data', replace
    
  // Pre-format data
    foreach var in p20_hae p20_hae_lo p20_hae_hi p_hae p_hae_lo p_hae_hi p20_man p20_man_lo p20_man_hi p_man p_man_lo p_man_hi p20_tot p20_tot_lo p20_tot_hi p_tot p_tot_lo p_tot_hi {
      quietly generate double logit_`var' = .
      format %16.0g logit_`var'
      quietly replace logit_`var' = logit(`var')
    }
 
    foreach var in logit_p20_hae logit_p_hae logit_p20_man logit_p_man logit_p20_tot logit_p_tot {
      quietly generate double `var'_se1 = .
      quietly generate double `var'_se2 = .
      quietly generate double `var'_se = .
      format %16.0g `var'_se1 `var'_se2 `var'_se
      
      quietly replace `var'_se1 = (`var' - `var'_lo)/invnormal(0.975)
      quietly replace `var'_se2 = (`var'_hi - `var')/invnormal(0.975)
      quietly replace `var'_se = (`var'_se1 + `var'_se2)/2
        quietly replace `var'_se = `var'_se2 if missing(`var'_se1)  
      drop `var'_se1 `var'_se2 `var'_lo `var'_hi
    }
    
    drop nid citation file table year notes p20_hae_lo p20_hae_hi p_hae_lo p_hae_hi p20_man_lo p20_man_hi p_man_lo p_man_hi p20_tot_lo p20_tot_hi p_tot_lo p_tot_hi
    
    save `inf_prev_data', replace
    
  // Homogenize the prevalence dataset by converting all estimates to species-specific prevalence
  // estimates for the entire population.
    use `inf_prev_data', clear
    
    expand 1000
	bysort location_id: generate int draw = _n - 1

    // Replace observed raw prevalence data with a randomly drawn prevalence, assuming normal
    // distribution of prevalence on logit scale with mean equal to observed and standard deviation
    // as calculated (or if missing, assume standard deviation = 0.5, for now). Assuming that species-specific
    // and total prevalences are all perfectly correlated (for lack of better information at this point).
      generate double rns = .
      format %16.0g rns
      
      quietly replace rns = rnormal()
      foreach var in p20_hae p_hae p20_man p_man p20_tot p_tot {
        quietly generate double logit_`var'_draw = .
        quietly generate double `var'_draw  = .
        format %16.0g logit_`var'_draw `var'_draw
        
        quietly replace logit_`var'_draw = logit_`var' + rns*logit_`var'_se if !missing(logit_`var'_se)
        quietly replace logit_`var'_draw = logit_`var' + rns*0.5 if missing(logit_`var'_se)
        
        quietly replace `var'_draw = invlogit(logit_`var'_draw)
        quietly replace `var'_draw = 0 if `var' == 0
      }
      drop rns
      
    // Scale back down randomly drawn prevalences so that the mean is equal to the data.
    // (logit-transformation combined with normal distribution causes an upward bias).
      foreach var in p20_hae p_hae p20_man p_man p20_tot p_tot {
		quietly bysort location_id: egen draw_mean = mean(`var'_draw)
        quietly replace `var'_draw = `var'_draw * `var' / draw_mean
        quietly replace `var'_draw = 0 if `var' == 0
        quietly replace logit_`var'_draw = logit(`var'_draw)
        quietly drop draw_mean
      }
    
  // Convert prevalence in individuals under age 20 to prevalence in total population. 
      quietly generate double log_or_total_hae_draw = .
      quietly generate double log_or_total_man_draw = .
      quietly generate double log_or_total_tot_draw = .
      format %16.0g log_or_total_*
      
      quietly replace log_or_total_hae_draw = `log_or_total_hae_mu' + rnormal()*`log_or_total_hae_se'
      quietly replace log_or_total_man_draw = `log_or_total_man_mu' + rnormal()*`log_or_total_man_se'
      quietly replace log_or_total_tot_draw = `log_or_total_tot_mu' + rnormal()*`log_or_total_tot_se'
      
      quietly replace logit_p_hae_draw = logit_p20_hae_draw + log_or_total_hae_draw if missing(logit_p_hae_draw)
      quietly replace logit_p_man_draw = logit_p20_man_draw + log_or_total_man_draw if missing(logit_p_man_draw)
      quietly replace logit_p_tot_draw = logit_p20_tot_draw + log_or_total_tot_draw if missing(logit_p_tot_draw)
      
      foreach var in p_hae_draw p_man_draw p_tot_draw {
        quietly replace `var' = invlogit(logit_`var') if missing(`var')
      }
      
    // Synchronize the independent draws for different types of prevalences made for countries
    // where only one species is present (numbers for present species should be same as total!)
      foreach stub in p p20 {
        quietly replace `stub'_tot_draw = `stub'_man_draw if `stub'_hae == 0 
        quietly replace `stub'_tot_draw = `stub'_hae_draw if `stub'_man == 0
       
        quietly replace logit_`stub'_tot_draw = logit_`stub'_man_draw if `stub'_hae == 0 
        quietly replace logit_`stub'_tot_draw = logit_`stub'_hae_draw if `stub'_man == 0
      } 
  
  // North Africa/ Middle East: split total prevalence into mutually exclusive species-specific prevalences.
      quietly generate double log_rr_mansoni_egypt_draw = .
      quietly generate double rr_mansoni_egypt_draw = .
      format %16.0g log_rr_mansoni_egypt_draw rr_mansoni_egypt_draw
      
      quietly replace log_rr_mansoni_egypt_draw = `log_rr_mansoni_egypt_mu' + rnormal()*`log_rr_mansoni_egypt_se'
      quietly replace rr_mansoni_egypt_draw = exp(log_rr_mansoni_egypt_draw)
      
      quietly replace p_hae_draw = p_tot_draw / (1 + rr_mansoni_egypt_draw) if region == "North Africa / Middle East" & missing(p_hae_draw)
      quietly replace p_man_draw = p_tot_draw / (1 + 1/rr_mansoni_egypt_draw) if region == "North Africa / Middle East" & missing(p_man_draw)
      
      foreach var in p_hae_draw p_man_draw {
        quietly replace logit_`var' = logit(`var') if region == "North Africa / Middle East" & missing(logit_`var')
      }
    
    
  // Sub-Sahara Africa: convert total overall prevalence of infection to species-specific infection, assuming
  // that the proportions of species-specific infection are perfectly negatively correlated (for lack of more detailed data).
  // At most, this leads to an underestimation of the total schisto burden.
    quietly generate double rns = .
    quietly generate double log_or_hae_ssa_draw = .
    quietly generate double log_or_man_ssa_draw = .
    
    quietly replace rns = rnormal()
    quietly replace log_or_hae_ssa_draw = `log_or_hae_ssa_mu' + rns * `log_or_hae_ssa_se'
    quietly replace log_or_man_ssa_draw = `log_or_man_ssa_mu' - rns *`log_or_man_ssa_se'
    
    quietly replace logit_p_hae_draw = logit_p_tot_draw + log_or_hae_ssa_draw if missing(logit_p_hae_draw) & p_hae_draw != 0
    quietly replace logit_p_man_draw = logit_p_tot_draw + log_or_man_ssa_draw if missing(logit_p_man_draw) & p_man_draw != 0
    
    foreach var in p_hae_draw p_man_draw {
      quietly replace `var' = invlogit(logit_`var') if missing(`var')
    }
  
      
  // Keep relevant variables
    keep ihme_loc_id location_name location_id p_hae_draw p_man_draw p_tot_draw draw

  tempfile inf_draws
  save `inf_draws', replace

  save "`out_dir'/inf_prev_draws.dta", replace
  tabstat p_hae_draw p_man_draw p_tot_draw, by(ihme_loc_id) stat(mean)

//****************************************************************************************** 
// Prep data on coverage of MDA
  // Generate 6-month treatment effect draws to reflect midyear effects
    // Scale PZQ effect for S. haematobium to geometric midpoint between 1-month and 1-year effects
      local pzq_sh_mu = `pzq_sh_y_mu' * sqrt(`pzq_sh_m_mu'/`pzq_sh_y_mu')
      local pzq_sh_lo = `pzq_sh_y_lo' * sqrt(`pzq_sh_m_mu'/`pzq_sh_y_mu')
      local pzq_sh_hi = `pzq_sh_y_hi' * sqrt(`pzq_sh_m_mu'/`pzq_sh_y_mu')
    
    // Scale PZQ effect for S. mansoni to by same amount (for lack of better data)
      local pzq_sm_mu = `pzq_sm_m_mu' * sqrt(`pzq_sh_y_mu'/`pzq_sh_m_mu')
      local pzq_sm_lo = `pzq_sm_m_lo' * sqrt(`pzq_sh_y_mu'/`pzq_sh_m_mu')
      local pzq_sm_hi = `pzq_sm_m_hi' * sqrt(`pzq_sh_y_mu'/`pzq_sh_m_mu')
    
    // Derive standard errors on log-scale
      local pzq_sh_se = (ln(`pzq_sh_hi') - ln(`pzq_sh_mu'))/ invnormal(0.957)
      local pzq_sm_se = (ln(`pzq_sm_hi') - ln(`pzq_sm_mu'))/ invnormal(0.957)
      
      local ln_pzq_sh_mu = ln(`pzq_sh_mu')
      local ln_pzq_sm_mu = ln(`pzq_sm_mu')
      
    // Produce draws for treatment effects
      forvalues i = 0/999 {
        local pzq_sh_`i' = exp(`ln_pzq_sh_mu' + rnormal()*`pzq_sh_se')
        local pzq_sm_`i' = exp(`ln_pzq_sm_mu' + rnormal()*`pzq_sm_se')
      }
 
  // Homogenize MDA data
    insheet using "`in_dir'/pct_coverage_who_2015.csv", clear double //Indonesia (2010-2013 only), SSD (2011-2013 only)
    destring sac_at_risk pop_at_risk, replace force
    
    preserve
      keep location_id
      duplicates drop location_id, force
      expand 10
      bysort location_id: generate year = 2005 + _n
      tempfile template
      save `template', replace
    restore
    merge 1:1 location_id year using `template', nogen
    
    replace cov_national = 0 if missing(cov_national) & year != 2015
    bysort location_id (year): replace cov_national = cov_national[_n-1] if year == 2015
    generate cov_cumm = cov_national if year == 2006
    bysort location_id: replace cov_cumm = cov_cumm[_n-1] + cov_national if year > 2006
    
    merge m:1 location_id using `iso3s', keepusing(ihme_loc_id) keep(master match) nogen
    save `template', replace
	
  //merge with iso3s data to fill in subnational geographies with national coverage where necessary (BRA, CHN, KEN, SAU, ZAF)
	use `iso3s', clear
	expand 10
	bysort location_id: generate year = 2005 + _n
	replace ihme_loc_id = substr(ihme_loc_id, 1, 3)
	joinby ihme_loc_id year using "`template'", unmatched(none)
  
	tempfile template_filled
	save `template_filled', replace	
    
    keep ihme_loc_id location_id year cov_national cov_cumm
    sort ihme_loc_id year
    
  // Produce draws of expected reductions in overall infection prevalence:
  // Effect in treated population + effect in non-treated population (zero).
  // Assumptions: effects in consecutive year stack up; in untreated years, effects remains stable.
    foreach species in sh sm {
      forvalues i = 0/999 {
        quietly generate double rx_`species'_`i' = cov_national * (`pzq_`species'_`i'' - 1) + 1 if year == 2006
        quietly bysort location_id (year): replace rx_`species'_`i' = rx_`species'_`i'[_n-1] * (cov_national * (`pzq_`species'_`i'' - 1) + 1)  if year > 2006
      }
    }
    
    tempfile mda_cov
    save `mda_cov', replace
    save "`out_dir'/mda_cov.dta", replace

//****************************************************************************************** 
  // By country-year, calculate prevalence of sequelae, split by sex and age, and if sum of all sequelae is higher than
  // prevalence of infection, squeeze such that sum of all sequelae equals the total prevalence of infection.
    use "`out_dir'/inf_prev_draws.dta", clear
    levelsof ihme_loc_id, local(isos)
    
    foreach iso of local isos {
      di "`iso'"
    
      use "`out_dir'/inf_prev_draws.dta", clear
      quietly keep if ihme_loc_id == "`iso'"
            
      // Draw value for dispersion of infection within each country and simulate 1000 villages per draw
        quietly generate inf_sd = `inf_sd_lo' + runiform()*(`inf_sd_hi'-`inf_sd_lo')
        quietly expand `n_vill'
        foreach var in p_hae_draw p_man_draw {
          quietly generate logit_`var'_vill = logit(`var') + rnormal()*inf_sd
          quietly generate `var'_vill = 1/(1 + exp(-logit_`var'_vill))
            quietly replace `var'_vill = 0 if missing(`var'_vill)
          drop logit_`var'_vill
        }
        
      // Rescale drawn village prevalences on unit scale to correct for bias due to logit 
      // transformation; i.e. the mean of the drawn village prevalences is higher on the unit
      // scale than the expected mean prevalence on the unit scale.
        foreach var in p_hae_draw p_man_draw {
          bysort ihme_loc_id draw: egen `var'_vill_mu = mean(`var'_vill)
          quietly replace `var'_vill = `var'_vill * `var' / `var'_vill_mu if `var'_vill != 0 & `var' < 0.50
          quietly replace `var'_vill = 1-((1-`var'_vill) * (1-`var') / (1-`var'_vill_mu)) if `var'_vill != 0 & `var' > 0.50
          drop `var'_vill_mu
        }
        
      //*****************  MORBIDITY **************************************************
      // S. mansoni/japonicum morbidity
        foreach seq in dia hep hem asc {
          quietly generate double p_`seq' = (`a_`seq'' + `b_`seq'' * p_man_draw_vill^`c_`seq'')/(1 + `b_`seq'' * p_man_draw_vill^`c_`seq'') - `a_`seq''
          quietly replace  p_`seq' = 0 if p_man_draw_vill == 0
        }
        
        // Transform hematemesis lifetime-prevalence to point prevalence, assuming that 1-year-period prevalence
        // equals 1/2*lifetime-prevalence (Ongom and Bradley, 1972) and duration is 2 days.
          local duration 2
          local recall 365
          quietly replace p_hem = p_hem/2 * `duration'/(`duration' - 1 + `recall')
      
      
      // S. haematobium morbidity
        foreach seq in dys hyd bla {
          quietly generate double p_`seq' = (`a_`seq'' + `b_`seq'' * p_hae_draw_vill^`c_`seq'')/(1 + `b_`seq'' * p_hae_draw_vill^`c_`seq'') - `a_`seq'' 
          quietly replace  p_`seq' = 0 if p_hae_draw_vill == 0
        }
        
        // Transform dysuria two-week-period-prevalence to point prevalence, assuming duration is 14 days.
          local duration 14
          local recall 14
          quietly replace p_dys = p_dys * `duration'/(`duration' - 1 + `recall')
        
      // Squeeze cases into species-specific prevalence, if necessary
        generate p_any_man = p_dia + p_hep + p_hem + p_asc
        generate p_any_hae = p_dys + p_hyd + p_bla
        
        foreach seq in dia hep hem asc {
          quietly replace p_`seq' = p_`seq' * p_man_draw_vill / p_any_man if p_any_man > p_man_draw_vill
        }
        foreach seq in dys hyd bla {
          quietly replace p_`seq' = p_`seq' * p_hae_draw_vill / p_any_hae if p_any_hae > p_hae_draw_vill
        }
      
        drop *_vill
        
      // Collapse village-level simulations to national level
        collapse (mean) p_*, by(ihme_loc_id draw)
      
      // Squeeze cases into overall prevalence, if necessary
        generate p_any = p_any_man + p_any_hae
        foreach seq in dia hep hem asc dys hyd bla {
          quietly replace p_`seq' = p_`seq' * p_tot_draw / p_any if p_any > p_tot_draw
        }
        
        drop p_any*
        
      //***********************************************************
      
        tempfile `iso'_total_morb
        quietly save ``iso'_total_morb', replace      
    }
  
  // Append all country-level files
    clear
    foreach iso of local isos {
      append using ``iso'_total_morb'
    }
    
    save "`out_dir'/schisto_morb_total_prev_draws.dta", replace
	save "`in_dir'/schisto_morb_total_prev_draws.dta", replace

  //uses DisMod results: 
// ********************************************************************** 
// Generate a draw file for global age pattern in males and females for three models
  // Store model numbers as locals
	get_best_model_versions, gbd_team(epi) id_list(1465) clear
    local stage1_id = model_version_id
	get_best_model_versions, gbd_team(epi) id_list(1466) clear
    local stage2_id = model_version_id
	get_best_model_versions, gbd_team(epi) id_list(1467) clear
    local stage3_id = model_version_id
    

// ********************************************************************** 
 use `country_codes', replace
 
    egen region = group(region_name), label
    egen superregion = group(super_region_name), label
    keep ihme_loc_id location_id location_name region region_id superregion
    
		tempfile geo_data
		save `geo_data', replace
  
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
   
  keep if year >= 1980 & age < 80.1 & sex != 3 
  sort ihme_loc_id year sex age
  tempfile pop_env
  save `pop_env', replace  
  
// Split up all draws of overall prevalence of sequelae into age/sex-specific estimates
  // Margot's code below - adapted and reorganized by Luc to include treatment effects
    use "`out_dir'/schisto_morb_total_prev_draws.dta", clear
	merge m:1 ihme_loc_id using `geo_data', keep(matched) nogen
	tempfile prevdata
	save `prevdata', replace

  //apply same prevalence to all subnational locations where splits were not available (KEN, SAU, ZAF)
    //merge with pop_env data to fill in subnational geographies with national figures where necessary
  preserve
  use `pop_env', clear
  keep ihme_loc_id location_id year sex age age_group_id
  keep if year==2010 & sex==1 & age_group_id==5
  drop age_group_id - year
  replace ihme_loc_id = substr(ihme_loc_id, 1, 3)
  keep if inlist(ihme_loc_id, "KEN", "SAU", "ZAF")
  joinby ihme_loc_id using "`prevdata'", unmatched(none)
  drop if inlist(location_id, 180, 152, 196)
  tempfile ksz
  save `ksz', replace
  restore
  
  append using `ksz'
  drop ihme_loc_id
  merge m:1 location_id using `geo_data', keep(matched) nogen
  
	tempfile schisto_morb_prev_draws_filled
	save `schisto_morb_prev_draws_filled', replace
	save "`out_dir'/schisto_morb_prev_draws_filled.dta", replace
	save "`in_dir'/schisto_morb_prev_draws_filled.dta", replace
	
  // Create tempfiles for each sequelae
    foreach var of varlist p_dia p_hep p_dys p_hyd p_hem p_asc p_bla {
      preserve 
        quietly keep `var' ihme_loc_id draw
        quietly reshape wide `var', i(ihme_loc_id) j(draw)
        tempfile `var'
        quietly save ``var'', replace      
      restore
    }
	
  // Get ihme_loc_id's to loop through
    levelsof ihme_loc_id, local(isos) 
    quietly keep ihme_loc_id
    duplicates drop ihme_loc_id, force
    merge 1:m ihme_loc_id using `pop_env', keep(master match) nogen
    quietly keep if inlist(year,1990,1995,2000,2005,2010,2015) & inlist(sex,1,2) & age <= 80

    bysort ihme_loc_id year: egen total_pop = total(pop)
    quietly keep ihme_loc_id location_id year age age_group_id sex pop total_pop

    sort ihme_loc_id year age sex

    tempfile pop
    save `pop', replace

    // Bring in Dismod global age pattern for appropriate disease stage (country-year specific age patterns vary highly
    // due to paucity of data, whereas the global pattern looks plausible).
	//Get draws from the cluster
	  get_draws, gbd_id_field(modelable_entity_id) gbd_id(1465) location_ids(1) year_ids(2000) source(epi) status(best) clear
	  tempfile stage1_draws
      quietly save `stage1_draws', replace
	  
	  get_draws, gbd_id_field(modelable_entity_id) gbd_id(1466) location_ids(1) year_ids(2000) source(epi) status(best) clear
	  tempfile stage2_draws
      quietly save `stage2_draws', replace
	  
	  get_draws, gbd_id_field(modelable_entity_id) gbd_id(1467) location_ids(1) year_ids(2000) source(epi) status(best) clear
	  tempfile stage3_draws
      quietly save `stage3_draws', replace
	  
	// Loop through countries and sexes for all sequelae (except mild infection state without other sequelae,
  // this is handled separately below) and produce draws by age for every country-year-sex.
    foreach seq in p_dia p_bla p_hep p_dys p_hyd p_hem p_asc {
    foreach iso of local isos {

      di "`seq' `iso' pre-control"

    // Set grouping and healthstate
      if "`seq'" == "p_dia" {
          local grouping = "cases"
          local healthstate = "diarrhea_mild"
      }

      if "`seq'" == "p_bla" {
          local grouping = "bladder"
          local healthstate = "abdom_mild"
      }

      if "`seq'" == "p_hep" {
        local grouping = "hepatomegaly"
        local healthstate = "abdom_mild"
      }

      if "`seq'" == "p_dys" {
        local grouping = "dysuria"
        local healthstate = "abdom_mild"
      }

      if "`seq'" == "p_hyd" {
        local grouping = "hydronephrosis"
        local healthstate = "abdom_mild"
      }
      
      if "`seq'" == "p_hem" {
        local grouping = "hematemesis"
        local healthstate = "gastric_bleeding"
      }

      if "`seq'" == "p_asc" {
        local grouping = "ascites"
        local healthstate = "abdom_mod"
      }

    // Set age pattern
      if inlist("`seq'", "p_dia", "p_bla") {
        local stage = "stage1"
      }
      if inlist("`seq'", "p_hep", "p_dys", "p_hyd") {
        local stage = "stage2"
      }
      if inlist("`seq'", "p_hem", "p_asc") {
        local stage = "stage3"
      }
	  
    // Calculate pre-control prevalence (1990-2005)
    // Bring in Dismod global age pattern for appropriate disease stage (country-year specific age patterns vary highly
    // due to paucity of data, whereas the global pattern looks plausible).
	
      use ``stage'_draws', replace
	  drop location_id
	  rename sex_id sex
	  rename year_id year
      quietly gen ihme_loc_id = "`iso'"
 
      quietly drop if age_group_id > 21
      
      if inlist("`seq'","p_hep","p_hem","p_asc") {
        forvalues i = 0/999 {
		  quietly replace draw_`i' = 0 if age_group_id < 8 //age < 15
        }
      }
      else {
        forvalues i = 0/999 {
		  quietly replace draw_`i' = 0 if age_group_id < 5 //age < 1
        }
      }

    // Merge in population and overall prevalence estimates, and compute cases by age and sex
      quietly merge 1:1 ihme_loc_id sex age_group_id year using `pop', keepusing(pop total_pop location_id) keep(master matched) nogen
      quietly merge m:1 ihme_loc_id using ``seq'', keep(master matched) nogen
      
      format %16.0g age_group_id draw* `seq'*
  
      forvalues x= 0/999 {
      
      // Calculate unscaled cases by age, sex, and total (all ages and sexes)
        quietly replace draw_`x' = draw_`x' * pop
        quietly egen total_dis_cases_`x' = total(draw_`x')
      
      // Calculate total cases according to custom model
        quietly replace `seq'`x' = `seq'`x'*total_pop
        
      // Rescale age and sex-specific cases such that they add up to the total predicted by the custom model,
      // and convert to prevalence per capita
        quietly replace draw_`x' = (draw_`x' * (`seq'`x'/total_dis_cases_`x'))/pop
        quietly replace draw_`x' = 1 if draw_`x' > 1
      }

      keep draw_* age_group_id sex location_id
	  local id = location_id
      preserve
		quietly keep if sex == 1
        drop sex
        cap mkdir "`tmp_dir'/`grouping'"
        cap mkdir "`tmp_dir'/`grouping'/`healthstate'"
        
        foreach year in 1990 1995 2000 2005 {
          quietly outsheet using "`tmp_dir'/`grouping'/`healthstate'/5_`id'_`year'_1.csv", comma replace
        }
        
      restore
      preserve
        quietly keep if sex == 2
        drop sex
        cap mkdir "`tmp_dir'/`grouping'"
        cap mkdir "`tmp_dir'/`grouping'/`healthstate'"
        
        foreach year in 1990 1995 2000 2005 {
          quietly outsheet using "`tmp_dir'/`grouping'/`healthstate'/5_`id'_`year'_2.csv", comma replace
        }
        
      restore

    // For post-control years (2010-2015), take 2005 results and correct for effect of treatment
    // (assuming different effects for acute and chronic symptoms).
      di "`seq' `iso' during control"
      foreach year in 2010 2015 {
      foreach sex in 1 2 {
        quietly insheet using "`tmp_dir'/`grouping'/`healthstate'/5_`id'_2005_`sex'.csv", double clear
        
        format %16.0g draw* age
        
        generate year = `year'
        generate ihme_loc_id = "`iso'"

        quietly merge m:1 location_id year using "`out_dir'/mda_cov.dta", keepusing(cov_* rx*) keep(master match)
        
        // Check that there are coverage figures; if not, assume zero effect of mass treatment
          quietly summarize _merge
          if r(mean) == 1 {
            quietly replace cov_cumm = 0
            forvalues i = 0/999 {
              quietly replace rx_sh_`i' = 1
              quietly replace rx_sm_`i' = 1
            }
          }
          drop _merge
      
      // Effect on acute symptoms same as effect on infection (in terms of risk of parasitological failure)
        if inlist("`seq'","p_dia") {
          forvalues i = 0/999 {
            quietly replace draw_`i' = draw_`i' * rx_sh_`i'
            quietly replace draw_`i' = 1 if draw_`i' > 1
            
          }
        }
        if inlist("`seq'","p_bla","p_dys","p_hyd") {
          forvalues i = 0/999 {
            quietly replace draw_`i' = draw_`i' * rx_sm_`i'
            quietly replace draw_`i' = 1 if draw_`i' > 1
          }
        }
        
      // Effect on chronic symptoms: assume zero incidence in treated cases. Correct for excess mortality
      // among treated cohort (not balanced by incidence), assuming prevalent cases die at a rate of 0.1/year
      // (Kheir MM et al. Am J Trop Med Hyg. 1999 Feb;60(2):307-10). The proportion treated cases are
      // assumed to be the average coverage over the whole period since 2005
        if inlist("`seq'","p_hep","p_hem","p_asc") {
          if `year' == 2010 {
            gsort -age
            forvalues i = 0/999 {
              quietly replace draw_`i' = draw_`i' * (1-cov_cumm/5) + draw_`i'[_n+1] * cov_cumm/5 * 0.9^5 if age_group_id >= 8	//age >= 15
              quietly replace draw_`i' = 1 if draw_`i' > 1
            }
            sort age
          }
          if `year' == 2015 {
            gsort -age
            forvalues i = 0/999 {
              quietly replace draw_`i' = draw_`i' * (1-cov_cumm/10) + draw_`i'[_n+2] * cov_cumm/10 * 0.9^10 if age_group_id >= 8
              quietly replace draw_`i' = 1 if draw_`i' > 1
            }
            sort age
          }
        }
        
        quietly keep age draw*
        
        quietly outsheet using "`tmp_dir'/`grouping'/`healthstate'/5_`id'_`year'_`sex'.csv", comma replace
      }
      }
		
		}
		}


  //////////////////////////////////////////////////////////////////////////////////////////////
  
  // Create estimate of prevalence of infection by country-year-age-sex, based on assumed age-
  // distribution of overall infection
    use "`in_dir'/schisto_morb_prev_draws_filled.dta", clear
    preserve 
      quietly keep p_tot p_hae p_man ihme_loc_id draw
      recast double p_*
      format %16.0g p_*
      rename *_draw *
      
      quietly replace p_hae = 1 if p_hae > 1
      quietly replace p_man = 1 if p_man > 1
      quietly replace p_tot = 1 if p_tot > 1
      
      quietly reshape wide p_*, i(ihme_loc_id) j(draw)
      tempfile p_inf
      quietly save `p_inf', replace      
    restore
    
  // Get ihme_loc_id's to loop through
    levelsof ihme_loc_id, local(isos) 
   
  // Prep population data from mortality team
    quietly keep ihme_loc_id
    duplicates drop ihme_loc_id, force
	merge 1:m ihme_loc_id using `pop_env', keep(master match) nogen
    quietly keep if inlist(year,1990,1995,2000,2005,2010,2015) & inlist(sex,1,2) & age <= 80

    bysort ihme_loc_id year: egen total_pop = total(pop)
    quietly keep ihme_loc_id location_id year age age_group_id sex pop total_pop

    sort ihme_loc_id year age sex

    tempfile pop
    save `pop', replace
    
    cap mkdir "`tmp_dir'/p_hae"
    cap mkdir "`tmp_dir'/p_man"    
    cap mkdir "`tmp_dir'/p_tot"
    
    // Create general age pattern for infection (linear increase until age 15, then stable over age, same for the two sexes)
  clear
  quietly set obs 20
  quietly generate double age = .
  quietly format age %16.0g
  quietly replace age = _n * 5
  quietly replace age = 0 if age == 85
  quietly replace age = 0.01 if age == 90
  quietly replace age = 0.1 if age == 95
  quietly replace age = 1 if age == 100
  sort age

  generate double age_group_id = .
  format %16.0g age_group_id
  replace age_group_id = _n + 1
  tempfile ages
  save `ages', replace
  
      clear
      quietly insheet using "`tmp_dir'/cases/diarrhea_mild/5_168_2005_1.csv", double clear	//loc_id 168 = AGO
      format %16.0g age
      drop draw_*
	  merge 1:1 age_group_id using `ages', nogen
      
      local newobs = _N + 1
      set obs `newobs'
      replace age = 99 if missing(age)
      
      generate double p = .
        format %16.0g p
        replace p = 0.01*(age - 1) if age >= 1
        replace p = .14 if age > 15
        replace p = 0 if missing(p)
      generate double P = .
        format %16.0g P
        replace P = ((age[_n+1] - age) * (p[_n+1] - (p[_n+1] - p)/2)) / (age[_n+1] - age)
      drop if age == 99
      
      expand 2, generate(tag)
      generate sex = 1 if tag == 0
        replace sex = 2 if tag == 1
      
      drop tag p
	  drop location_id
      
      tempfile p_inf_pattern
      save `p_inf_pattern', replace
      
      
    // Create draw files
      foreach iso of local isos {
        
        di "`iso'"
        use `p_inf_pattern', clear
        
        quietly gen ihme_loc_id = "`iso'"
        quietly gen year = 2000
        
      // Merge in population and overall prevalence estimates, and compute cases by age and sex
        quietly merge 1:1 ihme_loc_id sex age year using `pop', keepusing(pop total_pop location_id) keep(master matched) nogen
        quietly merge m:1 ihme_loc_id using `p_inf', keep(master matched) nogen
		
        format %16.0g age P p_*
        
        // Calculate unscaled cases by age, sex, and total (all ages and sexes)
          quietly replace P = P * pop
          quietly egen total_P = total(P)
        
        foreach type in tot man hae {
        forvalues x= 0/999 {
        // Calculate total cases according to custom model
          quietly replace p_`type'`x' = p_`type'`x'*total_pop
          
        // Rescale age and sex-specific cases such that they add up to the total predicted by the custom model,
        // and convert to prevalence per capita
          quietly replace p_`type'`x' = (p_`type'`x' * (P/total_P))/pop
        }
        }
	
        local id = location_id 
		foreach type in tot man hae {
          preserve
            rename p_`type'* draw_*
            quietly keep if sex == 1
            keep draw_* age_group_id

            foreach year in 1990 1995 2000 2005 {
              quietly outsheet using "`tmp_dir'/p_`type'/5_`id'_`year'_1.csv", comma replace
            }
            
          restore
          preserve
            rename p_`type'* draw_*
            quietly keep if sex == 2
            keep draw_* age_group_id

            foreach year in 1990 1995 2000 2005 {
              quietly outsheet using "`tmp_dir'/p_`type'/5_`id'_`year'_2.csv", comma replace
            }
            
          restore
        }
        
      // For post-control years (2010-2015), use 2005 results and correct for effect of treatment
        drop year
        foreach year in 2010 2015 {
          
          preserve
                      
            generate year = `year'           
            quietly merge m:1 location_id year using "`out_dir'/mda_cov.dta", keepusing(rx*) keep(master match)
            local id = location_id 
          // Check that there are coverage figures; if not, assume zero effect of mass treatment
            quietly summarize _merge
            if r(mean) == 1 {
              forvalues i = 0/999 {
                quietly replace rx_sh_`i' = 1
                quietly replace rx_sm_`i' = 1
              }
            }
            drop _merge
          
          // Correct infection levels for effect of PCT. Effect on total prevalence is equal to weighted effect on specific species
            forvalues i = 0/999 {
              quietly replace p_tot`i' = p_tot`i' * (rx_sh_`i' * p_hae`i' + rx_sm_`i' * p_man`i') / (p_hae`i' + p_man`i') if p_hae`i' > 0 | p_man`i' > 0
              quietly replace p_hae`i' = p_hae`i' * rx_sh_`i'
              quietly replace p_man`i' = p_man`i' * rx_sm_`i'
            }
            
            keep age_group_id sex p_*
            
            tempfile post_control
            quietly save `post_control', replace
      
          // Write files
            foreach type in tot man hae {
            foreach sex in 1 2 {
              
              use `post_control', clear
              if `sex' == 1 {
                quietly keep if sex == 1
              }
              else {
                quietly keep if sex == 2
              }
              
              quietly keep age_group_id p_`type'*
              rename p_`type'* draw_*
              
              quietly outsheet using "`tmp_dir'/p_`type'/5_`id'_`year'_`sex'.csv", comma replace
            }
            }
            
          restore
        }
      
      }
      
    // Generate draws for infection without specific sequelae by country-year-age-sex.
	  use `pop', clear  
	  levelsof location_id, local(isos)	
      foreach iso of local isos {
      foreach year in 1990 1995 2000 2005 2010 2015 {
      foreach sex in 1 2 {
        di "`iso' `year' `sex'"
      
      foreach seq in p_dia p_bla p_hep p_dys p_hyd p_hem p_asc {
        if "`seq'" == "p_dia" {
            local grouping = "cases"
            local healthstate = "diarrhea_mild"
        }

        if "`seq'" == "p_bla" {
            local grouping = "bladder"
            local healthstate = "abdom_mild"
        }

        if "`seq'" == "p_hep" {
          local grouping = "hepatomegaly"
          local healthstate = "abdom_mild"
        }

        if "`seq'" == "p_dys" {
          local grouping = "dysuria"
          local healthstate = "abdom_mild"
        }

        if "`seq'" == "p_hyd" {
          local grouping = "hydronephrosis"
          local healthstate = "abdom_mild"
        }
        
        if "`seq'" == "p_hem" {
          local grouping = "hematemesis"
          local healthstate = "gastric_bleeding"
        }

        if "`seq'" == "p_asc" {
          local grouping = "ascites"
          local healthstate = "abdom_mod"
        }

        quietly insheet using "`tmp_dir'/`grouping'/`healthstate'/5_`iso'_`year'_`sex'.csv", clear double
        
        format %16.0g age draw*
        
        rename draw* `seq'*
        
        tempfile `seq'_temp
        quietly save ``seq'_temp'

      }

      quietly insheet using "`tmp_dir'/p_tot/5_`iso'_`year'_`sex'.csv",  clear double

      format %16.0g age draw*
      
      foreach seq in p_dia p_bla p_hep p_dys p_hyd p_hem p_asc {
        quietly merge 1:1 age using ``seq'_temp', nogen
        forvalues i = 0/999 {
          quietly replace draw_`i' = draw_`i' - `seq'_`i' if !missing(`seq'_`i')
        }
        drop `seq'*
      }
      
      forvalues i = 0/999 {
        quietly replace draw_`i' = 0 if draw_`i' < 0
      }
      
      quietly keep age draw*
      cap mkdir `tmp_dir'/cases/inf_mild
      quietly outsheet using "`tmp_dir'/cases/inf_mild/5_`iso'_`year'_`sex'.csv", comma replace
      
      }
      }
      }
  
        
  // Create draw files with zeroes for non-endemic countries
    // Create list of endemic countries
      use "`out_dir'/schisto_morb_prev_draws_filled.dta", clear
      quietly keep ihme_loc_id
      quietly duplicates drop ihme_loc_id, force
      generate endemic = 1
      
      tempfile endemic
      save `endemic', replace
      
    // Get list of all countries considered for non-fatal conditions
      use `pop_env', replace
	  keep if year == 2000 & age_group_id == 5 & sex == 1
	  keep location_id ihme_loc_id

    // Create list of non-endemic countries
      merge 1:1 ihme_loc_id using `endemic', keepusing(endemic) keep(master match) nogen
      quietly drop if endemic == 1
      levelsof location_id, local(non_endemic)
      
    // Create draw file with zeroes
      clear
      quietly insheet using "`tmp_dir'/cases/inf_mild/5_168_2005_1.csv", clear double
      format %16.0g age draw*
      
      forvalues i = 0/999 {
        quietly replace draw_`i' = 0
      }
      
      tempfile zeroes
      save `zeroes', replace
      
    // Write draw files
      use `zeroes', clear
      foreach iso of local non_endemic {
	  foreach year in 1990 1995 2000 2005 2010 2015 {
      foreach sex in 1 2 {
        
        di "`iso' `year' `sex' `seq'"

      foreach seq in p_dia p_nos p_bla p_hep p_dys p_hyd p_hem p_asc p_inf {
        
        if "`seq'" == "p_dia" {
            local grouping = "cases"
            local healthstate = "diarrhea_mild"
        }

        if "`seq'" == "p_nos" {
            local grouping = "cases"
            local healthstate = "inf_mild"
        }
        
        if "`seq'" == "p_bla" {
            local grouping = "bladder"
            local healthstate = "abdom_mild"
        }

        if "`seq'" == "p_hep" {
          local grouping = "hepatomegaly"
          local healthstate = "abdom_mild"
        }

        if "`seq'" == "p_dys" {
          local grouping = "dysuria"
          local healthstate = "abdom_mild"
        }

        if "`seq'" == "p_hyd" {
          local grouping = "hydronephrosis"
          local healthstate = "abdom_mild"
        }
        
        if "`seq'" == "p_hem" {
          local grouping = "hematemesis"
          local healthstate = "gastric_bleeding"
        }

        if "`seq'" == "p_asc" {
          local grouping = "ascites"
          local healthstate = "abdom_mod"
        }
        
        if "`seq'" == "p_inf" {
          quietly outsheet using "`tmp_dir'/p_tot/5_`iso'_`year'_`sex'.csv", comma replace
          quietly outsheet using "`tmp_dir'/p_man/5_`iso'_`year'_`sex'.csv", comma replace
          quietly outsheet using "`tmp_dir'/p_hae/5_`iso'_`year'_`sex'.csv", comma replace
        }
        else {
          quietly outsheet using "`tmp_dir'/`grouping'/`healthstate'/5_`iso'_`year'_`sex'.csv", comma replace 
        }
        
        
      }
      }
      }
      }

  // Upload draws to central database
  ********************************
	quietly do "$prefix/WORK/10_gbd/00_library/functions/save_results.do"
	save_results, modelable_entity_id(2797) description("Schisto total infection cases custom model") in_dir("`tmp_dir'/p_tot") metrics(prevalence) mark_best(yes)
	save_results, modelable_entity_id(2966) description("Schisto mansoni infection cases custom model") in_dir("`tmp_dir'/p_man") metrics(prevalence) mark_best(yes)
	save_results, modelable_entity_id(2965) description("Schisto haematobium infection cases custom model") in_dir("`tmp_dir'/p_hae") metrics(prevalence) mark_best(yes)
	save_results, modelable_entity_id(1468) description("Schisto infection mild infection no specific sequelae custom model") in_dir("`tmp_dir'/cases/inf_mild") metrics(prevalence) mark_best(yes)
	save_results, modelable_entity_id(1469) description("Schisto diarrhea custom model") in_dir("`tmp_dir'/cases/diarrhea_mild") metrics(prevalence) mark_best(yes)
	save_results, modelable_entity_id(1470) description("Schisto hematemesis custom model") in_dir("`tmp_dir'/hematemesis/gastric_bleeding") metrics(prevalence) mark_best(yes)
	save_results, modelable_entity_id(1471) description("Schisto hepatomegaly custom model") in_dir("`tmp_dir'/hepatomegaly/abdom_mild") metrics(prevalence) mark_best(yes)
	save_results, modelable_entity_id(1472) description("Schisto ascites custom model") in_dir("`tmp_dir'/ascites/abdom_mod") metrics(prevalence) mark_best(yes)
	save_results, modelable_entity_id(1473) description("Schisto dysuria custom model") in_dir("`tmp_dir'/dysuria/abdom_mild") metrics(prevalence) mark_best(yes)
	save_results, modelable_entity_id(1474) description("Schisto bladder pathology custom model") in_dir("`tmp_dir'/bladder/abdom_mild") metrics(prevalence) mark_best(yes)
	save_results, modelable_entity_id(1475) description("Schisto hydronephrosis custom model") in_dir("`tmp_dir'/hydronephrosis/abdom_mild") metrics(prevalence) mark_best(yes)

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
