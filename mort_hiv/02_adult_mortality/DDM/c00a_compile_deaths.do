** ***********************************************************************
** Description: Compiles data on deaths by age and sex from a variety of sources.
**
** ***********************************************************************

** ***********************************************************************
** Set up Stata 
** ***********************************************************************

	clear all  
	capture cleartmp
	set mem 500m
	set more off
	pause on
	capture restore, not

	
** ***********************************************************************
** Filepaths 
** ***********************************************************************

	if (c(os)=="Unix") global root "/home/j"
	if (c(os)=="Windows") global root "J:"
	global rawdata_dir "strPath"
    global newdata_dir "strPath"
    global hhdata_dir "strPath"
	global save_file "strPath/d00_compiled_deaths.dta"
	
	adopath + "strPath"
	
** ***********************************************************************
** Set up codes for merging 
** ***********************************************************************
	get_locations
	keep local_id_2013 ihme_loc_id location_name // Keeping iso3 to merge on with old iso3s here
	rename local_id_2013 iso3
	rename location_name country
	sort iso3
	tempfile countrymaster
	save `countrymaster'
	
	// Create a duplicate observation for subnationals: we want to make sure that GBD2013 subnationals have iso3s
	// For both the old iso3 (X**) and the new iso3 (GBR_***) to merge appropriately
	expand 2 if regexm(ihme_loc_id,"_") & iso3 != "", gen(new)
	replace iso3 = ihme_loc_id if new == 1 
	drop new
	
	replace iso3 = ihme_loc_id if iso3 == "" // For new subnationals and other locations
	tempfile countrycodes
	save  `countrycodes', replace

	// Make a list of all the countries which contain subnational locations, for use in scaling/aggregation later
	get_locations, level(subnational)
	keep if regexm(ihme_loc_id,"_")
	split ihme_loc_id, parse("_")
	duplicates drop ihme_loc_id1, force
	keep ihme_loc_id1
	rename ihme_loc_id1 ihme_loc_id
	replace ihme_loc_id = "CHN_44533" if ihme_loc_id == "CHN" // Mainland has all the data
	keep ihme_loc_id
	tempfile parent_map
	save `parent_map'

	// Get all subnational locations, along with the total number of subnationals expected in each
	get_locations, level(subnational)
	drop if level == 4 & (regexm(ihme_loc_id,"CHN") | regexm(ihme_loc_id,"IND"))
	drop if ihme_loc_id == "GBR_4749" // Screws everything up
	split ihme_loc_id, parse("_")
	rename ihme_loc_id1 parent_loc_id
	keep ihme_loc_id parent_loc_id
	bysort parent_loc_id: gen num_locs = _N
	keep ihme_loc_id parent_loc_id num_locs
	replace parent_loc_id = "CHN_44533" if parent_loc_id == "CHN" // Mainland has all the data
	tempfile subnat_locs
	save `subnat_locs'
	
** ***********************************************************************
** Compile data
** ***********************************************************************
	noisily: display in green "COMPILE DATA"

** ************
** Multi country sources
** ************

** WHO database (both CoD and raw) 
	** raw WHO VR numbers
	use "$newdata_dir/who_vr/data/USABLE_ALL_AGE_DEATHS_VR_WHO_1950-2011.dta", clear
	replace SUBDIV = "VR"
	
	** COD age-sex split VR numbers
	append using "$newdata_dir/cod_vr/data/USABLE_ALL_AGE_DEATHS_VR_WHO_GLOBAL_vICD7-10.dta"
	
	** Removing Duplicates between WHO and COD
	** In general we prefer COD numbers - unknown age/sex deaths have been redistributed
	** Exceptions are areas where raw WHO series are more reliable than CoD estimates
		drop if CO == "THA" & VR_S != "WHO" &  YEAR < 1992 
		drop if CO == "BIH" & YEAR <= 1991 & YEAR >= 1985 & VR_SOURCE == "WHO_causesofdeath"
		drop if CO == "GBR" & VR_SOURCE == "WHO_causesofdeath" & YEAR < 2011
		drop if regexm(CO,"SWE") & VR_SOURCE == "WHO_causesofdeath" & YEAR >= 1987 & YEAR <= 1989

		** General duplicate removal
		duplicates tag CO YEAR SEX if VR_S == "WHO" | VR_S == "WHO_causesofdeath", g(dup)
		drop if dup != 0 & VR_S == "WHO"
		drop dup

	** Drop unknown CHN VR data
	drop if CO == "CHN" & SUBDIV == "VR" 
	
	** Drop MMR VR data (probably subnational like earlier data from DYB)
	drop if CO == "MMR" & SUBDIV == "VR"
	
	** Drop Bahamas 1969 WHO point; we have DYB already
	drop if CO == "BHS" & SUBDIV == "VR" & VR_SOURCE == "WHO" & YEAR == 1969
	
	** Drop Dominican Republic 2010 WHO point and CoD 2011 VR point; we have DYB for that year anyway
	drop if CO == "DOM" & SUBDIV == "VR" & VR_SOURCE == "WHO" & inlist(YEAR, 2010, 2009, 2008, 2007)

	** Drop Tunisia 2006
	drop if CO == "TUN" & SUBDIV == "VR" & VR_SOURCE == "WHO_causesofdeath" & YEAR == 2006

	** Drop CoD from Morocco
	drop if CO == "MAR" & SUBDIV == "VR" & VR_SOURCE == "WHO_causesofdeath" & YEAR >= 2000

** WHO Internal Database
	append using "$rawdata_dir/WHO_OTHER/CRUDE_EST_WHO_MULTI_1980-1999_vWHO_INTERNAL.dta"
	
** Demographic Yearbook
	append using "$rawdata_dir/DYB/USABLE_VR_DYB_ALL_YEARS_GLOBAL.DTA"

	**  internal are problematic when missing youngest age groups
	drop if VR_SOURCE == "DYB_INTERNAL" & DATUM0to0 == . & DATUM0to4 == .
	
	** older VR data in MMR, GHA, and KEN are not nationally representative (per footnotes) 
	drop if (CO == "GHA" | CO == "KEN") & SUBDIV == "VR" & regexm(VR_SOURCE, "DYB") 
	drop if CO == "MMR" & SUBDIV == "VR" & YEAR < 2000 & regexm(VR_SOURCE, "DYB") 
	
	** VR data in GNQ, AGO, MOZ, CAF, MLI, TGO, and GNB are colonial-period only and likely have poor (or no) coverage of non-Europeans
	drop if inlist(CO, "GNQ", "AGO", "MOZ", "CAF", "MLI", "TGO", "GNB")==1 & SUBDIV == "VR" & regexm(VR_SOURCE, "DYB") 

	** Drop DYB from Dominican Republic in favor of CoD
	drop if CO == "DOM" & VR_SOURCE == "DYB_ONLINE" & YEAR == 2011

	** we have no idea what these data are
	drop if CO == "SAU" & regexm(VR_SOURCE, "DYB") & SUBDIV == "VR"
    
    ** not sure if 1993 SDN is just north, or both north and south, so we drop it
    drop if CO == "SDN" & regexm(VR_SOURCE, "DYB") & SUBDIV == "CENSUS" & YEAR == 1993
	
	** make source type corrections
	replace SUBDIV = "VR" if CO == "KOR" & regexm(VR_SOURCE, "DYB")
	replace SUBDIV = "VR" if CO == "PRY" & regexm(VR_SOURCE, "DYB")
	replace SUBDIV = "CENSUS" if CO == "SRB" & YEAR <= 1991 & regexm(VR_SOURCE, "DYB")
	replace SUBDIV = "CENSUS" if CO == "MWI" & YEAR == 1977 & regexm(VR_SOURCE, "DYB")
	replace SUBDIV = "CENSUS" if CO == "PRK" & regexm(VR_SOURCE, "DYB")
	replace SUBDIV = "dyb_from_statistical_report" if CO == "BWA" & YEAR == 2007 & regexm(VR_SOURCE, "DYB")
	replace SUBDIV = "CENSUS" if CO == "CHN" & regexm(VR_SOURCE, "DYB")
	replace SUBDIV = "CENSUS" if CO == "NAM" & YEAR == 2001 & regexm(VR_SOURCE, "DYB")
	replace SUBDIV = "CENSUS" if CO == "BOL" & YEAR == 1991 & regexm(VR_SOURCE, "DYB")
	replace SUBDIV = "SRS" if CO == "PAK" & regexm(VR_SOURCE, "DYB") 
	replace SUBDIV = "SRS" if CO == "BGD" & YEAR >= 1980 & regexm(VR_SOURCE, "DYB")
	
	** dropping CHN census 2000: the data from the DYB are wrong
	drop if COUNTRY == "CHN" & YEAR == 1999 & SUBDIV == "CENSUS" & VR_SOURCE == "DYB_ONLINE"
	
