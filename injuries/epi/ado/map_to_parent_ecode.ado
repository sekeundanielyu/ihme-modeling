
capture program drop map_to_parent_ecode
program define map_to_parent_ecode
	version 13
	syntax varname, GENerate(name)
	
	qui {
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}
		
		tempfile current
		save `current'
		
		clear
		
	// Load injury params
		load_params
		
	// parent-child relationships
		local obsnum 0
		gen `varlist' = ""
		gen `generate' = ""
		foreach e of global final_sequelae {
			local ++obsnum
			set obs `obsnum'
			replace `varlist' = "`e'" in `obsnum'
			local par = regexr("`e'","_[^_]+$","")
			foreach match of global final_sequelae {
				if "`match'" == "`par'" {
					replace `generate' = "`par'" in `obsnum'
					continue, break
				}
			}
		}
		
		merge 1:m `varlist' using `current', assert(match master)
		keep if _m == 3
		drop _m
	}
end
