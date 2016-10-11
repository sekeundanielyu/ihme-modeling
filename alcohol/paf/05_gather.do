** Gather all of the alcohol files and save into GBD2013 format
** include "/home/j/WORK/05_risk/01_database/02_data/drugs_alcohol/04_paf/04_models/code/05_gather.do"

clear all
set more off

** Set directories
	if c(os) == "Windows" {
		global j "J:"
	}
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}

** Set options
{
	local DEBUG 0
	
	** If all arguments are passed in:
	if "`5'" != "" {
		local temp_dir "`1'"
		local yyy "`2'"
		local cause_cw_file "`3'"
		local version "`4'"
		local out_dir "`5'"
	}
	** Set to defaults if debug
	else if "`DEBUG'" == "1" {
		local temp_dir "/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/temp"
		local yyy 1990
		local cause_cw_file "$j/WORK/05_risk/risks/drugs_alcohol/data/meta/cause_crosswalk.csv"
		local version 1
		local out_dir "/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/output"	
	}
	** Otherwise display error message.
	else {
		noisily di in red "Missing arguments"
		error(999)
	}
}	


cap log close

// BREAK THE GATHER SCRIPT IF SOMETHING IS OUT OF ORDER
local breaker 0

// Toggle draw numbers
if "`DEBUG'" == "1" local max_draw = 9
else local max_draw = 999

** Expand functions (From PAF Calculator)
do "$j/WORK/2013/05_risk/03_outputs/01_code/02_paf_calculator/functions_expand.ado"

** Locals
	local sexes 1 2
	// local ages 1 2 3
	
** Prep cause crosswalk
	insheet using "`cause_cw_file'", comma clear names
	tempfile cause_cw
	save `cause_cw'

** Load list of russian countries (these get the PAFs from the Russia calculation)
** Russian Federation all years
** Belarus all years
** Ukraine all years
** Estonia 1990
** Latvia 1990
** Lithuania 1990
** Moldova all years
	if `yyy' == 1990 local in_russia_statement `"(inlist(location_id, 57,58,59,60,61,62,63))"'
	** Belarus, Russia, Ukraine
	if `yyy' != 1990 local in_russia_statement `"(inlist(location_id, 57,61,62,63))"'

** "	
	
