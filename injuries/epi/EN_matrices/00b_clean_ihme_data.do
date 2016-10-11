
** Purpose: find all individual-level observations with injury e-code/n-code combinations from the data in here: J:/WORK/06_hospital/01_inputs/sources

clear all
set more off
capture log close
capture restore, not

local check =99
if `check'==1 {
	local 1 "/snfs1"
	local 2 "`1'/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2013/01_code/dev_IB"
	local 3 "`1'/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2013/03_steps/2014_05_30/03b_EN_matrices/02_temp/03_data/00_cleaned"
	local 4 "`1'/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2013/03_steps/2014_05_30/03b_EN_matrices/02_temp/02_logs"
	local 5 "`1'/WORK/04_epi/01_database/01_code/00_library/ado"
}

** import macros
global prefix `1'
local code_dir `2'
local output_data_dir `3'
local log_dir `4'
// Directory of general GBD ado functions
local gbd_ado `5'
// slots used
local slots `6'
// Step diagnostics directory
local diag_dir `7'
// Name for this job
local name `8'

// Import GBD functions
adopath + `gbd_ado'

// start_timer, dir("`diag_dir'") name("`name'") slots(`slots')

// Log
log using "`log_dir'/clean_ihme_data.smcl", replace name(worker)

** set other macros
local hospital_data_dir "$prefix/WORK/06_hospital/01_inputs/sources"
if "$prefix" == "/home/j" set odbcmgr unixodbc

** first get the list of sources to grab
local hospital_dir_list : dir "`hospital_data_dir'" dirs "*"

** loop through the sources
local x=1
foreach source of local hospital_dir_list {
	
	local source=upper("`source'")
	di in red "starting source `source'"
	
	local source_file "`hospital_data_dir'/`source'/data/intermediate/01_mapped.dta"
	di "`source_file'"
	
	** want to use only sources where the "01_mapped.dta" file exists
	capture confirm file "`source_file'"
	
	if !_rc {
		
		display "`source' is ready"
		
		** bring in the data; might be very large so try restricting what you are bringing in to just the variables you need to save some time
		use iso3 year age sex platform *yld_cause* using "`source_file'", clear
		
		** get the list of diagnosis and e-code variables we have in this data set: max number is 10?
		local ecode_list=""
		local ecode_vars=0
		local diagnosis_list=""
		local diagnosis_vars=0
		forvalues i=1/25 {
			capture confirm variable ecode_`i'_yld_cause
			if !_rc {
				local ecode_list = "`ecode_list' " + "ecode_`i'_yld_cause"
				local ++ecode_vars
			}
			capture confirm variable dx_`i'_yld_cause
			if !_rc {
				local diagnosis_list = "`diagnosis_list' " + "dx_`i'_yld_cause"	
				local ++diagnosis_vars
				
			}
					
		}
		count
		display "`source' has `r(N)' observations'"
		** going to generate new variables to put the extracted e-codes and n-codes in. 
		** E-codes can be in either the diagnosis list, or the e-code list, so the maximum number of e-codes that we have is ecode_vars+diagnosis_vars
		local max_ecodes=`ecode_vars'+`diagnosis_vars'
		** N-Codes are only in the diagnosis list, so we will only make that many n-code variables
		local max_ncodes=`diagnosis_vars'
		
		** first generate new ecode variables using the "Ecode" variables, keeping only the cases containing the stem "inj"
		forvalues j=1/`ecode_vars' {
			generate tmp_ecode_`j'=ecode_`j'_yld_cause if regexm(ecode_`j'_yld_cause, "^inj")
			generate has_ecode_`j'=1 if regexm(ecode_`j'_yld_cause, "^inj")
		}
		
		** next generate more ecode variables using the "diagnosis" variables, keeping only the cases containing the stem "inj"
		** need to generate new e-code variables and not write over the old ones
		local ecode_plus=`ecode_vars'+1
		forvalues j=1/`diagnosis_vars' {			
			generate tmp_ecode_`ecode_plus'=dx_`j'_yld_cause if regexm(dx_`j'_yld_cause, "^inj")
			generate has_ecode_`ecode_plus'=1 if regexm(dx_`j'_yld_cause, "^inj")
			local ++ecode_plus
		}
		
		** now we generate n-code variables if the diagnosis variables contain "N" at the beginning - also replacing N29 with N28 because Mohsen said so
		forvalues j=1/`diagnosis_vars' {
			generate tmp_ncode_`j'=dx_`j'_yld_cause if regexm(dx_`j'_yld_cause, "^N")
			generate has_ncode_`j'=1 if regexm(dx_`j'_yld_cause, "^N")
			replace tmp_ncode_`j'="N28" if tmp_ncode_`j'=="N29" & has_ncode_`j'==1
		}
		
		** keep only those that have both ecode and ncode information
		egen confirm_ecode = rowtotal(has_ecode*)
		egen confirm_ncode = rowtotal(has_ncode*)
		keep if confirm_ecode>0 & confirm_ncode>0
		
		** the code below will break if the previous line causes all observations to be dropped, so we add a check
		count
		if `r(N)' > 0 {
			** get the actual maximum number of ecodes and ncodes that any death in this data set has
			summ confirm_ecode
			local true_max_ecodes=`r(max)'
			
			summ confirm_ncode
			local true_max_ncodes=`r(max)'
			
			
			** cycle through the newly generated e-codes, filling in the blank slots so all patients have ecodes in order with no missing values
			forvalues i=1/`true_max_ecodes' {
				generate final_ecode_`i'=""
				
				forvalues j=1/`max_ecodes' {
					
					replace final_ecode_`i'=tmp_ecode_`j' if final_ecode_`i'==""
					replace tmp_ecode_`j'="" if tmp_ecode_`j'==final_ecode_`i'
					
				}
				** end j loop
			}
			** end i loop
			
			drop tmp_ecode_* has_ecode_* confirm_ecode
			
			** cycle through the newly generated n-codes, filling in the blank slots so all patients have ncodes in order with no missing values
			forvalues i=1/`true_max_ncodes' {
				generate final_ncode_`i'=""
				
				forvalues j=1/`max_ncodes' {
					
					replace final_ncode_`i'=tmp_ncode_`j' if final_ncode_`i'==""
					replace tmp_ncode_`j'="" if tmp_ncode_`j'==final_ncode_`i'
					
				}
				** end j loop
			}
			** end i loop
			drop tmp_ncode_* has_ncode* confirm_ncode *yld_cause*

			local source = upper("`source'")
			
			** generate a binary indicator for inpatient/not-inpatient
			generate inpatient=0
			replace inpatient=1 if platform=="Inpatient"
			drop platform
			
			** replace sex with missing
			replace sex=. if sex==9		
			
			** capture mkdir "`output_data_dir'//`source'"
			** save "`output_data_dir'/`source'//`source'.dta", replace
			
			** need to append all of the sources onto one another
			if `x'==1 {
				gen source = "`source'"
				tempfile sources
				save `sources', replace
				local ++x
			}
			
			else {
				gen source = "`source'"
				append using `sources'
				save `sources', replace
				local ++x
			}
	
		}
		** end block for sources with E-N data
	
	}
	** end block for sources where the "01_mapped.dta" file exists
	
	else {
		display "`source' is incomplete today"
	}
	** end block for sources where the "01_mapped.dta" file does not exist


	}
	** end source loop
	
	** save appended/cleaned sources
	compress
	export delimited using "`output_data_dir'/cleaned_ihme_data.csv", delim(",") replace
	
	// end_timer, dir("`diag_dir'") name("`name'")
	
	log close worker
	