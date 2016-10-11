use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\output\MASTER PREVALENCE FILES\master_met_need_prevalence_11aug2016_all_ages_new_calculation_new_extraction.dta", clear

** drop subnational surveys
drop if filename == "KEN_BUNGOMA_MICS5_2013_2014_WN_Y2016M03D14.DTA"
drop if filename == "KEN_KAKAMEGA_MICS5_2013_2014_WN_Y2016M03D14.DTA"
drop if filename == "KEN_TURKANA_MICS5_2013_2014_WN_Y2016M03D14.DTA"
drop if filename == "MKD_ROMA_SETTLEMENTS_MICS4_2011_WN_Y2013M10D04.DTA"
drop if filename == "MNE_MICS5_2013_WN_ROMA_Y2015M01D12.DTA"
** drop if filename == "SDN_SOUTH_MICS4_2010_WN_Y2015M03D25.DTA" // lol south sudan isn't subnational
drop if filename == "SOM_NORTHEAST_ZONE_MICS4_2011_WN_Y2015M03D25.DTA"
drop if filename == "SRB_MICS5_2014_WN_ROMA_Y2015M02D09.DTA"
drop if filename == "NER_NIAMEY_PMA2020_2015_R1_HHQFQ_Y2016M05D13.DTA"
drop if filename == "NGA_LAGOS_PMA2020_2014_R1_HHQFQ_Y2016M05D17.DTA"
drop if filename == "NGA_KADUNA_PMA2020_2014_R1_HHQFQ_Y2016M05D17.DTA"


** drop YEM & RWA survey with no unmet need data
drop if filename == "YEM_DHS2_1991_1992_WN_Y2008M09D23.DTA"
drop if filename == "RWA_ITR_DHS5_2007_2008_WN_Y2010M08D25.DTA"

** replace TLS outlier  with Statcompile data
replace met_need_modern_prev = 39.2 if iso3 == "TLS"

** replace other outliers with Statcompile data
replace met_need_modern_prev = .365 if iso3 == "MOZ" & ihme_start_year == 2011
replace met_need_modern_prev = .314 if iso3 == "TCD" & ihme_start_year == 2004
replace met_need_modern_prev = .127 if iso3 == "YEM" & ihme_start_year == 1991
replace met_need_modern_prev = .385 if iso3 == "RWA" & ihme_start_year == 2007
replace met_need_modern_prev = .359 if iso3 == "NER" & ihme_start_year == 2006 




			
// generate a variable for sample size and include sample sizes of surveys extracted through ubcov.  this will hopefully make it easier to calculate variance for st-gpr.

