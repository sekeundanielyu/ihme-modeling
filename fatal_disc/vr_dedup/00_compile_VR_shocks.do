** ****************************************************
** Purpose: Prepare and compile all final Cause of Death sources for mortality team
** Location: do "compile_VR_data_for_mortality.do"
** Location: do "compile_VR_data_for_mortality.do"
** ****************************************************

** ***************************************************************************************************************************** **
** set up stata
clear all
set more off
set mem 4g
if c(os) == "Windows" {
	global j ""
}
if c(os) == "Unix" {
	global j ""
	set odbcmgr unixodbc
}

** ***************************************************************************************************************************** **
** define globals
global vrdir ""
global date = c(current_date)


** ***************************************************************************************************************************** **
** make the file

	** load the online database to identify the folders with nationally representative VR
	
	** Alternatively, we have to skip through our source files and find ones that have VR
	clear
	gen source = "blank"
	gen list = ""
	gen national = .
	set obs 1
	tempfile list 
	save `list'
	
	local sources: dir "" dirs "*", respectcase
	local sources: list clean sources

	quietly foreach source of local sources {
		if substr("`source'", 1, 1) == "_" continue
		capture use source source_type national list using "00_formatted.dta", clear
		if _rc == 0 {
			keep if regexm(source_type, "VR")
			count
			if `r(N)'>0 {
				noisily display "`source' has VR"
				keep source list national source_type
				duplicates drop
				append using `list'
				tempfile list
				save `list', replace
			}
		}
	}
	drop if source == "blank"
	drop if national == 0
	
	** Drop Bangledesh, Kenya, and Other Maternal, as these were incorrectly coded as VR
	drop if inlist(source, "Other_Maternal", "Bangladesh_SRS_2010", "Kenya_Report_2000_2006")

	** Drop maternal VR from the list because we fill with the envelope
	drop if source == "Middle_East_Maternal"
	
	
	** save a checkpoint (can be helpful sometimes)
	tempfile before_append
	save `before_append', replace

	** capture the list of remaining sources
	levelsof source, local(sources)

	** first check that we have all the sources we need
		foreach source of local sources {
		capture confirm file "02_agesexsplit_compile.dta"
		if _rc!=0 {
			display "`source' not yet prepped in GBD2015"
			break
		}
	}
	
	di "STARTING"
	local num_iterations = 0
	local skips = 0
	** loop over sources and load in it's "after age split" file, then collapse to all causes
	foreach source of local sources {
		if "`source'"!= "China_1991_2002" & "`source'" != "China_2004_2012" {
			use "02_agesexsplit_compile.dta", clear
			display "Collapsing `source'"
			keep if inlist(acause, "inj_disaster", "inj_war", "inj_war_war", "inj_war_execution", "inj_war_terrorism")
			count
			if `r(N)' == 0 {
				local ++skips
				continue
			}
			collapse (sum) deaths1, by(acause iso3 location_id year sex subdiv source NID list) fast
		}
		if "`source'"== "China_1991_2002" | "`source'" == "China_2004_2012" {
			use "07_merged_long.dta", clear
			display "Collapsing `source'"
			keep if inlist(acause, "inj_disaster", "inj_war", "inj_war_war", "inj_war_execution", "inj_war_terrorism")
			if `r(N)' == 0 {
				local ++skips
				continue
			}
			collapse(sum) deaths_raw, by(acause iso3 location_id year sex subdiv source NID list) fast
			rename deaths_raw deaths1
		}
		if "`source'" == "US_NCHS_counties_ICD9" | "`source'" == "US_NCHS_counties_ICD10" {
			use "02_agesexsplit_compile_states.dta", clear
			display "Collapsing `source'"
			keep if inlist(acause, "inj_disaster", "inj_war", "inj_war_war", "inj_war_execution", "inj_war_terrorism")
			if `r(N)' == 0 {
				local ++skips
				continue
			}
			collapse (sum) deaths1, by(iso3 location_id year sex subdiv source NID list) fast
			
		}
		local num_iterations = `num_iterations' + 1
		tempfile tmp`num_iterations'
		save `tmp`num_iterations'', replace
	}
	
	** append together each source
	clear
	gen foo = .
	local skips = `num_iterations' - `skips'
	local num_iterations = 0

	foreach source of local sources {
		if `num_iterations' == `skips' continue, break
		local num_iterations = `num_iterations' + 1
		append using `tmp`num_iterations''
	}
	cap drop foo
	
	

** save!
	order iso3 location_id year source subdiv sex deaths1
	sort iso3 location_id year source subdiv sex deaths1
	compress
	save "VR_shocks.dta", replace
	