** Human Mortality Database
	append using "$newdata_dir/hmd_vr/data/USABLE_ALL_AGE_DEATHS_HMD_VR.DTA"
    drop if inlist(COUNTRY,"XNI","XSC") & SUBDIV == "VR" & VR_SOURCE == "HMD"

    ** Drop Belgium
    drop if CO == "BEL" & YEAR > 2000 & VR_SOURCE == "HMD"
    
** Data from Alan Lopez
	append using "$rawdata_dir/ALAN LOPEZ/SRI LANKA AND PHILIPPINES/USABLE_LOPEZ_LKA-PHL_1995-2003.dta"
	append using "$rawdata_dir/ALAN LOPEZ/MONGOLIAN YEARBOOK/USABLE_VR_LOPEZ_MNG_2002-2005.dta"
	append using "$rawdata_dir/ALAN LOPEZ/FIJI/USABLE_MOH_FIJI_1996-2004_vRestrictedData.dta"

** OECD database
	append using "$rawdata_dir/OECD/USABLE_VR_OECD_MULTIPLE_1948-1975.dta"

	** drop subnational and suspicious data
	** not obvious what the source is
	drop if CO == "IRN" & VR_SOURCE == "OECD"  
	drop if CO == "JAM" & VR_SOURCE == "OECD" 
	drop if CO == "NPL" & VR_SOURCE == "OECD" 
	** rural only 
	drop if CO == "MAR" & VR_SOURCE == "OECD" 
	** duplicate of VR 
	drop if CO == "SUR" & VR_SOURCE == "OECD" 
	drop if CO == "SYC" & VR_SOURCE == "OECD" & YEAR == 1974 
	drop if CO == "MDG" & VR_SOURCE == "OECD"
	drop if CO == "KEN" & VR_SOURCE == "OECD"	
	** subnational 
	drop if CO == "DZA" & VR_SOURCE == "OECD" 
	drop if CO == "TCD" & VR_SOURCE == "OECD" 
	drop if CO == "TUN" & VR_SOURCE == "OECD" 
	** duplicate of a survey in DYB (also in the wrong year, should be 1961, not 1965)
	drop if CO == "TGO" & VR_SOURCE == "OECD" 
	** duplicates of other sources 
	drop if CO == "CPV" & VR_SOURCE == "OECD"
	drop if CO == "AGO" & VR_SOURCE == "OECD" 
	drop if CO == "SLV" & VR_SOURCE == "OECD"	
	** non national VR
	drop if CO == "MOZ" & VR_SOURCE == "OECD"

	** make source type corrections for OECD data
	replace SUBDIV = "VR" if CO == "CUB" & VR_SOURCE == "OECD" 
	replace SUBDIV = "VR" if CO == "MAC" & VR_SOURCE == "OECD" 
	replace SUBDIV = "VR" if CO == "KOR" & VR_SOURCE == "OECD" 
	replace SUBDIV = "CENSUS" if CO == "COM" & VR_SOURCE == "OECD" 
	replace SUBDIV = "CENSUS" if CO == "SYC" & VR_SOURCE == "OECD" 
	
	** these points are just terrible
	drop if CO == "BDI" & VR_SOURCE == "OECD" 
	drop if CO == "GIN" & VR_SOURCE == "OECD"  
	drop if CO == "GAB" & VR_SOURCE == "OECD" 
	
** IPUMS
	append using "$rawdata_dir/IPUMS/PROJECT_IPUMS_GIN-MLI-NPL-PAN-RWA-SEN-TZA-UGA-VNM-ZAF_vDEATHS.dta"
	append using "$rawdata_dir/IPUMS/PROJECT_IPUMS2011_GLOBAL_vDEATHS.dta"
    append using "$newdata_dir/ipums_census/data/USABLE_ALL_AGE_POP_IPUMS_CENSUS_2013_UPDATE.dta"
	** reclassify non-census source
	replace SUBDIV = "SURVEY" if CO == "ZAF" & YEAR == 2007 & VR_SOURCE == "IPUMS_HHDEATHS"
	
** ************
** Country-Specific sources
** ************
	
** ARE: VR
	append using "$rawdata_dir/ARE/ARE_DEATHS_VR.dta"
	append using "$rawdata_dir/ARE/ARE_DEATHS_MinOfPlanning.dta" 

** AUS: VR
	append using "$rawdata_dir/AUS_2010_VR/AUS_2010_vDEATHS.dta"
	append using "$newdata_dir/aus_vr/data/USABLE_ALL_AGE_DEATHS_aus_vr_2012_2014.dta"

** BGD: Sample Registration System
	append using "$rawdata_dir/SRS LIBRARY/BANGLADESH 2001-2003/USABLE_SRSDEATHS_BGD_2001-2003.dta"
	drop if YEAR == 2003 & CO == "BGD" & VR_SOURCE == "SRS_LIBRARY" 
	append using "$rawdata_dir/BGD_SRS/USABLE_BGD_SRS_REPORT_2010_DEATHS.DTA"
	append using "$newdata_dir/bgd_srs/data/USABLE_ALL_AGE_DEATHS_BGD_SRS_REPORT_2012-2014.DTA"
	
** BFA: 1985, 1996, 2006 Censuses
	append using "$rawdata_dir/BFA_census/USABLE_BFA_CENSUS_DEATHS.DTA"
	
** BRA: 2010 Census
	append using "$rawdata_dir/BRA_2010_CENSUS/USABLE_BRA_2010_CENSUS_DEATHS.DTA"
	
** CAN: 2010-2011 VR deaths
	append using "$rawdata_dir/STATISTICS_CAN_VR_2010-2011/data/USABLE_STATISTICS_CAN_VR_2010-2011.dta"

** CAN: 2012 VR deaths
	append using "$newdata_dir/can_vr/data/USABLE_ALL_AGE_DEATHS_CAN_VR_2012.dta" 

** CHN: 1982 Census
	append using "$rawdata_dir/CHINA 1982 census/USABLE_VR_GOV_CHINA_CENSUS_1982.dta"

** CHN: 2000 Census
	append using "$rawdata_dir/CHN_2000_CENSUS_STATYB2002/USABLE_CHN_2000_CENSUS_STATYB2002_DEATHS.dta"
			
** CHN: 2010 Census
	append using "$rawdata_dir/CHN_CENSUS_2010/USABLE_CHN_CENSUS_2010_DEATHS.DTA"

** CHN: DSP
	** this is urban/rural aggregated
	append using "$rawdata_dir/CHINA DSP/1996_2000/USABLE_DSPDEATHS_CHN_1996-2000.dta" 
	append using "$rawdata_dir/CHINA DSP/2004_2010/USABLE_DSP_2004_2010_noweight.dta"
	
	** new CHN DSP data from provincial aggregated up to national- Matt
	append using "$newdata_dir/chn_dsp/data/USABLE_ALL_AGE_DEATHS_CHN_DSP_91_12.dta"

** CHN: Intra-census surveys (1%; DC)
	append using "$rawdata_dir/CHINA 1 percent/USABLE_INT_GOV_CHN_1995_vDeaths.dta"

** CHN: SSPC (1 per 1000)
	append using "$rawdata_dir/CHN_SSPC/USABLE_SURVEY_SSPC_CHN_1986-2008.dta"

** CIV: 1998 Census
	append using "$rawdata_dir/CIV/USABLE_CENSUS_CIV_1998_vDEATHS.dta"

** CMR: 1987 Census
	append using "$rawdata_dir/CMR/USABLE_CENSUS_CMR_1987_vDEATHS.dta"
	
