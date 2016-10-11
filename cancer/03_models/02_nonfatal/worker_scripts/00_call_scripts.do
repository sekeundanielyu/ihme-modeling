** *************************************************************************************************************
** Purpose:		Submit and run nonfatal scripts 
** *************************************************************************************************************
** *************************************************
** set parameters
** *************************************************
// Toggle run_dont_submit if only one cause is selected
	if word("$cause_list", 1) != "" & word("$cause_list", 2) == "" global run_dont_submit = 1

// Set launch parameters: negate other options if just_check is enabled
	if $just_check {
		global run_dont_submit = 0
		global remove_old_outputs = 0
	}

// If remove_old_outputs is selected, verify that the user wants this option
	if $remove_old_outputs {
		di "Sanity Check: Are you sure you want to remove all previous outputs for the sections requested? Enter 'delete' for yes" _request(notMistake)
		if "$notMistake" != "delete" {
			global remove_old_outputs = 0
			noisily di "Canceling Script. Verify if previous outputs should be removed"
			BREAK
		}
	}
	
// Create Parameter file
	if 	$create_parameter_files {
		do "$generate_parameters"
	}

** *************************************************
** Set Data Lists
** *************************************************
// Set pre-defined lists, if present
	local cause_list = "$cause_list"
	local locations = "$locations"

// Set cause-information lists	
	use "$parameters_folder/causes.dta", clear
	// create list of causes if not provided
		if "`cause_list'" == "" levelsof(acause) if model == 1, local(cause_list) clean

	// cause_ids
		gen in_list = 0
		quietly foreach c of local cause_list {
			replace in_list = 1 if model == 1 & acause == "`c'"
		}
		capture levelsof cause_id if in_list == 1, clean local(cause_ids)
		capture levelsof mi_cause_name if in_list == 1 & model == 1, clean local(mi_cause_list)
		capture levelsof CoD_model if in_list == 1 & model == 1, clean local(cod_models)
		capture levelsof procedure_proportion_id if in_list == 1, clean local(procedure_proportions)
		capture levelsof procedure_rate_id if in_list == 1, clean local(procedure_rates)
		capture levelsof procedure_rate_id if in_list == 1 & to_adjust == 1, clean local(procedure_adjustments)

//  Set list of locations if not provided
	if "`locations'" == "" {
		use "$parameters_folder/locations.dta", clear
		capture levelsof(location_id) if model == 1, local(locations) clean
	}

** *************************************************
** Define Program to Submit scripts
** *************************************************
capture program drop submit_script
program define submit_script 
		syntax , script(string) script_arguments(string) iterable_list(string) output(string) sleep_time(string) timeout(string)

		// Submit script for each cause in cause_list
		local sname = substr(word(subinstr("`script'", "/", " ", .), -1), 1, 3)
		foreach item in `iterable_list' {
			local arguments = subinstr("`script_arguments'", "{iterable}", "`item'", .)
			local iname = subinstr("`item'", "neo_", "", .)
			if $run_dont_submit {
				noisily di "Running `sname' on `arguments'"
				sleep 2000
				do "`script'" "`arguments' $troubleshooting"
			}
			else if !$just_check {
				$qsub -pe multi_slot 4 -l mem_free=8g -N "_`sname'M_`iname'" "$shell" "`script'" "`arguments' $troubleshooting"
				if !$troubleshooting sleep `sleep_time'
			}
		}

		// Check for completion
		foreach item in `iterable_list' {
			local checkfile = subinstr("`output'", "{iterable}", "`item'", .)
			noisily di "Checking for `checkfile'"
			local display_found = word(subinstr("`checkfile'", "/", " ", .), -1)
			local arguments = subinstr("`script_arguments'", "{iterable}", "`item'", .)
			if $just_check {
				check_for_output, locate_file("`checkfile'") displayWhenFound("`item' `display_found'") timeout(0) failScript("`script'") scriptArguments("`arguments' 1")	
			}
			else {
				check_for_output, locate_file("`checkfile'") displayWhenFound("`item' `display_found'") timeout(`timeout') failScript("`script'") scriptArguments("`arguments' 1")	
			}
		}

end

** *************************************************
** Submit the selected scripts
**    
** *************************************************
// load script control and ensure that it is sorted
use "$script_control", clear
sort script_section
save "$script_control", replace
global num_scripts = _N

// iterate through each script in the control
foreach i of numlist 1/$num_scripts {
	local process = process[`i']
	local submission_type = submission_type[`i']
	if $`process' == 1 {
		// Handle Exceptions
			if "$`process'" == "calculate_special_sequelae" & !regexm("$cause_list", "neo_prostate") continue
		
		// Provie Feedback and Set Values Based On the Script Control
			noisily di "`process'"
			local script = master_script[`i']
			local arguments = arguments[`i']
			local iterable_list_name = iterable_list[`i']
			local output_folder = output_folder[`i']
			local filepattern = output_file_pattern[1]

		// Remove old outputs, if requested
		if $remove_old_outputs & "`output_folder'" != "" {
			noisily di "    Removing old `process' outputs..."
			if "`iterable_list_name'" == "" better_remove, path("`output_folder'")
			else {
				foreach item of local `iterable_list_name' {
					local item_output_directory = subinstr("`output_folder'", "{iterable}", "`item'", .)
					if "`filepattern'" != "" local filepattern = subinstr("`filepattern'", "{iterable}", "`item'", .)
					better_remove, path("`item_output_directory'") pattern("`filepattern'")
				}
			}
		}

		// Run or submit script
		if $run_dont_submit | "`submission_type'" == "do" {
			if "`iterable_list_name'" == "" {
				do "`script'" `arguments'
			}
			else {
				foreach item in ``iterable_list_name'' {
					local do_arguments = subinstr(`arguments', "{iterable}", "`item'", .)
					noisily di "   `do_arguments'"
					do "`script'" `do_arguments'
				}
			}
		}
		else {
			local sleep_time = sleep_time[`i']
			local output_file = output_file[`i']
			local timeout = timeout[`i']
			submit_script, script("`script'") script_arguments("`arguments'") iterable_list("``iterable_list_name''") output("`output_folder'/`output_file'") sleep_time(`sleep_time') timeout(`timeout')
		}
	}
	// restore script_control
	use "$script_control", clear
}

** *****************
** END CALL SCRIPTS
** *****************
