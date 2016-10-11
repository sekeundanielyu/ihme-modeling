
// PURPOSE: Get age group values from SQL database and save to the inputs folder so you don't have to query the SQL server every time you use load_params



capture program drop save_ages
program define save_ages
	version 13
	syntax , input_folder(string)
	
	preserve
	
// prep stata
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

	odbc load, exec("select age_data,age_start,age_end from age_groups where plot=1") dsn(epi) clear
	gen age_mdpt = (age_start + age_end) / 2
	
	foreach i in age_data age_mdpt {
		levelsof `i', l(`i') clean
	}
	global gbd_ages `age_data'
	global gbd_ages_mdpt `age_mdpt'
	
	export delimited "`input_folder'/for_get_ages.csv", delim(",") replace
	
	restore
	
end
	
	
