	clear
	set more off
// Set to run all selected code without pausing
	set more off
// Remove previous restores
	cap restore, not
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		local prefix "/home/j"
		set odbcmgr unixodbc
	}
	else{
		local prefix J:/
	}
	adopath + `prefix'/WORK/10_gbd/00_library/functions/
	
	args location_id output ver_desc
	
	di "`location_id' `output' `ver_desc'"
	
	local exclusions `prefix'/WORK/01_covariates/02_inputs/malaria/exclusions/malaria_exclusions_from_amillear_6-1-16_locadj.dta
	
	//load the draws
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(1446) location_ids(`location_id') measure_ids(5 6) sex_ids(1 2) source(epi) clear
	
	keep if inrange(age_group_id, 2,21)
	
	//make exclusions
	merge m:1 location_id year_id using `exclusions', assert(2 3) keep(3) nogen
	
	foreach draw of varlist draw*{
		replace `draw' = 0 if malaria==0
	}
	
	local years 1990 1995 2000 2005 2010 2015
	levelsof sex_id, local(sexes)
	
	local counter = 0
	
	forvalues i = 5/6{
		//set measure
		if `i'==5{
			local measure prevalence
		}
		else{
			local measure incidence
		}
		foreach year of local years{
			foreach s of local sexes{
				di "`loc' `year' `s' `i'"
				//set exclusion
				preserve
					local counter = `counter' +1 
					keep age_group_id draw_* sex_id location_id year_id measure_id
					keep if sex_id == `s' & location_id == `location_id' & year_id == `year' & measure_id == `i' 
					count
					
					export delim "`output'`ver_desc'/`measure'_`location_id'_`year'_`s'.csv", replace
				restore
				
			}
		}
	}
	
	
	