** *************************************************************************
** Description: Compile estimates of 45q15 from all sources
** *************************************************************************

** **********************
** Set up Stata 
** **********************

	clear all
    cap restore, not
	capture cleartmp
	set mem 500m
	set more off
	pause on
	
	if (c(os)=="Unix") global root "/home/j"
	if (c(os)=="Windows") global root "J:"

	adopath + "strPath"
	get_locations
	rename local_id_2013 iso3
	rename location_name country
	replace iso3 = ihme_loc_id if iso3 == ""
	keep iso3 ihme_loc_id country location_id
	tempfile iso3_map
	save `iso3_map'
	

** **********************
** Add in DDM and growth balance files 
** **********************	
	cd "strPath"

** Main DDM file
// This file has death NID and pop nid, but to my knowledge, we only use death NID for citations, so we just use that

	use "d10_45q15.dta", clear
	gen exposure = c1_15to19 + c1_20to24 + c1_25to29 + c1_30to34 + c1_35to39 + c1_40to44 + c1_45to49 + c1_50to54 + c1_55to59
	cap rename deaths_nid nid
	keep ihme_loc_id year sex deaths_source source_type comp sd adjust adj45q15 obs45q15 exposure nid
	destring nid, replace force


** **********************
** Add in China DSP data
** **********************	

	** We don't have age specific deaths or mortality rates, so instead we're using 
	** an approximation of the qx - mx relationship to appropriately correct the provided 45q15
	** and convert to 45q15. 
	preserve
	use "d08_smoothed_completeness.dta", clear
	keep if iso3_sex_source == "CHN_44533_both_DSP" & inlist(year, 1986, 1987, 1988)
	keep year pred2 sd	
	rename pred2 comp
	tempfile comp
	save `comp'
	insheet using "strPath/CHN_DSP_1986_1988_45q15.CSV", clear
	rename v1 ihme_loc_id
	replace ihme_loc_id = "CHN_44533"
	rename v2 year
	rename v3 sex
	rename v4 obs45q15
	merge m:1 year using `comp'
	drop _m 
	gen adj45q15 = 1-exp((1/comp)*ln(1-obs45q15))
	gen adjust = 1
	gen source_type = "DSP"
	gen deaths_source = "DSP"
	* drop obs45q15
	tempfile china
	save `china'
	restore
	append using `china'
	
	gen exclude = 0


** **********************
** Add in SIBS
** **********************

	preserve 
	use "strPath/EST_GLOBAL_SIB_45q15s.dta", clear
	gen adjust = 0
	gen exclude = 0
	// replace exclude = 1 if svy == "COG_2011"
	// replace exclude = 1 if svy == "GAB_2012"
	gen source_type = "SIBLING_HISTORIES"
	drop if adj45q15 == . // Subnationals that don't compute -- we drop here
	drop adj45q15_*
    cap drop svy
	tempfile sibs
	save `sibs', replace 
	restore
	append using `sibs'

** **********************
** Add in aggregate points from reports (no microdata)
** **********************
	cd "strPath"

	preserve
	use "strPath/BGD BMMS 2010/BGD_BMMS_2010_45q15.dta", clear
	append using "strPath/ifls_45q15s.dta"
	append using "strPath/EST_SUSENAS_1996_v45q15.dta"
	append using "strPath/EST_SUSENAS_1998_v45q15.dta"
	append using "strPath/various_45q15s.dta" 
	append using "strPath/EST_PCFPS_VNM_HHDeaths_v45q15.dta"
	append using "strPath/china_life_table_1973_1975_aggregate_45q15.dta"
    append using "strPath/USABLE_45q15_PAK_DEMOGRAPHIC_SURVEY_1991_2005.dta"
    
	keep iso3 sex year source_type deaths_source adjust adj45q15
	
	// Merge on ihme_loc_id
	merge m:1 iso3 using `iso3_map', keep(1 3) nogen keepusing(ihme_loc_id)
	drop iso3
	
	replace ihme_loc_id = "CHN_44533" if ihme_loc_id == "CHN" & inlist(deaths_source,"FERTILITY_SURVEY","EPI_SURVEY") // Relabel fertility survey and epi survey
	
	replace adjust = 0 
	replace source_type = "HOUSEHOLD_DEATHS" 
	tempfile other
	save `other', replace 
	restore
	append using `other'

