// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:	Upload mortality estimates and data to the idie2 database
// Code:		do "strPath/create_idie_dev.do"

// prep stata
	clear all
	set more off
	set maxvar 32000
	set mem 1g
	if c(os) == "Unix" {
		global prefix "/home/j/"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
		local db "strDb"
	}
	
	local out_dir "strPath" 
	// local out_dir "../_exclude/data"
	// local current_data "strPath" // "../_exclude/data" // 
	local current_data "strPath"
	// local out_dir "strPath"
	// local current_data "strPath"
	// local db "strDb"

/*
// get file SHA1 digest for version tracking
	// insheet using "strURL", clear comma
	// insheet using "strURL"
	qui insheet using "strURL", delimiter(",")	
	gen version_process = process	
	sort process
	
	if loaded[1] == float(0) local ver_45q15 = string(version_id[1])

	di "versions: `ver_45q15'"	
	
	tempfile sha1s
	save `sha1s', replace
*/

	local date = c(current_date)
	local time = c(current_time)
	odbc exec("insert into idie_versions (description, status, assignee) values('45q15 `date' `time'',1,'45q15_est')"), dsn(`db') 
	// Grab the version that you just created
	odbc load, exec("select version_id from idie_versions where description = '45q15 `date' `time''") dsn(`db')
	local ver_45q15 = version_id[1]
	di in red "version is `ver_45q15'"

// prep type list
	odbc load, exec("select * from idie_types_versioned ORDER BY type_id") dsn(`db') clear
	replace type_short=lower(type_short)
	tempfile types
	save `types', replace

// prep method list
	odbc load, exec("select * from idie_methods_versioned ORDER BY method_id") dsn(`db') clear
	tempfile methods
	save `methods', replace

// prep cleaned citation list
	* insheet using "strPath/cod_mortality_citations_korea.csv", comma clear
	* changed to bring in the new citation list. - CEL 3/20/2014
	insheet using "strPath/source-id_source-citation_link.csv", comma clear
	rename suggested_mortality_citation source_citation
	keep source_id source_citation
	duplicates drop
	tempfile citations
	save `citations', replace
	
	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// MODELS:  45q15


// load 45q15 estimates as needed
if "`ver_45q15'" != "" {
	di "(re)loading (`ver_45q15')"

	use "`current_data'/estimates_45q15.dta", clear
	gen process = "45q15"

	foreach variable of varlist sex iso3 {
		decode `variable', generate( `variable'2)
		drop `variable'
		rename `variable'2 `variable'
	}
	
	order iso3 sex, first
	tempfile adults
	save `adults', replace	
}


if "`ver_45q15'" != "" {
	use `adults'

	// merge m:1 iso3 using `countries', keep(3) nogen
	keep if year >= 1949.5 & year <= 2013.5
	replace sex = "1" if sex == "male"
	replace sex = "2" if sex == "female"
	replace sex = "3" if sex == "both"
	destring sex, replace
	rename pred_1b mean_stage1
	rename pred_2_final mean_stage2
	rename gpr_med mean_gpr
	rename gpr_lower lower_gpr
	rename gpr_upper upper_gpr
	rename shocks_med mean_shock
	rename shocks_lower lower_shock
	rename shocks_upper upper_shock

	// gen id="NULL"
	gen version_id = `ver_45q15'

	drop if version_id==. | year==.
	drop if process != "45q15" 

	// upload data
	keep version_id iso3 year sex process mean_stage1 mean_stage2 mean_gpr lower_gpr upper_gpr mean_shock lower_shock upper_shock hivfree wpp
	order version_id iso3 year sex process mean_stage1 mean_stage2 mean_gpr lower_gpr upper_gpr mean_shock lower_shock upper_shock hivfree wpp
	sort iso3 year sex process
	format mean* upper* lower* %15.0g
	compress

	outsheet using "`out_dir'/idie_models_versioned.txt", replace nolabel noquote nonames
		
	odbc exec("DELETE FROM idie_models_versioned WHERE version_id IN (0,`ver_45q15');"), dsn(`db')
	odbc exec("LOAD DATA LOCAL INFILE '`out_dir'/idie_models_versioned.txt' INTO TABLE idie_models_versioned FIELDS TERMINATED BY '\t' LINES TERMINATED BY '\n' (version_id,iso3,year,sex,process,mean_stage1,mean_stage2,mean_gpr,lower_gpr,upper_gpr,mean_shock,lower_shock,upper_shock,hivfree,wpp);"), dsn(`db')
}

