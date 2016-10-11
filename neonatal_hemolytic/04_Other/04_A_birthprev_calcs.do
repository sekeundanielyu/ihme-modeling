/* **************************************************************************
NEONATAL HEMOLYTIC MODELING
PART 4: Other
Part A: Birth prevalence of Kernicterus due to all other causes
6.9.14

The hemolytic modeling process is described in detail in the README in the 
hemolytic code folder.  This script completes the first and only step of modeling 
kernicterus due to other birth conditions: taking the sum of preterm, g6pd, and 
rh disease ehb birth prevalences, subtracting this number from one to get the prevalence 
of all other hemolytic conditions, and multiplying this prevalence by scalar values
 to get kernicterus birth prevalence.

Copied from README:
D. Other
	1. Babies that don't have any of the three conditions above still have some probability of developing EHB and kernicterus.   We begin by summing the birth prevalences of rh disease from part A, G6PD from part B, and preterm births from part C, 	and subtracting this from 1 to get the birth prevalence of all other births:

		other_birth_prev = 1 - (rh_birth_prev +  g6pd_birth_prev + preterm_birth_prev)

	2. The proportion of other children who go on to have EHB is 0.00038 (0.00033, 0.00163).  We multiply other_birth_prev by 	  this value: 

			other_ehb_prev = other_birth_prev * 0.00038 (0.00033, 0.00163)

	3. We know that living in less-developed countries increases the risk of EHB.  Thus, we multiply the above value by 2.45 	in country-years with an NMR greater than 15:

		other_ehb_prev = other_ehb_prev * 2.45 if NMR>15 

	4. Like for G6PD, we muliply this birth prevalence by some NMR-dependent proportion to determine children who go on to 		have kernicterus (these values are the same as for G6PD):

								  	other_ehb_prev * 0.23 (0.099, 0.361) if NMR <5
			other_kern_prev   =     other_ehb_prev * 0.35 (0.12, 0.58) if 5<= NMR <15
									other_ehb_prev * 0.438 (0.255, 0.621) if NMR >=15

	This concludes the other portion of hemolytic modeling.
		
******************************************************************************/

	clear all
	set graphics off
	set more off
	set maxvar 32000


	/*  //////////////////////////////////////////////
			WORKING DIRECTORY
	////////////////////////////////////////////// */ 

	// discover root 
		if c(os) == "Windows" {
			local j "J:"
			// Load the PDF appending application
			quietly do "`j'/Usable/Tools/ADO/pdfmaker_Acrobat11.do"
		}
		if c(os) == "Unix" {
			local j "/home/j"
			ssc install estout, replace 
			ssc install metan, replace
		} 
		
	// functions
	run "`j'/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
	run "`j'/WORK/10_gbd/00_library/functions/fastpctile.ado"
		
	// directories
		local working_dir  "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data"
		local in_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/02_analysis/neonatal_hemolytic"
		local log_dir  "`j'/temp/User/neonatal/logs/neonatal_hemolytic"
		local out_dir "`working_dir'/02_analysis/neonatal_hemolytic/04_other"
		local plot_dir "`out_dir'/time_series"
		
		// three input directories; one from each of the other causes
		local rh_disease_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/02_analysis/neonatal_hemolytic/01_rh_disease/01_D_final_birthprev/rh_disease_ehb_all_draws.dta"
		local g6pd_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/02_analysis/neonatal_hemolytic/02_g6pd/g6pd_ehb_all_draws.dta"
		local preterm_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/02_analysis/neonatal_hemolytic/03_preterm/preterm_ehb_all_draws.dta"
		
	// Create timestamp for logs
		local c_date = c(current_date)
		local c_time = c(current_time)
		local c_time_date = "`c_date'"+"_" +"`c_time'"
		display "`c_time_date'"
		local time_string = subinstr("`c_time_date'", ":", "_", .)
		local timestamp = subinstr("`time_string'", " ", "_", .)
		display "`timestamp'"
		
		//log
		capture log close
		log using "`log_dir'/hemo_04_A_other_kern_prev_`timestamp'.smcl", replace
		
		
	