** CYP: Adjust Cyprus's VR for the fact that WHO VR only has South and our Census has South and North
** We take the ratio of 2009-2013 for CYP + N Turkey Cyprus, then apply it to all years 
***************************************
	tempfile master
	save `master'
	keep if CO == "CYP"
	tempfile cyp_temp
	save `cyp_temp'
	
	keep if SEX == 0 // All CYP years have a sex == 0
	keep if VR_SOURCE == "WHO_causesofdeath"
	tempfile cyp_merge
	save `cyp_merge'
	
	// Source for CSV
	/*
	Table 21 on page 30 of the file [http://www.devplan.org/ISTYILLIK/IST-YILLIK-2013.pdf] has the deaths by sex for 2009-2013 from the Turkish Republic of North Cyprus [TPNC]. 
	*/
	
	insheet using "strPath/cyp_tempfix2.csv", comma clear
	rename year YEAR
	merge 1:m YEAR using `cyp_merge', keep(3) nogen
	// Use average over all years
	collapse (sum) deaths DATUMTOT, by(SUBDIV)
	gen cyp_total = deaths + DATUMTOT // CYP + Northern Cyprus which isn't counted
	gen scalar = cyp_total/DATUMTOT
	keep scalar SUBDIV
	tempfile scale_cyp
	save `scale_cyp'
	
	merge 1:m SUBDIV using `cyp_temp', nogen
	
	foreach var of varlist DATUM* {
		replace `var' = `var' * scalar if YEAR >= 1986 // Pre-1986 is representative
	}
	
	drop scalar
	replace FOOTNOTE = "Scaled from non-govt controlled to total CYP using ratio in 2009-2011" if YEAR >= 1986
	tempfile cyp_add
	save `cyp_add'
	
	use `master', clear
	drop if COUNTRY == "CYP"
	append using `cyp_add'
	
** ETH: 2007 Census
	append using "$rawdata_dir/ETH_CENSUS_2007/USABLE_ETH_2007_CENSUS_DEATHS.DTA" 
	
** IDN: SUSENAS & SUPAS & 2000 long form census
	append using "$rawdata_dir/SUSENAS/USABLE_SURVEY_SUSENAS_IDN_2000_2004_2007_vDEATHS.dta"
	** These are bad, way too many deaths (in the millions)
	// append using "$rawdata_dir/SUSENAS/USABLE_SURVEY_SUSENAS_IDN_1996-1998_vDEATHS.dta"
	append using "$rawdata_dir/SUPAS/USABLE_SURVEY_SUPAS_IDN_1985_vDEATHS.dta"
	append using "$rawdata_dir/IDN CENSUS/USABLE_CENSUS_IDN_2000_vDEATHS.dta"
	
** IND: Sample Registration System
	append using "$rawdata_dir/SRS LIBRARY/INDIA 1997-2000-2006/NEWUSABLE_SRSDEATHS_IND_1997-2000-2008.dta" // includes correct population-weighting for 1992 SRS to be consistent with rest of analysis group
	append using "$rawdata_dir/SRS LIBRARY/INDIA 1970-1988/USABLE_SRSDEATHS_IND_1970-1988.dta"
	append using "$rawdata_dir/IND_SRS/USABLE_IND_SRS_2010_DEATHS.DTA"
    append using "$newdata_dir/ind_srs/data/USABLE_ALL_AGE_DEATHS_IND_SRS_2011.dta"
	
	// Subnational SRS
	append using "$newdata_dir/ind_srs_state_urban_rural/data/USABLE_ALL_AGE_DEATHS_IND_URBAN_RURAL_SRS_1995_2013.dta"

** LKA
	append using "$newdata_dir/lka_vr/data/USABLE_ALL_AGE_DEATHS_LKA_2009.dta"

** LBY: VR
	append using "$rawdata_dir/LBY_VR/USABLE_LBY_VR_DEATHS.DTA"

** LTU: VR
	append using "$newdata_dir/ltu_vr/data/USABLE_ALL_AGE_DEATHS_LTU_VR_2010-2012.dta"
	
** MNG: Stat yearbook
	append using "$rawdata_dir/MNG Statistical Yearbook/MNG_2001YB_1999/USABLE_VR_STATYB2001_MNG_1999_DEATHS.dta"
	** dropping other sources for MNG in 1999
	drop if YEAR == 1999 & CO == "MNG" & VR_SOURCE != "MNG_STAT_YB_2001"
	
** MOZ: 2007 Census
	append using "$rawdata_dir/MOZ_CENSUS/USABLE_MOZ_CENSUS.DTA"
    
** PAK: SRS
	append using "$rawdata_dir/PAK_SRS/PAK_1995_vDEATHS.dta"
	append using "$rawdata_dir/PAK_SRS/PAK_1999_vDEATHS.dta"	
	append using "$rawdata_dir/PAK_SRS/PAK_2006_vDEATHS.dta"
	
** SAU: 2007 Demographic Bulletin
	append using "$rawdata_dir/SAU/SAU_CENSUS_2007_BULLETIN_SAU_2007_vDEATHS.dta"

** TUR: 1989 Demographic Survey, household deaths scaled up to population
	append using "$rawdata_dir/tur_demog_surv_1989/USABLE_tur_demog_surv_1989_deaths.dta"
	
** TUR: 2009-2010 VR: no longer want 2009.  We will use 2010 data from TurkStat tabulations
	append using "$rawdata_dir/TUR_VR/USABLE_TUR_VR.DTA"
		drop if COUNTRY == "TUR" & inlist(YEAR,2009,2010) & VR_SOURCE == "Stats website"
	
** TUR: 2010 and 2011 VR from TurkStat Tabulations
	append using "$rawdata_dir/turkstat_tabulations/USABLE_TURKSTAT_TABULATIONS_2010-2011_DEATHS.dta"
	drop if COUNTRY == "TUR" & inlist(YEAR,2010,2011) & VR_SOURCE == "TurkStat_Tabs_MERNIS_data"

** USA: 2010 VR 
	append using "$rawdata_dir/USA_VR/USABLE_USA_VR_2010_DEATHS.DTA"
	
** USA NVRS 2011 VR
	** append using "$rawdata_dir/USA_CDC_NVSR/USABLE_USA_VR_2010_2011_CDC_NVSR.dta"

** USA CDC 2014 VR -- not using, bad age-groupings
	// append using "$newdata_dir/usa_vr_2014/data/USABLE_ALL_AGE_DEATHS_USA_VR_2014.dta"

** VEN VR 2010 and 2011 for kids
	// append using "$rawdata_dir/VEN_VR_2010_2011/data/USABLE_VEN_VR_2010_2011.DTA"	
	
** WSM: 2006 Census
	append using "$rawdata_dir/WSM/CRUDE_CENSUS_SBS_WSM_2006_DEATHS.dta" 

** XKX (Kosovo): VR -- we're adding this onto our SRB VR deaths for 2008-2013
	preserve
	keep if COUNTRY == "SRB" & YEAR > 2007 & VR_SOURCE =="WHO_causesofdeath"
	append using "$newdata_dir/xkx_vr/data/USABLE_5YR_ALL_AGE_DEATHS_VR_XKX_2008_2013.dta"
	replace COUNTRY = "SRB" if COUNTRY == "XKX"
	collapse (sum) DATUM*, by(COUNTRY YEAR SEX SUBDIV AREA version)

	gen FOOTNOTE = "Added together SRB CausesofDeath VR with Kosovo Ministry of Public Services VR for 2008-2013"
	gen VR_SOURCE = "WHO_causesofdeath"  // so it isn't dropped in favor of DYB/HMD

	tempfile srb_xkx
	save `srb_xkx'
	restore

	drop if COUNTRY == "SRB" & YEAR > 2007 & VR_SOURCE =="WHO_causesofdeath"
	append using `srb_xkx'
	foreach var of varlist DATUM* {
		replace `var' =. if `var' == 0 & COUNTRY == "SRB" & YEAR > 2007 & VR_SOURCE == "WHO_causesofdeath"
	}

** ZAF: 2010 VR (Stats South Africa; de facto)
    append using "$newdata_dir/zaf_vr/data/USABLE_ALL_AGE_DEATHS_ZAF_VR_SSA_2010.dta" 
    
** ZAF Census 2011
	** append using "$hhdata_dir/zaf_census_2011/data/USABLE_ALL_AGE_DEATHS_ZAF_CENSUS_2011.dta"
    ** replace SUBDIV = "CENSUS" if SUBDIV == "Census" & COUNTRY == "ZAF" & YEAR == 2011

