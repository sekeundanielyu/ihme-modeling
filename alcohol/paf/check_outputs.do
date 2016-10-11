
** figure out if we're missing anything from alcohol


clear all 
capture log close
set more off

** MAKE THE SHOCK LIFETABLES FOR MORTALITY/COD CAPSTONE

** normal setup
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"
	
** set directories and macros
	local check_dir "/clustertmp/gregdf/alcohol_temp"

** get countrynames that we need to replace for
	** create dataset to store list of countries
	local years "1990 1995 2000 2005 2010 2013"
	local ages "15 20 25 30 35 40 45 50 55 60 65 70 75 80"
	local sexes "1 2"
	local causes "russia chronic ihd ischemicstroke"
	
	cd "`check_dir'"
	local missingfiles ""
	foreach year of local years {
		foreach age of local ages {
			foreach sex of local sexes {
				foreach cause of local causes {
					capture confirm file "AAF_`year'_a`age'_s`sex'_`cause'.csv"
						if _rc != 0 {
							di in red "AAF_`year'_a`age'_s`sex'_`cause'.csv is missing"
							local missingfiles "`missingfiles' AAF_`year'_a`age'_s`sex'_`cause'.csv"
						}
				}
			}
		}
	}
	
	local numfiles : word count `missingfiles'	
	set obs `numfiles'
	gen filelist = ""
	local count = 1
	foreach file of local missingfiles {
		replace filelist = "`file'" if _n == `count'
		local count = `count' + 1
	}
	saveold "/home/j/WORK/05_risk/02_models/03_diagnostics/alcohol_tshoot/missing_files.dta", replace