/* ///////////////////////////////////////////////////////////
// G6PD BIRTH PREVALENCE CALCULATIONS
///////////////////////////////////////////////////////////// */

	local plot_prev= 1

	//1. get NMR data ready (we use it as a scale to determine what countries get which scalars)
		// import data
	use "`j'/WORK/02_mortality/03_models/3_age_sex/results/stable_output/estimated_enn-lnn-pnn-ch-u5_noshocks.dta", clear
		keep ihme_loc_id sex year q_nn_med
		keep if year>=1980
		rename q_nn_med nmr

		// convert from probability to NMR
		replace nmr = nmr*1000
		replace sex = "1" if sex == "male"
		replace sex = "2" if sex == "female" 
		replace sex = "3" if sex == "both"
		destring sex, replace
		drop if sex==3

		//year is at midear in this file, switch it to beginning of the year
		replace year = year - 0.5
		tempfile nmr
		save `nmr'

		// merge on additional lcoation data
		// location set 21 is for mortality computation; includes China (without Hong Kong and Macao)
		get_location_metadata, location_set_id(21) clear 
		tempfile locations
		save `locations'

		// _merge == 1 are global, super region and regions
		merge 1:m ihme_loc_id using `nmr', keep(3) nogen 

		// save prepped nmr template
		keep ihme_loc_id location_id sex year nmr
		tempfile neo
		save `neo'
	

	//2. bring in ehb prevalence data 
		di in red "importing rh disease data"
		use "`rh_disease_dir'", clear 
		drop if sex==3
		keep if year==1990 | year==1995 | year==2000 | year==2005 | year==2010 | year==2015
		rename draw_* rh_disease_draw_*
		
		di in red "merging on g6pd data"
		//merge will only include dismod yearvals
		merge 1:1 location_id year sex using "`g6pd_dir'", nogen
		rename draw_* g6pd_draw_*
		
		di in red "merging on preterm data"
		merge 1:1 location_id year sex using "`preterm_dir'", keep(3) nogen
		rename draw_* preterm_draw_* 

	//3. add nmr data, merge==2 will be non-gbd countries
		merge 1:1 location_id year sex using `neo', nogen
		keep if _merge==3
	
	//3. Define scalars
	// we need to multiply these draws by the following scalars(with uncertainty):
	// 1. the proportion of g6pd babies who will develop EHB: 
	// 		0.00038 (0.00033, 0.00163)
	// 	  However, in high-nmr countries, that number gets multiplied by this value:
	// 		2.45, (1.44, 4.16)
	// 2. The proportion of EHB babies who will go on to develop kernicterus:
	//		0.23 (0.099, 0.361) if nmr<5
	//		0.35 (0.12, 0.58) if 5=<nmr<15
	//		0.438 (0.255, 0.621) if 15=<nmr
	//
	// To get proper uncertainty bounds for both of these, we define the parameters
	// of a beta distribution for those bounded between 0 and 1 and a gamma distribution,
	// for those bounded between 0 and infinity, and draw from that distribution to get 
	// the scalar of use when looping through draws.

		di in red "calculating scalar parameters"
		local baseline_ehb_scalars 0.00038 0.00033 0.00163
		local high_ehb_scalars 2.45 1.44 4.16
		local low_kern_scalars 0.23 0.099 0.361
		local mid_kern_scalars 0.35 0.12 0.58
		local high_kern_scalars 0.438 0.255 0.621

		foreach scalar_type in baseline_ehb high_ehb low_kern mid_kern high_kern{
			di in red "finding scalar parameters for `scalar_type'"
			local scalar_mean : word 1 of ``scalar_type'_scalars'
			local scalar_lower : word 2 of ``scalar_type'_scalars'
			local scalar_upper : word 3 of ``scalar_type'_scalars'
			local scalar_se = (`scalar_upper' - `scalar_lower')/(2*1.96)
			if `scalar_mean'<1{
				di in red "generating beta parameters"
				local count_n = (`scalar_mean' * (1-`scalar_mean') ) / `scalar_se'^2
				local `scalar_type'_alpha = `count_n' * `scalar_mean'
				local `scalar_type'_beta = `count_n' * (1-`scalar_mean')
				di in red "for `scalar_type', scalar_se is `scalar_se', count is `count_n', alpha is ``scalar_type'_alpha', beta is ``scalar_type'_beta'"
			}
			else{
				di in red "generating gamma parameters"
				local `scalar_type'_k = (`scalar_mean'/`scalar_se') ^2
				local `scalar_type'_theta = (`scalar_se'^2) / `scalar_mean'
				di in red "for `scalar_type', scalar_se is `scalar_se', k is ``scalar_type'_k', theta is ``scalar_type'_theta'"
			}
		}
	
	//4. Loop through draws, running the calculation:
		
		di in red "calculating kernicterus prevalence"
		//quietly{
			forvalues i=0/999{
				if mod(`i', 100)==0{
							di in red "working on number `i'"
				}
				
				di "generate 'other' prevalence"
				gen other_draw_`i' = 1- (rh_disease_draw_`i' + g6pd_draw_`i' + preterm_draw_`i')
				drop rh_disease_draw_`i' g6pd_draw_`i' preterm_draw_`i'
				
				di "pull ehb scalars"
				local baseline_ehb_scalar = rbeta(`baseline_ehb_alpha', `baseline_ehb_beta')
				local high_ehb_scalar = rgamma(`high_ehb_k', `high_ehb_theta')
				
				di "get baseline ehb prevalence"
				gen ehb_draw_`i' = other_draw_`i' * `baseline_ehb_scalar'
				drop other_draw_`i'
				
				di "multiply by higher value if necessary"
				replace ehb_draw_`i' = ehb_draw_`i' * `high_ehb_scalar' if nmr>15
				
				di "pull kern scalars"
				foreach scalar_type in low mid high{
					local `scalar_type'_kern_scalar = rbeta(``scalar_type'_kern_alpha', ``scalar_type'_kern_beta')
				}
				
				di "convert to kernicterus prevalence"
				gen kernicterus_draw_`i' = ehb_draw_`i' * `low_kern_scalar' if nmr<5
				replace kernicterus_draw_`i' = ehb_draw_`i' * `mid_kern_scalar' if (nmr>=5 & nmr<15)
				replace kernicterus_draw_`i' = ehb_draw_`i' * `high_kern_scalar' if nmr>15
				
			}
		//}
		
	//5. Save ehb and kern, get summary stats

	foreach disease_type in ehb kernicterus {
		di "all draws"
		preserve
			keep ihme_loc_id year sex location_id `disease_type'_draw*
			rename `disease_type'_draw* draw*
			save "`out_dir'/other_`disease_type'_all_draws.dta", replace	
			export delimited "`out_dir'/other_`disease_type'_all_draws.csv",  replace
		
		di "summary stats"
			
			egen mean = rowmean(draw*)
			fastpctile draw*, pct(2.5 97.5) names(lower upper)
			drop draw*

			sort location_id year sex 
			save "`out_dir'/other_`disease_type'_summary_stats.dta", replace
			export delimited "`out_dir'/other_`disease_type'_summary_stats.csv", replace
		restore
		
	}


