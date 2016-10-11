// Date: November 4, 2013
// Purpose: Create master dataset containing NHANES data to be used for calculating physical activity level in the USA

// Notes: 


// Set up
	clear all
	set more off
	set mem 2g
	capture log close
	capture restore not
	
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	
	else if c(os) == "Windows" {
		global j "J:"
	}
	
// Create locals for relevant files and folders
	local years 1988_1994 1999_2000 2001_2002 2003_2004 2005_2006 2007_2008 2009_2010 2011_2012
	local files PAQ DEMO
	local data_dir = "$j/DATA/USA/NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY"
	local outdir = "$j/WORK/05_risk/risks/activity/data/exp/raw"

// Loop through NHANES directories for each year and merge the three necessary data files, containing demographic/survey weight data, household smoke exposure data and respondent smoking status 
	foreach year in `years' {
		di in red "`year'"
		
		// 1.)  First year is different
		if "`year'" == "1988_1994" {
				use "`data_dir'/`year'/USA_NHANES_1988_1994_ADULT_Y2011M04D25.dta", clear
				
				gen file = "`data_dir'/`year'/USA_NHANES_1988_1994_ADULT_Y2011M04D25.DTA"
				gen year_start = substr("`year'", 1, 4)
				gen year_end = substr("`year'", 6, 9)
			
			// Rename key variables for clarity
				rename sdppsu6 psu 
				rename sdpstra6 strata
				rename wtpfqx6 wt 
				rename hsageir age
				rename hssex  sex
				
				keep seqn age sex wt psu strata hat* year_start year_end file
				
				tempfile data`year'
				save `data`year'', replace
		}

		// 2.) 1999-2006 have 3 separate files that we need
		if inlist("`year'", "1999_2000", "2001_2002", "2003_2004", "2005_2006") {
			local files PAQ DEMO PAQIAF HSQ
			foreach file of local files {
				local filename : dir  "`data_dir'/`year'" files "*`file'*.DTA", respectcase
				foreach name of local filename {

					if "`file'" == "DEMO" & "`year'" == "2003_2004" { 
						use "`data_dir'/`year'/USA_NHANES_2003_2004_DEMO_C.DTA", clear 
						renvars, lower
					}

					else {
						use "`data_dir'/`year'/`name'", clear
						renvars, lower // Make variable names lower case
					}

					if "`file'" == "DEMO" {
						gen file = "`data_dir'/`year'/`name'"
					}

					if "`file'" == "PAQ" { 
						duplicates drop seqn, force 
					}
					
					tempfile `file'_`year'
					save ``file'_`year'', replace
				}
			} 
				
				// Merge on individual identifier (seqn) to get file for each year that contains all necessary variables
					use `DEMO_`year'', clear
					merge 1:1 seqn using `PAQ_`year'', nogen
					merge 1:m seqn using `PAQIAF_`year'', nogen
					merge m:1 seqn using `HSQ_`year'', nogen
					
					gen year_start = substr("`year'", 1, 4)
					gen year_end = substr("`year'", 6, 9)
					
				// Rename key variables for clarity
					rename sdmvpsu  psu 
					rename sdmvstra strata
					rename wtint2yr wt 
					rename ridageyr age
					rename riagendr sex
					rename indhhinc hh_income 
					cap rename hsd010 general_health
					rename ridreth1 race_1
					cap rename ridreth2 race_2

					cap keep seqn age sex wt psu strata pa* year_start year_end hh_income general_health race_1 race_2 file
					
				tempfile data`year'
				save `data`year'', replace
		} 
		
		// 3.) 2007 onward have 2 files we need
		if inlist("`year'", "2007_2008", "2009_2010", "2011_2012") {
				local files PAQ DEMO HSQ
				foreach file of local files {
						local filename : dir  "`data_dir'/`year'" files "*`file'*.DTA", respectcase
					foreach name of local filename {
						use "`data_dir'/`year'/`name'", clear
						renvars, lower // Make variable names lower case
						
						gen file = "`data_dir'/`year'/`name'"
						gen year_start = substr("`year'", 1, 4)
						gen year_end = substr("`year'", 6, 9)	
						
						tempfile `file'_`year'
						save ``file'_`year'', replace
					}
				}
				
				// Merge on individual identifier (seqn) to get file for each year that contains all necessary variables
					use `DEMO_`year'', clear
					merge 1:1 seqn using `PAQ_`year'', nogen
					merge 1:1 seqn using `HSQ_`year'', nogen
					capture generate year_start = "`year_start'"
					capture generate year_end = "`year_end'"
					
				// Rename key variables for clarity
					rename sdmvpsu  psu 
					rename sdmvstra strata
					rename wtint2yr wt 
					rename ridageyr age
					rename riagendr sex
					rename hsd010 general_health
					cap rename indhhin2 hh_income 
					rename ridreth1 race_1

					cap keep seqn age sex wt psu strata pa* year_start year_end general_health hh_income race_1 file
					
				tempfile data`year'
				save `data`year'', replace
		}
	}

// Append all year-specific files together to make one master file with all survey years of NHANES data from 1988 onward
	use `data1988_1994', clear	
	
	foreach datafile in "1999_2000" "2001_2002" "2003_2004" "2005_2006" "2007_2008" "2009_2010" "2011_2012" {
		di in red "`data`datafile''"
		append using `data`datafile''
	}
	
save `outdir'/nhanes_compiled_revised.dta, replace
