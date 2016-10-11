
// Date: June 2016
// Purpose: Create fraction married variables from data extracted through ubcov. Used in 2016 SDG paper.

cd "J:/Project/Coverage/Contraceptives/2015 Contraceptive Prevalence Estimates/_ubcov_data_output"

clear
gen foo = "null"
tempfile master
save `master', replace


cap restore 


local countries : dir "./" dir "*", respectcase // get a list of all countries
local countries : list clean countries 
if substr("`country'", 1, 3) == "log"  continue // ignore log folder


foreach country of local countries {
	local dtas : dir "./`country'/" file "*" // get a list of all dtas
	local dtas : list clean dtas 
	di in red "`country'"
	
	foreach dta of local dtas {
	
		use "./`country'/`dta'", clear
		di in red "`dta'"
		
		quietly{	
		
				
				drop if ihme_age_yr < 15 & ihme_age_yr >= 49 // drop women outside of the age range of interest
				drop if ihme_male == 1 // drop non-women
		
				replace ihme_pweight = 1 if ihme_pweight == . // replace empty pweights with 1
				destring ihme_psu, replace
				if ihme_psu != . {
					svyset ihme_psu [pweight = ihme_pweight] // weight at psu level if applicable
					} 
				if ihme_psu == . {
					svyset [pweight = ihme_pweight] // otherwise apply weights equally
					}
					
	forvalues i=15(5)45 {
			count if ihme_age_yr>=`i' & ihme_age_yr<(`i'+5)
					if r(N)!=0 {

				preserve 
				// drop it outside of age range of interest
				keep if ihme_age_yr >=`i' & ihme_age_yr <(`i'+5)
				
				gen currmarr = 1 if marr_status == 1
				replace currmarr = 0 if currmarr != 1
			
							
				gen evermarr = 1 if marr_status == 1 | marr_status == 2
				replace evermarr = 0 if evermarr != 1
								
				gen nomarr = 1 if evermarr == 0
				replace nomarr = 0 if evermarr == 1
					
				// calculate the fraction of women who are currently married
				svy: mean currmarr
				matrix mean_currmarr = e(b)
				gen currmarr_prev = mean_currmarr[1,1]
				matrix var_currmarr=e(V)
				gen currmarr_var=var_currmarr[1,1]
						
				// calculate % women who have ever been married
				svy: mean evermarr
				matrix mean_evermarr = e(b)
				gen evermarr_prev = mean_evermarr[1,1]
				matrix var_evermarr=e(V)
				gen evermarr_var=var_evermarr[1,1]
							
				// calculate % women never married
				svy: mean nomarr
				matrix mean_nomarr = e(b)
				gen nomarr_prev = mean_nomarr[1,1]
				matrix var_nomarr=e(V)
				gen nomarr_var=var_nomarr[1,1]
				
				
				// gen avg interview date
				svy: mean ihme_end_year
				matrix date = e(b)
				gen cmc_int = date[1,1]
				gen agegroup=`i'
									
									
				keep if _n==1
				gen iso3 = ihme_loc_id
				gen year = ihme_end_year
				gen filename = ihme_file_name
				gen survey = ihme_type


				
				keep iso3 survey ihme_start_year ihme_end_year filename currmarr_prev currmarr_var evermarr_prev evermarr_var nomarr_prev nomarr_var agegroup 
				order iso3 survey ihme_start_year ihme_end_year filename agegroup currmarr_prev currmarr_var evermarr_prev evermarr_var nomarr_prev nomarr_var
				
				
			
		
// save each dataset individually 
save "J:/Project/Coverage/Contraceptives/2015 Contraceptive Prevalence Estimates/output/married/`i'_`country'_`dta'", replace


// append into one dataset
append using `master', force
save `master', replace

			
restore
				}
			
			}
			
		}
		
	}
	
}

use `master', clear
save "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\output\MASTER PREVALENCE FILES\master_married.dta", replace


drop foo
