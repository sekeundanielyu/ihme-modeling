** Use cirrhosis DisMod and CoD models to rescale cirrhosis mortality and morbidity PAFs so that all cirrhosis due to alcohol prevalence/deaths are accounted for 


clear all
set more off

** Set directories
	if c(os) == "Windows" {
		global j "J:"
		global prefix "J:"
	}
	if c(os) == "Unix" {
		global j "/home/j"
		global prefix "/home/j"
		set odbcmgr unixodbc
	}

** Set options
local DEBUG = 0

** If all arguments are passed in:
if "`6'" != "" {
	local temp_dir "`1'"
	display "`temp_dir'"
	local year_id "`2'"
	display "`year_id'"
	local cause_cw_file "`3'"
	display "`cause_cw_file'"
	local version "`4'"
	display "`version'"
	local out_dir "`5'"
	display "`out_dir'"
	local location_id "`6'"
	display "`location_id'"
}

** Set to defaults if debug
else if `DEBUG' == 1 {
	local temp_dir "/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/output/1_prescale"
	local year_id "2000"
	local cause_cw_file ""
	local version "2"
	local location_id "20"
	local out_dir "/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/output"	
}

********************************
** Create the locals we need  **
********************************

*Local for type of PAF/sex
local mort "yll yld"
local sexes "1 2"

*Get causes we're interested in, as well as sequela (Found in epi database)
local causes "cirrhosis neo_liver"
local subcauses "hepb hepc alcohol other"

*Create index locals for subcauses to make looping through easier
tokenize `subcauses'

*Get deaths for each subcause
local cirrhosis_yll "522 523 524 525"
local neo_liver_yll "418 419 420 421"

*Get prevalences for each subcause
local cirrhosis_yld "2891 2892 2893 2894"
	
*Get sequela for liver cancer prevalences (the sum of these is the prevalence of liver cancer)
local neo_liver_yld
forvalues i = 1682/1697 {
	local neo_liver_yld = "`neo_liver_yld' `i'"
}

**********************************************
** Get cirrhosis and liver cancer draws 	**
**********************************************

*Use central functions to get deaths/prevalences
adopath + "$prefix/WORK/10_gbd/00_library/functions"

