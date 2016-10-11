** ****************************************************************
** Author: Laura Dwyer-Lindgren
** Description: Runs the entire adult completeness process 
** ****************************************************************

** **********************
** Set up Stata 
** **********************
	clear all
	capture cleartmp 
	set mem 1g
	set more off
	
	global before_kids = 1
	global ddm = 1	// Technically before kids, but putting this option here to make things easier to run/troubleshoot
	global after_kids = 1
	
	global end_year = "2015" // For c09 population file targeting
	
	local source_dir "strPath"
	local source_out_dir "strPath"
	
	** Set code directory for Git
	local user "`c(username)'"
	
	if (c(os)=="Unix") global code_dir "strPath"
	if (c(os)=="Windows") {
		else global code_dir "strPath"
	}
	
	cd $code_dir
	
	adopath + "strPath" // For get_locations
	global function_dir "strPath" // DDM-specific functions

** **********************
** Run 00 
** **********************

	if ($before_kids==1) qui do "c00a_compile_deaths.do"
	if ($before_kids==1) qui do "c00b_compile_population.do"
    
** **********************
** Run 01-03
** **********************

if ($before_kids==1) { 	
	** **********************
	** Clear the temp folder
	** **********************
	di "`source_dir'"
	cd "`source_dir'"
		local files: dir "temp" files *
		foreach file of local files { 
			rm "temp/`file'"
		} 

	** **********************
	** Submit 01 02 and 03 jobs for each country
	** **********************
		set seed 1234
		get_locations, gbd_year(2015) 
		sort ihme_loc_id
		gen n = _n
		egen group = cut(n), group(75) // Make 75 equally sized groups for analytical purposes
		levelsof ihme_loc_id, clean local(locations)
		levelsof group, local(groups)
		cd "$code_dir"

		foreach i of local groups {
			! /usr/local/bin/SGE/bin/lx24-amd64/qsub -P proj_mortenvelope -N ddm01_`i' "run_all.sh" "$code_dir/c01_format_population_and_deaths.do" "`i'"
			! /usr/local/bin/SGE/bin/lx24-amd64/qsub -P proj_mortenvelope -hold_jid ddm01_`i' -N ddm02_`i' "run_all.sh" "$code_dir/c02_reshape_population_and_deaths.do" "`i'"
			! /usr/local/bin/SGE/bin/lx24-amd64/qsub -P proj_mortenvelope -hold_jid ddm02_`i' -N ddm03_`i' "run_all.sh" "$code_dir/c03_combine_population_and_deaths.do" "`i'"
		}

	** **********************
	** Wait for jobs to finish 
	** **********************
	cd "`source_dir'"
		local goal: word count `locations'
		local goal = `goal'*5
		
		local actual_count = 0 
		local start_time = clock(c(current_time), "hms")
		while (`actual_count' < `goal') { 
			sleep 30000 
			local current_time = clock(c(current_time), "hms")
			local files: dir "temp" files *
			local actual_count: word count `files' 
			local elapsed = (`current_time' - `start_time') / (1000*60) 
			noisily di "       `actual_count' files of `goal' files in `elapsed' minutes"
			if (`elapsed' > (2*60)) { 
				noisily di in red "******** WAITING MORE THAN 2 HOURS TO FINISH!!!!!!!!!!!! ********" 
				foreach loc in `locations' {
					di in red "Checking `loc'"
					local files: dir "temp" files "*_`loc'.dta", respectcase
					local actual_count: word count `files'
					if `actual_count' < 5 local error_countries = "`error_countries' `loc'"
				}
				di in red "Error countries are `error_countries'"
				
				exit, clear STATA
			}
		} 
	
	** **********************
	** Compile all files  
	** **********************	
	quietly { 
		cd "`source_dir'"
		local files: dir "temp" files "d01_formatted_population*.dta", respectcase
		clear 
		tempfile temp
		local count = 0 
		foreach f of local files { 
			use "temp/`f'", clear
			if (_N == 0) continue 
			local count = `count' + 1
			if (`count'>1) append using `temp'
			save `temp', replace
		} 
		use `temp', clear
		noi save "`source_out_dir'/d01_formatted_population.dta", replace 
		
		local files: dir "temp" files "d01_formatted_deaths*.dta", respectcase
		tempfile temp
		local count = 0 
		foreach f of local files { 
			use "temp/`f'", clear
			if (_N == 0) continue 
			local count = `count' + 1
			if (`count'>1) append using `temp'
			save `temp', replace
		} 	
		use `temp', clear
		noi save "`source_out_dir'/d01_formatted_deaths.dta", replace 
		
		local files: dir "temp" files "d02_reshaped_population*.dta", respectcase
		tempfile temp
		local count = 0 
		foreach f of local files { 
			use "temp/`f'", clear
			if (_N == 0) continue 
			local count = `count' + 1		
			if (`count'>1) append using `temp'
			save `temp', replace
		} 	
		use `temp', clear
		noi save "`source_out_dir'/d02_reshaped_population.dta", replace 
		
		local files: dir "temp" files "d02_reshaped_deaths*.dta", respectcase
		tempfile temp
		local count = 0 
		foreach f of local files { 
			use "temp/`f'", clear
			if (_N == 0) continue 
			local count = `count' + 1
			if (`count'>1) append using `temp'
			save `temp', replace
		} 		
		use `temp', clear
		noi save "`source_out_dir'/d02_reshaped_deaths.dta", replace 
		
		local files: dir "temp" files "d03_combined_population_and_deaths*.dta", respectcase
		tempfile temp
		local count = 0 
		foreach f of local files { 
			use "temp/`f'", clear
			if (_N == 0) continue 
			local count = `count' + 1
			if (`count'>1) append using `temp'
			save `temp', replace
		} 		
		use `temp', clear
		duplicates drop 
		noi save "`source_out_dir'/d03_combined_population_and_deaths.dta", replace 
	}
}

	
** **********************
** Run 04-10
** **********************

    if ($ddm==1) qui do "$code_dir/c04_apply_ddm.do"
	if ($ddm==1) qui do "$code_dir/c05_format_ddm.do"
    
	if ($after_kids==1) qui do "$code_dir/c06_calculate_child_completeness.do"
	if ($after_kids==1) qui do "$code_dir/c07_combine_child_and_adult_completeness.do"
	if ($after_kids==1) {
		// Delete 08 because DDM doesn't crash automatically on this part
		! rm "`source_out_dir'/d08_smoothed_completeness.dta"
		! "/usr/local/bin/R" < "$code_dir/c08_smooth_ddm.r" --no-save
	}
	qui do "$code_dir/c09_compile_denominators.do"
	if ($after_kids==1) qui do "$code_dir/c10_calculate_45q15.do"
	if ($after_kids==1) qui do "$code_dir/c11_create_archive.do"
	