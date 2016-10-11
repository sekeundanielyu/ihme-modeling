	
	clear
	set more off, perm
	
// Import macros
local check=99
if `check'==1 {
	if c(os) == "Unix" {
		set odbcmgr unixodbc
	}
	local 1 "/snfs1"
	local 2 "`1'/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015"
	local 3 "/snfs2/HOME/ngraetz/local/inj/gbd2015"
	local 4 "EN_matrices"
	local 5 "/clustertmp/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/03b_EN_matrices/02_temp/03_data/00_cleaned"
	local 6 "/clustertmp/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/03b_EN_matrices/02_temp/03_data/01_prepped"
	local 7 0 1 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80
	local 8 "/clustertmp/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/03b_EN_matrices/02_temp/03_data"
	local 9 "`1'/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/03b_EN_matrices/02_temp/02_logs"
	local 10 "`1'/WORK/04_epi/01_database/01_code/00_library/ado"
}
	global prefix `1'
	local inj_dir `2'
	local code_dir `3'
	local step_name `4'
	local cleaned_dir `5'
	local prepped_dir `6'
	local ages `7'
	local data_dir `8'
	local log_dir `9'
	// Directory of general GBD ado functions
	local gbd_ado `10'
	// Step diagnostics directory
	local diag_dir `11'
	
// a) Clean (and prep) 2010 expert group data
	cap confirm file "`prepped_dir'/prepped_expert_group_en_data.csv"
	do "`code_dir'/`step_name'/00a_clean_and_prep_EN_data_from_expert_group_2010.do" $prefix "`inj_dir'" "`prepped_dir'" "`ages'" `code_dir'


// b) Clean IHME hospital data: as of 2/28/2014 new hospital data sets have been added that are very large(32.4 gb), so we need to run this on the cluster, allocating enough memory for the job to run
		** check if latest cleaned IHME data was created AFTER all of the hospital data were uploaded
		capture ssc install dirlist
		
		local hospital_data_dir "$prefix/WORK/06_hospital/01_inputs/sources"
	
		** first get the list of sources to grab
		local hospital_dir_list : dir "`hospital_data_dir'" dirs "*"
		
		capture confirm file "`cleaned_dir'/cleaned_ihme_dataaa.csv"
		if _rc {
			if c(os) == "Unix" {
				local mem 32.4
				local slots = 100
				local mem = 200
				local name IHME_hosp_EN_data
				! qsub -N `name' -P proj_injuries -pe multi_slot `slots' -l mem_free=`mem' "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh" "`code_dir'/`step_name'/00b_clean_ihme_data.do" "$prefix `code_dir' `cleaned_dir' `log_dir' `gbd_ado' `slots' `diag_dir' `name'"
			}
			else {
				di in red "please clean these data sets by running this code on the cluster, as they may be too large"
				di in red "these data sets need to be cleaned: `sources'"
				BREAK
			}		
		
		}
		else {
			** loop through the sources
			local x=1
			foreach source of local hospital_dir_list {
				local dir_date ""
				local source=upper("`source'")
				di in red "checking source `source'"
				local source_file "`hospital_data_dir'//`source'/data/intermediate/01_mapped.dta"
				
				** want to use only sources where the "01_mapped.dta" file exists
				capture confirm file "`source_file'"
				di "`source_file'"
				
				if !_rc {
					di "`source_file'"
					** get a list of the dates that all of these sources were modified
					** IMPORTANT: in WINDOWS THE DIRLIST FUNCTION REQUIRES THE FILE PATH TO HAVE BACK SLASHES INSTEAD OF FORWARD SLASHES. DO NOT CHANGE THIS.
					if c(os)=="Windows" {
						local source_file = subinstr("`source_file'", "/" , "\", .)
					}
					
					dirlist "`source_file'"
					local dir_date `r(fdates)'
					
					if `x'==1 {
						clear
						set obs 1
						gen source = "`source'"
						gen date = date("`dir_date'","MDY")
						tempfile file_date_list
						save `file_date_list', replace
						local ++x
					}
					
					else {
						use `file_date_list', clear
						set obs `x'
						replace source = "`source'" in `x'
						replace date = date("`dir_date'","MDY") in `x'
						save `file_date_list', replace
						local ++x
					}
			
					}
					** end _rc loop for checking in 01_mapped.do files exist
						
			}
			** end source file loop
			use `file_date_list', clear
			** IMPORTANT: in WINDOWS THE DIRLIST FUNCTION REQUIRES THE FILE PATH TO HAVE BACK SLASHES INSTEAD OF FORWARD SLASHES. DO NOT CHANGE THIS.
			if c(os)=="Windows" {
				local check_file = subinstr("`cleaned_dir'/cleaned_ihme_data.csv", "/", "\", .)
			}
			else {
				local check_file = "`cleaned_dir'/cleaned_ihme_data.csv"
			}
			
			di "`check_file'"
			
			dirlist "`check_file'"
			return list
			
			gen last_cleaned=date("`r(fdates)'", "DMY")		
			count if last_cleaned < date
			local tot_unp = `r(N)'
			levelsof source if last_cleaned < date, local(sources)
			
			if `tot_unp' > 0 {
				if c(os) == "Unix" {
					local mem 32.4
					local slots = ceil(`mem'/2)
					local mem = `slots' * 2
					local name IHME_hosp_EN_data
					! qsub -N `name' -pe multi_slot `slots' -l mem_free=`mem' "$prefix/WORK/04_epi/01_database/01_code/00_library/stata_shell.sh" "`code_dir'/`step_name'/00b_clean_ihme_data.do" "$prefix `code_dir' `cleaned_dir' `log_dir' `gbd_ado' `slots' `diag_dir' `name'"
				}
				else {
					di in red "There are `r(N)' hospital data sets from IHME that have not been cleaned"
					di in red "please clean these data sets by running this code on the cluster, as they may be too large"
					di in red "these data sets need to be cleaned: `sources'"
					BREAK
				}
			}
			
			else {
				di "All available IHME hospital datasets have already been cleaned"
			}
		}
		
// c) Clean Chinese data (only do so if cleaned data is not present b/c this will not work when run centrally unless person running has permissions for limited use folder)
	cap confirm file "`cleaned_dir'/cleaned_chinese_niss.csv"
	if _rc do "`code_dir'/`step_name'/00c_clean_chinese_niss.do" $prefix "`data_dir'"
	
// d) Clean Chinese surveillance data (ICSS) (only do so if cleaned data is not present b/c this will not work when run centrally unless person running has permissions for limited use folder)
	cap confirm file "`cleaned_dir'/cleaned_chinese_icss.csv"
	if _rc do "`code_dir'/`step_name'/00d_clean_chinese_icss.do" $prefix "`code_dir'" "`cleaned_dir'" "`log_dir'"
	
// e) Clean NLD data
	do "`code_dir'/`step_name'/00e_clean_nld_data.do" $prefix "`cleaned_dir'"

// f) Clean HDR data 
	do "`code_dir'/`step_name'/00f_clean_hdr.do" $prefix "`code_dir'" "`cleaned_dir'" "`log_dir'"
	
// g) Clean Argentina data
	do "`code_dir'/`step_name'/00g_clean_argentina.do" $prefix "`code_dir'" "`cleaned_dir'" "`log_dir'"
	
	
// confirm that cluster job is done before moving to next step	
	local check_file = "`cleaned_dir'/cleaned_ihme_data.csv"
	local i = 0
	while `i' == 0 {
		capture confirm file "`check_file'"
		if (!_rc) continue, break
		else sleep 60000
	}
	
	di in red "00_clean_en_data done"
	