** ZAF Census 2011 updated: REPLACED BY SUBNATIONAL INCLUSIVE RESULTS
    // append using "$newdata_dir/zaf_census/data/USABLE_ALL_AGE_DEATHS_ZAF_CENSUS_2011.dta"
    
** GBR: 1981-2012 VR (from collaborators)
    append using "$rawdata_dir/GBR/USABLE_ENGLAND_WALES_DEATHS_BY_REGION_1981_2012.dta"
	append using "$rawdata_dir/GBR/USABLE_NORTH_IRELAND_SCOTLAND_DEATHS_BY_REGION_1950_2012.dta"
	append using "$rawdata_dir/GBR/USABLE_COMBINED_GBR_DEATHS_DAVIS.dta" // combined two above to nat'l level (2/2/16)
	append using "$newdata_dir/gbr_vr/data/USABLE_ALL_AGE_DEATHS_GBR_2013.dta"
 
** CHN provincial data 
    
    ** Censuses
        append using "$newdata_dir/chn_province_census_2000/data/USABLE_ALL_AGE_DEATHS_CHN_PROVINCE_2000_CENSUS.DTA"
        append using "$newdata_dir/chn_province_census_2010/data/USABLE_ALL_AGE_DEATHS_CHN_PROVINCE_2010_CENSUS.DTA"
        append using "$newdata_dir/chn_province_census_1990/data/USABLE_ALL_AGE_DEATHS_CHN_PROVINCE_1990_CENSUS.DTA"
        append using "$newdata_dir/chn_province_census_1982/data/USABLE_ALL_AGE_DEATHS_CHN_PROVINCE_1982_CENSUS.DTA"
		
    ** DSP
        append using "$newdata_dir/chn_dsp_prov/data/USABLE_ALL_AGE_DEATHS_CHN_PROVINCE_DSP_91_12.dta" 
		append using "$newdata_dir/chn_dsp_prov/data/usable_all_age_deaths_CHN_province_DSP_13_14.dta" 
		
	** 1 % survey
		append using "$newdata_dir/chn_1percent_survey/data/USABLE_ALL_AGE_DEATHS_CHN_PROVINCE_1PERCENT_SURVEY_2005.dta"
		
	** Family planning survey 1992	
		append using "$newdata_dir/chn_ffps_1992/data/USABLE_ALL_AGE_DEATHS_CHN_FFPS_1992.dta"
		
** IND urban rural
	** SRS 
		// Also includes national 2012 SRS numbers, which do not exist elsewhere currently
		append using "$newdata_dir/ind_srs_urban_rural/data/USABLE_ALL_AGE_DEATHS_IND_URBAN_RURAL_SRS.dta"
		
	** DLHS III
		** append using "$newdata_dir/ind_dlhs3_urban_rural/data/USABLE_ALL_AGE_DEATHS_IND_URBAN_RURAL_DLHS3.dta"
        
    ** IND CRS 2010 Report
        ** append using "$rawdata_dir/IND_CRS_REPORTS/USABLE_IND_CRS_2010_DEATHS_URBAN_AND_RURAL_AGE_SEX.dta"
    
    ** IND CRS 2009 Report
        ** append using "$rawdata_dir/IND_CRS_REPORTS/USABLE_IND_CRS_2009_DEATHS_URBAN_AND_RURAL_AGE_SEX.dta"	
		
