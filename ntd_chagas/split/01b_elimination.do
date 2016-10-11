	
	
/******************************************************************************\
           SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS
\******************************************************************************/

* BOILERPLATE *
  clear all
  set maxvar 12000
  set more off
  
  adopath + /home/j/WORK/10_gbd/00_library/functions
 
  tempfile appendTemp mergeTemp preElimPrev streamingTemp

  

* PULL IN LOCATION_ID AND INCOME CATEGORY FROM BASH COMMAND *  
  local location "`1'"


* SET UP OUTPUT DIRECTORIES *  
  local outDir /ihme/scratch/users/stanaway/chagas


* SET UP LOCALS WITH MODELABLE ENTITY IDS AND AGE GROUPS *  
  local meid  1450
  local ages 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21
  
 
* SET UP LOCALS WITH CHAGAS ELIMINATION YEARS *  
  if `location' == 98 local eYear 1999
  else if `location' == 99 local eYear 1997
	
	
  
* CREATE EMPTY ROWS FOR INTERPOLATION *
  
  set obs `=_N + 2015 - 1979'
  generate year_id = _n + 1979
  drop if mod(year_id, 5)==0 & year>1989
  
  expand 20
  bysort year_id: generate age_group_id = _n + 1
  
  expand 2
  bysort year_id age_group_id: generate sex_id = _n
  
  generate location_id = `location'
  
  save `appendTemp'
  
  
  
/******************************************************************************\
                      PULL IN DRAWS AND MAKE CALCULATIONS
\******************************************************************************/
  
    * PULL IN DRAWS FROM DISMOD MODELS FOR INCIDENCE AND PREVALENVCE *
      get_draws, gbd_id_field(modelable_entity_id) gbd_id(`meid') source(dismod) location_ids(`location') age_group_ids(`ages') measure_ids(5 6 9) status(best) clear
	  
      drop model*
      rename draw_* draw_*_
      reshape wide draw_*_, i(location_id year_id age_group_id sex_id) j(measure_id)

	  rename draw_*_5 prev_*
	  rename draw_*_6 inc_*
	  rename draw_*_9 em_*
	  
      preserve
	  
	  drop inc_* em_*
	  keep if year_id <= `eYear'
	  save `preElimPrev'
	  
	  restore
	  
	  
	
/******************************************************************************\
                             INTERPOLATE DEATHS
\******************************************************************************/			

append using `appendTemp'

foreach metric in prev inc em {

  fastrowmean `metric'_*, mean_var_name(`metric'Mean)	
	
  forvalues year = 1980/2015 {
	
	local index = `year' - 1979

	if `year'< 1990  {
	  local indexStart = 1990 - 1979
	  local indexEnd   = 2015 - 1979
	  }	
	  
	else {
	  local indexStart = 5 * floor(`year'/5) - 1979
	  local indexEnd   = 5 * ceil(`year'/5)  - 1979
	  if `indexStart'==`indexEnd' continue
	  }

  
	foreach var of varlist `metric'_* {
		quietly {
		bysort age_group_id sex_id (year_id): replace `var' = `var'[`indexStart'] * exp(ln(`metric'Mean[`indexEnd']/`metric'Mean[`indexStart']) * (`index'-`indexStart') / (`indexEnd'-`indexStart')) if year_id==`year'
        }
		
		di "." _continue
		}	
	}
  drop `metric'Mean
  }
				  
				  
/******************************************************************************\
                             BIRTH PREVALENCE
\******************************************************************************/				  



* DERIVE PARAMETERS OF BETA DISTRIBUTION FOR RATE OF VERTICAL TRANSMISSION *
  local mu    = 0.047  // mean and SD here are from meta-analysis by Howard et al (doi: 10.1111/1471-0528.12396)
  local sigma = (0.056 - 0.039) / (invnormal(0.975) * 2)
  local alpha = `mu' * (`mu' - `mu'^2 - `sigma'^2) / `sigma'^2 
  local beta  = `alpha' * (1 - `mu') / `mu'  
 
  
	
   * BRING IN DATA ON PROPORTION ON NUMBER OF PREGNANCIES BY AGE, YEAR, LOCATION (USING ESTIMATES CREATED FOR HEPATITIS E ESTIMATION) *  
     merge m:1 location_id age_group_id year_id using /home/j/WORK/04_epi/02_models/01_code/06_custom/hepatitis/inputs/prPreg.dta, assert(2 3) keep(3) nogenerate

   * ESTIMATE BIRTH PREVALENCE *  
     bysort location_id year_id sex_id: egen nPregTotal = total(nPreg)

	  
	sort location_id year_id sex_id age_group_id  
	  
	save `streamingTemp'  
	  
	forvalues year = `eYear'/2014 { 
	
	 preserve
	 drop if year_id==`=`year'+1'
	 save `streamingTemp', replace
	 restore
	 
	 keep if year_id == `year'	
	 replace year_id = `year' + 1
	 
     forvalues i = 0 / 999 {
       local vertical    = rbeta(`alpha', `beta')  
       quietly generate posPregTemp = nPreg * prev_`i' * `vertical' if sex_id==2
	   bysort location_id year_id (sex_id age_group_id): egen posPregTempTotal = total(posPregTemp)
	   replace prev_`i' = posPregTempTotal / nPregTotal if age_group_years_start<1
		  
       replace em_`i' = em_`i' * (age_group_years_end - age_group_years_start) if age_group_years_start<1
	   bysort sex_id (age_group_id): replace em_`i' = sum(em_`i') if age_group_years_start<1
		
       bysort sex_id (age_group_id): replace prev_`i' = (4/5 * prev_`i') + (1/5 * prev_`i'[_n-1]) if age_group_years_start>=5
	   bysort sex_id (age_group_id): replace prev_`i' = (3/4 * prev_`i') + (1/4 * prev_`i'[1]) if age_group_years_start==1
	   replace prev_`i' = prev_`i' * (1 - em_`i')
			
	   drop posPregTemp*
	  }
	  
	append using `streamingTemp'
	save `streamingTemp', replace
    }

keep if year_id>=1990 & mod(year_id, 5)== 0	
keep location_id year_id age_group_id sex_id prev_*
generate measure_id = 5
