
capture program drop zip_inj_steps
program define zip_inj_steps
	version 13
	syntax , STEPFile(string) STEPNum(string) Rundir(string) [Unzip]
	
	qui {
	
		preserve
		
		import excel "`stepfile'", sheet("steps") clear firstrow
		keep step name unzips zips
		tempfile steps_`stepnum'
		save `steps_`stepnum''
		keep if step == "`stepnum'"
		if missing("`unzip'") local zips = zips[1]
		else local zips = unzips[1]

		foreach step of local zips {
			use `steps_`stepnum'', clear
			keep if step == "`step'"
			local stepname = step[1] + "_" + name[1]
			
			if missing("`unzip'") {
				local output_path "`rundir'/`stepname'/03_outputs/01_draws"
				zip_dir, dir("`output_path'") name("zip_`step'")
			}
			else {
				local output_path "`rundir'/`stepname'/03_outputs"
				unzip_dir, dir("`output_path'")
			}
		}
		
		restore
		
	}
	
end
