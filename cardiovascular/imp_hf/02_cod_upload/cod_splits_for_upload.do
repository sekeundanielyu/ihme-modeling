// Prep Stata
	clear all
	set more off
	set maxvar 32767 
	
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	
	else if c(os) == "Windows" {
		global prefix "J:"
	}
// Add adopaths
	adopath + "strPath/functions"
	
// Locals for file paths
	local code_dir "strPath/01_code"
	local tmp_dir "strPath"
	local source_dir "strPath"
	local out_dir "strPath"
	
insheet using "`source_dir'/heart_failure_target_props_subnat.csv", comma names clear


local cause_ids "493 498 520 492 499 507"
local nids "250478 250479 250480 250481 250482 250483"
local me_ids "2414 2415 2416 2417 2418 2419"
local names "ihd htn cpm valvu cmp other"
#delimit ;
local me_names `" "Heart failure due to ischemic heart disease impairment envelope" "Heart failure due to hypertensive heart disease impairment envelope" 
					"Heart failure due to cardiopulmonary disease impairment envelope" "Heart failure due to valvular heart disease impairment envelope" 
					"Heart failure due to cardiomyopathy impairment envelope" "Heart failure due to other causes impairment envelope" "';	  //"
#delimit cr ;

forvalues i = 1/6 {
	preserve

		local a : word `i' of `nids'
		local b : word `i' of `me_ids'
		local c : word `i' of `me_names'
		local d : word `i' of `names'
		local e : word `i' of `cause_ids'
		
		keep if cause_id == `e'
		rename hf_target_prop mean
		rename std_err_adj standard_error
		
		gen year_start = 1990
		gen year_end = 2015
		
		gen age_start = .
		replace age_start = 0 if age_group_id==28
		replace age_start = 1 if age_group_id==5
		replace age_start = 5 if age_group_id==6
		replace age_start = 10 if age_group_id==7
		replace age_start = 15 if age_group_id==8
		replace age_start = 20 if age_group_id==9
		replace age_start = 25 if age_group_id==10
		replace age_start = 30 if age_group_id==11
		replace age_start = 35 if age_group_id==12
		replace age_start = 40 if age_group_id==13
		replace age_start = 45 if age_group_id==14
		replace age_start = 50 if age_group_id==15
		replace age_start = 55 if age_group_id==16
		replace age_start = 60 if age_group_id==17
		replace age_start = 65 if age_group_id==18
		replace age_start = 70 if age_group_id==19
		replace age_start = 75 if age_group_id==20
		replace age_start = 80 if age_group_id==21
		gen age_end = age_start+4
		replace age_end = 99 if age_start==80
		replace age_end = 1 if age_start==0
		
		gen sex = cond(sex_id==1, "Male", "Female")

		gen nid = "`a'"
		gen underlying_nid = ""
		gen modelable_entity_id = `b'
		gen modelable_entity_name = `"`c'"' //"
		gen data_sheet_id = ""
		gen source_type_id = "36"
		gen measure_id = 18
		//gen standard_error = . //should be back calculated
		gen lower = .
		gen upper = .
		gen unit_type = "Person"
		gen unit_type_value = 2
		gen unit_value_as_published = 1
		gen input_type = ""
		gen effective_sample_size = .
		gen is_outlier = 0
		gen uncertainty_type_value = .
		gen representative_name = "Nationally and subnationally representative"
		gen urbanicity_type = "Unknown"
		gen recall_type = "Point"
		gen recall_type_value = 1
		gen sampling_type = ""
		gen note_modeler = "Proportion generated from CoDCorrect Deaths using multiple discharge hospital datasets"
		gen note_SR = ""
		gen extractor = "strUser"
		gen source_type = "Mixed or estimation"
		gen measure = "proportion"
		gen uncertainty_type = "Standard error"
		gen sample_size = ""
		gen cases = ""
		gen design_effect = ""
		gen site_memo = ""
		gen case_name = ""
		gen case_definition = ""
		gen case_diagnostics = ""
		gen response_rate = ""
		gen parent_id = ""
		
		gen age_issue=0
		gen sex_issue=0
		gen measure_issue=0
		gen year_issue=0
		
		gen row_num=""

		gen cv_marketscan=1
		
		drop age_group_id sex_id cause_id

		save "`tmp_dir'/splits/hf_`b'_splitprev.dta", replace
		capture mkdirs, dirs("`out_dir'/`b'/04_big_data")
		export excel "`out_dir'/`b'/04_big_data/hf_`b'_prop_31Jul.xlsx", replace sheet("extraction") firstrow(variables)
		
	restore
}