** MEX deaths
    ** the death numbers in this are not usable (give completeness estimates that are much too high; haven't been put through the COD system yet)
	** append using "$rawdata_dir/2012_Mex_Vr/USABLE_MEXICO_VR_SUBNATIONAL.dta"
    
** CHL deaths from Ministeria de Salud 2010-2011
    append using "$rawdata_dir/CHL_2010_2011_MINISTRY_OF_HEALTH/USABLE_CHL_DEATHS_2010_2011.dta"
    drop if CO == "CHL" & VR_SOURCE == "CHL_MOH" & SUBDIV == "VR" & YEAR == 2010
	
** COD MEX SUBNATIONAL VR 1979-2011 -- no longer needed, because it's brought into the system via the CoD VR update.
	* append using "$rawdata_dir/COD_MEX_SUBNAT/USABLE_MEX_SUBNAT_COD_VR_1979_2011.dta"
	
** DEU VR-- no longer needed because we have CoD VR instead
	* append using "$rawdata_dir/DEU_VR_2012/USABLE_DEU_2012_VR.dta"
	
** ********************************
** Add in household deaths (will be dropped before DDM and added back in at the 45q15 calculation)
** ********************************
** BDI Demographic survey 1965
	append using "$hhdata_dir/BDI_demographic_survey_1965/data/USABLE_ALL_AGE_DEATHS_BDI_demographic_survey_1965.dta"

** BDI Demographic survey 1970-1971
	append using "$hhdata_dir/BDI_demographic_survey_1970-1971/data/USABLE_ALL_AGE_DEATHS_BDI_demographic_survey_1970-1971.dta"	

** BGD 2011 census
	append using "$hhdata_dir/BGD_CENSUS_2011/data/USABLE_ALL_AGE_DEATHS_BGD_CENSUS_2011.dta"	
	
** BWA Demographic Survey 2006
	append using "$hhdata_dir/bwa_demog_survey_2006/data/USABLE_ALL_AGE_DEATHS_BWA_DEMOG_SURVEY_2006.dta"

** BWA census 1981
	append using "$hhdata_dir/BWA_census_1981/data/USABLE_ALL_AGE_DEATHS_BWA_CENSUS_1981.dta"
	
** CMR: Census 1976
	append using "$hhdata_dir/cmr_census_1976/data/USABLE_ALL_AGE_DEATHS_CMR_CENSUS_1976.dta"

** Cote d'Ivoire 1978-1979 Demographic Survey
	append using "$hhdata_dir/CIV_DS_1978_1979/data/USABLE_ALL_AGE_DEATHS_CIV_DS_1978_1979.dta"

** COG census 1984
	append using "$hhdata_dir/COG_census_1984/data/USABLE_ALL_AGE_DEATHS_COG_CENSUS_1984.dta"
	
** Ecuador ENSANUT 2012
	append using "$hhdata_dir/ECU_ENSANUT_2012/data/USABLE_ALL_AGE_DEATHS_ECU_ENSANUT_2012.dta"
	
** Ethiopia Census 1984: EXCLUDED: Only has report data for Addis Ababa
	// append using "$hhdata_dir/ETH_census_1984/data/USABLE_ALL_AGE_DEATHS_ETH_CENSUS_1984.dta" 
	
** HND EDENH 1971-1972
	append using "$hhdata_dir/HND_EDENH_1971_1972/data/USABLE_ALL_AGE_DEATHS_HND_EDENH_1971_1972.dta"
	
** HND survey of living conditions 2004
	append using "$hhdata_dir/HND_SLC_2004/data/USABLE_ALL_AGE_DEATHS_HND_SLC_2004.dta"
	
** IRQ: IMIRA
    append using "$hhdata_dir/irq_imira_2004/data/USABLE_ALL_AGE_DEATHS_IRQ_IMIRA_2004.dta"
	
** KEN: Census 2009
	append using "$hhdata_dir/ken_census_2009/data/USABLE_ALL_AGE_DEATHS_KEN_2009_CENSUS.dta"
	replace VR_SOURCE = "7427#KEN 2009 Census 5% sample" if VR_SOURCE == ""
	
** KEN AIDS Indicator Survey 2007	
	append using "$hhdata_dir/KEN_AIS_2007/data/USABLE_ALL_AGE_DEATHS_KEN_AIS_2007.dta"
	
** KHM 1997 socioeconomic survey
	append using "$hhdata_dir/khm_socioeconomic_survey_1997/data/USABLE_ALL_AGE_DEATHS_KHM_SOCIOECONOMIC_SURVEY_1997.dta"
  
** KIR 2010 census
	append using "$hhdata_dir/KIR_CENSUS_2010/data/USABLE_ALL_AGE_DEATHS_KIR_CENSUS_2010.dta"

** Malawi Population Change Survey 1970-1972
	append using "$hhdata_dir/MWI_POP_CHANGE_SURVEY_1970-1972/data/USABLE_ALL_AGE_DEATHS_MWI_POP_CHANGE_SURVEY_1970-1972.dta"

** Mauritania 1988 Census
	append using "$hhdata_dir/MRT_CENSUS_1988/data/USABLE_ALL_AGE_DEATHS_MRT_CENSUS_1988.dta"	
	
** NAM 2011 census
	append using "$hhdata_dir/NAM_CENSUS_2011/data/USABLE_ALL_AGE_DEATHS_NAM_CENSUS_2011.dta" 
 
** NGA: GHS 2006
    append using "$hhdata_dir/nga_ghs_2006/data/USABLE_ALL_AGE_DEATHS_NGA_GHS_2006.dta"
	
** SLB 2009 census
	append using "$hhdata_dir/SLB_CENSUS_2009/data/USABLE_ALL_AGE_DEATHS_SLB_CENSUS_2009.dta"
	
** Tanzania Census 1967
	append using "$hhdata_dir/TZA_CENSUS_1967/data/USABLE_ALL_AGE_DEATHS_TZA_CENSUS_1967.dta"

** TGO Census 2010
	append using "$hhdata_dir/tgo_census_2010/data/USABLE_ALL_AGE_DEATHS_TGO_CENSUS_2010.dta"
	
** ZAF: October Household Survey 1993, 1995-1998
	append using "$hhdata_dir/zaf_household_survey/data/USABLE_ALL_AGE_DEATHS_ZAF_OCT_HOUSEHOLD_SURVEY_1993.dta"
	append using "$hhdata_dir/zaf_household_survey/data/USABLE_ALL_AGE_DEATHS_ZAF_OCT_HOUSEHOLD_SURVEY_1995.dta"
	append using "$hhdata_dir/zaf_household_survey/data/USABLE_ALL_AGE_DEATHS_ZAF_OCT_HOUSEHOLD_SURVEY_1996.dta"
	append using "$hhdata_dir/zaf_household_survey/data/USABLE_ALL_AGE_DEATHS_ZAF_OCT_HOUSEHOLD_SURVEY_1997.dta"
	append using "$hhdata_dir/zaf_household_survey/data/USABLE_ALL_AGE_DEATHS_ZAF_OCT_HOUSEHOLD_SURVEY_1998.dta"

** ZAF community survey 2007
	append using "$hhdata_dir/ZAF_CS_2007/data/USABLE_ALL_AGE_DEATHS_ZAF_CS_2007.dta"
	
** ZMB: 2008 HHC
    append using "$hhdata_dir/zmb_hhc_2008/data/USABLE_ALL_AGE_DEATHS_ZMB_HHC_2008.dta"
    
** ZMB LCMS
    append using "$hhdata_dir/zmb_lcms/data/USABLE_ALL_AGE_DEATHS_ZMB_LCMS.dta"
    
** ZMB SBS
    append using "$hhdata_dir/zmb_sbs/data/USABLE_ALL_AGE_DEATHS_ZMB_SBS_2009.dta"
	append using "$hhdata_dir/zmb_sbs/data/USABLE_ALL_AGE_DEATHS_ZMB_SBS_2005.dta"
	append using "$hhdata_dir/zmb_sbs/data/USABLE_ALL_AGE_DEATHS_ZMB_SBS_2003.dta" 

** NGA MCSS	
	** append using "$hhdata_dir/nga_mcss_2000_2001/USABLE_NGA_MCSS_2000_2001_HH_DEATHS.dta"

// Drop location ID variable (used as IHME location id above, but filepath of the source below)
	cap drop location_id
 	
** VNM NHS 
	append using "$hhdata_dir/vnm_nhs_2001_2002/data/USABLE_ALL_AGE_DEATHS_1986_NHS.dta"
	
** Papchild surveys: DZA EGY LBN LBY MAR MRT SDN SYR TUN YEM
	append using "$hhdata_dir/papchild/data/USABLE_ALL_AGE_DEATHS_1990_1997_papchild.dta"
	replace SUBDIV = "HOUSEHOLD" if SUBDIV == ""
	cap drop location_id
	
** DHS surveys, ERI 1995-1996 and 2002, NGA 2013, MWI 2010, ZMB 2007, RWA 2005, IND 1998-1999, DOM 2013, UGA 2006, HTI 2005-2005, ZWE 2005-2006, NIC 2001, BGD SP 2001, JOR 1990, DOM_2013, MWI 2010
	append using "$hhdata_dir/ERI_DHS/data/USABLE_ALL_AGE_DEATHS_ERI_DHS.dta"	
	append using "$hhdata_dir/NGA_DHS_2013/data/USABLE_ALL_AGE_DEATHS_NGA_DHS_2013.dta"
	append using "$hhdata_dir/MWI_DHS_2010/data/USABLE_ALL_AGE_DEATHS_MWI_DHS_2010.dta"
	append using "$hhdata_dir/ZMB_DHS_2007/data/USABLE_ALL_AGE_DEATHS_ZMB_DHS_2007.dta"
	append using "$hhdata_dir/RWA_DHS_2005/data/USABLE_ALL_AGE_DEATHS_RWA_DHS_2005.dta"
	// append using "$hhdata_dir/IND_DHS_1998_1999/data/USABLE_ALL_AGE_DEATHS_IND_DHS_1998_1999.dta" // Subnationals have too small of sample sizes to be reliable
	append using "$hhdata_dir/DOM_DHS_2013/data/USABLE_ALL_AGE_DEATHS_DOM_DHS_2013.dta"
	append using "$hhdata_dir/UGA_DHS_2006/data/USABLE_ALL_AGE_DEATHS_UGA_DHS_2006.dta"	
	append using "$hhdata_dir/HTI_DHS_2005_2006/data/USABLE_ALL_AGE_DEATHS_HTI_DHS_2005_2006.dta"
	append using "$hhdata_dir/ZWE_DHS_2005_2006/data/USABLE_ALL_AGE_DEATHS_ZWE_DHS_2005_2006.dta"
	append using "$hhdata_dir/NIC_DHS_2001/data/USABLE_ALL_AGE_DEATHS_NIC_DHS_2001.dta"
	append using "$hhdata_dir/BGD_SP_DHS_2001/data/USABLE_ALL_AGE_DEATHS_BGD_SP_DHS_2001.dta"
	append using "$hhdata_dir/JOR_DHS_1990/data/USABLE_ALL_AGE_DEATHS_JOR_DHS_1990.dta"
	
	/* Excluded, nonrepresentative
	append using "$hhdata_dir/DOM_SP_DHS_2013/data/USABLE_ALL_AGE_DEATHS_DOM_SP_DHS_2013.dta"
	replace SUBDIV = "HOUSEHOLD_SP_DHS" if regexm(VR_SOURCE,"DOM_SP_DHS_2013")
	*/
	
** ZAF NIDS
	append using "$hhdata_dir/ZAF_NIDS_2010_2011/data/USABLE_ALL_AGE_DEATHS_ZAF_NIDS_2010_2011.dta" 

** TZA LSMS
	append using "$hhdata_dir/TZA_LSMS_2008_2009/data/USABLE_ALL_AGE_DEATHS_TZA_LSML_2008_2009.dta" 
	
	replace SUBDIV = "HOUSEHOLD" if SUBDIV == ""

** Subnationals not previously run at the national level
	** IND SAGE
	// append using "$hhdata_dir/IND_SAGE_2007/data/NEW_USABLE_ALL_AGE_DEATHS_IND_SAGE_2007.dta" 
	
	** MEX SAGE
	append using "$hhdata_dir/MEX_SAGE_2009_2010/data/USABLE_ALL_AGE_DEATHS_MEX_SAGE_2009_2010.dta" 
	
	** CHN SAGE
	append using "$hhdata_dir/CHN_SAGE_2008_2010/data/USABLE_ALL_AGE_DEATHS_CHN_SAGE_2008_2010.dta" 
	replace SUBDIV = "HOUSEHOLD" if SUBDIV == ""

	** IND DLHS 2002-2005
	 // append using "$hhdata_dir/IND_DLHS_2002/data/NEW_USABLE_ALL_AGE_DEATHS_IND_DLHS_2002.dta" 
	
	** IND DLHS 2007-2008
	// append using "$hhdata_dir/ind_DLHS_2007/data/NEW_USABLE_ALL_AGE_DEATHS_IND_DHSL_2007_2008.dta" 
	// replace SUBDIV = "HOUSEHOLD_DLHS" if SUBDIV == "" | regexm(VR_SOURCE,"IND_DLHS")
	
	** IND HDS
	// append using "$hhdata_dir/IND_HDS_2004_2005/data/USABLE_ALL_AGE_DEATHS_IND_HDS_2004_2005.dta" 
	
	** ZAF CS IPUMS 2007
	append using "$hhdata_dir/IPUMS/data/USABLE_ALL_AGE_DEATHS_ZAF_IPUMS_2007.dta" 
	
	** ZAF IPUMS 2001
	append using "$hhdata_dir/IPUMS/data/USABLE_ALL_AGE_DEATHS_ZAF_IPUMS_2001.dta" 
	
	** IND MCSS
	// append using "$hhdata_dir/ind_MCSS_2000_2000/data/NEW_USABLE_ALL_AGE_DEATHS_IND_DHSL_2000_2001.dta" 
	
	replace SUBDIV = "HOUSEHOLD" if SUBDIV == ""

** Subnationals previously run at the national level 
	** ZAF Census 2011
	append using "$hhdata_dir/zaf_census_2011/data/USABLE_ALL_AGE_DEATH_ZAF_CENSUS_2011.dta" 
	
	** IND DHS 1998-1999
	// append using "$hhdata_dir/IND_DHS_1998_1999/data/USABLE_ALL_AGE_DEATHS_IND_DHS_1998_1999.dta" 
	// duplicates issues
	// replace SUBDIV = "HOUSEHOLD_DHS_1998-1999" if SUBDIV == "HOUSEHOLD" & VR_SOURCE == "19950#IND_DHS_1998_1999" & inlist(YEAR, 1998, 1999, 2000)

	replace SUBDIV = "HOUSEHOLD" if SUBDIV == ""
	
	** SAU_CENSUS_2004: Only has Saudi (no non-Saudi) deaths, exclude
	// append using "$hhdata_dir/SAU_CENSUS_2004/data/USABLE_ALL_AGE_DEATHS_SAU_CENSUS_2004.dta"
	
	** SAU_DRB_2007: Only has Saudi (no non-Saudi) deaths, exclude
	// append using "$hhdata_dir/SAU_DRB_2007/data/USABLE_ALL_AGE_DEATHS_SAU_DRB_2007.dta"
	
** SLV_IPUMS_CENSUS
	append using "$hhdata_dir/SLV_IPUMS_CENSUS_2007/data/USABLE_ALL_AGE_DEATHS_SLV_IPUMS_CENSUS_2007.dta"
	
** DOM_ENHOGAR
	append using "$hhdata_dir/dom_enhogar_2006/data/USABLE_ALL_AGE_DEATHS_DOM_ENHOGAR_2006.dta"
	
** GIN_Demosurvey_1954_1955
	append using "$hhdata_dir/GIN_Demosurvey_1954_1955/data/USABLE_ALL_AGE_DEATHS_GIN_DemoSurvey_1954_1955.dta"
	
** THA Population Change survey
	append using "$hhdata_dir/THA_SurveyPopChange_2005_06/data/USABLE_ALL_AGE_DEATHS_THA_SPC_2005_2006.dta"
	
** NRU Census 2011
	append using "$hhdata_dir/NRU_Census_2011/data/USABLE_ALL_AGE_DEATHS_NRU_CENSUS_2011.dta"
	
** MWI FFS 1984
	append using "$hhdata_dir/MWI_FFS_1984/data/USABLE_ALL_AGE_DEATHS_MWI_FFS_1984.dta"
	
** DJI Demographic Survey
	append using "$hhdata_dir/DJI_Demosurvey_1991/data/USABLE_ALL_AGE_DEATHS_DJI_DEMOSURVEY_1991.dta"
	replace SUBDIV = "HOUSEHOLD" if SUBDIV == ""

** IND DLHS4 2012-2014
	append using "$hhdata_dir/IND_DLHS4_2012_2014/data/USABLE_ALL_AGE_DEATHS_IND_DLHS_2012_2014.dta"
	replace SUBDIV = "HOUSEHOLD" if SUBDIV == ""
	replace SUBDIV = "HOUSEHOLD_DLHS" if regexm(VR_SOURCE,"DLHS")
	
** ***********************************************************************
** Drop duplicates and other problematic data
** ***********************************************************************
	noisily: display in green "DROP OUTLIERS AND MAKE CORRECTIONS TO THE DATABASE"

** Drop if AREA is urban or rural. We assume missing means national, not urban or rural
	keep if AREA == 0 | AREA == .

** Drop unknown sex
	drop if SEX == 9
	
** Drop if everything is missing 
	lookfor DATUM
	return list
	local misscount = 0
		foreach var of varlist `r(varlist)' {
			local misscount = `misscount'+1
		}
	egen misscount = rowmiss(DATUM*)
	drop if misscount == `misscount'
	drop misscount
	
** Drop duplicates 
	** General Rule: Keep WHO from causes of deaths over WHO over HMD over DYB
		** Exception: In some countries we prefer HMD over all other sources
		** However, HMD doesn't have all the years that WHO has (particularly recent years), so keep the WHO data when HMD doesn't have that country-year
		duplicates tag COUNTRY YEAR SEX if inlist(COUNTRY, "DEU", "TWN", "ESP") & (VR_SOURCE == "HMD" | regexm(VR_SOURCE, "WHO")==1), generate(deu_twn_esp_duplicates)
		drop if inlist(COUNTRY, "DEU", "TWN", "ESP") & deu_twn_esp_duplicates != 0 & VR_SOURCE != "HMD" & YEAR != 2012
		drop deu_twn_esp_duplicates
		
		** Exception: In some country-years the WHO data are inconsistent and we prefer other sources 
		duplicates tag COUNTRY YEAR SEX if COUNTRY=="ISR", generate(isr_duplicates)
			drop if strpos(VR_SOURCE,"DYB") == 0 & isr_duplicates != 0 & CO == "ISR"
			drop isr_duplicates
		drop if CO == "PHL" & VR_SOURCE == "WHO_causesofdeath" & YEAR == 1985
		drop if CO == "BRA" & strpos(VR_SOURCE, "WHO")!=0 & YEAR<=1980
		drop if CO == "ARG" & YEAR == 2006 & VR_SOURCE=="WHO_causesofdeath"
		drop if CO == "ARG" & inlist(YEAR, 1966, 1967) & VR_SOURCE=="WHO"
		// drop if CO == "BEL" & VR_SOURCE=="WHO_causesofdeath" & YEAR < 2011
		drop if CO == "BEL" & VR_SOURCE == "WHO_causesofdeath" & inlist(YEAR, 1986, 1987)
		drop if CO == "MYS" & VR_SOURCE=="WHO_causesofdeath"
		drop if CO == "MYS" & VR_SOURCE=="WHO" & (YEAR > 1999 & YEAR < 2009)
		drop if CO == "KOR" & YEAR >= 1985 & YEAR <= 1995 & VR_SOURCE=="WHO"
		drop if CO == "FJI" & YEAR==1999 & VR_SOURCE == "WHO_causesofdeath"
		** drop if CO == "ARG" & (YEAR == 1966 | YEAR == 1967) & VR_SOURCE == "WHO_causesofdeath"	
		drop if CO == "PAK" & (YEAR == 1993 | YEAR == 1994) & strpos(VR_SOURCE,"WHO") != 0	
		drop if CO == "BHS" & (YEAR == 1969 | YEAR == 1971) & VR_SOURCE == "WHO_causesofdeath"
		drop if CO == "AUS" & YEAR == 2006 & VR_SOURCE == "WHO_causesofdeath" 
		// drop if CO == "PRT" & (YEAR == 2005 | YEAR == 2006) & VR_SOURCE == "WHO_causesofdeath"
		// drop if CO == "DZA" & (YEAR == 2005 | YEAR == 2006) & VR_SOURCE == "WHO_causesofdeath"
		drop if CO == "EGY" & YEAR == 1954 & VR_SOURCE == "WHO"
		drop if CO == "EGY" & (YEAR >= 1955 & YEAR <= 1964) & VR_SOURCE == "WHO_causesofdeath"
		// drop if CO == "TUR" & YEAR >= 2009 & VR_SOURCE == "WHO_causesofdeath"
		drop if CO == "GBR" & VR_SOURCE == "ADRIAN_DAVIS" & YEAR < 2011
		drop if CO == "GBR" & VR_SOURCE == "WHO_causesofdeath" & inlist(YEAR, 2011, 2012, 2013)
		
		** Exception: We sometimes prefer country-specific sources (kept in CoD for 2012-2013)
		// drop if CO == "TUR" & regexm(VR_SOURCE, "WHO") & (YEAR >= 2009 & YEAR <2012)
	
	** Take out duplicates from the DYB for the same country year  
	gsort +COUNTRY +YEAR +SEX -DATUMTOT 
	duplicates drop COUNTRY YEAR SEX if strpos(VR_SOURCE, "DYB") != 0, force
	
	** Drop WHO internal VR if we have other sources
	duplicates tag COUNTRY YEAR SEX if SUBDIV == "VR", g(dup) 
    replace dup = 0 if dup == .
    drop if dup != 0 & VR_SOURCE == "WHO_internal"
    drop dup
    
    ** Drop DYB VR if we have other sources
    duplicates tag COUNTRY YEAR SEX if SUBDIV == "VR", g(dup) 
    replace dup = 0 if dup == .
    drop if dup != 0 & strpos(VR_SOURCE,"DYB") != 0
    drop dup
	
	** Drop HMD VR if we have other sources 
	duplicates tag COUNTRY YEAR SEX if SUBDIV == "VR", g(dup) 
    replace dup = 0 if dup == .
    drop if dup != 0 & strpos(VR_SOURCE,"HMD") != 0 
    drop dup
	
	** Drop original WHO VR if we have other sources 
	duplicates tag COUNTRY YEAR SEX if SUBDIV == "VR", g(dup) 
    replace dup = 0 if dup == .
    drop if dup != 0 & VR_SOURCE == "WHO"
    drop dup
	
    ** Drop CHN national data from provincial level estimates (AS: 1/23/2014)
    duplicates tag CO YEAR SEX if SUBDIV == "CENSUS" & CO == "CHN", g(dup)
	replace dup = 0 if dup == . 
    drop if dup != 0 & CO == "CHN" & regexm(VR_SOURCE,"CHN_PROV_CENSUS")
	drop dup
	
	** Drop DYB Census if we have other sources
	duplicates tag COUNTRY YEAR SEX if SUBDIV == "CENSUS", g(dup)
	replace dup = 0 if dup == . 
	drop if dup != 0 & regexm(VR_SOURCE, "DYB") 
	drop dup

    ** Drop Alan's data if we have other sources
    duplicates tag CO YEAR SEX if SUBDIV == "VR", g(dup)
	replace dup = 0 if dup == . 
    drop if dup != 0 & VR_SOURCE == "ALAN_LOPEZ"    
    ** AS: 1 AUG 2013
    drop if dup !=0 & VR_SOURCE == "VR" & CO == "AUS" 
    drop dup 
    
    ** drop USA NCHS data if we have other sources (AS: 1 AUG 2013)
    duplicates tag CO YEAR SEX if SUBDIV == "VR", g(dup)
	replace dup = 0 if dup == . 
    drop if dup != 0 & CO == "USA" & VR_SOURCE == "NCHS"
    drop dup
    

	** drop MNG, LBY, GBR duplicates
	duplicates tag COUNTRY YEAR SEX SUBDIV, gen(dup)
	drop if COUNTRY == "LBY" & VR_SOURCE == "report" & SUBDIV == "VR" & inlist(YEAR, 2006, 2007, 2008) & dup ==1
	drop if COUNTRY == "MNG" & VR_SOURCE == "ALAN_LOPEZ_MNG_YEARBOOK" & SUBDIV == "VR" & inlist(YEAR, 2004, 2005) & dup ==1
	* for now, don't drop ADRIAN DAVIS source; the CoD subnational VR for GBR is not reliable. instead, drop COD
	* drop if VR_SOURCE == "ADRIAN_DAVIS" & SUBDIV == "VR" & YEAR >= 1979 & YEAR <= 2011 & dup == 1
	drop if regexm(COUNTRY,"GBR_") & SUBDIV == "VR" & regexm(VR_SOURCE, "WHO") & YEAR < 2013 // Don't need duplicate (iso3s don't match up anymore)
	drop dup
	
	** drop LTU duplicates: we have WHO (causes of death) for 2010, so don't need the report
	duplicates tag COUNTRY YEAR SEX SUBDIV, gen(dup)
	drop if dup == 1 & COUNTRY == "LTU" & YEAR == 2010 & SUBDIV == "VR" & VR_SOURCE == "135808#LTU COD REPORT 2010"
	drop if dup == 1 & COUNTRY == "LTU" & YEAR == 2011 & SUBDIV == "VR" & VR_SOURCE == "135810#LTU COD REPORT 2011"
	drop if dup == 1 & COUNTRY == "LTU" & YEAR == 2012 & SUBDIV == "VR" & VR_SOURCE == "135811#LTU COD REPORT 2012"
	
** Drop VR years before Cyprus split
	drop if YEAR < 1974 & CO == "CYP"
	drop dup
	
** PNG fix - DDM terminal age group issue
	replace DATUM75plus = DATUM75to79 if CO =="PNG" & YEAR == 1977
	foreach var of varlist DATUM75to79 DATUM80to84 DATUM80plus DATUM85plus {
		replace `var' = . if CO =="PNG" & YEAR == 1977
	}