gen sample_size = .
replace sample_size = 11735 if filename == "ZAF_DHS3_1998_WN_Y2008M09D23.DTA"
replace sample_size = 9256 if filename == "MAR_DHS2_1992_WN_Y2008M09D23.DTA"
replace sample_size = 8531 if filename == "UGA_DHS5_2006_WN_Y2008M09D23.DTA"
replace sample_size = 7246 if filename == "UGA_DHS4_2000_2001_WN_Y2008M09D23.DTA"
replace sample_size = 1968 if filename == "UGA_PMA2020_2015_R2_HHQFQ_Y2016M05D17.DTA"
replace sample_size = 1943 if filename == "UGA_PMA2020_2014_R1_HHQFQ_Y2016M05D13.DTA"
replace sample_size = 1750 if filename == "UGA_DHS3_1995_WN_Y2008M09D23.DTA"
replace sample_size = 2102 if filename == "UGA_PMA2020_2015_R3_HHQFQ_Y2016M05D16.DTA"
replace sample_size = 8674 if filename == "UGA_DHS6_2011_WN_Y2012M10D11.DTA"
replace sample_size = 12476 if filename == "BFA_DHS4_2003_WN_Y2008M09D23.DTA"
replace sample_size = 6445 if filename == "BFA_DHS3_1998_1999_WN_Y2008M09D23.DTA"
replace sample_size = 6354 if filename == "BFA_DHS2_1992_1993_WN_Y2008M09D23.DTA"
replace sample_size = 17087 if filename == "BFA_DHS6_2010_2011_WN_Y2012M11D19.DTA"
replace sample_size = 6128 if filename == "ZWE_DHS3_1994_WN_Y2008M09D23.DTA"
replace sample_size = 5907 if filename == "ZWE_DHS4_1999_WN_Y2008M09D23.DTA"
replace sample_size = 8907 if filename == "ZWE_DHS5_2005_2006_WN_Y2008M09D23.DTA"
replace sample_size = 9171 if filename == "ZWE_DHS6_2010_2011_WN_Y2012M04D05.DTA"
replace sample_size = 6688 if filename == "ETH_PMA2020_2014_R1_HHQFQ_Y2016M05D12.DTA"
replace sample_size = 6888 if filename == "ETH_PMA2020_2014_R2_HHQFQ_Y2016M05D12.DTA"
replace sample_size = 4155 if filename == "ETH_PMA2020_2015_R3_HHQFQ_Y2016M05D12.DTA"
replace sample_size = 4987 if filename == "SWZ_DHS5_2006_2007_WN_Y2008M09D23.DTA"
replace sample_size = 3040 if filename == "CIV_DHS3_1998_1999_WN_Y2008M09D23.DTA"
replace sample_size = 10060 if filename == "CIV_DHS6_2011_2012_WN_Y2013M09D13.DTA"
replace sample_size = 8099 if filename == "CIV_DHS3_1994_WN_Y2008M09D23.DTA"
replace sample_size = 3771 if filename == "KAZ_DHS3_1995_WN_Y2008M09D23.DTA"
replace sample_size = 4800 if filename == "KAZ_DHS4_1999_WN_Y2008M09D23.DTA"
replace sample_size = 7728 if filename == "MRT_DHS_2000_2001_WN_Y2008M09D23.DTA"
replace sample_size = 13497 if filename == "RWA_DHS7_2014_2015_WN_Y2016M05D10.DTA"
replace sample_size = 13671 if filename == "RWA_DHS6_2010_2011_WN_Y2012M03D22.DTA"
replace sample_size = 11321 if filename == "RWA_DHS4_2005_WN_Y2008M09D23.DTA"
replace sample_size = 6551 if filename == "RWA_DHS2_1992_WN_Y2008M09D23.DTA"
replace sample_size = 10421 if filename == "RWA_DHS4_2000_WN_Y2008M09D23.DTA"
replace sample_size = 9804 if filename == "NAM_DHS5_2006_2007_WN_Y2008M10D22.DTA"
replace sample_size = 5421 if filename == "NAM_DHS2_1992_WN_Y2008M09D23.DTA"
replace sample_size = 6755 if filename == "NAM_DHS4_2000_WN_Y2008M09D23.DTA"
replace sample_size = 21762 if filename == "EGY_DHS6_2014_WN_Y2015M05D11.DTA"
replace sample_size = 13745 if filename == "MOZ_DHS6_2011_WN_Y2013M05D02.DTA"
replace sample_size = 12418 if filename == "MOZ_DHS4_2003_WN_Y2008M09D23.DTA"
replace sample_size = 8779 if filename == "MOZ_DHS3_1997_WN_Y2008M09D23.DTA"
replace sample_size = 5884 if filename == "CAF_DHS3_1994_1995_WN_Y2008M09D23.DTA"
replace sample_size = 6183 if filename == "GAB_DHS4_2000_2001_WN_Y2008M09D23.DTA"
replace sample_size = 8422 if filename == "GAB_DHS6_2012_WN_Y2013M07D15.DTA"
replace sample_size = 17375 if filename == "MDG_DHS5_2008_2009_WN_Y2010M06D18.DTA"
replace sample_size = 6260 if filename == "MDG_DHS2_1992_WN_Y2008M09D23.DTA"
replace sample_size = 7060 if filename == "MDG_DHS3_1997_WN_Y2008M09D23.DTA"
replace sample_size = 7949 if filename == "MDG_DHS4_2003_2004_WN_Y2008M09D23.DTA"
replace sample_size = 38948 if filename == "NGA_DHS6_2013_WN_Y2014M06D17.DTA"
replace sample_size = 33385 if filename == "NGA_DHS5_2008_WN_Y2009M11D23.DTA"
replace sample_size = 7620 if filename == "NGA_DHS4_2003_WN_Y2008M09D23.DTA"
replace sample_size = 8781 if filename == "NGA_DHS2_1990_WN_Y2008M09D23.DTA"
replace sample_size = 13137 if filename == "TLS_DHS6_2009_2010_WN_Y2011M01D07.DTA"
replace sample_size = 9142 if filename == "GIN_DHS6_2012_WN_Y2014M01D30.DTA"
replace sample_size = 7954 if filename == "GIN_DHS5_2005_WN_Y2008M09D23.DTA"
replace sample_size = 6753 if filename == "GIN_DHS4_1999_WN_Y2008M09D23.DTA"
replace sample_size = 4849 if filename == "MWI_DHS2_1992_WN_Y2008M09D23.DTA"
replace sample_size = 23020 if filename == "MWI_DHS6_2010_WN_Y2011M10D13.DTA"
replace sample_size = 13220 if filename == "MWI_DHS4_2000_WN_Y2008M09D23.DTA"
replace sample_size = 11698 if filename == "MWI_DHS4_2004_2005_WN_Y2008M09D23.DTA"
replace sample_size = 9656 if filename == "TJK_DHS6_2012_WN_Y2013M12D04.DTA"
replace sample_size = 6085 if filename == "TCD_DHS4_2004_WN_Y2008M09D23.DTA"
replace sample_size = 7454 if filename == "TCD_DHS3_1996_1997_WN_Y2008M09D23.DTA"
replace sample_size = 6621 if filename == "LSO_DHS7_2014_WN_Y2016M06D16.DTA"
replace sample_size = 7624 if filename == "LSO_DHS6_2009_2010_WN_Y2011M03D01.DTA"
replace sample_size = 5665 if filename == "VNM_DHS4_2002_WN_Y2008M09D23.DTA"
replace sample_size = 5664 if filename == "VNM_DHS3_1997_WN_Y2008M09D23.DTA"
replace sample_size = 11352 if filename == "JOR_DHS6_2012_WN_Y2015M08D05.DTA"
replace sample_size = 6006 if filename == "JOR_DHS4_2002_WN_Y2008M09D23.DTA"
replace sample_size = 10109 if filename == "JOR_ITR_DHS6_2009_WN_Y2010M11D03.DTA"
replace sample_size = 5548 if filename == "JOR_DHS3_1997_WN_Y2008M09D23.DTA"
replace sample_size = 10876 if filename == "JOR_DHS5_2007_WN_Y2008M09D23.DTA"
replace sample_size = 6461 if filename == "JOR_DHS2_1990_WN_Y2008M09D23.DTA"
replace sample_size = 18754 if filename == "KHM_DHS6_2010_2011_WN_Y2011M10D26.DTA"
replace sample_size = 17578 if filename == "KHM_DHS7_2014_WN_Y2015M11D06.DTA"
replace sample_size = 15351 if filename == "KHM_DHS4_2000_WN_Y2008M09D23.DTA"
replace sample_size = 1653 if filename == "GHA_PMA2020_2014_R3_GHA_PMA2020_2014_R2_HHQFQ_Y2016M05D16.DTA"
replace sample_size = 4916 if filename == "GHA_DHS5_2008_WN_Y2009M10D09.DTA"
replace sample_size = 5691 if filename == "GHA_DHS4_2003_WN_Y2008M09D23.DTA"
replace sample_size = 9064 if filename == "GHA_PMA2020_2015_R4_HHQFQ_Y2016M05D17.DTA"
replace sample_size = 1871 if filename == "GHA_PMA2020_2014_R3_HHQFQ_Y2016M05D16.DTA"
replace sample_size = 4843 if filename == "GHA_DHS4_1998_1999_WN_Y2008M09D23.DTA"
replace sample_size = 9396 if filename == "GHA_DHS6_2014_WN_Y2015M10D15.DTA"
replace sample_size = 4562 if filename == "GHA_DHS3_1993_1994_WN_Y2008M09D23.DTA"
replace sample_size = 3050 if filename == "COM_DHS3_1996_WN_Y2008M09D23.DTA"
replace sample_size = 5329 if filename == "COM_DHS6_2012_2013_WN_RECODE_Y2014M06D11.DTA"
replace sample_size = 8422 if filename == "DOM_DHS3_1996_WN_Y2008M09D23.DTA"
replace sample_size = 1575 if filename == "DOM_SP_DHS5_2007_WN_Y2010M04D02.DTA"
replace sample_size = 9372 if filename == "DOM_DHS6_2013_WN_Y2010M10D22.DTA"
replace sample_size = 1286 if filename == "DOM_DHS4_1999_WN_Y2008M09D23.DTA"
replace sample_size = 7318 if filename == "DOM_DHS2_1991_WN_Y2008M09D23.DTA"
replace sample_size = 23384 if filename == "DOM_DHS4_2002_WN_Y2008M09D23.DTA"
replace sample_size = 8208 if filename == "KGZ_DHS6_2012_WN_Y2014M02D04.DTA"
replace sample_size = 3848 if filename == "KGZ_DHS3_1997_WN_Y2008M09D23.DTA"
replace sample_size = 5827 if filename == "PRY_DHS2_1990_WN_Y2008M09D23.DTA"
replace sample_size = 8444 if filename == "AZE_DHS5_2006_WN_Y2008M09D23.DTA"
replace sample_size = 13060 if filename == "NIC_DHS4_2001_WN_Y2008M09D23.DTA"
replace sample_size = 13634 if filename == "NIC_DHS3_1997_1998_WN_Y2008M09D23.DTA"
replace sample_size = 18827 if filename == "COD_DHS6_2013_WN_Y2014M10D08.DTA"
replace sample_size = 9995 if filename == "COD_DHS5_2007_WN_Y2008M10D22.DTA"
replace sample_size = 7374 if filename == "SLE_DHS5_2008_WN_Y2008M12D17.DTA"
replace sample_size = 16658 if filename == "SLE_DHS6_2013_WN_Y2014M10D01.DTA"
replace sample_size = 7584 if filename == "ALB_DHS5_2008_2009_WN_Y2010M11D12.DTA"
replace sample_size = 9223 if filename == "NER_DHS5_2006_WN_Y2008M09D23.DTA"
replace sample_size = 7577 if filename == "NER_DHS3_1998_WN_Y2008M09D23.DTA"
replace sample_size = 6503 if filename == "NER_DHS2_1992_WN_Y2008M09D23.DTA"
replace sample_size = 11160 if filename == "NER_DHS6_2012_WN_Y2014M01D17.DTA"
replace sample_size = 5501 if filename == "CMR_DHS3_1998_WN_Y2008M09D23.DTA"
replace sample_size = 10656 if filename == "CMR_DHS4_2004_WN_Y2008M09D23.DTA"
replace sample_size = 3871 if filename == "CMR_DHS2_1991_WN_Y2008M09D23.DTA"
replace sample_size = 15426 if filename == "CMR_DHS5_2011_WN_Y2013M01D16.DTA"
replace sample_size = 8593 if filename == "SEN_DHS3_1997_WN_Y2008M09D23.DTA"
replace sample_size = 6310 if filename == "SEN_DHS2_1992_1993_WN_Y2008M09D23.DTA"
replace sample_size = 8488 if filename == "SEN_DHS7_2014_WN_Y2015M06D29.DTA"
replace sample_size = 15688 if filename == "SEN_DHS6_2010_2011_WN_Y2012M05D08.DTA"
replace sample_size = 8636 if filename == "SEN_DHS6_2012_2013_WN_Y2015M09D14.DTA"
replace sample_size = 14602 if filename == "SEN_DHS4_2005_WN_Y2008M09D23.DTA"
replace sample_size = 4415 if filename == "UZB_DHS3_1996_WN_Y2008M09D23.DTA"
replace sample_size = 8569 if filename == "TGO_DHS3_1998_WN_Y2008M09D23.DTA"
replace sample_size = 9480 if filename == "TGO_DHS6_2013_WN_Y2015M04D02.DTA"
replace sample_size = 6566 if filename == "ARM_DHS5_2005_WN_Y2008M09D23.DTA"
replace sample_size = 5922 if filename == "ARM_DHS6_2010_WN_Y2012M04D30.DTA"
replace sample_size = 6430 if filename == "ARM_DHS4_2000_WN_Y2008M09D23.DTA"
replace sample_size = 8754 if filename == "ERI_DHS4_2002_WN_Y2008M09D23.DTA"
replace sample_size = 5054 if filename == "ERI_DHS3_1995_1996_WN_Y2008M09D23.DTA"
replace sample_size = 7092 if filename == "LBR_DHS5_2006_2007_WN_Y2008M10D22.DTA"
replace sample_size = 9239 if filename == "LBR_DHS6_2013_WN_Y2014M09D24.DTA"
replace sample_size = 10793 if filename == "NPL_DHS5_2006_WN_Y2008M09D23.DTA"
replace sample_size = 12674 if filename == "NPL_DHS6_2011_WN_Y2012M04D05.DTA"
replace sample_size = 8726 if filename == "NPL_DHS4_2001_WN_Y2008M09D23.DTA"
replace sample_size = 8429 if filename == "NPL_DHS3_1996_WN_Y2008M09D23.DTA"
replace sample_size = 7146 if filename == "ZMB_DHS5_2007_WN_Y2009M03D30.DTA"
replace sample_size = 8021 if filename == "ZMB_DHS3_1996_1997_WN_Y2008M09D23.DTA"
replace sample_size = 7658 if filename == "ZMB_DHS4_2001_2002_WN_Y2008M09D23.DTA"
replace sample_size = 16411 if filename == "ZMB_DHS6_2013_2014_WN_Y2015M04D17.DTA"
replace sample_size = 7060 if filename == "ZMB_DHS2_1992_WN_Y2008M09D23.DTA"
replace sample_size = 6841 if filename == "UKR_DHS5_2007_WN_Y2008M09D23.DTA"
replace sample_size = 10996 if filename == "BGD_DHS5_2007_WN_Y2009M05D11.DTA"
replace sample_size = 11440 if filename == "BGD_DHS4_2004_WN_Y2008M09D23.DTA"
replace sample_size = 17863 if filename == "BGD_DHS7_2014_WN_Y2016M03D23.DTA"
replace sample_size = 10544 if filename == "BGD_DHS4_1999_2000_WN_Y2008M09D23.DTA"
replace sample_size = 9640 if filename == "BGD_DHS3_1993_1994_WN_Y2008M09D23.DTA"
replace sample_size = 9127 if filename == "BGD_DHS3_1996_1997_WN_Y2008M09D23.DTA"
replace sample_size = 17842 if filename == "BGD_DHS6_2011_2012_WN_Y2013M02D11.DTA"
replace sample_size = 8902 if filename == "IDN_DHS6_2012_WN_Y2015M08D07.DTA"
replace sample_size = 32895 if filename == "IDN_DHS5_2007_WN_Y2009M05D05.DTA"
replace sample_size = 29483 if filename == "IDN_DHS4_2002_2003_WN_Y2008M09D23.DTA"
replace sample_size = 22909 if filename == "IDN_DHS2_1991_WN_Y2008M09D23.DTA"
replace sample_size = 28810 if filename == "IDN_DHS3_1997_WN_Y2008M09D23.DTA"
replace sample_size = 28168 if filename == "IDN_DHS3_1994_WN_Y2008M09D23.DTA"
replace sample_size = 8644 if filename == "COL_DHS2_1990_WN_Y2008M09D23.DTA"
replace sample_size = 11585 if filename == "COL_DHS4_2000_WN_Y2008M09D23.DTA"
replace sample_size = 11140 if filename == "COL_DHS3_1995_WN_Y2008M09D23.DTA"
replace sample_size = 41344 if filename == "COL_DHS5_2004_2005_WN_Y2008M09D23.DTA"
replace sample_size = 12612 if filename == "BRA_DHS3_1996_WN_Y2008M09D23.DTA"
replace sample_size = 16939 if filename == "BOL_DHS5_2008_WN_Y2010M06D18.DTA"
replace sample_size = 11187 if filename == "BOL_DHS3_1998_WN_Y2008M09D23.DTA"
replace sample_size = 8603 if filename == "BOL_DHS3_1993_1994_WN_Y2008M09D23.DTA"
replace sample_size = 17654 if filename == "BOL_DHS4_2003_2004_WN_Y2008M09D23.DTA"
replace sample_size = 25434 if filename == "YEM_DHS6_2013_WN_Y2015M07D13.DTA"
replace sample_size = 6010 if filename == "YEM_DHS2_1991_1992_WN_Y2008M09D23.DTA"
replace sample_size = 10023 if filename == "PAK_DHS5_2006_2007_WN_Y2008M09D23.DTA"
replace sample_size = 6611 if filename == "PAK_DHS2_1990_1991_WN_Y2008M09D23.DTA"
replace sample_size = 13558 if filename == "PAK_DHS6_2012_2013_WN_Y2014M01D22.DTA"
replace sample_size = 15882 if filename == "PER_DHS2_1991_1992_WN_Y2008M09D23.DTA"
replace sample_size = 27843 if filename == "PER_DHS4_2000_WN_Y2008M09D23.DTA"
replace sample_size = 28951 if filename == "PER_DHS3_1996_WN_Y2008M09D23.DTA"
replace sample_size = 12403 if filename == "GTM_DHS3_1995_WN_Y2008M09D23.DTA"
replace sample_size = 6021 if filename == "GTM_ITR_DHS4_1998_1999_WN_Y2008M09D23.DTA"
replace sample_size = 90303 if filename == "IND_DHS4_1998_2000_WN_Y2008M09D23.DTA"
replace sample_size = 89777 if filename == "IND_DHS2_1992_1993_WN_Y2008M09D23.DTA"
replace sample_size = 124385 if filename == "IND_DHS5_2005_2006_WN_Y2008M09D23.dta"
replace sample_size = 7881 if filename == "KEN_DHS3_1998_WN_Y2008M09D23.DTA"
replace sample_size = 8195 if filename == "KEN_DHS4_2003_WN_Y2008M09D23.DTA"
replace sample_size = 31079 if filename == "KEN_DHS7_2014_WN_Y2016M01D14.DTA"
replace sample_size = 8444 if filename == "KEN_DHS5_2008_2009_WN_Y2010M08D25.DTA"
replace sample_size = 2221 if filename == "KEN_PMA2020_2014_R1_HHQFQ_Y2016M05D13.DTA"
replace sample_size = 2511 if filename == "KEN_PMA2020_2015_R3_HHQFQ_Y2016M05D18.DTA"
replace sample_size = 2416 if filename == "KEN_PMA2020_2014_R2_HHQFQ_Y2016M05D18.DTA"
replace sample_size = 7540 if filename == "KEN_DHS3_1993_WN_Y2008M09D23.DTA"
replace sample_size = 19948 if filename == "HND_DHS5_2005_2006_WN_Y2008M09D23.DTA"
replace sample_size = 22757 if filename == "HND_DHS6_2011_2012_WN_Y2013M06D26.DTA"
replace sample_size = 10757 if filename == "HTI_DHS5_2005_2006_WN_Y2008M09D23.DTA"
replace sample_size = 5356 if filename == "HTI_DHS3_1994_1995_WN_Y2008M09D23.DTA"
replace sample_size = 10159 if filename == "HTI_DHS4_2000_WN_Y2008M09D23.DTA"
replace sample_size = 14287 if filename == "HTI_DHS6_2012_WN_Y2013M07D15.DTA"
replace sample_size = 6219 if filename == "BEN_DHS4_2001_WN_Y2008M09D23.DTA"
replace sample_size = 16599 if filename == "BEN_DHS6_2011_2012_WN_Y2014M02D12.DTA"
replace sample_size = 5491 if filename == "BEN_DHS3_1996_WN_Y2008M09D23.DTA"
replace sample_size = 17794 if filename == "BEN_DHS5_2006_WN_Y2008M09D23.DTA"
replace sample_size = 7440 if filename == "MDA_DHS5_2005_WN_Y2008M09D23.DTA"
replace sample_size = 10819 if filename == "COG_DHS6_2011_2012_WN_Y2013M10D15.DTA"
replace sample_size = 7051 if filename == "COG_DHS5_2005_WN_Y2008M09D23.DTA"
replace sample_size = 10139 if filename == "TZA_DHS6_2009_2010_WN_Y2011M06D22.DTA"
replace sample_size = 9238 if filename == "TZA_DHS2_1991_1992_WN_Y2008M09D23.DTA"
replace sample_size = 8120 if filename == "TZA_DHS3_1996_WN_Y2008M09D23.DTA"
replace sample_size = 10329 if filename == "TZA_DHS4_2004_2005_WN_Y2008M09D23.DTA"
replace sample_size = 4029 if filename == "TZA_DHS4_1999_WN_Y2008M09D23.DTA"
replace sample_size = 15029 if filename == "PHL_DHS3_1993_WN_Y2008M09D23.DTA"
replace sample_size = 13983 if filename == "PHL_DHS3_1998_WN_Y2008M09D23.DTA"
replace sample_size = 16155 if filename == "PHL_DHS6_2013_WN_Y2014M09D24.DTA"
replace sample_size = 13594 if filename == "PHL_DHS5_2008_WN_Y2015M07D27.DTA"
replace sample_size = 13633 if filename == "PHL_DHS4_2003_WN_Y2008M09D23.DTA"
replace sample_size = 9704 if filename == "MLI_DHS3_1995_1996_WN_Y2008M09D23.DTA"
replace sample_size = 14583 if filename == "MLI_DHS5_2006_WN_Y2008M09D23.DTA"
replace sample_size = 10424 if filename == "MLI_DHS6_2012_2013_WN_Y2014M08D20.DTA"
replace sample_size = 12849 if filename == "MLI_DHS4_2001_WN_Y2008M09D23.DTA"
replace sample_size = 6519 if filename == "TUR_DHS3_1993_WN_Y2008M09D23.DTA"
replace sample_size = 8576 if filename == "TUR_DHS4_1998_WN_Y2008M09D23.DTA"
replace sample_size = 8075 if filename == "TUR_DHS4_2003_2004_WN_Y2008M09D23.DTA"
replace sample_size = 9389 if filename == "BDI_DHS6_2010_2011_WN_Y2012M09D19.DTA"
replace sample_size = 10233 if filename == "GMB_DHS6_2013_WN_Y2015M05D04.DTA"
replace sample_size = 16798 if filename == "MAR_DHS4_2003_2004_WN_Y2008M09D23.DTA"
replace sample_size = 7313 if filename == "RWA_ITR_DHS5_2007_2008_WN_Y2010M08D25.DTA"
replace sample_size = 10018 if filename == "NAM_DHS6_2013_WN_Y2015M06D22.DTA"
replace sample_size = 9159 if filename == "EGY_ITR_DHS4_2003_WN_Y2008M09D23.DTA"
replace sample_size = 15573 if filename == "EGY_DHS4_2000_WN_Y2008M09D23.DTA"
replace sample_size = 19474 if filename == "EGY_DHS5_2005_WN_Y2008M09D23.DTA"
replace sample_size = 14779 if filename == "EGY_DHS3_1995_1996_WN_Y2008M09D23.DTA"
replace sample_size = 9864 if filename == "EGY_DHS2_1992_1993_WN_Y2008M09D23.DTA"
replace sample_size = 16527 if filename == "EGY_DHS5_2008_WN_Y2009M06D19.DTA"
replace sample_size = 7095 if filename == "LSO_DHS4_2004_2005_WN_Y2008M09D23.DTA"


