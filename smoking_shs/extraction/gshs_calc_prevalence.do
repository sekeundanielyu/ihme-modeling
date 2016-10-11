** Date: August 8, 2013
** Purpose: Calculate prevalence
	
** Set up
	clear *
	set more off
	if "`c(os)'" == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else {
		global j "J:"
	}

** id surveys
	clear *
	set more off
	if "`c(os)'" == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else {
		global j "J:"
	}
	set more off
	cd "$j/DATA/WHO_STEP_GSHS"
	local gshs "$j/DATA/WHO_STEP_GSHS"
	local isofolders: dir "`gshs'" dirs "*", respectcase
	set obs 1000
	local iter=1
	gen filepath=""
	gen filenames=""
	foreach c of local isofolders {
		local yearfolders: dir "`gshs'/`c'" dirs "*", respectcase
		foreach y of local yearfolders {
			local filenames: dir"`gshs'/`c'/`y'" files "*.DTA", respectcase
			foreach file of local filenames{
				replace filenames="`file'" if _n==`iter'
				replace filepath="`gshs'/`c'/`y'" if _n==`iter'
				local iter= `iter' + 1
			
			}	
				
		}
	}
	
	drop if filepath==""
	gen file=filepath + "/" + filenames
	split file, p(_)
	gen national=""
	replace national="National" if file6==""
	replace national="Subnational" if file6!=""
	replace file6=subinstr(file6, ".DTA", "", .)
	rename file6 city
	replace city="National" if city==""
	split filenames, p(_)
	rename filenames1 iso3
	rename filenames2 survey
	split filenames3, p(/)
	split filenames31, p(.)
	rename filenames311 year
	keep filepath filenames file national iso3 survey year city
	
	// Iso3 codes have changed since 2013 for islands and assign China subnationals 
	replace iso3 = "VIR" if iso3 == "VGB"
	tempfile data
	save `data', replace
	/*
	clear
	odbc load, exec("select iso3,country_name as country from id_countries where reporting=1") dsn(codmod) clear
    expand 3 if iso3 == "IND"
    bysort iso3: gen copy = _n
    replace iso3 = "XIR" if iso3 == "IND" & copy == 1
    replace iso3 = "XIU" if iso3 == "IND" & copy == 2
    replace country = "India Rural" if iso3 == "XIR"
    replace country = "India Urban" if iso3 == "XIU"
    drop copy
	merge 1:m iso3 using `data'
	drop if _m==1
	drop _m
	*/
	
	clear
	#delim ;
	odbc load, exec("SELECT ihme_loc_id, location_name, location_id, location_type
	FROM shared.location_hierarchy_history 
	WHERE (location_type = 'admin0' OR location_type = 'admin1' OR location_type = 'admin2')
	AND location_set_version_id = (
	SELECT location_set_version_id FROM shared.location_set_version WHERE 
	location_set_id = 9
	and end_date IS NULL)") dsn(epi) clear;
	#delim cr
	
	rename ihme_loc_id iso3
	drop location_type location_id 
	
	merge 1:m iso3 using `data'
	
	drop if _m != 3
	drop _m 
	replace year = "2010" if iso3 == "DZA"
	replace year = "2006" if iso3 == "TZA"
	cd "J:/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw"
	sort iso3 year
	rename location_name country
	save "GSHS_FILES.DTA", replace
	
** calculate prev
	clear
	use "./GSHS_FILES.DTA"
	replace file = subinstr(file, "/home/j", "J:", .)
	mata: files=st_sdata(., "file")
	mata: year=st_sdata(., "year")
	mata: country=st_sdata(., "country")
	mata: iso3=st_sdata(., "iso3")
	mata: city=st_sdata(., "city")
	local iter=1
	foreach gender in "Male" "Female" {
		forvalues q=1(1)110 {
			mata: st_local("file", files[`q', 1])
			mata: st_local ("country", country[`q', 1])
			mata: st_local("year", year[`q', 1])
			mata: st_local("city", city[`q', 1])
			mata: st_local("iso3",iso3[`q',1])
			use "`file'", clear
			// rename all variables lowercase
			renvars *, lower
		
			// rename *, lower
			cap decode q2, gen(gender)
			cap gen gender = "Male" if q2 == "1"
			cap replace gender = "Female" if q2 == "2"
			// cap decode q2, g(gender)
			destring q*, replace force
			
			gen agegrp=.
			replace agegrp=1 if q1<5
			replace agegrp=2 if q1>=5 & q1!=.
			describe q28
			destring q28, replace force
			gen smoker = 0
			replace smoker = 1 if q28 > 1
			replace smoker=. if q28==.
			describe qn33
			gen shs=0
			replace shs=1 if qn33==1
			replace shs=0 if qn33==2
			replace shs=. if qn33==.
			// check for variables that are all missing
			egen check=total(qn33)
			replace shs=0 if check==0
			egen check_2=total(qn28)
			replace smoker=0 if check_2==0
			
			gen Lower_Bound=.
			gen Upper_Bound=.
			gen mean_smok=.
			gen standard_error=.
			
			keep if gender=="`gender'"
			forvalues m=1(1)2 {
				capture mean smoker if agegrp==`m'
				if _rc {
					replace mean_smok=0 if agegrp==`m'
					continue
				}
				svyset psu [pweight=weight]
				svy linearized, subpop(if agegrp==`m' & smoker==0): mean shs
				matrix mean_matrix=e(b)
				matrix variance_matrix=e(V)
				local mean=mean_matrix[1,1]
				local var=variance_matrix[1,1]
				local SE=sqrt(`var')
				replace standard_error=`SE' if agegrp==`m'
				replace mean_smok=`mean' if agegrp==`m'
				replace Upper_Bound=`mean' + 1.96*`SE' if agegrp==`m'
				replace Lower_Bound=`mean' - 1.96*`SE' if agegrp==`m'
			}
			replace Lower_Bound=0 if Lower_Bound<0
			replace Upper_Bound=1 if Upper_Bound>1 & Upper_Bound<.
			count
			local total=`r(N)'
			gen sample_size=`total'
			gen age_sex_ss=.
			forvalues u=1(1)2 {
				count if agegrp==`u'
				replace age_sex_ss=`r(N)' if agegrp==`u'
			}
			count if smoker==.
			local pctmiss=`r(N)'/`total'
			gen pctmiss=`pctmiss'
			tostring pctmiss, replace force
			gen pctmiss1=substr("pctmiss", 0, 4)
			local pctmiss= substr(pctmiss, 1, 4)
			keep  mean_smok Upper_Bound Lower_Bound agegrp pctmiss sample_size age_sex_ss gender standard_error
			gen iso3 = "`iso3'"
			gen country="`country'"
			gen year="`year'"
			destring year, replace
			drop if mean_smok==.
			sort country year agegrp
			gen city="`city'"
			by country year agegrp: gen keep=_n
			keep if keep==1
			drop keep
			gen orig_file="`file'"
			drop sample_size
			rename age_sex_ss sample_size
			gen ss_level = "age_sex"
			gen sex = 1 if gender == "Male"
			replace sex = 2 if gender == "Female"
			rename Lower lower
			rename Upper upper
			rename mean_smok prevalence
			if "`city'" == "National" gen national = 1
			else gen national = 0
			drop city 
			gen source = "micro - gshs"
			gen age_start = 10 if agegrp == 1
			gen age_end = 14 if agegrp == 1
			replace age_start = 15 if agegrp == 2
			replace age_end = 18 if agegrp == 2
			gen subnational_area = "`city'"
			save "J:/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/gshs/`gender'_`country'_`year'_`city'_GSHS.dta", replace
		}
		}
		


// append
	clear
	cd "J:/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/gshs/"

	local i=0
	cap erase shs_gshs.dta
	local files : dir . files "*.dta"

	foreach f of local files {
		drop _all
		use "`f'"
		if `i'>0 append using shs_gshs
		save shs_gshs, replace
		local i=1
		}
		

tempfile shs_gshs
save `shs_gshs', replace

// drop where prevalence==0 because this occurs when there were no observations
drop if prevalence==0

// Remap Chinese cities to subnationals 
	// Hangzhou is in the Zhejiang province; Beijijng to Beijing; Wurumqi is in the Shanxi province; Wuhan in the Hubei province

	replace iso3 = "CHN_521" if subnational_area == "HANGZHOU" 
	replace iso3 = "CHN_492" if subnational_area == "BEIJING" 
	replace iso3 = "CHN_515" if subnational_area == "WURUMQI" 
	replace iso3 = "CHN_503" if subnational_area == "WUHAN" 

// Fix surveys marked as subnational vs. national because the coding had previously not been capturing all of the national surveys 

	replace national = 1 if regexm(subnational, "[0-9][0-9][0-9][0-9]") == 1 
 	replace national = 1 if subnational_area == "NATIONAL" 
 	replace subnational_area = "URBAN" if subnational_area == "MALE" // capital of Maldives 
 	replace subnational_area = "RURAL" if subnational_area == "ATOLLS" 

save "J:/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped/gshs_prepped_revised.dta", replace