** **********************
** Mark shocks 
** **********************

	gen shock = 0

	replace shock = 1 if ihme_loc_id == "ALB" & floor(year) == 1997
	replace shock = 1 if ihme_loc_id == "ARM" & year == 1988
	replace shock = 1 if ihme_loc_id == "BGD" & floor(year) == 1975
	replace shock = 1 if ihme_loc_id == "COG" & floor(year) == 1997 // Civil war
    replace shock = 1 if ihme_loc_id == "CYP" & sex == "male" & floor(year) == 1974
   //  replace shock = 1 if ihme_loc_id == "DOM" & floor(year) == 2010    
    replace shock = 1 if ihme_loc_id == "GTM" & floor(year) == 1981
	replace shock = 1 if ihme_loc_id == "HRV" & (floor(year) == 1991 | floor(year) == 1992)
	replace shock = 1 if ihme_loc_id == "HUN" & floor(year) ==1956
	replace shock = 1 if ihme_loc_id == "IDN" & floor(year)>=1963 & floor(year) <= 1966
	replace shock = 1 if ihme_loc_id == "IDN" & source_type == "SIBLING_HISTORIES" & year == 2004.5 // changed from 2004-2006 to 2004 only now that we're not as concerned with pooled effect issues
	replace shock = 1 if ihme_loc_id == "IRQ" & floor(year) >= 2003 & floor(year) <= 2013  
    replace shock = 1 if ihme_loc_id == "JPN" & source_type == "VR" & floor(year) == 2011
	replace shock = 1 if ihme_loc_id == "LKA" & floor(year) == 1996
	replace shock = 1 if ihme_loc_id == "PAN" & floor(year) == 1989
	replace shock = 1 if ihme_loc_id == "PRT" & (floor(year) == 1975 | floor(year) == 1976)
	replace shock = 1 if ihme_loc_id == "RWA" & (floor(year) == 1994 | floor(year) == 1993)
	replace shock = 1 if ihme_loc_id == "SLV" & (floor(year) >= 1980 & floor(year) <= 1983) & source_type == "VR" 
	replace shock = 1 if ihme_loc_id == "TJK" & floor(year) == 1993   
	replace shock = 1 if ihme_loc_id == "TLS" & floor(year) == 1999
    replace shock = 1 if ihme_loc_id == "MEX_4651" & floor(year) == 1985
	
	// Japanese Earthquakes (Fukushima and other one)
	replace shock = 1 if ihme_loc_id == "JPN_35426" & floor(year) == 2011
	replace shock = 1 if ihme_loc_id == "JPN_35427" & floor(year) == 2011
	replace shock = 1 if ihme_loc_id == "JPN_35430" & floor(year) == 2011
	replace shock = 1 if ihme_loc_id == "JPN_35451" & floor(year) == 1995
	

