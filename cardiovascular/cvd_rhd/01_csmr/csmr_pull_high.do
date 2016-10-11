set more off

adopath + strPath/functions

tempfile csmr_high
save `csmr_high', emptyok

insheet using "strPath/RHD_locations2015.csv", clear comma names
levelsof location_id if income=="High", local(high)


get_demographics, gbd_team(epi)
local years 1980 1981 1982 1983 1984 1985 1986 1987 1988 1989 1990 1991 1992 1993 1994 1995 1996 1997 1998 1999 2000 2001 2002 2003 2004 2005 2006 2007 2008 2009 2010 2011 2012 2013 2014 2015

foreach location of local high { 
	get_outputs, topic(cause) metric_id(3) year_id(`years') sex_id(1 2) age_group_id($age_group_ids) cause_id(492) location_id(`location') gbd_round(2015) clear
	append using `csmr_high'
	save `csmr_high', replace
}

use `csmr_high', clear
drop if age_group_id < 5 //all missing

gen row_num = ""
generate modelable_entity_id = 3076
gen modelable_entity_name = "Rheumatic heart disease - High income"
gen nid = 259602
gen field_citation_value = "Institute for Health Metrics and Evaluation (IHME). Post-CoDCorrect estimates of cause-specific mortality rates for high-income/non-endemic countries for the relevant rheumatic heart disease DisMod model."
gen source_type = "Mixed or estimation"
gen smaller_site_unit = 0

gen age_demographer = 1
gen age_issue = 0
gen age_start = 1 if age_group_id==5
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

gen sex_issue = 0

gen year_start = year_id
gen year_end = year_id
gen year_issue = 0

gen unit_type = "Person"
gen unit_value_as_published = 1
gen measure_adjustment = 0
gen measure_issue = 0
replace measure = "mtspecific"
gen case_definition = "CSMR for high income/non-endemic model"
gen note_modeler = "3076 - high income countries only"
gen extractor = "strUser"
gen is_outlier = 0

gen underlying_nid = ""
gen sampling_type = ""
gen representative_name = "Unknown"
gen urbanicity_type = "Unknown"
gen recall_type = "Not Set"
gen uncertainty_type = ""
gen input_type = ""
rename val mean
gen standard_error = ""
gen effective_sample_size = ""
gen design_effect = ""
gen site_memo = ""
gen case_name = ""
gen case_diagnostics = ""
gen response_rate = ""
gen note_SR = ""
gen uncertainty_type_value = "95"
gen sample_size = ""
gen parent_id = ""
gen recall_type_value = ""
gen cases = ""
drop measure_id cause_id cause_name sequela_id year_id age_group_id age_group_name sex_id year_id age_group_id age_group_name  metric_id metric_name 

export excel using "strPath/me_3076_csmr_28Jun2016.xlsx", replace sheet("extraction") firstrow(variables)