** IDN separate SUPAS and SUSENAS and 2000 Census-Survey
	replace SUBDIV = "SUSENAS" if strpos(VR_SOURCE,"SUSENAS") !=0
	replace SUBDIV = "SUPAS" if strpos(VR_SOURCE,"SUPAS") !=0
	replace VR_SOURCE = "2000_CENS_SURVEY" if VR_SOURCE == "SURVEY" & CO == "IDN" & YEAR == 1999
	replace SUBDIV = "2000_CENS_SURVEY" if VR_SOURCE == "2000_CENS_SURVEY" & CO == "IDN" & YEAR == 1999
	
** Drop Canada source and use WHO VR (same numbers)
	duplicates tag COUNTRY YEAR SEX SUBDIV, gen(dup)
	drop if dup == 1 & COUNTRY == "CAN" & (YEAR == 2010 | YEAR == 2011) & SUBDIV == "VR" & VR_SOURCE == "STATISTICS_CANADA_VR_121924"
	
** Drop Chile source and use WHO VR (same numbers)
	drop if dup == 1 & COUNTRY == "CHL" & YEAR == 2011 & SUBDIV == "VR"	& VR_SOURCE == "CHL_MOH"

** Drop China DC survey: Duplicate of China 1 % survey
	drop if dup == 1 & COUNTRY == "CHN" & YEAR == 2005 & SUBDIV == "DC" & VR_SOURCE == "DC"
