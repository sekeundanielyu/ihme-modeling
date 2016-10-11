
// PURPOSE: Get age group values from SQL database


capture program drop get_ages
program define get_ages
	version 13
	syntax
	
	preserve
	
// prep stata
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

	** odbc load, exec("select age_data,age_start,age_end from age_groups where plot=1") dsn(epi) clear
	** gen age_mdpt = (age_start + age_end) / 2
	import delimited "$prefix/WORK/04_epi/01_database/02_data/_inj/archive_2013/04_models/gbd2013/02_inputs/parameters/automated/for_get_ages.csv", delim(",") asdouble clear
	
	foreach i in age_data age_mdpt {
		levelsof `i', l(`i') clean
	}
	global gbd_ages `age_data'
	global gbd_ages_mdpt `age_mdpt'
	
	restore
	
end
	
	
