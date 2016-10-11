	clear
	set more off
// Set to run all selected code without pausing
	set more off
// Remove previous restores
	cap restore, not
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		local j "/home/j"
		set odbcmgr unixodbc
		local code "/ihme/code/epi/strUser/nonfatal/malaria/anemia"
		local stata_shell "/ihme/code/epi/strUser/nonfatal/stata_shell.sh"
		local output "/share/scratch/users/strUser/copd/"
	}
	else if c(os) == "Windows" {
		local j "J:"
		local code "C:/Users/strUser/Documents/Code/malaria/COPD"
	}
	qui adopath + `j'/WORK/10_gbd/00_library/functions/
	
	args location_id base_folder folder_name
	
	di "`location_id' `base_folder' `folder_name'"
	
	//gen prevalence/proportion draws
	local ages 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21
	
	get_draws, gbd_id_field(modelable_entity_id) gbd_id(3265) source(epi) location_ids(`location_id') age_group_ids(`ages')
	//use j:/temp/strUser/Malaria/uga_draws_anemia_adj.dta, clear
	//local location_id 190
	tempfile draws
	save `draws', replace
	
	//get populations
	//use single year groups to make it slightly more comparable--doesn't actually make that much of a difference
	local pop_ages inlist(age_group_name, "2","3","4","5","6","7","8","9","10")
	use if (year == 2010 & location_id == `location_id' & `pop_ages') using "`j'/WORK/02_mortality/03_models/1_population/results/population_singleyear_gbd2015.dta", clear
	
	destring age_group_name, replace
	drop age_group_id
	gen age_group_id =cond(age_group_name<5, 5, .)
	replace age_group_id = cond(age_group_name == 10, 7, 6) if age_group_id == .
	
	rename year year_id 
	rename pop pop_scaled
	
	fastcollapse pop_scaled, by(age_group_id year_id location_id sex_id) type(sum)
	
	//merge in the draws
	merge 1:1 age_group_id year_id location_id sex_id using `draws', assert(2 3) keep(3) nogen
	
	//convert from prevalence to cases
	foreach d of varlist draw*{
		replace `d' = `d' * pop_scaled
	}
	
	//collapse by age and year
	fastcollapse draw* pop_scaled,by(year_id) type(sum)

	//find the average number of cases
	egen mean_cases = rowmean(draw*)
	drop draw*
	
	//convert back to pfpr
	gen prev_dismod = mean_cases/pop_scaled
	gen location_id = `location_id'
	
	//merge in MAP/ihme pfpr
	merge 1:1 location_id year_id using "`base_folder'/`folder_name'/pfpr.dta", assert(2 3) keep(3)
	
	//generate a scalar
	gen pfpr_scalar = mean_value/prev_dismod
	
	replace pfpr_scalar = 0 if scalar == .
	
	
	local the_scalar = scalar[1]
	
	//apply the scalar to the draws
	use `draws', clear
	di "`the_scalar'"
	sum draw_1
	forvalues i = 0/999 {
		replace draw_`i' = draw_`i' * (`the_scalar')
		replace draw_`i' = 1 if draw_`i'>1 //can't have prevalence over 1
		
	}
	sum draw_1
	
	//save the draws
	
	local years 1990 1995 2000 2005 2010 2015
	levelsof sex_id, local(sexes)

	foreach year of local years{
		foreach s of local sexes{
			di "`loc' `year' `s'"
			
			preserve
				keep age_group_id draw_* sex_id location_id year_id
				keep if sex_id == `s' & location_id == `location_id' & year_id == `year'
				gen measure_id = 5
				export delim "`base_folder'/`folder_name'/prevalence_`location_id'_`year'_`s'.csv", replace
			restore
			
		}
	}

	
	
	