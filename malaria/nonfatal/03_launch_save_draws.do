//About: Takes short term incidence and converts to prevalence
	clear all
	set more off
	set maxvar 32767
	cap restore, not
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		local j "/home/j"
		set odbcmgr unixodbc
		local ver 1
	}
	else if c(os) == "Windows" {
		local j "J:"
		local ver 0
	}
	qui adopath + `j'/WORK/10_gbd/00_library/functions/

//Set Locals
	local versions v53
	local base_dir "`j'/WORK/04_epi/02_models/02_results/malaria/custom"
	local clust_folder /share/scratch/users/strUser/malaria/
	local code_folder /ihme/code/general/strUser/malaria/nonfatal
	
foreach version of local versions{
	local base_file `base_dir'/`version'/malaria_nonfatal_incidence.dta
//Make the file structure
	cap mkdir `clust_folder'
	cap mkdir `clust_folder'/nonfatal_`version'
	local save_folder `clust_folder'/nonfatal_`version'
	
	
//generate draws of duration
	clear
	set obs 1000
	gen durdraw_ = (14+(28-14)*runiform())/365
	xpose, clear
	rename v* dur_*
	gen id = 1
	save `save_folder'/duration_draws.dta, replace
	
//Get the locations to loop over
	get_demographics, gbd_team(epi)
	local location_ids = r(location_ids)
	
	// submit by locations
	
		foreach loc of local location_ids {
			!qsub -N "bmalaria_`version'_`loc'" -o /share/temp/sgeoutput/strUser/output -e /share/temp/sgeoutput/strUser/errors -l mem_free=2 -pe multi_slot 1 -P "proj_custom_models" "/ihme/code/general/strUser/malaria/stata.sh" "`code_folder'/03a_drawmaker.do" "`save_folder' `loc' `base_file'"
		}
	clear
}
	
