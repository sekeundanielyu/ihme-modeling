// Set application preferences
	clear all
	set more off
	cap restore, not
	set maxvar 32700
	
// change directory
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}


local data_dir "$prefix/WORK/05_risk/risks/abuse_ipv_exp/data/exp/01_tabulate/raw/dhs"
use "`data_dir'/ipv_search_vars_revised.dta", clear

drop if regexm(variable, "hd|sd|md")
keep if variable == "d115j" | variable == "d115k" | variable == "d115l" | variable == "d105a" | variable == "d105b" | variable == "d105c" | variable == "d105d" | variable == "d105e" | variable == "d105f" | variable == "d105g" | variable == "d105h" | variable == "d105i" | variable == "d105j" | variable == "d105k" | /// 
variable == "D105A" | variable == "D105B" | variable == "D105C" | variable == "D105D" | variable == "D105E" | variable == "D105F" | variable == "D105G" | variable == "D105H" | variable == "D105I" | variable == "D105J" | variable == "D105K" | ///
regexm(variable, "s1205") & regexm(file, "BOL") | regexm(variable, "s515") & regexm(file, "IND") & regexm(file, "1998")| regexm(variable, "s516") & regexm(file, "IND") & regexm(file, "1998") | variable == "d106" & regexm(file, "MLI") | variable == "d107" & regexm(file, "MLI") | variable == "d108" & regexm(file, "MLI") | regexm(variable, "sc720") & regexm(file, "ZMB") | /// 
regexm(variable, "s720") & regexm(file, "ZMB") | variable == "s704" & regexm(file, "ZAF") | variable == "s712" & regexm(file, "ZAF") | variable == "v502" & regexm(file, "ZAF") | variable == "v502" & regexm(file, "COL") 

