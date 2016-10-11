// Date: October, 2013
// Purpose: Create master dataset containing NHANES data from 1999-2012 to be used for calculating secondhand smoke exposure prevalence among nonsmokers in the USA

// Notes: 
	** Household secondhand smoke question: "Does anyone who lives here smoke cigarettes, cigars, or pipes anywhere inside this home?" 1= Yes, 2= No, 7 = Refused, 9= Don't know
	** Smoking status question: Do you now smoke... 1= everyday, 2= some days, 3 = not at all, 7 = refused, 9=don't know


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
	local years 1999_2000 2001_2002 2003_2004 2005_2006 2007_2008 2009_2010 2011_2012
	local files SMQFAM SMQ_ DEMO
	local nhanes_dir = "$j/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw"
	local count 0 // local to count loop iterations and save each survey-year as numbered tempfiles to be appended later
	
	
// Loop through NHANES directories for each year and merge the three necessary data files, containing demographic/survey weight data, household smoke exposure data and respondent smoking status 
	foreach year in `years' {
		di in red "`year'"
		local year_start = substr("`year'", 1, 4)
		local year_end = substr("`year'", 6, 9)
		
			foreach file in `files' {
					local filename : dir  "`nhanes_dir'/`year'" files "*`file'*", respectcase
					di `filename'
				foreach name of local filename {
					use "`nhanes_dir'/`year'/`name'", clear
					renvars, lower // Make variable names lower case
						tempfile data`count'
						save `data`count'', replace
						local count = `count' + 1
						di `count'
				}
			
			}
			
			local smqfam = `count' - 3
			di "`smqfam'"
			local smq = `count' - 2
			di "`smq'"
			local demo = `count' - 1
			di "`demo'"
		
		// Merge on individual identifier (seqn) to get file for each year that contains all necessary variables
			use `data`demo'', clear
			merge 1:1 seqn using `data`smqfam'', nogen
			merge 1:1 seqn using `data`smq'', nogen
			
			capture generate year_start = "`year_start'"
			capture generate year_end = "`year_end'"
			keep seqn riagendr ridageyr wtint2yr sdmvpsu sdmvstra smd410 smd415a smd430 smq020 smq040 year_start year_end
			tempfile data`year'
			save `data`year'', replace
	}

// Append all year-specific files together to make one master file with all survey years of NHANES data from 1999-2012
	use `data1999_2000', clear	
	
	foreach datafile in "2001_2002" "2003_2004" "2005_2006" "2007_2008" "2009_2010" "2011_2012" {
		append using `data`datafile''
	}

	generate nid = .
	destring year_start year_end, replace
	replace nid = 52110 if year_start == 1999
	replace nid = 49205 if year_start == 2001
	replace nid = 47962 if year_start == 2003
	replace nid = 47478 if year_start == 2005
	replace nid = 25914 if year_start == 2007
	replace nid = 48332 if year_start == 2009
	replace nid = 110300 if year_start == 2011

save `nhanes_dir'/nhanes_compiled.dta, replace