** Drop China DSP duplicates -- we will keep the 1991-1995 data from CHN_DSP, but use Lozano for 1996 onwards 
// Lozano has more raw data without significant data cleaning etc. present in the other file)
	drop if dup == 1 & COUNTRY == "CHN" & YEAR >= 1996 & SUBDIV == "DSP" & VR_SOURCE == "CHN_DSP"
	
** Fix age group naming for youngest age groups 
	replace DATUM0to0 = DATUM0to1 if DATUM0to0 == . & DATUM0to1 != . & (DATUM1to4 != . | DATUM0to4 != .)
	replace DATUM0to1 = . if DATUM0to0 != . & (DATUM1to4 != . | DATUM0to4 != .)		

** Relabel source_type for surveys that overlap time-wise but have same source type
** We want to analyze them separately -- don't want them to be considered the same source
	replace SUBDIV = "VR-SSA" if VR_SOURCE == "stats_south_africa" & COUNTRY == "ZAF" // Adjusted VR source?
	replace SUBDIV = "HOUSEHOLD_HHC" if VR_SOURCE == "ZMB_HHC" & COUNTRY == "ZMB"
	
** drop VR in 2009 in LKA from S_Dharmaratne because it duplices data in the COD file
	drop if COUNTRY=="LKA" & YEAR==2009 & VR_SOURCE=="S_Dharmaratne"