** **********************
** Mark outliers 
** **********************

	replace exclude = 0 if exclude == .

	replace exclude = 1 if ihme_loc_id == "AFG" & source_type == "SIBLING_HISTORIES" & deaths_source == "DHS" // Not nationally representative survey
	replace exclude = 1 if ihme_loc_id == "AGO" & source_type == "VR" & year <=1965 & year >= 1961 
	replace exclude = 1 if ihme_loc_id == "AND" & source_type == "VR" & year <= 1952
	// replace exclude = 1 if ihme_loc_id == "AUT" & source_type == "VR" & year == 1983 was an errror in VR file now corrected

	replace exclude = 1 if ihme_loc_id == "BFA" & source_type == "SURVEY" & year == 1960
	replace exclude = 1 if ihme_loc_id == "BGD" & source_type == "SURVEY"
	replace exclude = 1 if ihme_loc_id == "BGD" & deaths_source == "DHS 2001" & year == 2001
	replace exclude = 1 if ihme_loc_id == "BGD" & source_type == "SRS" & inlist(year, 1982, 1990, 2002)
	replace exclude = 1 if ihme_loc_id == "BLR" & deaths_source == "HMD" & inlist(year,2012,2013,2014) 
	// replace exclude = 1 if ihme_loc_id == "BRA" & source_type == "SIBLING_HISTORIES" & year <= 1990.5 & sex == "male"
	replace exclude = 1 if ihme_loc_id == "BRA" & source_type == "CENSUS" & year == 2010
	replace exclude = 1 if regexm(ihme_loc_id,"BRA_") & deaths_source == "dhs_bra" // Really crazy DHS household
	// replace exclude = 1 if ihme_loc_id == "BRA_4776" & source_type == "SIBLING_HISTORIES" & year < 1986 & year > 1981
	replace exclude = 1 if ihme_loc_id == "BRA_4755" & source_type == "VR" & year < 1986 // VR scale-up?
	replace exclude = 1 if ihme_loc_id == "BRA_4758" & source_type == "VR" & (year < 1983 | inlist(year,1990,1991)) // VR Scale-up and then weird jagged pattern
	replace exclude = 1 if ihme_loc_id == "BRA_4759" & source_type == "VR" & year < 1985 // Starts super low then goes super high
	replace exclude = 1 if ihme_loc_id == "BRA_4761" & source_type == "VR" & year == 1979
	replace exclude = 1 if ihme_loc_id == "BRA_4763" & source_type == "VR" & year == 1979
	replace exclude = 1 if ihme_loc_id == "BRA_4767" & source_type == "VR" & year < 1982 // Assume VR scale-up issues, very low
	replace exclude = 1 if ihme_loc_id == "BRA_4769" & source_type == "VR" & year == 1979
	replace exclude = 1 if ihme_loc_id == "BRA_4776" & source_type == "VR" & year == 1990
	replace exclude = 1 if ihme_loc_id == "BRN" & year < 1960.5
	replace exclude = 1 if ihme_loc_id == "BTN" & year == 2005 & source_type == "CENSUS"
    replace exclude = 1 if ihme_loc_id == "BWA" & deaths_source == "21970#bwa_demographic_survey_2006" & year == 2006
    replace exclude = 1 if ihme_loc_id == "BWA" & deaths_source == "DYB" & inlist(year,2001,2007)
	replace exclude = 1 if ihme_loc_id == "BWA" & source_type == "HOUSEHOLD" & year == 1981

	replace exclude = 1 if ihme_loc_id == "CAF" & source_type == "SIBLING_HISTORIES" & year == 1984.5
    // replace exclude = 1 if ihme_loc_id == "CHL" & source_type == "VR" & year == 2011
	replace exclude = 1 if ihme_loc_id == "CHN_44533" & source_type == "DSP" & year <= 1994
	replace exclude = 1 if ihme_loc_id == "CHN_361" & year < 1970 & adj45q15 > 0.4
	replace exclude = 1 if ihme_loc_id == "CHN_361" & source_type == "VR" & year < 1970 // Macao -- looks really high
	replace exclude = 1 if ihme_loc_id == "CMR" & deaths_source == "105633#CMR 1976 Census IPUMS" & source_type == "household" & year == 1976
	// replace exclude = 1 if ihme_loc_id == "COD" & source_type == "SIBLING_HISTORIES" & year == 1996.5
	replace exclude = 1 if ihme_loc_id == "COL" & source_type == "VR" & (year == 1979 | year == 1980)
	replace exclude = 1 if ihme_loc_id == "COG" & year == 1984 & source_type == "HOUSEHOLD"
	replace exclude = 1 if ihme_loc_id == "CPV" & source_type == "VR" & year < 1980
	replace exclude = 1 if ihme_loc_id == "CYP" & source_type == "VR" & year == 1975 & sex == "female"

    replace exclude = 1 if ihme_loc_id == "DOM" & source_type == "VR" & deaths_source == "WHO_causesofdeath" & year >= 2006 & year <= 2009
    replace exclude = 1 if ihme_loc_id == "DOM" & deaths_source == "DOM_ENHOGAR" & year==2001
    replace exclude = 1 if ihme_loc_id == "DOM" & deaths_source == "77819#DOM_DHS_2013" & year==2011
	replace exclude = 1 if ihme_loc_id == "DZA" & source_type == "HOUSEHOLD" & year == 1991 // Algerian PAPCHILD -- just too low compared to all other years around it
    
	replace exclude = 1 if ihme_loc_id == "ECU" & source_type == "HOUSEHOLD" & deaths_source == "153674#ECU_ENSANUT_2012" & year == 2011 // This source provides estimates slightly lower than desired/unadjusted gives, and pulls things down
	// replace exclude = 1 if ihme_loc_id == "ETH" & source_type == "SIBLING_HISTORIES" & year == 2003.5
	replace exclude = 1 if ihme_loc_id == "ETH" & deaths_source == "Ethiopia 2007 Census" & source_type == "HOUSEHOLD_DEATHS"
	// replace exclude = 1 if ihme_loc_id == "ETH" & source_type == "SIBLING_HISTORIES" & year >= 2008.5
	replace exclude = 1 if ihme_loc_id == "EGY" & adj45q15 < 0.15 & sex == "female" & year < 1965 
	replace exclude = 1 if ihme_loc_id == "EGY" & adj45q15 < 0.25 & sex == "male" & year < 1965 
	replace exclude = 1 if ihme_loc_id == "EGY" & source_type=="HOUSEHOLD" & year == 1990  // 1/26 outliered because unadjusted 
	replace exclude = 1 if ihme_loc_id == "ERI" & (year == 2001 | year == 1994) & source_type == "HOUSEHOLD"
	
   // replace exclude = 1 if ihme_loc_id == "GAB" & source_type == "SIBLING_HISTORIES" & sex== "male" & year > 1997 & year < 2012 & adj45q15 < 0.35  
   
	// no longer excluded as of 2/10/16
	** replace exclude = 1 if ihme_loc_id == "GBR" & source_type == "VR" & inlist(year,2011,2012,2013, 2014)
	** replace exclude = 1 if ihme_loc_id == "GBR_433" & source_type == "VR" & inlist(year,2013, 2014) 
	** replace exclude = 1 if ihme_loc_id == "GBR_434" & source_type == "VR" & inlist(year,2013, 2014) 
	** replace exclude = 1 if ihme_loc_id == "GBR_4618" & source_type == "VR" & inlist(year,2013, 2014)
	** replace exclude = 1 if ihme_loc_id == "GBR_4619" & source_type == "VR" & inlist(year,2013, 2014)
	** replace exclude = 1 if ihme_loc_id == "GBR_4620" & source_type == "VR" & inlist(year,2013, 2014)
	** replace exclude = 1 if ihme_loc_id == "GBR_4621" & source_type == "VR" & inlist(year,2013, 2014)
	** replace exclude = 1 if ihme_loc_id == "GBR_4622" & source_type == "VR" & inlist(year,2013, 2014)
	** replace exclude = 1 if ihme_loc_id == "GBR_4623" & source_type == "VR" & inlist(year,2013, 2014)
	** replace exclude = 1 if ihme_loc_id == "GBR_4624" & source_type == "VR" & inlist(year,2013, 2014)
	** replace exclude = 1 if ihme_loc_id == "GBR_4625" & source_type == "VR" & inlist(year,2013, 2014)
	** replace exclude = 1 if ihme_loc_id == "GBR_4626" & source_type == "VR" & inlist(year,2013, 2014)
	** replace exclude = 1 if ihme_loc_id == "GBR_4636" & source_type == "VR" & inlist(year,2013, 2014)

	replace exclude = 1 if ihme_loc_id =="GBR" & year==2000
	replace exclude = 1 if ihme_loc_id == "GHA" & source_type == "VR"
	replace exclude = 1 if ihme_loc_id == "GNQ" & source_type == "VR"

	replace exclude = 1 if ihme_loc_id == "HND" & source_type == "VR" & year == 1989
	replace exclude = 1 if ihme_loc_id == "HND" & source_type == "VR" & year >= 2008 // Observed 45q15 of .02.... not plausible at all. From WHO CoD
	replace exclude = 1 if ihme_loc_id == "HND" & source_type == "HOUSEHOLD" & year == 2001 // Outlier household point
	replace exclude = 1 if ihme_loc_id == "HTI" & (source_type == "VR" | source_type == "SURVEY")
	replace exclude = 1 if ihme_loc_id == "HTI" & source_type == "HOUSEHOLD" & inlist(year,2005,2006)
	
	replace exclude = 1 if ihme_loc_id == "IDN" & source_type == "HOUSEHOLD_DEATHS"

	replace exclude = 1 if ihme_loc_id == "IDN" & source_type == "SUPAS"
	replace exclude = 1 if ihme_loc_id == "IDN" & source_type == "SUSENAS"
	replace exclude = 1 if ihme_loc_id == "IDN" & source_type == "SURVEY"
	replace exclude = 1 if ihme_loc_id == "IDN" & source_type == "2000_CENS_SURVEY"
	
	replace exclude = 1 if ihme_loc_id == "IND" & source_type == "SRS" & (year == 1970 | year == 1971)
	replace exclude = 1 if ihme_loc_id == "IND" & source_type == "HOUSEHOLD_DEATHS"
	
	// India subnational 
	
	replace exclude = 1 if ihme_loc_id == "IND_43883" & (year==2001 | year==2002) & sex=="male"
	replace exclude = 1 if ihme_loc_id == "IND_43883" & (year==1999) & sex=="female"
	replace exclude = 1 if ihme_loc_id == "IND_43899" & (year==1997) & sex=="male"
	replace exclude = 1 if ihme_loc_id == "IND_43916" & (year==2004 | year==2006) & sex=="female"
	replace exclude = 1 if ihme_loc_id == "IND_43919" & (year==1999) & sex=="male"
	replace exclude = 1 if ihme_loc_id == "IND_43932" & (year==2002) & sex=="female"
	replace exclude = 1 if ihme_loc_id == "IND_4852" & (year==1999) & sex=="female"
	replace exclude = 1 if ihme_loc_id == "IND_4853" & (year==2007) & sex=="female"
	
	
	// end of India subnational
	replace exclude = 1 if strmatch(ihme_loc_id, "IND*") & source_type=="HOUSEHOLD"
	replace exclude = 1 if ihme_loc_id == "IND" & source_type == "VR"
	replace exclude = 1 if ihme_loc_id == "IRN" & source_type == "VR" & year == 1986
	replace exclude = 1 if ihme_loc_id == "IRN" & source_type == "VR" & year >= 2004 // VR past this point was Tehran-only
    replace exclude = 1 if ihme_loc_id == "IRQ" & source_type == "VR" & year == 2008

	replace exclude = 1 if ihme_loc_id == "JAM" & source_type == "VR" & inlist(year, 2005)

	replace exclude = 1 if ihme_loc_id == "JOR" & deaths_source == "DHS_1990" & source_type == "HOUSEHOLD_DEATHS"

	replace exclude = 1 if ihme_loc_id == "KEN" & source_type == "VR"
	replace exclude = 1 if regexm(ihme_loc_id,"KEN") & source_type == "HOUSEHOLD" & year == 2008 // Really small sample sizes at the subnational make these estimates (KEN 5% sample) impossible to use
	replace exclude = 1 if ihme_loc_id == "KEN" & deaths_source == "133219#KEN_AIS_2007" & year == 2007
	replace exclude = 1 if ihme_loc_id == "KIR" & deaths_source == "193927#KIR_CENSUS_2010"
	replace exclude = 1 if ihme_loc_id == "KHM" & source_type == "CENSUS" & year == 2008 // IPUMS too high
	replace exclude = 1 if ihme_loc_id == "KHM" & source_type == "HOUSEHOLD" & year == 1996 // KHM socioeconomic survey too low
	replace exclude = 1 if ihme_loc_id == "KOR" & year < 1977

	replace exclude = 1 if ihme_loc_id == "LBR" & source_type == "SURVEY" & year == 1970
	replace exclude = 1 if ihme_loc_id == "LBY" & deaths_source == "7761#LBY_papchild_1995"
	replace exclude = 1 if ihme_loc_id == "LKA" & source_type == "VR" & (year == 2005 | year == 2006) 

	replace exclude = 1 if ihme_loc_id == "MAR" & source_type == "VR"
	replace exclude = 1 if ihme_loc_id == "MAR" & source_type == "HOUSEHOLD" & year == 1996 // Morocco PAPCHILD underestimates 45q15 drastically 
	// replace exclude = 1 if ihme_loc_id == "MDG" & year >= 1977.5 & year <= 1981.5 & source_type == "SIBLING_HISTORIES"
	replace exclude = 1 if ihme_loc_id == "MEX_4671" & year < 1985 // The numbers are pretty jumpy -- we think this is probably because of VR establishment/scale-up
	replace exclude = 1 if ihme_loc_id == "MEX_4657" & year < 1985 & source_type == "VR"
	replace exclude = 1 if ihme_loc_id == "MEX_4664" & year <= 1982 & source_type == "VR"
	replace exclude = 1 if ihme_loc_id == "MEX_4668" & year <= 1983 & source_type == "VR"
	replace exclude = 1 if ihme_loc_id == "MEX_4649" & year == 1983 & source_type == "VR" // Sudden drop in VR that isn't matched on either side
	replace exclude = 1 if ihme_loc_id == "MEX_4674" & year == 2012 & source_type == "VR" // Too big of a jump in males to be plausible
	replace exclude = 1 if ihme_loc_id == "MMR" & source_type == "VR"
	replace exclude = 1 if ihme_loc_id == "MOZ" & source_type == "VR"
	replace exclude = 1 if ihme_loc_id == "MRT" & source_type == "HOUSEHOLD" & year == 1989 // Mauritania PAPCHILD point super low
    
	replace exclude = 1 if ihme_loc_id == "NAM" & deaths_source == "134132#NAM_CENSUS_2011"
    replace exclude = 1 if ihme_loc_id == "NGA" & deaths_source == "NGA_GHS" & year == 2006
    replace exclude = 1 if ihme_loc_id == "NGA" & deaths_source == "NGA_MCSS" & year == 2000
	replace exclude = 1 if ihme_loc_id == "NGA" & source_type == "VR" & deaths_source == "WHO_causesofdeath" & year == 2007
	replace exclude = 1 if ihme_loc_id == "NGA" & source_type == "HOUSEHOLD" & year == 2013 // High unadjusted household point
    replace exclude = 1 if ihme_loc_id == "NIC" & source_type == "HOUSEHOLD" & year == 2000
	replace exclude = 1 if ihme_loc_id == "NPL" & source_type == "SIBLING_HISTORIES" & year == 2005.5
	
	replace exclude = 1 if ihme_loc_id == "OMN" & source_type == "VR" & year <= 2004

	replace exclude = 1 if ihme_loc_id == "PAK" & source_type == "SURVEY" 
	replace exclude = 1 if ihme_loc_id == "PAK" & deaths_source == "PAK_demographic_survey"	
	replace exclude = 1 if ihme_loc_id == "PAN" & source_type == "CENSUS"
	replace exclude = 1 if ihme_loc_id == "PER" & source_type == "SIBLING_HISTORIES" & (source_date=="2013" | source_date=="2014") 

	replace exclude = 1 if ihme_loc_id == "PRK" & source_type == "CENSUS" & year == 1993
	replace exclude = 1 if ihme_loc_id == "PRY" & source_type == "VR" & (year == 1950 | year == 1992)
	replace exclude = 1 if ihme_loc_id == "PSE" & source_type == "VR" & year >= 2008 // Unrealistically low deaths (less than UK)

	replace exclude = 1 if ihme_loc_id == "RWA" & source_type == "CENSUS"
	replace exclude = 1 if ihme_loc_id == "RWA" & source_type == "HOUSEHOLD" & year == 2005 // Unadjusted household point -- not outside of the estimate range, but unadjusted so leave out
	// replace exclude = 1 if ihme_loc_id == "RWA" & source_type == "SIBLING_HISTORIES" & year == 1992 & adj45q15 > .9 // Rwanda bumps up to a 45q15 of 1
    
	// replace exclude = 1 if regexm(ihme_loc_id,"SAU") & source_type == "CENSUS" & year == 2004 
	replace exclude = 1 if regexm(ihme_loc_id,"SAU") & source_type == "HOUSEHOLD" & year == 2007
	replace exclude = 1 if regexm(ihme_loc_id,"SAU") & source_type == "SURVEY" & year == 2006 // Why is the 2007 DRB here twice with different numbers (household 2007, survey 2006) In any case, excluding it all
	replace exclude = 1 if ihme_loc_id == "SAU_44542" & source_type == "VR" & year == 2000 // huge spike in 45q15 
	replace exclude = 1 if ihme_loc_id == "SAU_44543" & source_type == "VR" & inlist(year,2000,2002,2003) // Big drop then spike in 45q15 that can't be true
	replace exclude = 1 if ihme_loc_id == "SAU_44544" & source_type == "VR" & year == 2000 // Big spike in 45q15
	replace exclude = 1 if ihme_loc_id == "SAU_44546" & source_type == "VR" & inlist(year,1999,2000,2001) // Big spike then drop in 45q15 that can't be true
	replace exclude = 1 if ihme_loc_id == "SAU_44547" & source_type == "VR" & inlist(year,1999,2000,2009)
	replace exclude = 1 if ihme_loc_id == "SAU_44548" & source_type == "VR" & inlist(year,1999,2000,2001)
	replace exclude = 1 if ihme_loc_id == "SAU_44549" & source_type == "VR" & inlist(year,1999,2000,2001)
	replace exclude = 1 if ihme_loc_id == "SAU_44553" & source_type == "VR" & inlist(year,1999,2000,2001)
    replace exclude = 1 if ihme_loc_id == "SDN" & source_type == "CENSUS" & year == 2008
	replace exclude = 1 if ihme_loc_id == "SDN" & source_type == "HOUSEHOLD" & year == 1992
	replace exclude = 1 if ihme_loc_id == "SEN" & source_type == "CENSUS"
	replace exclude = 1 if ihme_loc_id == "SLB" & source_type == "HOUSEHOLD" & year == 2009
	replace exclude = 1 if ihme_loc_id == "SLE" & deaths_source == "DHS" & inlist(year, 1998.5, 1999.5, 2000.5, 2001.5, 2002.5) & source_date=="2013" & sex=="male"
	replace exclude = 1 if ihme_loc_id == "SRB" & source_type == "VR" & year >= 1998 & year <= 2007 // Kosovo is included in VR but not census here
	replace exclude = 1 if ihme_loc_id == "SUR" & adj45q15 < 0.2 & year < 1976.5
	replace exclude = 1 if ihme_loc_id == "SYR" & deaths_source == "PAPCHILD" & year == 1993

	replace exclude = 1 if ihme_loc_id == "THA" & source_type == "VR" & (year == 1997 | year == 1998)
	replace exclude = 1 if ihme_loc_id == "THA" & deaths_source == "209221#THA Survey Population Change 2005-200" & year == 2006
	replace exclude = 1 if ihme_loc_id == "TGO" & source_type == "SURVEY"
	replace exclude = 1 if ihme_loc_id == "TGO" & source_type == "HOUSEHOLD" & year == 2010 // Togo Census point is super low compared to DHS estimates
	replace exclude = 1 if ihme_loc_id == "TLS" & source_type == "SIBLING_HISTORIES" & year == 1994.5 // First year of TLS independence or something like that?
	replace exclude = 1 if ihme_loc_id == "TON" & source_type == "VR" & year == 1966
	replace exclude = 1 if ihme_loc_id == "TUN" & source_type == "VR" & inlist(year,2006,2009,2013) // Extremely low 45q15 estimates
	replace exclude = 1 if ihme_loc_id == "TUR" & source_type == "SURVEY" & (year == 1967 | year == 1989)
	replace exclude = 1 if ihme_loc_id == "TZA" & source_type == "HOUSEHOLD" & year == 2007 // TZA LSML: TZA has a high 45q15 but not .5-.6
	
	replace exclude = 1 if ihme_loc_id == "UGA" & floor(year) == 2006 & deaths_source =="21014#UGA_DHS_2006"
	
	replace exclude = 1 if ihme_loc_id == "USA" & floor(year) == 2014  // USA 1/26/16  probably because of uptick
	
	replace exclude = 1 if ihme_loc_id == "VNM" & deaths_source == "PCFPS" & year == 2006.5
	replace exclude = 1 if ihme_loc_id == "VCT" & year == 2009 // quite low

	replace exclude = 1 if ihme_loc_id == "YEM" & source_type == "HOUSEHOLD" & year == 1990 // Unadjusted household
    
	replace exclude = 1 if ihme_loc_id == "ZAF" & source_type == "HOUSEHOLD" & inlist(year,2007,2009) // Unadjusted points too high
	replace exclude = 1 if ihme_loc_id == "ZAF" & source_type == "CENSUS" & year == 2000 // IPUMS unrealistic 45q15
    replace exclude = 1 if ihme_loc_id == "ZMB" & deaths_source == "ZMB_LCMS"
    replace exclude = 1 if ihme_loc_id == "ZMB" & deaths_source == "ZMB_SBS"
    replace exclude = 1 if ihme_loc_id == "ZMB" & deaths_source == "ZMB_HHC"
	replace exclude = 1 if ihme_loc_id == "ZMB" & deaths_source == "21117#ZMB_DHS_2007"
    
    replace exclude = 1 if inlist(ihme_loc_id, "CHN_493", "CHN_497","CHN_499") & source_type == "CENSUS" & year == 1982
    
    ** CHN subnational DSP 
    replace exclude = 1 if regexm(ihme_loc_id,"CHN_") & ihme_loc_id != "CHN_44533" & year >= 1990 & year <= 1995 & source_type == "DSP"
    replace exclude = 1 if inlist(ihme_loc_id,"CHN_491","CHN_496","CHN_500","CHN_502","CHN_504","CHN_508","CHN_512","CHN_515") & source_type == "DSP" & year >= 1996 & year <= 2003
    replace exclude = 1 if inlist(ihme_loc_id,"CHN_493","CHN_507","CHN_511","CHN_519","CHN_520") & source_type == "DSP" & year >= 1996 & year <= 2003
    replace exclude = 1 if inlist(ihme_loc_id, "CHN_493", "CHN_498", "CHN_499", "CHN_508", "CHN_510", "CHN_512", "CHN_515", "CHN_516") & source_type == "DSP"
    replace exclude = 1 if inlist(ihme_loc_id, "CHN_511") & source_type == "DSP"
    replace exclude = 1 if ihme_loc_id == "CHN_492" & source_type == "DSP" & year == 1996
    replace exclude = 1 if ihme_loc_id == "CHN_44533" & year < 1996 & source_type == "DSP"  // outlier dsp on mainland before 1996
	replace exclude = 1 if ihme_loc_id =="CHN_44533" & (year== 2001 | year==2002) & source_type=="DSP" // outlier messed up dsp points 
	replace exclude = 1 if ihme_loc_id == "CHN_501"  & year <= 2002 & source_type == "DSP"
	replace exclude = 1 if ihme_loc_id == "CHN_508"  & year <= 2002 & source_type == "DSP"
	replace exclude = 1 if ihme_loc_id == "CHN_514"  & year == floor(2001) & source_type == "DSP" // outlier high dsp point in 2001
	replace exclude = 1 if ihme_loc_id == "CHN_514" & (year == 2012 | year == 2013 | year== 2014) & source_type=="DSP" // outlier because we think too low 3/9/16
	
	** KEN subnational DHS
	replace exclude = 1 if ihme_loc_id == "KEN_35621" & sex=="female" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35623" & sex=="female" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35625" & sex=="male" & source_type == "SIBLING_HISTORIES" // 3/9/16	
	replace exclude = 1 if ihme_loc_id == "KEN_35625" & sex=="female" & source_type == "SIBLING_HISTORIES" // 3/9/16	
	replace exclude = 1 if ihme_loc_id == "KEN_35626" & sex=="female" & source_type == "SIBLING_HISTORIES" // 3/9/16	
	replace exclude = 1 if ihme_loc_id == "KEN_35630" & sex=="male" & source_type == "SIBLING_HISTORIES" // 3/9/16	
	replace exclude = 1 if ihme_loc_id == "KEN_35634" & sex=="female" & source_type == "SIBLING_HISTORIES" & (floor(year)==2000 | floor(year)==2003) // 3/9/16	
	replace exclude = 1 if ihme_loc_id == "KEN_35636" & sex=="female" & source_type == "SIBLING_HISTORIES" & adj45q15 > .5 // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35637" & sex=="male" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35637" & sex=="female" & source_type == "SIBLING_HISTORIES" & adj45q15 > .6 // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35640" & sex=="male" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35641" & sex=="male" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35641" & sex=="female" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35642" & sex=="male" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35644" & sex=="male" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35645" & sex=="female" & source_type == "SIBLING_HISTORIES" & floor(year)==2003 // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35648" & sex=="female" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35650" & sex=="female" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35653" & sex=="female" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35655" & sex=="male" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35655" & sex=="female" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35656" & sex=="female" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35657" & sex=="female" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35658" & sex=="female" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35659" & sex=="female" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35663" & sex=="male" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35663" & sex=="female" & source_type == "SIBLING_HISTORIES" // 3/9/16
	replace exclude = 1 if ihme_loc_id == "KEN_35623" // 3/10/16
	replace exclude = 1 if ihme_loc_id == "KEN_35628"  // 3/10/16
	replace exclude = 1 if ihme_loc_id == "KEN_35636"  // 3/10/16
	replace exclude = 1 if ihme_loc_id == "KEN_35637"  // 3/10/16
	replace exclude = 1 if ihme_loc_id == "KEN_35644"  // 3/10/16
	
	replace exclude = 1 if ihme_loc_id == "KEN_35627"  // 3/11/16
	replace exclude = 1 if ihme_loc_id == "KEN_35631"  // 3/11/16
	replace exclude = 1 if ihme_loc_id == "KEN_35653"  // 3/11/16
	replace exclude = 1 if ihme_loc_id == "KEN_35658"  // 3/11/16
	
	// Mark all unadjusted datapoints as excluded for now -- we don't want to include those like Congo 1984 that are obviously wrong
	// These are points that are unadjusted by DDM and that are not necessarily complete
	// This happens regularly with sources where population and death estimates are for the same years, without census years bracketing it.
	replace exclude = 1 if adjust == 0 & !regexm(source_type,"HOUSEHOLD") & !regexm(source_type,"household") & !regexm(source_type,"SIBLING_HISTORIES")
    
	replace exclude = 0 if ihme_loc_id == "AFG"  & year == floor(1979) & source_type == "CENSUS" // unoutlier census point that is unadjusted