tempfile yll
save `yll', emptyok

*First get deaths from dalynator by cause_id
foreach category in `causes'{

	*Create local for refering to tokens of subcauses to generate cause_name
	local i = 1

	foreach cause in ``category'_yll'{

		*Loop through causes and append together, then reshape to long
		display "cause `cause' " "location `location_id' " "year `year_id'" 
		get_draws, gbd_id_field(cause_id) gbd_id("`cause'") source(dalynator) location_ids("`location_id'") year_ids("`year_id'") clear
		keep if measure_id==1 & metric_id==1
		gen cause_name = "`category'_``i''"
		display "`category'_``i''_yll"
		local i = `i'+1
		append using `yll'
		save `yll', replace
	}
}

*Reshape to make calculations easier later on
reshape long draw_, i(location_id year_id sex_id age_group_id cause_id cause_name) j(n)
rename draw_ yll
save `yll', replace

*Now get prevalences from dismod by modelable_entity_id

clear
tempfile yld
save `yld', emptyok

foreach category in `causes' {

	*Cirrhosis prevalences are the same as for deaths
	if "`category'"=="cirrhosis"{
		local i = 1
		foreach cause in `cirrhosis_yld' {

			get_draws, gbd_id_field(modelable_entity_id) gbd_id("`cause'") source(dismod) location_ids("`location_id'") year_ids("`year_id'") clear
			keep if measure_id==5
			gen cause_name = "`category'_``i''"
			display "`category'_``i''_yld"
			local i = `i'+1
			append using `yld'
			save `yld', replace
		}
	}

	else {
		clear

		*Create dummy variable to loop through 4 subcategories for sequela and sum across to get total prevalence for liver cancer
		local i = 1

		*Create dummy variable for indexing cause_name
		local j = 1

		tempfile dummy_`j'
		save `dummy_`j'', emptyok

		foreach cause in `neo_liver_yld'{
			get_draws, gbd_id_field(modelable_entity_id) gbd_id("`cause'") source(dismod) location_ids("`location_id'") year_ids("`year_id'") clear
			keep if measure_id==5
			append using `dummy_`j''
			save `dummy_`j'', replace

			*Once we get all 4, collapse together to get total prevalence for that cause
			if `i'== 4 {
				collapse (sum) draw_*, by(age_group_id sex_id location_id year_id)
				gen cause_name = "`category'_``j''"
				display "`category'_``j''_yld"
				save `dummy_`j'', replace

				use `yld', clear
				append using `dummy_`j''
				save `yld', replace

				local j = `j'+1
				local i = 1

				clear
				tempfile dummy_`j'
				save `dummy_`j'', emptyok
			}

			else {
				local i = `i'+1
			}
		}
	}
}

use `yld', clear
keep draw_* location_id year_id sex_id age_group_id cause_name

reshape long draw_, i(location_id year_id sex_id age_group_id cause_name) j(n)
rename draw_ yld
save `yld', replace

*Bring in PAF intermediary draws
foreach mort_type in `mort'{
	clear
	tempfile paf_`mort_type'
	save `paf_`mort_type'', emptyok

	foreach sex in `sexes'{
		insheet using "`out_dir'/`version'_prescale/`mort_type's/paf_`mort_type'_`location_id'_`year_id'_`sex'.csv", clear	
		append using `paf_`mort_type'', force
		save `paf_`mort_type'', replace
	}
	
	reshape long draw_, i(sex_id age_group_id acause) j(n)
	rename acause cause_name
	rename draw_ paf_`mort_type'

	*Issue with age_group_id being saved as string
	capture keep if age_group_id != "NA"
	capture destring age_group_id, replace

	save `paf_`mort_type'', replace
}

*******************
** Rescale PAFs  **
*******************

*For each cause/paf, rescale so that alcohol is fully attributable, rescaling the other pafs on this basis. 
foreach mort_type in `mort' {
	clear
	tempfile final_`mort_type'
	save `final_`mort_type'', emptyok

	foreach cause in `causes' {
		display("`cause'")
		use `paf_`mort_type'', clear
		merge m:1 age_group_id sex_id cause_name n using ``mort_type'', nogen keep(3)
		keep if age_group_id >= 8

		keep if regexm(cause_name, "`cause'") == 1

		*Generate attributable deaths/prevalence
		*Also the all-cause envelope, and the proportion of non-alcohol envelope that goes to each non-alcohol cause
		gen attributable_`mort_type' = `mort_type' * paf_`mort_type'
		bysort age_group_id sex_id n: egen envelope_`mort_type' = total(attributable_`mort_type')		
		bysort age_group_id sex_id n: egen prop_`mort_type' = pc(`mort_type') if regexm(cause_name, "alcohol") != 1
		replace prop_`mort_type' = prop_`mort_type'/100
	
		tempfile everything
		save `everything', replace
		
		*Generate a dataset with the prevalence/deaths for alcohol alone (which we will use as the attributable figure for alcohol)
		keep if cause_name=="`cause'_alcohol"

		rename `mort_type' subtraction
		
		keep age_group_id sex_id n subtraction
		tempfile subtraction
		save `subtraction', replace
			
		merge 1:m age_group_id sex_id n using `everything', nogen

		*Now, rescale all the others
		*We have the proportion of the burden-attributable (yll/ylds) that should go to each non-alcohol draw
		*So we just subtract alcohol prevalence/deaths from the envelope of total deaths/prevalence, and then distribute the remaining envelope proportionally to the burden-attributable (yll/ylds)
		gen newenvelope_`mort_type' = envelope_`mort_type' - subtraction
	
		*If the prevalence of cirrhosis due to alcohol exceeds the attributable cirrhosis prevalence, per our PAFs, constrain the remaining PAFs to 0 instead of negative
		replace newenvelope_`mort_type' = 0 if newenvelope_`mort_type' < 0 
	
		*Determine how the remaining metrics should be allocated based on cause
		gen newattributable_`mort_type' = prop_`mort_type' * newenvelope_`mort_type'
		replace newattributable_`mort_type' = `mort_type' if cause_name=="`cause'_alcohol"

		*Recalculate the adjusted PAF
		gen newpaf_`mort_type' = newattributable_`mort_type' / `mort_type'
		
		*Format nicely to be output for save_results
		keep age_group_id sex_id cause_name newpaf_`mort_type' n
		rename newpaf_`mort_type' paf_`mort_type'
		
		append using `final_`mort_type''
		save `final_`mort_type'', replace
	}

	use `paf_`mort_type'', clear
	keep if regexm(cause_name, "cirrhosis") != 1 & regexm(cause_name, "neo_liver") != 1
	append using `final_`mort_type''

	rename paf_`mort_type' draw_
	reshape wide draw_, i(age_group_id sex_id cause_name) j(n)
	save `final_`mort_type'', replace

	*Export by mort type in a format for save_results
	foreach sex in `sexes'{
		use `final_`mort_type'', clear
		keep if sex_id==`sex'
		tempfile temp
		save `temp', replace

		import delimited "/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/cause_id.csv", clear
		merge 1:m cause_name using `temp', nogen
		export delimited age_group_id cause_id cause_name draw_* using "`out_dir'/`version'/paf_`mort_type'_`location_id'_`year_id'_`sex'.csv", replace delim(",")
	}
}
