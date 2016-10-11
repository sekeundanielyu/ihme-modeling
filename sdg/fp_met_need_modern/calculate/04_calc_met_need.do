// Date: June 2016
// Purpose: Create modern contraceptive use prevalence variables from data extracted through ubcov. Used in 2016 SDG paper.

cd "J:/Project/Coverage/Contraceptives/2015 Contraceptive Prevalence Estimates/_ubcov_data_output"

clear
gen foo = "null" // generate place holder variable to save empty tempfile
tempfile master
save `master', replace


cap restore 

global date	= string(date("`c(current_date)'", "DMY"), "%tdYYNNDD") // generate a date global to save new versions of output
global date	= lower(subinstr("`c(current_date)'"," ","",.))
	
local countries : dir "./" dir "*", respectcase // get a list of all countries
local countries : list clean countries 
if substr("`country'", 2, .) == "log"  continue // ignore log folder



foreach country of local countries {
	local dtas : dir "./`country'/" file "*" // get a list of all dtas
	local dtas : list clean dtas 
	di in red "`country'"
	
	foreach dta of local dtas {
		use "./`country'/`dta'", clear
		di in red "`dta'"
		
		quietly {
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
					

		
						 
			
				// some countries only ask ever married women about contraceptive use.  replace all = 0 if that's the case. (note these are the pre-2010 surveys, update for post-2010 surveys where this is true)
				gen sample = 1 if ihme_file_name == "BGD_DHS3_1993_1994_WN_Y2008M09D23.DTA" | ihme_file_name == "BGD_DHS3_1996_1997_WN_Y2008M09D23.DTA" | ihme_file_name == "BGD_DHS4_1999_2000_WN_Y2008M09D23.DTA" | ihme_file_name == "BGD_DHS4_2004_WN_Y2008M09D23.DTA" | ihme_file_name == "BGD_DHS5_2007_WN_Y2009M05D11.DTA"| ihme_file_name == "ALL_COUNTRIES_PAPFAM_2001_2004_WN.DTA" | ihme_file_name == "EGY_DHS2_1992_1993_WN_Y2008M09D23.DTA" | ihme_file_name == "EGY_DHS3_1995_1996_WN_Y2008M09D23.DTA" | ihme_file_name == "EGY_DHS4_2000_WN_Y2008M09D23.DTA" | ihme_file_name == "EGY_DHS5_2005_WN_Y2008M09D23.DTA" | ihme_file_name == "EGY_DHS5_2008_WN_Y2009M06D19.DTA" | ihme_file_name == "EGY_ITR_DHS4_2003_WN_Y2008M09D23.DTA"  | ihme_file_name == "IDN_DHS2_1991_WN_Y2008M09D23.DTA" | ihme_file_name == "IDN_DHS3_1994_WN_Y2008M09D23.DTA" | ihme_file_name == "IDN_DHS3_1997_WN_Y2008M09D23.DTA" | ihme_file_name == "IDN_DHS4_2002_2003_WN_Y2008M09D23.DTA" | ihme_file_name == "IDN_DHS5_2007_WN_Y2009M05D05.DTA" | ihme_file_name == "IND_DHS2_1992_1993_WN_Y2008M09D23.DTA" | ihme_file_name == "JOR_DHS2_1990_WN_Y2008M09D23.DTA" | ihme_file_name == "JOR_DHS3_1997_WN_Y2008M09D23.DTA" | ihme_file_name == "JOR_DHS4_2002_WN_Y2008M09D23.DTA" | ihme_file_name == "JOR_DHS5_2007_WN_Y2008M09D23.DTA" | ihme_file_name == "JOR_ITR_DHS6_2009_WN_Y2010M11D03.DTA" | ihme_file_name == "NPL_DHS3_1996_WN_Y2008M09D23.DTA" | ihme_file_name == "NPL_DHS4_2001_WN_Y2008M09D23.DTA" | ihme_file_name == "PAK_DHS2_1990_1991_WN_Y2008M09D23.DTA" | ihme_file_name == "PAK_DHS5_2006_2007_WN_Y2008M09D23.DTA" | ihme_file_name == "TUR_DHS3_1993_WN_Y2008M09D23.DTA" | ihme_file_name == "TUR_DHS4_2003_2004_WN_Y2008M09D23.DTA" | ihme_file_name == "VNM_DHS3_1997_WN_Y2008M09D23.DTA" | ihme_file_name == "VNM_DHS4_2002_WN_Y2008M09D23.DTA" | ihme_file_name == "YEM_DHS2_1991_1992_WN_Y2008M09D23.DTA" | ihme_file_name == "BGD_DHS4_2004_WN_Y2008M09D23.DTA" | ihme_file_name == "BGD_SP_DHS4_2001_WN_Y2008M11D03.DTA" | ihme_file_name == "BGD_DHS6_2011_2012_WN_Y2013M02D11.DTA" | ihme_file_name == "BGD_DHS7_2014_WN_Y2016M03D23.DTA" | ihme_file_name == "EGY_DHS1_1988_1989_WN_Y2008M09D23.DTA" | ihme_file_name == "EGY_DHS6_2014_WN_Y2015M05D11.DTA" | ihme_file_name == "IDN_DHS6_2012_WN_Y2015M08D07.DTA" | ihme_file_name == "IDN_DHS1_1987_WN_Y2008M09D23.DTA" | ihme_file_name == "JOR_DHS6_2012_WN_Y2015M08D05.DTA" | ihme_file_name == "NPL_MICS4_2010_WN_Y2012M11D19.DTA" | ihme_file_name == "NPL_MICS5_2014_WN_Y2015M06D08.DTA" | ihme_file_name == "PAK_PUNJAB_MICS4_2011_WN.DTA" | ihme_file_name == "PAK_DHS6_2012_2013_WN_Y2014M01D22.DTA" | ihme_file_name == "TUR_DHS4_1998_WN_Y2008M09D23.DTA" | ihme_file_name == "VNM_MICS5_2013_2014_WN_Y2015M09D28.DTA" | ihme_file_name == "VNM_MICS2_2000_WN_Y2008M09D23.DTA" | ihme_file_name == "VNM_MICS3_2006_WN_Y2008M09D23.DTA" | ihme_file_name == "YEM_MICS3_2006_WN_Y2009M04D06.DTA"




				
				**************************************
				** Modern Contraception Use Prevalence **
				**************************************

				cap confirm variable unmet_need trad_contra
				
				if !_rc {
							
			
				
				** all women regardless of marital status population
				gen all = 1 
				replace all = 0 if all!= 1
				
				
				** currently married women population (also includes women in unions, as this was done in gbd2010)
				gen curr=1 if marr_status==1
				replace curr=0 if curr!=1	

				** ever married women population (includes currently married and formerly married women)
				gen ever=1 if (marr_status==2 | marr_status == 1)
				replace ever=0 if ever!=1		
				
						
				
				
				** any contraception 
				gen any_contra = 1 if modern_contra == 1 | trad_contra == 1
				replace any_contra = 0 if modern_contra == 0 & trad_contra == 0 
				
				** need
				gen need = 1 if any_contra == 1 | unmet_need == 1
				replace need = 0 if any_contra == 0 & unmet_need == 0 
		
				** met need
				gen met_need_modern = 1 if modern_contra == 1 & need == 1
				replace met_need_modern = 0 if need == 1 & (trad_contra == 1 | any_contra == 0)
				
						

				
					svy: mean met_need_modern
					matrix met_need = e(b)
					matrix met_need_var = e(V)
					gen met_need_modern_prev = met_need[1,1]
					gen met_need_modern_var = met_need_var[1,1]
					
					svy: mean met_need_modern, over(curr)
					matrix met_need_curr = e(b)
					matrix met_need_curr_var = e(V)
					gen met_need_modern_curr_prev = met_need_curr[1,1]
					gen met_need_modern_curr_var = met_need_curr_var[1,1]
		

						
						
				
		
		
				// gen avg interview date
					svy: mean ihme_end_year
					matrix date = e(b)
					gen cmc_int = date[1,1]
				
							
							
					keep if _n==1
					gen iso3 = ihme_loc_id
					gen filename = ihme_file_name
					gen survey = ihme_type
							
				
					
				
					keep iso3 survey ihme_start_year ihme_end_year filename  sample met_need_modern* 
					drop met_need_modern
								
					order iso3 survey ihme_start_year ihme_end_year filename  sample met_need_modern* 
					
							
				// put vars in order
					order iso3 survey filename  
					cap drop ihme_type ihme_file_name
					
						
					
	// save each dataset individually 
	save "J:/Project/Coverage/Contraceptives/2015 Contraceptive Prevalence Estimates/output/met_need/`country'_`dta'", replace


	// append into one dataset
	append using `master', force
	save `master', replace
	
	
				
	
			} // close _rc unmet_need 
			
		} // closing quiet loop
	
	} // closing dta loop

} // closing country loop





use `master', clear
drop foo
save "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\output\MASTER PREVALENCE FILES\master_met_need_prevalence_${date}_all_ages_new_calculation_new_extraction.dta", replace

