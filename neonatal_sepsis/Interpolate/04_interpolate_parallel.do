************************************************************
** Description: This is the parallelized script submitted by 04_interpolate.do.
** It saves files for each me_id for preterm, enceph and sepsis in the proper 
** format and saves them using save_results. 

** Inputs:

** 

** Outputs:

** 


************************************************************


// priming the working environment
clear 
set more off
set maxvar 30000
version 13.0


// discover root 
		if c(os) == "Windows" {
			local j "J:"
			// Load the PDF appending application
			quietly do "`j'/Usable/Tools/ADO/pdfmaker_acrobat11.do"
			local working_dir = "H:/neo_model" 
		}
		if c(os) == "Unix" {
			local j "/home/j"
			local working_dir = "/homes/User/neo_model"
		} 

// test
//local me_id 1558

// arguments
local me_id `1'
local acause `2'

// functions
run "`j'/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
run "`j'/WORK/10_gbd/00_library/functions/save_results.do"


// directories
local data_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/02_analysis"

// logs 
local log_dir "/ihme/scratch/users/User/neonatal/logs/`acause'/04_interpolate_parallel_testing.smcl"
capture log close 
log using "`log_dir'", replace 


**********************************************************************************************


// launch interpolation jobs
get_location_metadata, location_set_id(9) clear
levelsof location_id, local(location_ids)
local year_ids 1990 1995 2000 2005 2010 2015
local sex_ids 1 2 

foreach location_id of local location_ids {
	foreach year_id of local year_ids{
		foreach sex_id of local sex_ids {
			!qsub -pe multi_slot 4 -l mem_free=8g -N interpolate_`me_id'_`location_id'_`year_id'_`sex_id' -P proj_custom_models -e /share/temp/sgeoutput/User/errors -o /share/temp/sgeoutput/User/output "`working_dir'/stata_shell.sh" "`working_dir'/enceph_preterm_sepsis/model_custom/interpolate/04_interpolate_parallel_parallel.do" "`me_id' `acause' `location_id' `year_id' `sex_id'"
		}
	}
}

get_location_metadata, location_set_id(9) clear
levelsof location_id, local(location_ids)
local year_ids 1990 1995 2000 2005 2010 2015
local sex_ids 1 2 

// wait until interpolation jobs are done
cap mkdir "`data_dir'/temp/`acause'/`me_id'"
cd "`data_dir'/temp/`acause'/`me_id'"
!qstat -u User |grep inter* |wc -l > job_counts.csv
import delimited "job_counts.csv", clear 
local job_count v1
while `job_count' > 0 {
	di "`job_count' jobs are not finished. Take a nap."
	!rm *csv
	sleep 10000
	!qstat -u User |grep inter* |wc -l > job_counts.csv
	import delimited "job_counts.csv", clear
	local job_count v1	
}
if `job_count' == 0 {
	di "Jobs are all done!"
}

// check to see if all the files are present
foreach location_id of local location_ids {
	foreach year_id of local year_ids{
		foreach sex_id of local sex_ids {
			capture noisily confirm file "`data_dir'/`acause'/prev_28_days/`me_id'/draws/5_`location_id'_`year_id'_`sex_id'.csv"
			if _rc!=0 {
				di "File 5_`location_id'_`year_id'_`sex_id'.csv is missing."
				local failed_locations `failed_locations' `location_id'
				local failed_years `failed_years' `year_id'
				local failed_sexes `failed_sex' `sex_id'
			}
			else if _rc==0 {
				di "File 5_`location_id'_`year_id'_`sex_id'.csv found!"
			}
			
		}
	}
}

// resubmit jobs that randomly failed
foreach location_id of local failed_locations {
	foreach year_id of local failed_years {
		foreach sex_id of local failed_sexes {
			di "RESUBMITTING: `location_id'_`year_id'_`sex_id'"
			!qsub -pe multi_slot 4 -l mem_free=8g -N interpolate_`me_id'_`location_id'_`year_id'_`sex_id' -P proj_custom_models -e /share/temp/sgeoutput/User/errors -o /share/temp/sgeoutput/User/output "`working_dir'/stata_shell.sh" "`working_dir'/enceph_preterm_sepsis/model_custom/interpolate/04_interpolate_parallel_parallel.do" "`me_id' `acause' `location_id' `year_id' `sex_id'"
		}
	}
}

