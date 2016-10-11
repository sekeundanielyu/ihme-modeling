********************************************************
** Description: Compile populations to be used as denominators 
** 
********************************************************

** **********************
** Set up Stata 
** **********************
	clear all
	capture cleartmp 
    cap restore, not
	set mem 500m
	set more off

** **********************
** Filepaths 
** **********************
	if (c(os)=="Unix") global root "/home/j"	
	if (c(os)=="Windows") global root "J:"
    if "$end_year" == "" global end_year 2015
	
    global ihme_pop_file "strPath/population_gbd$end_year.dta"	
	global ddm_pop_file "strPath/d01_formatted_population.dta"
	global save_file "strPath/d09_denominators.dta"
	
	adopath + "$root/Project/Mortality/shared/functions"


** **********************
** Set up country codes file 
** **********************
	get_locations
	keep location_name ihme_loc_id region_name location_id
	tempfile codes
	save `codes', replace

** **********************
** Format IHME National Populations 
** **********************
	use "$ihme_pop_file", clear
	drop age_group_id sex_id location_name location_id // Location IDs will get added later
	drop if regexm(age_group_name,"Neonatal")
	drop if age_group_name == "All Ages" // Don't need this aggregate at all
	replace age_group_name = "0to0" if age_group_name == "<1 year"
	replace age_group_name = subinstr(age_group_name," ","",.)
	rename pop c1_
	reshape wide c1_, i(ihme_loc_id year sex source) j(age_group_name) string
	
	gen c1_0to4 = c1_0to0 + c1_1to4

	rename source pop_source
	gen source_type = "IHME" 
	tempfile ihme
	save `ihme', replace

** **********************
** Format source-specific populations 
** **********************
	use "$ddm_pop_file", clear
    
    drop if source_type == "CENSUS" & ihme_loc_id != "CHN_44533" & !regexm(ihme_loc_id,"CHN_") & !regexm(ihme_loc_id,"MEX_") & !regexm(ihme_loc_id,"GBR_")  // Keep all GBD2010 subnational census data because we like that better than the GBD pop estimates, but otherwise we like GBD pops better
    drop if source_type == "CENSUS" & ihme_loc_id == "GBR_4749" // Drop England, if it's there
	replace source_type = "SRS" if regexm(source_type, "SRS")==1
	replace source_type = "DSP" if regexm(source_type, "DSP")==1
	drop month day pop_footnote agegroup* 
	
	drop if source_type == "SRS" & inlist(ihme_loc_id, "PAK", "BGD") 
	
	gen c1_0to0 = pop0
	gen c1_1to4 = pop1+pop2+pop3+pop4
	gen c1_0to4 = c1_0to0 + c1_1to4
	forvalues j=5(5)80 { 
		local j_plus = `j'+4
		egen c1_`j'to`j_plus' = rowtotal(pop`j'-pop`j_plus')
	} 
	egen c1_80plus = rowtotal(pop80-pop100)
	drop pop0-pop100
	keep ihme_loc_id country sex year source_type pop_source c1* pop_nid
	
	append using `ihme'
	drop country*
	
** **********************
** Make country-specific changes 
** **********************
** Oman: For the year 2009, deaths were gathered until July 2009. Because of this, we must multiply the number of 
**            person years by 7/12, or .583. This will give us the person-years for that fractional year. For the year 2004, 
**            deaths were gathered from May onward. Because of this, we must multiply the number of
**            person years by 8/12, or .666. This will give us the person-years for that fractional year.
	foreach newpop of varlist c1* {
		// replace `newpop'=`newpop'*.583 if ihme_loc_id=="OMN" & year==2009 // Taking this out as we are now using a WHO 2009 source that appears to be consistent over time. 
		replace `newpop'=`newpop'*.666 if ihme_loc_id=="OMN" & year==2004
	}
	
** **********************
** Format and save file 
** **********************
	
** get regions and country names
	merge m:1 ihme_loc_id using `codes'
	keep if _m == 3
	drop _m 
	
** get both sexes if it's missing 
	preserve
	drop if sex == "both"
	gen count = 1
	collapse (sum) c1* count, by(region_name location_name location_id ihme_loc_id year source_type pop_source pop_nid)
	keep if count == 2
	drop count 
	gen sex = "both"
	tempfile both
	save `both'
	restore
	
	gen temp = 1
	append using `both' 
	duplicates tag ihme_loc_id location_id year sex source_type, gen(d)
	drop if d > 0 & temp == . 
	drop d temp
	
** save
	keep location_id location_name region_name ihme_loc_id year sex source_type pop_source pop_nid c*
    order location_id location_name region_name ihme_loc_id year sex source_type pop_source pop_nid c*
	sort ihme_loc_id year sex source_type
	save "$save_file", replace

