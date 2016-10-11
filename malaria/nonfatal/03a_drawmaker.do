//Takes a folder location, location  and a dta full of draws and does the actual formatting and saving for save results	
** **************************************************************************
** PREP STATA
** **************************************************************************
	
	// prep stata
	clear
	set more off

	// Set OS flexibility 
	if c(os) == "Unix" {
		local j "/home/j"
		set odbcmgr unixodbc
		local h "~"
	}
	else if c(os) == "Windows" {
		local j "J:"
		local h "H:"
	}
	sysdir set PLUS "`h'/ado/plus"
	adopath+ "`j'/WORK/10_gbd/00_library/functions/"
	
	//interpolate rates
	args save_folder loc base_file
	local location_id loc
	di "`save_folder' `loc' `location_id' `base_file'"
	
	//get malaria draws by country

	use "`base_file'", clear
	
	keep if location_id == `loc'
	
	//levelsof location_id, local(thelocs)
	local years 1990 1995 2000 2005 2010 2015
	levelsof sex_id, local(sexes)
	
	
	//save incidence
	foreach year of local years{
		foreach s of local sexes{
			di "`loc' `year' `s'"
			
			preserve
				keep age_group_id draw_* sex_id location_id year_id
				keep if sex_id == `s' & location_id == `loc' & year_id == `year'
				gen measure_id = 6
				export delim "`save_folder'/incidence_`loc'_`year'_`s'.csv", replace
				
			restore
			
		}
	}
	
	//save prevalence
	gen id = 1
	merge m:1 id using `save_folder'/duration_draws.dta, assert(3) nogen
	forvalues i = 0/999 {
		local d = `i'+1
		replace draw_`i' = draw_`i' * dur_`d'
		drop dur_`d'
	}
	
	foreach year of local years{
		foreach s of local sexes{
			di "`loc' `year' `s'"
			
			preserve
				keep age_group_id draw_* sex_id location_id year_id
				keep if sex_id == `s' & location_id == `loc' & year_id == `year'
				gen measure_id = 5
				export delim "`save_folder'/prevalence_`loc'_`year'_`s'.csv", replace
				
			restore
			
		}
	}
di "DONE"
