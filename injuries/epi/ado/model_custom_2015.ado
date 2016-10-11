// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This ado file runs the steps involved in cod/epi custom modeling for a functional group submitted from 00_master.do file; do not make edits here

cap program drop model_custom_2015
program define model_custom_2015
	version 12
	syntax , gbd(string) functional(string) date(string) steps(string) parallel(integer) repo(string)

// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	global repo "`repo'"
	global out_dir "$prefix/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'"
	global tmp_dir "/clustertmp/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'"
	cap mkdir "${out_dir}/03_steps/`date'"
	cap mkdir "${tmp_dir}/03_steps/`date'"
	cap log close
	log using "${out_dir}/03_steps/`date'/model_log.smcl", replace

// run steps
	// load steps template
	import excel using "${out_dir}/`functional'_steps.xlsx", sheet("steps") firstrow case(lower) clear
	tostring step, replace
	
	// get current step number
	if "`steps'" == "_all" levelsof step, local(steps) c

	// get list of parent steps (i.e. numbered steps only)
	gen step_num = regexr(step,"[a-z]","")
	levelsof step_num, local(step_nums) c
	
	// get last step(s) in last_steps local
	numlist "`step_nums'"
	local tmp = "`r(numlist)'"
	local maxnum 0
	foreach n of local tmp {
		if `n' > `maxnum' local maxnum `n'
	}
	local last_steps
	foreach step of local steps {
		if regexm("`step'","`maxnum'") local last_steps `last_steps' `step'
	}
	
	// generate default hold lists for submitting parallel jobs
	local total_parent_steps = wordcount("`step_nums'")
	forvalues i = 2/`total_parent_steps' {
		local current_step = word("`step_nums'",`i')
		local previous_step = word("`step_nums'",`i'-1)
		// develop local that will be used when submitting on cluster to identify which jobs to hold on
		local hold_on_steps_`current_step'
		// add previous steps to the hold for the current parent step IF step belongs to immediately anterior parent step AND it is one of the steps you are running
		foreach substep of local steps {
			if regexm("`substep'","`previous_step'") & regexm("`steps'","`previous_step'") {
				if "`hold_on_steps_`current_step''" == "" local hold_on_steps_`current_step' `functional'_`substep'
				else local hold_on_steps_`current_step' `hold_on_steps_`current_step'',`functional'_`substep'
			}
		}
	}
	tempfile step_info
	save `step_info', replace
	
	foreach step of local steps {
		use `step_info', clear
		levelsof name if step == "`step'", local(name) c
		global name `name'
		global fullname "`step'_$name"
		
		// get parent step if step has multiple substeps (i.e. a,b,c)
		local parent_step = regexr("`step'","[a-z]","")
		
		// override default hold list if specified or use default hold list for parent step
		levelsof hold if step == "`step'", local(h) c
		if "`h'" == "" local holds `hold_on_steps_`parent_step''
		else local holds = "`functional'_" + subinstr("`h'"," ",",`functional'_",.)
		
		// get memory needed for job (default 2G) and assign slots accordingly
		levelsof mem if step == "`step'", local(mem) c
		if "`mem'" == "" local mem 2
		local slots = ceil(`mem'/2)
		local mem = `slots' * 2
		
		// create step directories
		foreach dir in out_dir tmp_dir {
			cap mkdir "${`dir'}/03_steps/`date'/$fullname"
			cap mkdir "${`dir'}/03_steps/`date'/$fullname/01_inputs"
			cap mkdir "${`dir'}/03_steps/`date'/$fullname/02_temp"
			cap mkdir "${`dir'}/03_steps/`date'/$fullname/02_temp/01_code"
			cap mkdir "${`dir'}/03_steps/`date'/$fullname/02_temp/02_logs"
			cap mkdir "${`dir'}/03_steps/`date'/$fullname/02_temp/03_data"
			cap mkdir "${`dir'}/03_steps/`date'/$fullname/02_temp/04_diagnostics"
			cap mkdir "${`dir'}/03_steps/`date'/$fullname/03_outputs"
			cap mkdir "${`dir'}/03_steps/`date'/$fullname/03_outputs/01_draws"
			cap mkdir "${`dir'}/03_steps/`date'/$fullname/03_outputs/02_summary"
			cap mkdir "${`dir'}/03_steps/`date'/$fullname/03_outputs/03_other"
		}
		
		// create space separated list of previous jobs necessary to pass to Stata code (comma-separated necessary for BASH qsub command
		local holds_ss = subinstr(subinstr("`holds'",","," ",.),"`functional'_","",.)
		
		// delete finished.txt file for step if rerunning
		cap erase "${out_dir}/03_steps/`date'/$fullname/finished.txt"
		
		// submit job/call do-file
		if !`parallel' {
			di `"!qsub -N `functional'_`step' -pe multi_slot `slots' `args' "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh" "${repo}/`gbd'/`step'_$name.do" "`functional' `gbd' `date' `step' $name `repo' \"`holds_ss'\"  \"`last_steps'\""'
			
			do "${repo}/`gbd'/`step'_$name.do" `functional' `gbd' `date' `step' $name `repo' "`holds_ss'" "`last_steps'" 
		}
		else {
			// gemerate desired arguments for your job submission (holds and free memory needed to start job)
			local args
			if "`holds'" != "" local args -hold_jid `holds'
			if "`mem'" != "" local args `args' -l mem_free=`mem'
			
			// write out the actual job submit command so you have this info if it fails
			di `"!qsub -N `functional'_`step' -pe multi_slot `slots' `args' "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh" "${repo}/`gbd'/`step'_$name.do" "`functional' `gbd' `date' `step' $name `repo' \"`holds_ss'\"  \"`last_steps'\""'
			
			// submit job
			!qsub -N `functional'_`step' -pe multi_slot `slots' `args' "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh" "${repo}/`gbd'/`step'_$name.do" "`functional' `gbd' `date' `step' $name `repo' \"`holds_ss'\" \"`last_steps'\""
		}
	}

		log close
end