** Non- Russia files (age specific files)
	local count 0
	local debugger ""
	local bad_vars ""
	
	local cause_groups chronic ihd ischemicstroke inj_self 
	qui foreach ccc of local cause_groups {
	foreach sss of local sexes {
	// foreach aaa of local ages {
	forvalues aaa = 15 (5) 80 {
		noi di "`aaa' `sss' `ccc'"
		cap insheet using "`temp_dir'/AAF_`yyy'_a`aaa'_s`sss'_`ccc'.csv", comma clear double
		if _rc local debugger "`debugger' AAF_`yyy'_a`aaa'_s`sss'_`ccc'.csv"
		
		else {
			if "`DEBUG'" == "1" {
				forvalues n = 11/1000 {
					cap drop draw`n'
				}
			}
			preserve
			describe, replace clear
			levelsof name if isnumeric != 1 & regexm(name,"draw"), local(change_vars) c
			restore
			
			foreach var of local change_vars {
				destring `var', replace force
			}
			local count_bad = 0
			local count_bad = wordcount("`change_vars'") 
			if `count_bad' != 0 local bad_vars "`bad_vars'; file AAF_`yyy'_a`aaa'_s`sss'_`ccc'.csv had `count_bad' missing draw sets"
			
			rename region location_id
			** Get the cause out of the disease column
			split disease, parse(" - ")
			rename disease1 cause
			gen type = ""
			replace type = "Mortality" if regexm(disease, "Mortality") 
			replace type = "Morbidity" if regexm(disease, "Morbidity")
			replace type = "both" if type == ""	

			// IHD and ischemic stroke generate mortality and morbidity numbers, but they are generated with the same
			// Overall processes but differ because of high variance. To reflect the similarities between the two, we make them the same
			if "`ccc'" == "ihd" | "`ccc'" == "ischemicstroke" {
				drop if type == "Morbidity" 
				replace type = "both" if type == "Mortality"
			}
			
			
			// For hemorrhagic stroke, we use the female mortality RR (and subsequently, AAF) to sub in for the female morbidity AAF
			// The original RR functions defined by 03_1_chronicRR for female morbidity produce a strong protective effect for alcohol consumption under 40 g/day
			// Because this is inconsistent with the mortality trend, and we believe the data underlying it is unclear, we default to keeping the female curve consistent between mortality/morbidity (and more consistent with males as well, this way)
			if "`ccc'" == "chronic" {
				drop if type == "Morbidity" & cause == "Hemorrhagic Stroke" & sex == 2
				replace type = "both" if type == "Mortality" & cause == "Hemorrhagic Stroke" & sex == 2
			}
			
			
			drop dis* aaf_pe aaf_mean sd
			cap drop v1
			local ++count
			tempfile temp`count'
			save `temp`count''
		}
	}
	}
	}
	
** Non-Russia files (all age injury files)
	local cause_groups inj_aslt inj_mvaoth
	qui foreach ccc of local cause_groups {
		noi di "`ccc'"
		cap insheet using "`temp_dir'/AAF_`yyy'_`ccc'.csv", comma clear double
		if _rc local debugger "`debugger' AAF_`yyy'_a`aaa'_s`sss'_`ccc'.csv"
		
		else {
			if "`DEBUG'" == "1" {
				forvalues n = 11/1000 {
					cap drop draw`n'
				}
			}
			
			
			preserve
			describe, replace clear
			levelsof name if isnumeric != 1 & regexm(name,"draw"), local(change_vars) c
			restore
			
			foreach var of local change_vars {
				destring `var', replace force
			}
			local count_bad = 0
			local count_bad = wordcount("`change_vars'") 
			if `count_bad' != 0 local bad_vars "`bad_vars'; file AAF_`yyy'_a`aaa'_s`sss'_`ccc'.csv had `count_bad' missing draw sets"
						
			rename region location_id
			** Get the cause out of the disease column
			split disease, parse(" - ")
			rename disease1 cause
			gen type = ""
			replace type = "Mortality" if regexm(disease, "Mortality") 
			replace type = "Morbidity" if regexm(disease, "Morbidity")
			replace type = "both" if type == ""		
			drop dis*
			cap drop v1
			
			local ++count
			tempfile temp`count'
			save `temp`count''
		}
	}


	clear
	forvalues iii = 1/`count' {
		append using `temp`iii''
	}
	
	** Drop the rows that we should have gotten from the Russia file
	drop if (`in_russia_statement') & inlist(cause, "Pancreatitis", "Lower Respiratory Infections", "Hemorrhagic Stroke", "Ischemic Stroke", "Tuberculosis", "Liver Cirrhosis", "IHD")
	
	// Mis-naming of age
	// rename ages age
	
	tempfile non_russia
	save `non_russia'
	
	
** Russia files
	local cause_groups russia
	
	local count 0
	qui foreach ccc of local cause_groups {
	foreach sss of local sexes {
	// foreach aaa of local ages {
	forvalues aaa = 15 (5) 80 {
		noi di "`aaa' `sss' `ccc'"
		cap insheet using "`temp_dir'/AAF_`yyy'_a`aaa'_s`sss'_`ccc'.csv", comma clear double
		if _rc local debugger "`debugger' AAF_`yyy'_a`aaa'_s`sss'_`ccc'.csv"

		
		else {
			if "`DEBUG'" == "1" {
				forvalues n = 11/1000 {
					cap drop draw`n'
				}
			}
		
			preserve
			describe, replace clear
			levelsof name if isnumeric != 1 & regexm(name,"draw"), local(change_vars) c
			restore
			
			foreach var of local change_vars {
				destring `var', replace force
			}
			local count_bad = 0
			local count_bad = wordcount("`change_vars'")
			if `count_bad' != 0 local bad_vars "`bad_vars'; file AAF_`yyy'_a`aaa'_s`sss'_`ccc'.csv had `count_bad' missing draw sets"
			

			rename region location_id
			** Get the cause out of the disease column
			split disease, parse(" - ")
			rename disease1 cause
			gen type = "both"
			drop dis* aaf_pe aaf_mean sd
			cap drop v1
			
			local ++count
			tempfile temp`count'
			save `temp`count''
		}
	}
	}
	}
	
	clear
	forvalues iii = 1/`count' {
		append using `temp`iii''
	}	

	** keep the rows that are russia specific
	** Note that there is some injuries here, but they won't take into account effects to non-drinkers... So I use the ones
	** calculated the other way.
	keep if (`in_russia_statement') & inlist(cause, "Pancreatitis", "Lower Respiratory Infections", "Stroke", "Tuberculosis", "Liver Cirrhosis", "IHD")
	drop if cause == "IHD" // Now we're dropping IHD because we analyze it separately
	replace cause = "Hemorrhagic Stroke" if cause == "Stroke" // Let's apply the stroke proportion here only for hemorrhagic -- we have ischemic splits from the new analysis below
	append using `non_russia'
	save `non_russia', replace

	
	** New Russia IHD and Ischemic Stroke Analysis results here
	** These take the place of the IHD and Ischemic stroke numbers produced by the code above
	local count 0
	
	qui foreach sss of local sexes {
	// foreach aaa of local ages {
	forvalues aaa = 15 (5) 80 {
		noi di "`aaa' `sss' russ_ihd_is"
		cap insheet using "`temp_dir'/AAF_`yyy'_a`aaa'_s`sss'_russ_ihd_is.csv", comma clear double
		if _rc local debugger "`debugger' AAF_`yyy'_a`aaa'_s`sss'_`ccc'.csv"

		else {
			if "`DEBUG'" == "1" {
				forvalues n = 11/1000 {
					cap drop draw`n'
				}
			}
		
			preserve
			describe, replace clear
			levelsof name if isnumeric != 1 & regexm(name,"draw"), local(change_vars) c
			restore
			
			foreach var of local change_vars {
				destring `var', replace force
			}
			local count_bad = 0
			local count_bad = wordcount("`change_vars'")
			if `count_bad' != 0 local bad_vars "`bad_vars'; file AAF_`yyy'_a`aaa'_s`sss'_`ccc'.csv had `count_bad' missing draw sets"

			rename region location_id
			** Get the cause out of the disease column
			replace disease = "IHD" if disease == "IHD Mortality"
			gen cause = disease
			gen type = "both"
			drop dis* aaf_pe aaf_mean sd
			cap drop v1
			local ++count
			tempfile temp`count'
			save `temp`count''
		}
	}
	}	

	
	clear
	forvalues iii = 1/`count' {
		append using `temp`iii''
	}	
	
	keep if (`in_russia_statement')
	
	append using `non_russia'
	
	
	// See what is missing 
	di in red "These need debugging"
	di in red "`debugger'"
	
	di in red "These have bad missing draw sets inputs (missing values). Investigate further."
	di in red "`bad_vars'"
	
	// If we want to break if there are missing files or if any of the input files have missing draws
	if `breaker' == 1 {
		if "`debugger'" != "" BREAK
		if "`bad_vars'" != "" BREAK
	}
	
	** Format variables and output
	rename draw* draw_*
	if "`DEBUG'" == "1" rename draw_10 draw_0
	else rename draw_1000 draw_0
	
	** Fix mortality for some cases
		gen mortality = (type == "Mortality" | type == "both")
		gen morbidity = (type == "Morbidity" | type == "both")
		** some instances in which morbidity is tagged with both, even though it exists on its own
		duplicates tag location_id sex age cause morbidity, gen(dup)
		count if dup == 1 & cause != "Liver Cirrhosis"
		if `breaker' != 0 & `r(N)' > 0 BREAK
		
		replace morbidity = 0 if dup == 1 & type == "both"
		drop type dup

	** Fix causes
		joinby cause using `cause_cw', _merge(_merge)
		assert _merge == 3
		drop _merge cause
		levelsof acause, local(testcauses) c
		if regexm("`testcauses'","nasophar") != 1 BREAK
		if regexm("`testcauses'","diabetes") != 1 BREAK
		
	** Some causes (like motor vehicle accidents) have multiple rows per group because they are done to other people
	** As well as by the drunk people themselves
		preserve
			drop if inlist(acause, "inj_trans_road_2wheel", "inj_trans_road_4wheel")
			tempfile temp
			save `temp'
		restore
		
		keep if inlist(acause, "inj_trans_road_2wheel", "inj_trans_road_4wheel")
		
		// Check to make sure it's a 2:1 ratio of before and after-collapse
		di in red "Count of observations before collapse"
		count
		
		// Check that we have a full set of draws for inj_trans and that they are all solid
		local over_limit = 1.000001 // Alternative (if interested in extreme values): 4
		local under_limit = -.000001 // Alternative (if interested in extreme values): -4
		local miss_limit = "."
		
		di in red "Looking at inj_trans"
		local over_count = 0
		local under_count = 0
		local miss_count = 0
		
		foreach count_iteration in over under miss {
			if "`count_iteration'" == "over" local sign = ">"
			if "`count_iteration'" == "under" local sign = "<"
			if "`count_iteration'" == "miss" local sign = "=="
			forvalues n = 0/999 {
				if "`count_iteration'" != "over" qui count if draw_`n' `sign' ``count_iteration'_limit'
				else qui count if draw_`n' `sign' ``count_iteration'_limit' & draw_`n' != . // Because missing values will be counted separately in miss_count
				if `r(N)' > 0 local `count_iteration'_count = 1
				
				if ``count_iteration'_count' != 0  {
					noi {
						di in red "inj_trans has draws `count_iteration' the limit for draw `n'"
						levelsof location_id if draw_`n' `sign' ``count_iteration'_limit' , c
						levelsof sex if draw_`n' `sign' ``count_iteration'_limit' , c
						levelsof age if draw_`n' `sign' ``count_iteration'_limit' , c
						local ++count
					}
				}
				if ``count_iteration'_count' > 0 continue, break // We just need one example per cause
			}
		}
		
		if `breaker' == 1 & (`over_count' != 0 | `under_count' != 0 | `miss_count' != 0) BREAK
		
		
		// Use same method as PAF Independent aggregation (multiplicative)
		qui foreach var of varlist draw* {
			replace `var' = .99999 if `var' == 1
			replace `var' = log(1 - `var')
		}
		
		collapse (sum) draw*, by(location_id age sex acause mortality morbidity) fast
		
		di in red "Count of observations after collapse"
		count
		
		qui foreach var of varlist draw* {
			replace `var' = 1 - exp(`var')
		}
	
		append using `temp'
		tempfile temp2
		save `temp2'
		
		// Adjust neo_colorectal
		preserve
			drop if inlist(acause, "neo_colorectal+rectal","neo_colorectal")
			tempfile temp
			save `temp', replace
		restore
		
		keep if inlist(acause, "neo_colorectal+rectal","neo_colorectal")
		
		qui forvalues draw = 0/`max_draw' {
			replace draw_`draw' = draw_`draw' * .35 if acause == "neo_colorectal+rectal"
			replace draw_`draw' = draw_`draw' * .65 if acause == "neo_colorectal"
		}
		replace acause = "neo_colorectal" if acause == "neo_colorectal+rectal"
		collapse (sum) draw*, by(location_id age sex acause mortality morbidity) fast
		append using `temp'
		
		** Expand out to most detailed causes
		acause_expand acause
	
	
	save `temp', replace
		
	// Expand from ages 0-5 to the granular age groups
	preserve
	keep if age == 0
	expand 3 
	bysort location_id age sex acause mortality morbidity: gen counter = _n
	replace age = .01 if counter == 1
	replace age = .1 if counter == 2
	replace age = 1 if counter == 3
	drop counter
	
	tempfile temp
	save `temp'
	restore
	append using `temp'
	save `temp', replace
	
	** Add on 100% attributable cause 
	keep location_id
	duplicates drop
	gen sex = 3
	gen gbd_age_start = 0
	gen gbd_age_end = 80
	gen mortality = 1
	gen morbidity = 1
	gen acause = "mental_alcohol"
	forvalues draw = 0/`max_draw' {
		gen draw_`draw' = 1
	}
	
	sex_expand sex
	age_expand gbd_age_start gbd_age_end, gen(age)
	
	qui append using `temp'
	
	// Recode breast cancer for men
	qui forvalues draw = 0/`max_draw' {
		replace draw_`draw' = 0 if acause == "neo_breast" & sex == 1
	}
	
	
	// For a select number of causes, see what specific draws and countries are affected by under-0 or over-1 draws
		local investigate_causes = "cirrhosis_hepb cirrhosis_alcohol neo_liver_alcohol digest_pancreatitis cvd_stroke_cerhem tb lri inj_trans_road_pedal inj_trans_road_pedest inj_trans_road_4wheel"
	
	// Set upper and lower limits: just in case you want to look at any outliers, or just those that are extreme
	local over_limit = 1.000001 // Alternative (if interested in extreme values): 4
	local under_limit = -.000001 // Alternative (if interested in extreme values): -4
	local miss_limit = "."
	local count 0
	
	foreach cause in `investigate_causes' {
		di in red "Looking at `cause'"
		local over_count = 0
		local under_count = 0
		local miss_count = 0
		
		foreach count_iteration in over under miss {
			if "`count_iteration'" == "over" local sign = ">"
			if "`count_iteration'" == "under" local sign = "<"
			if "`count_iteration'" == "miss" local sign = "=="
			forvalues n = 0/999 {
				if "`count_iteration'" != "over" qui count if draw_`n' `sign' ``count_iteration'_limit' & acause == "`cause'"
				else qui count if draw_`n' `sign' ``count_iteration'_limit' & acause == "`cause'" & draw_`n' != . // Because missing values will be counted separately in miss_count
				if `r(N)' > 0 local `count_iteration'_count = 1
				
				if ``count_iteration'_count' != 0  {
					noi {
						di in red "`cause' has draws `count_iteration' the limit for draw `n'"
						levelsof location_id if draw_`n' `sign' ``count_iteration'_limit' & acause == "`cause'", c
						levelsof sex if draw_`n' `sign' ``count_iteration'_limit' & acause == "`cause'", c
						levelsof age if draw_`n' `sign' ``count_iteration'_limit' & acause == "`cause'", c
						local ++count
					}
				}
				if ``count_iteration'_count' > 0 continue, break // We just need one example per cause
			}
		}
	}
	
	
	gen draw_under = 0
	gen draw_over = 0
	qui forvalues n = 0/999 {
		replace draw_under = draw_under + 1 if draw_`n' < -.000001 & acause != "cvd_ihd" // Add all protective diseases here
		replace draw_over = draw_over + 1 if draw_`n' > 1.000001
	}
	di in red "Under causes are"
	levelsof acause if draw_under != 0
	
	di in red "Over causes are"
	levelsof acause if draw_over != 0
	
	sum draw_under if acause != "cvd_ihd"
	local under_count = `r(sum)'
	
	sum draw_over
	local over_count = `r(sum)'	
	
	if `under_count' > 0 | `over_count' > 0 {
		di in red "Total draws under 0 are: `under_count'"
		di in red "Total draws over 1 are: `over_count'"
		// BREAK // Put this in if you want to break it if we have draws under 0 (not IHD) or over 1
	}
	
	drop draw_under draw_over
	
	** Save
	qui levelsof location_id, local(isos)
	levelsof sex, local(sexes)
	
	// Duplicate draws so that I have a full dataset to test step 06 on (ONLY if we only have a test set of draws for a given cause)
	if "`DEBUG'" == "1" {
		forvalues i = 1/99 {
			forvalues n = 0/9 {
				gen draw_`i'`n' = draw_`n'
			}
		}
		// local isos "RUS"
	}
		
	foreach lll of local isos {
		di in red "Outputting `lll'"
	qui foreach sss of local sexes {
		if "`sss'" == "1" local sex_str "male"
		if "`sss'" == "2" local sex_str "female"
		
		save age acause draw_* using "`out_dir'/`version'_prescale/paf_yll_`lll'_`yyy'_`sex_str'.dta" if location_id == `lll' & mortality == 1 & sex == `sss', replace
		save age acause draw_* using "`out_dir'/`version'_prescale/paf_yld_`lll'_`yyy'_`sex_str'.dta" if location_id == `lll' & morbidity == 1 & sex == `sss', replace
		
	}
	}
	
	