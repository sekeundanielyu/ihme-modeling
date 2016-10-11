
//compare new rh disease code to old code to try and figure out why the final
// result is so different

clear all
set more off
set graphics off
set maxvar 32000


/*  //////////////////////////////////////////////
		WORKING DIRECTORY
////////////////////////////////////////////// */

		//root dir
	if c(os) == "Windows" {
		local j "J:"
		// Load the PDF appending application
		quietly do "`j'/Usable/Tools/ADO/pdfmaker_acrobat11.do"
	}
	if c(os) == "Unix" {
		local j "/home/j"
		ssc install estout, replace 
		ssc install metan, replace
	} 
	di in red "J drive is `j'"
	
	//add code for make_template, identify_locations, and fast_pctile to path
	adopath + "`j'/Usable/Tools/ADO"
	adopath + "`j'/WORK/01_covariates/common/lib"
	
	local new_data_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/02_analysis/neonatal_hemolytic/01_rh_disease"
	local old_data_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/regression_results/hemolytic/01_rh_disease"

	global log_dir = "`j'/temp/User/neonatal/logs/neonatal_hemolytic"
	local out_dir "`new_data_dir'/compare_results"
	capture mkdir "`out_dir'"
	capture mkdir "$log_dir"
	
	local iso3_country_code_dir = "`j'/DATA/IHME_COUNTRY_CODES/IHME_COUNTRY_CODES_Y2013M07D26.DTA"
	
// Create timestamp for logs
    local c_date = c(current_date)
    local c_time = c(current_time)
    local c_time_date = "`c_date'"+"_" +"`c_time'"
    display "`c_time_date'"
    local time_string = subinstr("`c_time_date'", ":", "_", .)
    local timestamp = subinstr("`time_string'", " ", "_", .)
    display "`timestamp'"
	global today `timestamp'
	
	//log
	capture log close
	log using "$log_dir/01_results_compare_${today}.smcl", replace
	
	
/*  //////////////////////////////////////////////
	COMPARISONS
////////////////////////////////////////////// */


local steps_list rh_prev rhogam_adjustment birth_order final_birthprev
local letter_list A B C D
local step_idx = 1

foreach step_name of local steps_list{

	if "`step_name'"!="final_birthprev"{
		local step_idx = `step_idx'+1
		continue
	}

	local step_letter: word `step_idx' of `letter_list'
	di in red "working on step `step_name', letter `step_letter'"
	
	local new_parent_dir = "`new_data_dir'/01_`step_letter'_`step_name'"
	local old_parent_dir = "`old_data_dir'/birth_prev/`step_letter'_`step_name'"
	
	//set up lists of file names to loop through
	
	//NAMES FOR RH INCOMPATIBILITY
	if "`step_name'"=="rh_prev"{
		local new_file_list rh_neg_prev rh_incompatible_prev rh_incompatible_count
		local old_file_list rh_minus pos_to_neg_prop pos_to_neg_count
		local title_list Rh_Negative_Prevalence Rh_Incompatible_Prevalence Rh_Incompatible_Counts
	}
	
	//NAMES FOR RHOGAM ADJUSTMENT
	else if "`step_name'"=="rhogam_adjustment"{
		local new_file_list rhogam_adjusted_pregnancies
		local old_file_list rhogam_adjusted_births
		local title_list Rhogam_Adjusted_Pregnancies
	}
		
	//NAMES FOR BIRTH ORDER 
	else if "`step_name'"=="birth_order"{
		local new_file_list notfirst_birth_prev
		local old_file_list birth_prop
		local title_list Notfirst_Birth_Prevalence
	}
		
	//NAMES FOR FINAL PREVALENCE
	else{
		local new_file_list kernicterus_birth_prev
		local old_file_list modsev_rh
		local title_list Kernicterus_Birth_Prev
	}
	
	//now loop through everything in that name list, making plots for each type
	local name_idx=1
	foreach old_name of local old_file_list{
		
		//define directories
		local new_name: word `name_idx' of `new_file_list'
		local title_name: word `name_idx' of `title_list'
		local new_dir = "`new_parent_dir'/`new_name'_summary_stats.dta"
		local old_dir = "`old_parent_dir'/`old_name'_summary_stats.dta"
		
		di in red "analyzing for file `new_name'"
		use "`old_dir'", clear
		drop if (substr(iso3,1,3)=="ZAF" | substr(iso3,1,3)=="IND") & length(iso3)>3
		capture rename mean data
		
		//what variables do you want to merge on?
		local merge_on iso3 year
		
		//some values aren't by sex
		if "`old_name'"=="rh_minus" | "`old_name'"=="pos_to_neg_prop" | "`old_name'"=="birth_prop"{
			gen sex=99
		}
		else{
			replace sex="3" if sex=="Both"
			replace sex="2" if sex=="Female"
			replace sex="1" if sex=="Male"
			destring sex, replace
			local merge_on `merge_on' sex
		}
		
		//sometimes the title of `old_name' doesn't match the variable name.  Fix.
		if "`old_name'"=="rh_minus"{
			local old_name rh_prev
		}
		else if "`old_name'"=="rhogam_adjusted_births"{
			local old_name adjusted_births
		}
		else if "`old_name'"=="modsev_rh"{
			local old_name modsev_imp_prev_mean
		}
	
		//merge with new
		di in red "merging on new data"
		merge 1:1 `merge_on' using "`new_dir'"
		
		count if _m!=3
		drop _m
		drop if year<1980
		
		//plot 
		di in red "plotting!"
		pdfstart using "`out_dir'/`title_name'_compare.pdf"
		
		//get max values so all plots have same scale
		qui sum(mean)
		local new_max= r(max)
		qui sum(`old_name')
		local old_max= r(max)
		local maxval= max(`new_max', `old_max')
		di in red "maxval is `maxval'"
		qui sum(mean)
		local minval=r(min) 
		
		if "`old_name'"=="pos_to_neg_count" | "`old_name'"=="adjusted_births"{
			local interval=100000
		}
		else{
			local interval=0.1
			local minval = 0
		}
		
		drop if sex==3
		
		levelsof iso3, local(iso3_list)
		
		foreach iso3 of local iso3_list{
			di in red "plotting for `iso3'"
			line mean year if iso3=="`iso3'", lcolor(purple) lwidth(*1.75) || ///
			line `old_name' year if iso3=="`iso3'", lcolor(lime) lwidth(*1.75) ///
			by(sex) ///
			title("`title_name', `iso3'") ///
			legend(order(1 2) label(1 "New Estimate") label(2 "Old Estimate") ) ///
			xlabel(1980(5)2013)
			pdfappend
		}  //end of plot for loop
		 pdffinish, view
		
		local name_idx = `name_idx'+1
		
	} //end of step 
		
	local step_idx = `step_idx'+1
		
} //end all
			
			
			




















	
	