split path, parse("/") 
rename path6 iso3
rename path7 year
drop path1-path5 // path8
keep if regexm(filename, "WN") | regexm(file, "PER")
drop if regexm(filename, "IND_DHS4") & filename != "IND_DHS4_1998_2000_WN_Y2008M09D23.DTA"


	// reshape
		bysort file: gen n=_n
		sort variable
		reshape wide variable description, i(file) j(n)
	
	// making a variable list for each of the variables found in a dataset 
	gen variables = ""
	foreach variable of varlist variable* {
		if regexm("`variable'","variables") == 1 continue
		replace variables = variables + " " + `variable'
		}
	// making a standard variable list (weight, strata, age, gender etc) - I kept both domestic violence and sample weights
	gen variables2 = "d005 v005 v007 v012 v013 v021 v022 v024 v044 v502"
	
	// fix filepaths
	replace file = subinstr(file, "/HOME/J", "J:",.)
	
	// save file
	save "`data_dir'/files_to_extract_formatted_revised.dta", replace
	
	levelsof file, local(files)

	// local files = "J:/DATA/MACRO_DHS/COL/2009_2010/COL_DHS6_2009_2010_WN_Y2011M03D17.DTA"


	local count = 1
	
	foreach file of local files {
		di "`file'"
		
			if regexm("`file'", "IND_DHS5") == 1 {
				di in red "HEY THERE"
				use d005 v005 v007 v012 v013 v021 v022 v024 v025 v044 d105* v502 using "`file'", clear
				gen file = "`file'"
				cap decode v044, gen(selection)
				cap decode v024, gen(state)
				cap decode v025, gen(urbanicity)

				foreach var of varlist d105* v502 {
					cap decode `var', gen(text_`var')
					cap drop `var'
					cap rename text_`var' `var'
				}
			}

			else if regexm("`file'", "PER_DHS6_2013_REC84DV_Y2015M04D16.DTA") == 1 {
				di in red "SPECIAL SHIT"
				use "`file'", clear // domestic violence (d105) variables
				rename *, lower
				tempfile temp
				save `temp', replace
				

				use "J:\DATA\MACRO_DHS\PER\2013\PER_DHS6_2013_REC0111_Y2015M04D16.DTA", clear // survey design variables
				rename *, lower
				merge 1:1 caseid using `temp', keep(3) nogen
				save `temp', replace

				use "J:\DATA\MACRO_DHS\PER\2013\PER_DHS6_2013_RE516171_Y2015M04D16.DTA", clear 
				rename *, lower
				merge 1:1 caseid using `temp', keep(3) nogen

				keep v005 v007 v012 v013 v021 v022 v044 d105* v502
				
				gen file = "`file'"
				cap decode v044, gen(selection)
				cap foreach var of varlist d105* v502 {
					cap decode `var', gen(text_`var')
					cap drop `var'
					cap rename text_`var' `var'
				}

			}

			else if regexm("`file'", "PER_DHS7_2014_REC84DV_Y2015M06D29.DTA") == 1 {
				use "`file'", clear 
				rename *, lower
				tempfile temp
				save `temp', replace

				use "J:/DATA/MACRO_DHS/PER/2014/PER_DHS7_2014_RE516171_Y2015M06D29.DTA", clear
				rename *, lower
				merge 1:1 caseid using `temp', keep(3) nogen
				save `temp', replace

				use "J:\DATA\MACRO_DHS\PER\2014\PER_DHS7_2014_REC0111_Y2015M06D29.DTA", clear
				rename *, lower
				merge 1:1 caseid using `temp', keep(3) nogen
				

				cap keep d005 v005 v007 v012 v013 v021 v022 v044 d105* v502 
				cap decode v044, gen(selection)
				gen file = "`file'"

				foreach var of varlist d105* v502 {
					cap decode `var', gen(text_`var')
					cap drop `var'
					cap rename text_`var' `var'
				}


			}

		else if regexm("`file'", "BOL_DHS5_2008_WN_Y2010M06D18.DTA") == 1 { 
			use "`file'", clear 
			rename *, lower 
			cap keep d005 v005 v012 v013 v021 v022 v024 v025 v044 s1205* v502
			cap decode v044, gen(selection) 
			gen file = "`file'"

			foreach var of varlist s1205* v502 {
					cap decode `var', gen(text_`var')
					cap drop `var'
					cap rename text_`var' `var'
				}

			}

		else if regexm("`file'", "MLI_DHS5_2006_WN_Y2008M09D23.DTA") == 1 { 
			use "`file'", clear 
			rename *, lower 
			keep d005 v005 v012 v013 v021 v022 v024 v025 v044 d106 d107 d108 v502 
			cap decode v044, gen(selection) 
			gen file = "`file'" 

			foreach var of varlist d106 d107 d108 v502 {
					cap decode `var', gen(text_`var')
					cap drop `var'
					cap rename text_`var' `var'
				}
		}

		else if regexm("`file'", "ZMB_DHS4_2001_2002_WN_Y2008M09D23.DTA") == 1 { 
			use "`file'", clear 
			rename *, lower 
			keep v005 v012 v013 v021 v022 v024 v025 v044 s720* v502
			rename s720wgt d005

			cap decode v044, gen(selection) 
			gen file = "`file'" 

			foreach var of varlist s720* v502 {
					cap decode `var', gen(text_`var')
					cap drop `var'
					cap rename text_`var' `var'
				}
			}

		else if regexm("`file'", "IND_DHS4_1998_2000_WN_Y2008M09D23") == 1 {
			use "`file'", clear 
			rename *, lower 
			cap keep v005 v012 v013 v021 v022 v024 v025 s515 s516* v502
			drop s516b
			
			cap decode v044, gen(selection) 
			cap decode v024, gen(state)
			cap decode v025, gen(urbanicity)

			gen file = "`file'" 

			foreach var of varlist v502 s515 s516* {
					cap decode `var', gen(text_`var')
					cap drop `var'
					cap rename text_`var' `var'
				}
			}

		else if regexm("`file'", "ZAF_DHS3_1998_WN_Y2008M09D23.DTA") == 1 { 
			use "`file'", clear 
			rename *, lower 
			keep v005 v012 v013 v021 v022 v024 v025 s704 s712 v502 

			gen file = "`file'" 

			foreach var of varlist s704 s712 v502 {
					cap decode `var', gen(text_`var')
					cap drop `var'
					cap rename text_`var' `var'
				}
			}


		else if regexm("`file'", "COL_DHS6_2009_2010_WN_Y2011M03D17.DTA") == 1 {
			use "`file'", clear 
			gen file = "`file'"
			rename *, lower 
			gen new_v044 = v044
			tostring new_v044, replace
			gen selection = "Woman selected and interviewed" if new_v044 == "1"

			foreach var of varlist d105* {
				_strip_labels `var'
			}

			drop v502
			rename s606 v502
			tostring v502, replace force
			replace v502 = "Currently married" if v502 == "1" 
			replace v502 = "Formerly married" if v502 == "2" 
			replace v502 = "Never married" if v502 == "3" 
			replace v502 = "" if v502 == "0" 
			replace v502 = "" if v502 == "."

			tostring d105*, replace 

			keep file d005 v005 v007 v012 v013 v021 v022 v024 v025 new_v044 selection d105* v502 

			// cap decode v044, gen(selection) -- already in 0 or 1 format 

		}

		else if regexm("`file'", "HND_DHS5") == 1 {
			use "`file'", clear 
			gen file = "`file'"
			rename *, lower 
			keep d005 v005 v007 v012 v013 v021 v022 v024 v025 v044 d106 d107 d108 v502 
			cap decode v044, gen(selection) 
			gen file = "`file'" 

			foreach var of varlist d106 d107 d108 v502 {
					cap decode `var', gen(text_`var')
					cap drop `var'
					cap rename text_`var' `var'
				}

		}

		else {
		

		use "`file'", clear 
		renvars, lower
		cap keep d005 v005 v007 v012 v013 v021 v022 v044 d105* v502
		// cap use d005 v005 v007 v012 v013 v021 v022 v044 d105* v502 using "`file'", clear
		gen file = "`file'"
		cap decode v044, gen(selection)
		foreach var of varlist d105* v502 {
			cap decode `var', gen(text_`var')
			cap drop `var'
			cap rename text_`var' `var'
			}
		}


		tempfile `count'
		save ``count'', replace
		local count = `count' + 1

		}
	
	

	local terminal = `count' - 1
	clear
	forvalues x = 1/`terminal' {
		di `x'
		qui: cap append using ``x'', force
	}

	keep file d005 v005 v007 v012 v013 v021 v022 state urbanicity v044 d105a d105b d105c d105d d105e d105f d105g d105h d105i d105j d105k d105l d106 d107 d108 selection v502 s1205* s720* s515 s516* s704 s712


	// Label the non-selected datasets
	replace selection = "Woman selected and interviewed" if regexm(file, "IND_DHS4") & s515 != ""
	replace selection = "Woman selected and interviewed" if regexm(file, "ZAF_DHS3") & s704 != "" & s712 != "" 
	gen selected = 1 if regexm(selection, "oman selected and interviewed")
	replace selected = 0 if regexm(selection, "oman not selected")
	replace selected = 0 if regexm(selection, "oman selected, but not interviewed") 
	// replace selected = 0 if regexm(selection, "privacy not possible")
	// replace selected = 0 if regexm(selection, "but privacy not") 
	gen usable = 0
	replace usable = 1 if selected == 1 & regexm(selection, "oman selected and interviewed")
	keep if selected == 1
	drop selected
	
	replace state = regexr(state, "\[(.)+\]", "")
	replace state = strproper(state)
	replace state = "Uttarakhand" if regexm(state, "Uttaranchal") 
	replace state = "Jammu and Kashmir" if regexm(state, "Jammu") 
	replace urbanicity = strproper(urbanicity)

	egen subnational = concat(state urbanicity), punct(", ") 
	replace subnational = "" if subnational == ","
	
	save "`data_dir'/compiled_raw_revised.dta", replace
	
