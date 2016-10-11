
// Function:	Compiles MI Model result (MI_model_result) of all cause-models entered in the model selection document

** **************************************************************************
** Configuration
** 		Sets application preferences (memory allocation, variable limits) 
** 		Accepts/Sets Arguments. Defines the J drive location.
** **************************************************************************
// Set to run all selected code without pausing
	clear 
	set more off

// accept arguments
	args cause sex modnum input_directory temp_folder output_file
	if "`cause'" == "" {
		local cause = "neo_nasopharynx"
		local sex = "female"
		local modnum = 151 
	}
	if "`input_directory'" == "" {
		local input_directory = "/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/03_st_gpr"
		local temp_folder = "/ihme/gbd/WORK/07_registry/cancer/04_outputs/01_mortality_incidence/model_outputs"
		capture mkdir "`temp_folder'"
		local output_file = "compiled_cause_output.csv"
	}
	
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" 	global j "/home/j"
	else if c(os) == "Windows" global j "J:"
	
** *************************************************************************	
** COMPILE DATA (Autorun)
** *************************************************************************	
// import data and label with cause name
	di "importing `input_directory'/model_`modnum'/`cause'/`sex'"
	import delimited using "`input_directory'/model_`modnum'/`cause'/`sex'/`output_file'", delim(",") clear asdouble varnames(1)
	capture gen acause = "`cause'"

// drop duplicates and keep only relevant variables
	drop gpr_lower gpr_upper
	duplicates tag ihme_loc_id year age sex, gen(tag)
	count if tag != 0
	drop tag
	rename gpr_mean gpr_prediction
	capture replace gpr_prediction = "" if gpr_prediction == "NA"
	capture destring gpr_prediction, replace
	duplicates drop
	bysort ihme_loc_id year age sex: egen gpr_mean = mean(gpr_prediction)
	drop gpr_prediction
	duplicates drop

// keep relevant variables
	keep gpr_mean ihme_loc_id year sex age acause
	replace gpr_mean = round(gpr_mean, .000001)
	duplicates drop
	
// format sex
	rename sex gender
	gen int sex = 2 if gender == "female"
	replace sex = 1 if gender == "male"
	drop gender
	
// format cause
	replace acause = trim(acause)
	
// format age
	replace age = 2 if age == 0
	replace age = (age/5) + 6 if age != 2
	drop if age == .

// format MI Model result variable
	rename gpr_mean MI_model_result_
	destring MI_model_result_, replace
	
// keep relevant variables
	keep MI_model_result_ ihme_loc_id year sex age acause
	gen modnum = `modnum'

// save
	save "`temp_folder'/model_`modnum'_`cause'_`sex'_MI_model_output.dta", replace


** **********
** End
** ************
