******************************************************************************************************
** NEONATAL HEMOLYTIC MODELING
** PART 3: Preterm
** Part A: Prevalence of Preterm birth complications
** 6.18.14

** We get preterm birth prevalence by summing the birth prevalences we calculated for preterm in our 
** preterm custom models. 
** Note: this script replaces the synonymous python script in the same location 
*****************************************************************************************************

// discover root
	if c(os) == "Windows" {
		local j "J:"
		// Load the PDF appending application
		quietly do "`j'/Usable/Tools/ADO/pdfmaker_Acrobat11.do"
	}
	if c(os) == "Unix" {
		local j "/home/j"
		ssc install estout, replace 
		ssc install metan, replace
	} 
	

// locals
local me_ids 

// functions
run "`j'/WORK/10_gbd/00_library/functions/fastpctile.ado"
run "`j'/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
run "`j'/WORK/10_gbd/00_library/functions/get_draws.ado"

// directories 	
	local in_dir "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/02_analysis/neonatal_preterm/draws"
	local out_dir = "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/01_prep/neonatal_hemolytic/03_preterm"
	local log_dir = "`j'/temp/User/neonatal/logs/neonatal_hemolytic"
	
	local plot_dir "`out_dir'/time_series"
	
// Create timestamp for logs
    local c_date = c(current_date)
    local c_time = c(current_time)
    local c_time_date = "`c_date'"+"_" +"`c_time'"
    display "`c_time_date'"
    local time_string = subinstr("`c_time_date'", ":", "_", .)
    local timestamp = subinstr("`time_string'", " ", "_", .)
    display "`timestamp'"

	
	//log
	capture log close
	log using "`log_dir'/03_A_append_preterm_`timestamp'.smcl", replace


*********************************************************************************************

tempfile data
save `data', emptyok

// loop over three gestational ages and append together
forvalues x=1/3 {
	
	di "importing data for ga group `x'"
	import delimited "`in_dir'/neonatal_preterm_ga`x'_draws.csv", clear

	di "generating ga var"
	gen ga = `x'

	di "appending and saving"
	append using `data'
	save `data', replace

}

// sum to one bprev for every location-sex-year
collapse (sum) draw*, by(location_id year sex)

// format
rename draw_1000 draw_0 

// save
export delimited "`out_dir'/preterm_aggregate_birth_prevalence.csv", replace