** ***********************************************************************
** Format the database 
** ***********************************************************************
	noisily: display in green "FORMAT THE DATABASE"

	drop RECTYPE RELIABIL AREA MONTH DAY 
	cap drop _fre
	// replace iso3 = COUNTRY if iso3 == ""
	rename COUNTRY iso3
	gen sex = "both" if SEX == 0
	replace sex = "male" if SEX == 1
	replace sex = "female" if SEX == 2
	drop SEX

	rename YEAR year
	rename VR_SOURCE deaths_source
	rename SUBDIV source_type
	rename FOOTNOTE deaths_footnote
	
	// Add locations
	replace iso3 = "" if ihme_loc_id != "" // We don't want any issues if iso3 was filled out as national but data is sub or something
	merge m:1 iso3 using `countrycodes', update
	levelsof iso3 if _merge == 1
	levelsof iso3 if _merge == 2
	levelsof iso3 if ihme_loc_id == "" 
	keep if ihme_loc_id != "" & _merge != 2 // If it merged ok or updated, or if the country had ihme_loc_id alreadybut not iso3
	drop _merge iso3
	merge m:1 ihme_loc_id using `countrymaster', update // Update country variable if ihme_loc_id was already present
	keep if ihme_loc_id != "" & _merge != 2
	drop _merge iso3
	
	// Recode all data prepped as China as China Mainland
	replace ihme_loc_id = "CHN_44533" if ihme_loc_id == "CHN"
		
	order ihme_loc_id country sex year deaths_source source_type deaths_footnote *
	
	replace deaths_source = "DYB" if regexm(deaths_source, "DYB_")

    ** if we have data for age 0 and ages 1-4, then drop data for ages 0-4 pooled
    replace DATUM0to4 = . if DATUM0to0 != . & DATUM1to4 != .
	
** ***********************************************************************
** Combine males and females to get both if they're not already in there 
** ***********************************************************************
	noisily: display in green "Generate both sexes combined"
	
	** drop both sexes combined if it's not from the same source as male and female
	preserve
	keep ihme_loc_id sex year deaths_source source_type
	reshape wide deaths_source, i(ihme_loc_id year source_type) j(sex, string)
	keep if (deaths_sourceboth != deaths_sourcefemale | deaths_sourceboth != deaths_sourcemale) & deaths_sourceboth != "" & deaths_sourcefemale != "" & deaths_sourcemale != ""
	keep ihme_loc_id year source_type
	tempfile dropboth
	save `dropboth'
	restore
	
	merge m:1 ihme_loc_id year source_type using `dropboth'
	drop if _m == 3 & sex == "both"
	drop _m 
	
	** drop male or female if the other is missing 
	preserve
	keep ihme_loc_id sex year deaths_source source_type
	reshape wide deaths_source, i(ihme_loc_id year source_type) j(sex, string)
	keep if (deaths_sourcemale == "" & deaths_sourcefemale != "") | (deaths_sourcemale != "" & deaths_sourcefemale == "")
	keep ihme_loc_id year source_type
	tempfile dropone
	save `dropone'
	restore
	
	merge m:1 ihme_loc_id year source_type using `dropone'
	drop if _m == 3 & sex != "both"
	drop _m 	
	
	** calculate both sexes combined numbers where they don't already exist 
	preserve
	bysort ihme_loc_id country year source_type: egen maxs = count(year)
	keep if maxs == 2

	lookfor DATUM
	return list
		foreach var of varlist `r(varlist)' {
			replace `var' = -1000000 if `var' == .
		}

	collapse (sum) DATUM*, by(ihme_loc_id country year deaths_source source_type deaths_footnote)
	gen sex = "both"

	lookfor DATUM
	return list
		foreach var of varlist `r(varlist)' {
			replace `var' = . if `var' < -100000
		}

	tempfile moreboth
	save `moreboth', replace
	restore
	append using `moreboth'

	tempfile master
	save `master'

	
** ***********************************************************************
** Split sources to be DDM'd seperately 
** ***********************************************************************
	noisily: display in green "Split sources to be DDM'd seperately"	
	
** We want DSP to be analyzed separately before and after the 3rd National Survey 
	replace source_type = "DSP-1996-2000" if ihme_loc_id == "CHN_44533" & year >= 1996 & year <= 2000 & source_type == "DSP"
	replace source_type = "DSP-2004-2010" if ihme_loc_id == "CHN_44533" & year >= 2004 & year <= 2010 & source_type == "DSP"

** We want SRS to be analyzed in five parts
	// This is because the sampling schemes are changed every 10 years or so
	// http://censusindia.gov.in/Vital_Statistics/SRS/Sample_Registration_System.aspx
	replace source_type = "SRS-1970-1976" if ihme_loc_id == "IND" & year >= 1970 & year <= 1976 & source_type == "SRS"
	replace source_type = "SRS-1976-1982" if ihme_loc_id == "IND" & year >= 1977 & year <= 1982 & source_type == "SRS"
	replace source_type = "SRS-1983-1992" if ihme_loc_id == "IND" & year >= 1983 & year <= 1992 & source_type == "SRS"
	replace source_type = "SRS-1993-2003" if regexm(ihme_loc_id, "IND") & year >= 1993 & year <= 2003 & source_type == "SRS" 
	replace source_type = "SRS-2004-2013" if regexm(ihme_loc_id, "IND") & year >= 2004 & year <= 2013 & source_type == "SRS" 
	
** We want Korea VR analyzed in two parts since there were two different collection methods
	replace source_type = "VR1" if ihme_loc_id == "KOR" & year <= 1977
	replace source_type = "VR2" if ihme_loc_id == "KOR" & year > 1977
	
** We want Turkey VR analyzed in two parts, before and after the system became national in 2009 
	replace source_type = "VR1" if ihme_loc_id == "TUR" & source_type == "VR" & year < 2009 
	replace source_type = "VR2" if ihme_loc_id == "TUR" & source_type == "VR" & year >= 2009 
    
** We want China provincial DSP analyzed separately before and after 3rd National survey in 2004
    replace source_type = "DSP1" if source_type == "DSP" & deaths_source == "CHN_DSP" & year < 1996 
	replace source_type = "DSP2" if source_type == "DSP" & deaths_source == "CHN_DSP" & year >= 1996 & year < 2004 
    replace source_type = "DSP3" if source_type == "DSP" & deaths_source == "CHN_DSP" & year >= 2004 
	
** We want ZAF data analyzed separately before and after 2002, when it started to become more complete
	replace source_type = "VR_pre2002" if regexm(ihme_loc_id,"ZAF") & year <= 2002 & source_type == "VR"
	replace source_type = "VR_post2002" if regexm(ihme_loc_id,"ZAF") & year > 2002 & source_type == "VR"
	
** Let's see if the Iran data pre-2003 (29/30 provinces) is different from post-2003 (urban cemetary data)
	replace source_type = "IRN_VR_pre2003" if ihme_loc_id == "IRN" & year <= 2003 & source_type == "VR"
	replace source_type = "IRN_VR_post2003" if ihme_loc_id == "IRN" & year > 2003 & source_type == "VR"
	
** MEX VR most recent years are a lot more complete suddenly
	replace source_type = "MEX_VR_pre2011" if regexm(ihme_loc_id,"MEX") & year <= 2011 & source_type == "VR"
	replace source_type = "MEX_VR_post2011" if regexm(ihme_loc_id,"MEX") & year > 2011 & source_type == "VR"
	
	
** ***********************************************************************
** Save
** ***********************************************************************

** keeping appropriate variables - extra variables can have far reaching consequences in the DDM process
	replace nid = NID if nid == . & NID != .
	rename nid deaths_nid
	tostring deaths_nid, replace
	replace deaths_nid = "" if deaths_nid == "." | deaths_nid == " "
	
	keep ihme_loc_id country sex year deaths_source source_type deaths_footnote DATUM* deaths_nid
	order ihme_loc_id country sex year deaths_source source_type deaths_footnote deaths_nid DATUM* 
	drop if year < 1930
	replace year = floor(year) 
		* want to put the ZAF 2007 community survey in 2006
		replace year = 2006.69 if ihme_loc_id == "ZAF" & year == 2006 & deaths_source == "IPUMS_HHDEATHS" & source_type == "SURVEY"
	
** final check to make sure duplicates haven't creeped back in
	isid ihme_loc_id sex year source_type

** save
	compress
	save "$save_file", replace
