// Preps custom CSMR for upload to epi database

// Prep stata
	clear all
	set more off
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

adopath + "strPath/functions"

local out_dir "strPath/cvd_ihd"
cap log close
cap log using "strPath/prep_upload_survivors.smcl", replace
	
// Append data

get_demographics, gbd_team(epi) clear

cd "strPath/cvd_ihd/chronic_ihd_survivor"

tempfile survivor_prep
save `survivor_prep', replace emptyok

foreach location of global location_ids {
	capture use "mi_survivors_`location'.dta", clear
	capture drop _merge
	capture drop draw_*
	capture drop cf_*
	capture drop incidence_*
	capture drop chronic_incidence_*

			if _rc {
			}
			else {
				append using `survivor_prep', force
				save `survivor_prep', replace
			}
		}
			
use `survivor_prep', clear

// Format for upload
	gen row_num = ""
	capture gen modelable_entity_id = 3233
	capture replace modelable_entity_id = 3233
	gen modelable_entity_name = "Asymptomatic ischemic heart disease following myocardial infarction"
	gen nid = 239851 //need to fix
	gen field_citation_value = "Institute for Health Metrics and Evaluation (IHME). IHME DisMod Output as Input Data 2015 (IHD CSMR)"
	gen source_type = "Mixed or estimation"
	gen smaller_site_unit = 0

	gen age_demographer = 1
	gen age_issue = 0
	gen age_start=1 if age_group_id==5
	replace age_start=5 if age_group_id==6
	replace age_start=10 if age_group_id==7
	replace age_start=15 if age_group_id==8
	replace age_start=20 if age_group_id==9
	replace age_start=25 if age_group_id==10
	replace age_start=30 if age_group_id==11
	replace age_start=35 if age_group_id==12
	replace age_start=40 if age_group_id==13
	replace age_start=45 if age_group_id==14
	replace age_start=50 if age_group_id==15
	replace age_start=55 if age_group_id==16
	replace age_start=60 if age_group_id==17
	replace age_start=65 if age_group_id==18
	replace age_start=70 if age_group_id==19
	replace age_start=75 if age_group_id==20
	replace age_start=80 if age_group_id==21
	gen age_end = age_start + 4
	replace age_end=99 if age_start==80

	gen sex = "Male" if sex_id==1
	replace sex="Female" if sex_id==2
	gen sex_issue = 0

	gen year_start = year_id
	gen year_end = year_id
	gen year_issue = 0

	gen unit_type = "Person"
	gen unit_value_as_published = 1
	gen measure_adjustment = 0
	gen measure_issue = 0
	gen measure = "incidence"
	gen case_definition = "incidence*30-day cfr"
	gen note_modeler = "30-day MI survivors"
	gen extractor = "strUser"
	gen is_outlier = 0

	gen underlying_nid = ""
	gen sampling_type = ""
	gen representative_name = "Unknown"
	gen urbanicity_type = "Unknown"
	gen recall_type = "Not Set"
	gen uncertainty_type = ""
	gen input_type = ""
	//gen upper = ""
	//gen lower = ""
	gen standard_error = ""
	gen effective_sample_size = ""
	gen design_effect = ""
	gen site_memo = ""
	gen case_name = ""
	gen case_diagnostics = ""
	gen response_rate = ""
	gen note_SR = ""
	gen uncertainty_type_value = 95
	gen parent_id = ""
	gen recall_type_value = ""
	gen cases = ""
	gen sample_size=""
	
capture drop cause_id envelope measure_id model_version_id age_group_id year_id sex_id pop // drop unneeded variables

cd "strPath"
save "strPath/survivors_forupload.dta", replace
export excel using "strPath/survivors_for_upload.xlsx", replace sheet("extraction") firstrow(variables)

log close
