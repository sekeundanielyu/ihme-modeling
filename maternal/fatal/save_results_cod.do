//Purpose: Pipe arguments from Python to Stata, in order to call save_results
//Original Date: July 13, 2015
//Edit Date: October 28, 2015

//Necessary Arguments to Be Passed In:
//Arg 1: log_dir
//Arg 2: jobname, to be passed in as the name of the log
//Arg 3: database
//Arg 4: cause or me_id, passed in as "target_id"
//Arg 5: in directory
//Arg 6: measure_id if uploading to EPI, or codem model vers if uploading to COD

clear all
set more off

di in red "first arg is `1'"
di in red "second arg is `2'"
di in red "third arg is `3'"
di in red "fourth arg is `4'"
di in red "fifth arg is `5'"
di in red "sixth arg is `6'"


qui do "/home/j/WORK/10_gbd/00_library/functions/save_results.do"

local log_dir "`1'"
capture confirm file "`log_dir'"
if _rc != 0 {
	mkdir "`log_dir'"
	di in red "log dir is `log_dir'"
	}
capture log close
local jobname "`2'"
log using "`log_dir'/`jobname'.smcl", replace

// Determine if data will be uploaded to the epi or cod databases
local database "`3'"
	di in red "database to which the data will be uploaded is `database'"

// Set the paramater for where the data to be uploaded is coming from
local in_dir "`5'"
	di in red "`in_dir'"

set obs 40
egen years = seq(), from(1980) to(2015)
levelsof years, local(year_ids)
local years = "`year_ids'"

// Set cause_id and description parameters if data will be uploaded to cod
if "`database'" == "cod" {
	local cause_id `4'
		di in red "`cause_id'"
	local description = "newtest from maternal custom modeling; codem model version `6'"
		di in red "model id is `description'"
	save_results, cause_id(`cause_id') in_dir(`in_dir') description(`description') sexes("2") mark_best("yes")
}

// Set me_id parameters if data will be uploaded to epi
if "`database'" == "epi" {
	local me_id `4'
		di in red "`me_id'"
	local measure "`6'"
		di in red "`measure'"
	local cause_id = .
	local description = "newtest from maternal custom modeling"
	if strpos("`jobname'", "deaths") {
		save_results, modelable_entity_id(`me_id') metrics(`measure') in_dir(`in_dir') description(`description') sexes("2") in_rate("no") mark_best("yes") years(`years')
	}
	if strpos("`jobname'", "cfs") {
		save_results, modelable_entity_id(`me_id') metrics(`measure') in_dir(`in_dir') description(`description') sexes("2") mark_best("yes") years(`years')
	}
}
di "results saved for target_id `4'!"
