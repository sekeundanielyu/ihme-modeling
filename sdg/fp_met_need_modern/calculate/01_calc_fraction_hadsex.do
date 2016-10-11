
// Date: June 2016
// Purpose: Create had sex variables from data extracted through ubcov. Used in 2016 SDG paper.

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
	
		// some countries only ask ever married women about contraceptive use.  replace all = 0 if that's the case. (note these are the pre-2010 surveys, update for post-2010 surveys where this is true)
		gen sample = 1 if ihme_file_name == "BGD_DHS3_1993_1994_WN_Y2008M09D23.DTA" | ihme_file_name == "BGD_DHS3_1996_1997_WN_Y2008M09D23.DTA" | ihme_file_name == "BGD_DHS4_1999_2000_WN_Y2008M09D23.DTA" | ihme_file_name == "BGD_DHS4_2004_WN_Y2008M09D23.DTA" | ihme_file_name == "BGD_DHS5_2007_WN_Y2009M05D11.DTA"| ihme_file_name == "ALL_COUNTRIES_PAPFAM_2001_2004_WN.DTA" | ihme_file_name == "EGY_DHS2_1992_1993_WN_Y2008M09D23.DTA" | ihme_file_name == "EGY_DHS3_1995_1996_WN_Y2008M09D23.DTA" | ihme_file_name == "EGY_DHS4_2000_WN_Y2008M09D23.DTA" | ihme_file_name == "EGY_DHS5_2005_WN_Y2008M09D23.DTA" | ihme_file_name == "EGY_DHS5_2008_WN_Y2009M06D19.DTA" | ihme_file_name == "EGY_ITR_DHS4_2003_WN_Y2008M09D23.DTA"  | ihme_file_name == "IDN_DHS2_1991_WN_Y2008M09D23.DTA" | ihme_file_name == "IDN_DHS3_1994_WN_Y2008M09D23.DTA" | ihme_file_name == "IDN_DHS3_1997_WN_Y2008M09D23.DTA" | ihme_file_name == "IDN_DHS4_2002_2003_WN_Y2008M09D23.DTA" | ihme_file_name == "IDN_DHS5_2007_WN_Y2009M05D05.DTA" | ihme_file_name == "IND_DHS2_1992_1993_WN_Y2008M09D23.DTA" | ihme_file_name == "JOR_DHS2_1990_WN_Y2008M09D23.DTA" | ihme_file_name == "JOR_DHS3_1997_WN_Y2008M09D23.DTA" | ihme_file_name == "JOR_DHS4_2002_WN_Y2008M09D23.DTA" | ihme_file_name == "JOR_DHS5_2007_WN_Y2008M09D23.DTA" | ihme_file_name == "JOR_ITR_DHS6_2009_WN_Y2010M11D03.DTA" | ihme_file_name == "NPL_DHS3_1996_WN_Y2008M09D23.DTA" | ihme_file_name == "NPL_DHS4_2001_WN_Y2008M09D23.DTA" | ihme_file_name == "PAK_DHS2_1990_1991_WN_Y2008M09D23.DTA" | ihme_file_name == "PAK_DHS5_2006_2007_WN_Y2008M09D23.DTA" | ihme_file_name == "TUR_DHS3_1993_WN_Y2008M09D23.DTA" | ihme_file_name == "TUR_DHS4_2003_2004_WN_Y2008M09D23.DTA" | ihme_file_name == "VNM_DHS3_1997_WN_Y2008M09D23.DTA" | ihme_file_name == "VNM_DHS4_2002_WN_Y2008M09D23.DTA" | ihme_file_name == "YEM_DHS2_1991_1992_WN_Y2008M09D23.DTA"

	
		keep if ihme_age_yr  >= `i' & ihme_age_yr <(`i' +5)
			
				
				gen currmarr = 1 if marr_status == 1
				replace currmarr = 0 if currmarr != 1
			
							
				gen evermarr = 1 if marr_status == 1 | marr_status == 2
				replace evermarr = 0 if evermarr != 1
								
				gen nomarr = 1 if evermarr == 0
				replace nomarr = 0 if evermarr == 1
		
			
		cap confirm variable first_sex
		if !_rc  {
			if first_sex != . {
				
		// generate a variable that indicates whether a woman has never had sex
			gen nosex = 1 if first_sex == 0 & ihme_age_yr>=`i' & ihme_age_yr<(`i'+5)
			replace nosex = 0 if first_sex != . & nosex == .
			
		// generate a variable that indicateds whether a woman has had sex
			gen hadsex = 1 if ihme_age_yr >= first_sex & first_sex != 0 & ihme_age_yr>=`i' & ihme_age_yr<(`i'+5)
			replace hadsex = 0 if hadsex == . & first_sex != .
				}
			}
			
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
			
		cap confirm variable first_sex
		if !_rc {
			if first_sex != . {
						
		// calculate % women never had sex
			svy: mean nosex
			matrix mean_nosex = e(b)
			gen nosex_prev = mean_nosex[1,1]
			matrix var_nosex=e(V)
			gen nosex_var=var_nosex[1,1]
						
		// calculate % women had sex
			svy: mean hadsex
			matrix mean_hadsex = e(b)
			gen hadsex_prev = mean_hadsex[1,1]
			matrix var_hadsex=e(V)
			gen hadsex_var=var_hadsex[1,1]
				}
			}
			
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


		cap confirm variable hadsex_prev
		if !_rc {
		keep iso3 survey ihme_start_year ihme_end_year filename currmarr_prev currmarr_var evermarr_prev evermarr_var nomarr_prev nomarr_var hadsex_prev hadsex_var nosex_prev nosex_var agegroup
		order iso3 survey ihme_start_year ihme_end_year filename agegroup currmarr_prev currmarr_var evermarr_prev evermarr_var nomarr_prev nomarr_var hadsex_prev nosex_prev nosex_var hadsex_var
		}
		
		else {
			keep iso3 survey ihme_start_year ihme_end_year filename currmarr_prev currmarr_var evermarr_prev evermarr_var nomarr_prev nomarr_var agegroup
			order iso3 survey ihme_start_year ihme_end_year filename agegroup currmarr_prev currmarr_var evermarr_prev evermarr_var nomarr_prev nomarr_var 
			}

				
// save each dataset individually 
save "J:/Project/Coverage/Contraceptives/2015 Contraceptive Prevalence Estimates/output/hadsex/`i'_`country'_`dta'", replace


// append into one dataset
append using `master', force

// label variables
lab var currmarr_prev "fraction of women currently married"
lab var currmarr_var "variance of fraction of women currently married"
lab var evermarr_prev "fraction of women ever married"
lab var evermarr_var "variance of fraction of women ever married"
lab var nomarr_prev "fraction of women never married"
lab var nomarr_var "variance of fraction of women never married"
lab var hadsex_prev "fraction of women who reported ever having sex"
lab var hadsex_var "variance of fraction of women who reported ever having sex"
lab var nosex_prev "fraction of women who reported never having sex"
lab var nosex_var "varianace of fraction of women who reported never having sex"

save `master', replace

			
restore
					} // close count of women in each age group loop
				
				} // close age group loop
			
			} // close quiet loop
		
		} // close dta loop
	
	} // close country loop
	
	


use `master', clear
drop foo
save "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\output\MASTER PREVALENCE FILES\master_had_sex.dta", replace