keep iso3 survey filename ihme_start_year ihme_end_year sample sample_size  met_need* 


tempfile extracted
save `extracted', replace

// append report data 

import delimited "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\lit_review\tabular_report_data_8_9_ageaggregate.csv", clear
gen report_data = 1
drop if iso3 == ""

local varlist any_contra_all modern_contra_all unmet_need_all any_contra_currmarr modern_contra_currmarr unmet_need_currmarr 
foreach var of local varlist {
replace `var' = `var' / 100
}

** drop sweden becasue no modern contraception
drop if iso3 == "SWE"


gen met_need_modern_prev = modern_contra_all/(any_contra_all + unmet_need_all)

gen met_need_modern_curr_prev = modern_contra_currmarr/(any_contra_currmarr + unmet_need_currmarr)

gen sample_size = .
replace sample_size = all_sample_size if all_sample_size != .
replace sample_size = currmarr_sample_size if currmarr_sample_size != .


keep iso3 year survey un_data all_ages_rep report_data met_need_modern_prev met_need_modern_curr_prev sample_size nationally_representative
** replace met_need_modern = met_need_modern * 100
** replace met_need_modern_curr = met_need_modern_curr * 100

** replace unmet_need_all = unmet_need_all / 100
** replace unmet_need_currmarr = unmet_need_currmarr / 100


append using `extracted'

replace year = ihme_start_year if year == .

drop ihme_start_year
replace un_data = 0 if un_data == .
replace report_data = 0 if report_data == 0


// drop duplicate france 2005 datapoints -- keeping estimates with samplesize
drop if iso3 == "FRA" & year == 2005 & sample_size == .


// drop belgium because it's not nationally representative
drop if nationally_representative == 0

gen agegroup = 30



save "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\unmet_need\unmet_need_extracted_and_report_data.dta", replace
