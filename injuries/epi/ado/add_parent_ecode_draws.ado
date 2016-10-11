
capture program drop add_parent_ecode_draws
program define add_parent_ecode_draws
	version 13
	syntax varname, BY(varlist)
	
	qui {
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}
		
		adopath + "$prefix/WORK/04_epi/01_database/01_code/04_models/prod"
		
	// Load injury params
		load_params
		
	// Generate parent e-code var
		map_to_parent_ecode `varlist', generate(e_parent)
		
	// Collapse
		fastcollapse draw*, type(sum) by(e_parent `by') append flag(appended)
		drop if e_parent == "" & appended == 1
		replace `varlist' = e_parent if appended == 1
		drop appended e_parent
	
	}
	
end
