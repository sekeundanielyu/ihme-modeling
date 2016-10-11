/* 
	this function parallelizes jobs that are run on country/sex/platforms with shock data from a previous step
	Inputs:	all standard inputs to parallelize function here: "J:\WORK\04_epi\01_database\01_code\04_models\prod\parallelize.ado"
			plus:
			prevstep = directory of the shock data draws that are to be transformed (should be saved in files that look like "`metric'_`iso3'_`platform'_`sex'.csv"
			
*/

capture program drop parallelize_shocks
program define parallelize_shocks
	version 13
	syntax , gbd(string) functional(string) date(string) step_num(string) step_name(string) envir(string) mem(string) type(string) code(string) subnational(string) prevstep(string)
	
	local tmp_dir "/clustertmp/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/03_steps/`date'/`step_num'_`step_name'"
	
	// set mem/slots and create job checks directory
		if `mem' < 2 local mem 2
		local slots = ceil(`mem'/2)
		local mem = `slots' * 2
		! rm -rf "`tmp_dir'/02_temp/01_code/shock_checks"
		! mkdir "`tmp_dir'/02_temp/01_code/shock_checks"
		
	local shock_counter=0
	foreach sex in male female {
		** get the list of all countries with either war or disaster shocks for any year for this sex
		di "`sex'"
		local counts=0
		local shocks : dir "`prevstep'/" files "*_`sex'.csv"
		foreach file of local shocks {
		clear
		set obs 1
		gen sex= "`sex'"
		gen location = subinstr("`file'", "incidence_", "", .)
		replace location = subinstr(location, "prevalence_", "", .)
		replace location = subinstr(location, "ylds_", "", .)
		if `counts'==0 {
			tempfile `sex'_filenames
			save ``sex'_filenames', replace
			local ++counts
		}
		else {
			append using ``sex'_filenames'
			save ``sex'_filenames', replace
			local ++counts				
		}
		}
		if `counts'==0 {
			di "there were no shocks files for `sex'"
		}
		else {
			use ``sex'_filenames', clear
			gen iso3 = substr(location, 1, 3)
			if "`subnational'"=="yes" {
				replace iso3 = substr(location, 1, 8) if inlist(iso3, "MEX", "GBR", "CHN")
				** two of the Great Britain subnational identifiers and all of the China subnational identifiers have three-digit location_ds
				replace iso3 = substr(iso3, 1, 7) if substr(iso3, 8, 8)=="_"
			}
			levelsof iso3, local(`sex'_shock_iso3s) clean
			
			foreach plat in inp otp {
				foreach iso3 of local `sex'_shock_iso3s {
					di "`iso3'"
					di "`sex'"
					di "`plat'"
					di "`code'"
					capture mkdir "`tmp_dir'/02_temp/01_code/shock_checks"
					! qsub -N `functional'_`step_num'_`iso3'_`plat'_`sex'_shocks -pe multi_slot `slots' -l mem_free=`mem' -p -2 "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh" "`code'" "`functional' `gbd' `date' `step_num' `step_name' `envir' `type' `iso3' `sex' `plat' `slots'"	
					local ++shock_counter
			}
		}
		** end platform loop for shock codes
	}
	** end sex-specific checks
}
** end sex loop for shock codes

** wait for the shock files to be writtten to continue
// wait for jobs to finish before passing execution back to main step file
	local i = 0
	while `i' == 0 {
			local checks : dir "`tmp_dir'/02_temp/01_code/shock_checks/" files "finished_*.txt", respectcase
			local count : word count `checks'
			di "checking `c(current_time)': `count' of `shock_counter' shock jobs finished"
			if (`count' == `shock_counter') continue, break
			else sleep 60000
	}

// end program
end
	
	
	