/* ///////////////////////////////////////////////////////////
// PLOTTING
///////////////////////////////////////////////////////////// */

	if `plot_prev'==1{

		di in red "plotting results"
		use "`out_dir'/other_kernicterus_summary_stats.dta", clear
		
		//for ylabeling 
		qui sum mean
		local max_val = r(max)

		pdfstart using "`plot_dir'/other_kernicterus_time_series.pdf"
		
		levelsof ihme_loc_id, local(ihme_loc_id_list)
		
		foreach ihme_loc_id of local ihme_loc_id_list{
					
			di in red "plotting for `ihme_loc_id'"
					
			line mean year if ihme_loc_id == "`ihme_loc_id'", lcolor(purple) lwidth(*1.75) || line  lower year if ihme_loc_id == "`ihme_loc_id'", lcolor(purple) lpattern(dash) lwidth(*1.75) || line  upper year if ihme_loc_id == "`ihme_loc_id'", lcolor(purple) lpattern(dash) lwidth(*1.75) by(sex) title("Other Kern, `ihme_loc_id'") xtitle("Year") ytitle("Prevalence") legend(order(1 2) label(1 "Birth Prevalence of Other Kernicterus") label(2 "95%CI")) xlabel(1990(10)2015)
			pdfappend
		}
				
		pdffinish, view

	}