** **********************
** Delete scrubs (no longer scrub data, just outlier it)
** **********************

	replace exclude = 1 if ihme_loc_id == "YEM" & deaths_source == "PAPCHILD" & source_type == "HOUSEHOLD_DEATHS"
	replace exclude = 1 if ihme_loc_id == "PNG" & source_type == "VR"
	
** **********************
** Correct exposure sizes where necessary
** **********************	

** get nat'l populations for things that were added as rates
	preserve
	use "strPath/d09_denominators.dta", clear
	keep if source_type == "IHME" & sex != "both"
	egen natl_pop = rowtotal(c1_15to19-c1_55to59)
	keep ihme_loc_id year sex natl_pop
	tempfile pop
	save `pop'
	restore
	replace year = floor(year)
	merge m:1 ihme_loc_id year sex using `pop'
	drop if _m == 2
	drop _m 
	
** correct nat'l populations where appropriate
	gen correction = 1
	** SRS 
	replace correction = 0.006 if inlist(ihme_loc_id,"IND","XIR","XIU") & source_type == "SRS" // see: 'Adult Mortality: Time for a Reappraisal' 
	replace correction = 0.003 if ihme_loc_id == "BGD" & source_type == "SRS" // there is an estimate of 0.003 in UN documentation for 1990 
	replace correction = 0.01 if ihme_loc_id == "PAK" & source_type == "SRS" // copied from child mortality code 
	** DSP national
	preserve
	insheet using "strPath/pop_covered_survey.csv", clear
	rename prop_covered correction
	keep if iso3 == "CHN"
	rename iso3 ihme_loc_id
	replace ihme_loc_id = "CHN_44533"
	keep ihme_loc_id year correction
	gen source_type = "DSP"
	expand 10 if year == 1990
	bysort year: replace year = 1979 + _n if _n > 1
	tempfile chn_correction
	save `chn_correction'
	restore
	merge m:1 ihme_loc_id year source_type using `chn_correction', update replace
	drop if _m == 2
	drop _m 
    ** DSP subnational
    preserve  
    ** these are sample populations from the actual DSP
	use "strPath/USABLE_ALL_AGE_SAMPLE_POP_CHN_PROVINCE_DSP_91_12.dta", clear
	rename COUNTRY iso3
	merge m:1 iso3 using `iso3_map', keep(1 3) nogen keepusing(ihme_loc_id)
	drop iso3
	
	append using "strPath/usable_all_age_sample_pop_CHN_province_DSP_13_14.dta"
    ren SEX sex
    tostring sex, replace
    replace sex = "male" if sex == "1"
    replace sex = "female" if sex == "2"
    ren YEAR year
    egen sample_pop = rowtotal(DATUM15to19 DATUM20to24 DATUM25to29 DATUM30to34 DATUM35to39 DATUM40to44 DATUM45to49 DATUM50to54 DATUM55to59)
    gen source_type = "DSP"
    keep ihme_loc_id sex year sample_pop source_type
	
	
	tempfile chn_sub_correction
	save `chn_sub_correction'

	restore
	
	merge m:1 ihme_loc_id sex year source_type using `chn_sub_correction', nogen
    replace correction = sample_pop/natl_pop if regexm(ihme_loc_id,"CHN_") & ihme_loc_id != "CHN_44533" & source_type == "DSP"
    drop sample_pop
	** Other China sources
	replace correction = 0.001 if ihme_loc_id == "CHN_44533" & (source_type == "SSPC" | deaths_source == "EPI_SURVEY")
	replace correction = 0.01 if ihme_loc_id == "CHN_44533" & source_type == "DC" 
	** Other (generic) sources 
	replace correction = 0.005 if inlist(source_type, "HOUSEHOLD_DEATHS", "SURVEY", "UNKNOWN") & natl_pop >= 5*10^6
	replace correction = 0.01 if inlist(source_type, "HOUSEHOLD_DEATHS", "SURVEY", "UNKNOWN") & natl_pop < 5*10^6
	
** fill in/replace calcualted exposures for SRS/DSP (these aren't always available since sometimes we start with rates and are sometimes incorrect because the data have been scaled to the national level) 
	replace exposure = correction*natl_pop if inlist(source_type, "SRS", "DSP")

** replace calculated exposures with corrected nat'l populations for sub-national sources from DYB (these are scaled to the national level in the raw data so the calculated exposure is too high) 
	replace exposure = correction*natl_pop if regexm(deaths_source, "DYB") & inlist(source_type, "SURVEY", "UNKNOWN")
	
** fill in exposures for sources that don't already have an exposure (usually aggregate estimates) 
	replace exposure = correction*natl_pop if exposure == . & source_type != "SIBLING_HISTORIES"
	
** **********************
** Format and save 
** **********************

	merge m:1 ihme_loc_id using `iso3_map', keepusing(location_id country)
	levelsof ihme_loc_id if _merge == 2
	keep if _m == 3
	drop _m 
	
	label define comp 0 "unadjusted" 1 "ddm_adjusted" 2 "gb_adjusted" 3 "complete"
	label values adjust comp 
	
	order location_id country ihme_loc_id year sex source_type deaths_source nid adjust comp sd adj45q15 obs45q15 exclude shock exposure
	sort ihme_loc_id year sex source_type
	local date = c(current_date)
	local date = subinstr("`date'", " ", "_", 2)
	outsheet using "strPath/raw.45q15.txt", c replace
	outsheet using "strPath/raw.45q15.`date'.txt", c replace
