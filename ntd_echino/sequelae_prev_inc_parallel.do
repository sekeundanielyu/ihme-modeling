// Prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	adopath + $prefix/WORK/10_gbd/00_library/functions

// Set locals from arguments passed on to job
  local out_dir `1'
  local sequela `2'  
  local metric `3'
  local iso `4'
  local sex `5'
  local year `6'

// Create thousand draws of proportions for abdominal, respiratory and epileptic symptoms among echinococcosis cases that
//  add up to 1, given the observed sample sizes in Eckert & Deplazes, Clinical Microbiology Reviews 2004; 17(1) 107-135 (Table 3).
// Assume that the observed cases follow a multinomial distribution cat(p1,p2,p3), where (p1,p2,p3)~Dirichlet(a1,a2,a3),
// where the size parameters of the Dirichlet distribution are the number of observations in each category (must be non-zero).
  local n1 = 316+17+15+9+1  // abdominal or pelvic cyst localization
  local n2 = 79+5           // thoracic cyst localization (lungs & mediastinum)
  local n3 = 4              // brain cyst localization
  local n4 = 10+3           // other localization (bones, muscles, and skin; currently not assigning this to a healthstate)

  forvalues i = 0/999 {
    quietly clear
    quietly set obs 1
    
    generate double a1 = rgamma(`n1', 1)
    generate double a2 = rgamma(`n2', 1)
    generate double a3 = rgamma(`n3', 1)
    generate double a4 = rgamma(`n4', 1)
    generate double A = a1 + a2 + a3 + a4
    
    generate double p1 = a1 / A
    generate double p2 = a2 / A
    generate double p3 = a3 / A
    generate double p4 = a4 / A
  
    local p_abd_`i' = p1 + p4  // Added these cases to abdominal (the largest group) so we at least assign some burden
    local p_resp_`i' = p2
    local p_epilepsy_`i' = p3
  
    di "`p_abd_`i''  `p_resp_`i''  `p_epilepsy_`i''"
  }	

// Multiply echinococcosis incidence and prevalence among with the proportions of sequelae  
//With parallelization 
  display in red "`sequela' `metric' `iso' `year' `sex'"
    
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(1484) measure_ids(`metric') location_ids(`iso') year_ids(`year') sex_ids(`sex') source(epi) status(best) clear
    
	quietly drop if age_group_id > 21 //age > 80 yrs
    quietly keep draw_* age_group_id
    format draw* %16.0g

      forvalues i = 0/999 {
        quietly replace draw_`i' = draw_`i' * `p_`sequela'_`i''
      }
      quietly outsheet using "`out_dir'/`sequela'_prev/`metric'_`iso'_`year'_`sex'.csv", comma replace

