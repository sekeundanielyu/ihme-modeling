
clear
set more off

* DEFINE LOCALS AND DIRECTORIES *

  if c(os) == "Unix" {
    local j = "/home/j"
    set odbcmgr unixodbc
    }
  else if c(os) == "Windows" {
    local j = "J:"
    }

  local dir         "`j'/WORK/04_epi/01_database/02_data/intest/2523/03_review"
  local  sensData   "`j'/Project/Causes of Death/codem/models/A04.2/DISMOD/Data/sensitivity_of_blood_cultures_typhoid_diag.dta"
  local  date       2014_01_14
 

  
* IMPORT DATASHEET *

import delimited using `dir'/01_download/me_2523_ts_2015_11_06__113452.csv, clear bindquotes(strict) case(preserve)

replace is_outlier=1 if standard_error==0


 
  
/******************************************************************************\
                 ADJUST FOR POOR DIAGNOSTIC SENSITIVITY
\******************************************************************************/  
  
 	
* OPEN SENSITIVITY DATA *
  preserve
  use "`sensData'", clear
  gen mean = positive_cases/total_cases
	
* CALCULATE STANDARD ERROR OF BINOMIAL * 
  gen se = sqrt((mean/(1-mean))/total_cases)
	
	
* RUN THE METAANLYSIS (NB THIS REQUIRES THAT YOU INSTALL METAN) *
  metan mean se, random nograph
  local pooled = `r(ES)'
  local upper = `r(ci_upp)'
  local lower = `r(ci_low)'
  local se = `r(seES)'

	
	
* RESTORE THE INTEST DATASHEET *
  restore


/* UNCERTAINTY...There are three sources of uncertainty: 1) uncertainty in each
   study's estimate of incidence, 2) uncertainty in our meta-estimate of sensitivity,
   and 3) uncertainty in the actual sensitivity in each study (random variation 
   that is largely a funciton of sample size).  Here, we pull 1,000 draws and
   incorporate three random distributions to account for the three sources of
   uncertainty */
   
   * First need to ensure that all observations have mean, standard error & sample size
   quietly replace sample_size = effective_sample_size if missing(sample_size)

   generate alpha = mean * (mean - mean^2 - standard_error^2) / standard_error^2
   generate beta  = alpha * (1 - mean) / mean
   
	forvalues i = 1/1000 {
		quietly {
		gen temp_`i' = rgamma(alpha, 1) / (rgamma(alpha, 1) + rgamma(beta, 1)) / (rbinomial(sample_size, rnormal(`pooled', `se')) / sample_size) 
		replace temp_`i' = rnormal(mean, standard_error) / (rbinomial(sample_size, rnormal(`pooled', `se')) / sample_size) if beta>1e+8
		replace temp_`i' = 0 if temp_`i'<0 
		}
		}


* Find the mean, confidence limits and standard error from the 1,000 draws
  egen tempMean = rowmean(temp_*)
  egen tempLower = rowpctile(temp_*), p(2.5)
  egen tempUpper = rowpctile(temp_*), p(97.5)
  egen tempSE = rowsd(temp_*)
	
  drop temp_*

* Ensure that we never end up with estimates below 0 or above 1
  foreach var of varlist tempMean tempLower tempUpper {
    assert `var'>=0  & `var'<=1
	}
	
	
  replace cases = cases * tempMean / mean 
  replace mean  = tempMean 
  replace lower = tempLower  
  replace upper = tempUpper  
  replace standard_error = tempSE  
  replace note_modeler = "Multiplied by adjustment factor (~1.8) to account for poor diagnostic sensitivity." 

  drop alpha beta temp*

export excel using `dir'/03_upload/me_2523_ts_`=subinstr(string(date("`c(current_date)'", "DMY"), "%tdCCYY_NN_DD"), " ", "_",.)'__`=subinstr("`c(current_time)'", ":", "", .)'.xlsx, sheet("extraction") firstrow(variables) replace