// check again to see if everything's done
foreach location_id of local location_ids {
	foreach year_id of local year_ids{
		foreach sex_id of local sex_ids {
			capture noisily confirm file "`data_dir'/`acause'/prev_28_days/`me_id'/draws/5_`location_id'_`year_id'_`sex_id'.csv"
			while _rc!=0 {
				di "File 5_`location_id'_`year_id'_`sex_id'.csv not found :["
				sleep 60000
				capture noisily confirm file "`data_dir'/`acause'/prev_28_days/`me_id'/draws/5_`location_id'_`year_id'_`sex_id'.csv"
			}
			if _rc==0 {
				di "File 5_`location_id'_`year_id'_`sex_id'.csv found!"
			}
			
		}
	}
}

// generate appended 28 day draws file for use in future steps
cd "`data_dir'/`acause'/prev_28_days/`me_id'/draws"
!cat *csv > all_draws.csv
import delimited "`data_dir'/`acause'/prev_28_days/`me_id'/draws/all_draws.csv", varnames(1) clear
capture noisily drop if age_group_id == "age_group_id"
quietly ds 
local _all = "`r(varlist)'"
foreach var of varlist _all {
	di "Var is `var'"
	gen `var'_copy = real(`var')
}
keep *copy
foreach var of local _all {
	di "Var is `var'"
	rename `var'_copy `var'
}
save "`data_dir'/`acause'/prev_28_days/`me_id'/draws/all_draws.dta", replace

// generate appended at birth draws file for use in future steps
cd "`data_dir'/`acause'/prev_28_days/`me_id'/draws/birth"
!cat *csv > all_draws.csv
import delimited "`data_dir'/`acause'/prev_28_days/`me_id'/draws/birth/all_draws.csv", varnames(1) clear
capture noisily drop if age_group_id == "age_group_id"
quietly ds 
local _all = "`r(varlist)'"
foreach var of varlist _all {
	di "Var is `var'"
	gen `var'_copy = real(`var')
}
keep *copy
foreach var of local _all {
	di "Var is `var'"
	rename `var'_copy `var'
}
save "`data_dir'/`acause'/prev_28_days/`me_id'/draws/birth/all_draws.dta", replace

// generate appended 0-6 draws file for use in future steps
cd "`data_dir'/`acause'/prev_28_days/`me_id'/draws/0-6"
!cat *csv > all_draws.csv
import delimited "`data_dir'/`acause'/prev_28_days/`me_id'/draws/0-6/all_draws.csv", varnames(1) clear
capture noisily drop if age_group_id == "age_group_id"
quietly ds 
local _all = "`r(varlist)'"
foreach var of varlist _all {
	di "Var is `var'"
	gen `var'_copy = real(`var')
}
keep *copy
foreach var of local _all {
	di "Var is `var'"
	rename `var'_copy `var'
}
save "`data_dir'/`acause'/prev_28_days/`me_id'/draws/0-6/all_draws.dta", replace

// generate appended 7-27 draws file for use in future steps
cd "`data_dir'/`acause'/prev_28_days/`me_id'/draws/7-27"
!cat *csv > all_draws.csv
import delimited "`data_dir'/`acause'/prev_28_days/`me_id'/draws/7-27/all_draws.csv", varnames(1) clear
capture noisily drop if age_group_id == "age_group_id"
quietly ds 
local _all = "`r(varlist)'"
foreach var of varlist _all {
	di "Var is `var'"
	gen `var'_copy = real(`var')
}
keep *copy
foreach var of local _all {
	di "Var is `var'"
	rename `var'_copy `var'
}
save "`data_dir'/`acause'/prev_28_days/`me_id'/draws/7-27/all_draws.dta", replace

// save results 

	// get target me_id - where the results will be saved
	if `me_id' == 1557 | `me_id' == 1558 | `me_id' == 1559 {
		di "Me_id is `me_id'"
		local target_me_id = `me_id' + 7058
	}

	if `me_id' == 2525 {
		di "Me_id is `me_id'"
		local target_me_id = 3961
	}

	if `me_id' == 9793 {
		di "Me_id is `me_id'"
		local target_me_id = 3963
	}

save_results, modelable_entity_id(`target_me_id') description(28 days prevalence for me_id `me_id') in_dir(`data_dir'/`acause'/prev_28_days/`me_id'/draws/) metrics(prevalence) skip_calc(yes)


log close
log off
