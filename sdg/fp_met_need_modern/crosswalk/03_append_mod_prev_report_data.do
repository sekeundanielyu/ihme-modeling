// July 2016
// Merge together report and extracted data on modern contraception use prevalence

use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\output\MASTER PREVALENCE FILES\master_modern_contra_11aug2016.dta", clear
		append using "J:\Project\Coverage\Contraceptives\MASTER\Prevalence\Report data.dta"

		drop if modcurrmarr_prev >= 1 & modcurrmarr_prev != .

			** clean the dataset
			order iso3 countryname_ihme year ihme_start_year ihme_end_year agegroup survey filename report_data gbd_developing ///
				gbd_super_region gbd_region modall_prev modall_var modcurrmarr_prev modcurrmarr_var
			replace report_data=0 if report_data!=1
			replace cw_age=0 if cw_age!=1
			replace ihme_start_year = year if ihme_start_year == .
			drop year
			rename ihme_start_year year


			duplicates tag iso3 year agegroup survey , gen(dup)
			sort iso3 year agegroup survey

			// drop duplicates

			** drop subnational surveys
			drop if filename == "KEN_BUNGOMA_MICS5_2013_2014_WN_Y2016M03D14.DTA"
			drop if filename == "KEN_KAKAMEGA_MICS5_2013_2014_WN_Y2016M03D14.DTA"
			drop if filename == "KEN_TURKANA_MICS5_2013_2014_WN_Y2016M03D14.DTA"
			drop if filename == "MKD_ROMA_SETTLEMENTS_MICS4_2011_WN_Y2013M10D04.DTA"
			drop if filename == "MNE_MICS5_2013_WN_ROMA_Y2015M01D12.DTA"
			drop if filename == "SOM_NORTHEAST_ZONE_MICS4_2011_WN_Y2015M03D25.DTA"
			drop if filename == "SRB_MICS5_2014_WN_ROMA_Y2015M02D09.DTA"
			drop if filename == "NER_NIAMEY_PMA2020_2015_R1_HHQFQ_Y2016M05D13.DTA"
			drop if filename == "NGA_LAGOS_PMA2020_2014_R1_HHQFQ_Y2016M05D17.DTA"
			drop if filename == "NGA_KADUNA_PMA2020_2014_R1_HHQFQ_Y2016M05D17.DTA"
			drop if filename == "PAK_PUNJAB_MICS4_2011_WN.DTA"
			drop if filename == "MNG_KHUVSGUL_MICS4_2012_WN_Y2015M03D25.DTA"

			** duplicates to report data
			drop if filename == "HND_RHS_1996_WN.DTA"
			drop if filename == "JAM_RHS_1993_WN_Y2011M03D24.dta"
			drop if filename == "JAM_RHS_1989_WN_Y2011M03D24.dta" & modall_prev > .9
			drop if iso3 == "JAM" & report_data == 0



			// drop repeat data from report data (taken from 2010 code)
		drop if (iso3 == "FRA" & survey == "FFS") | ///
		(survey == "Encuesta de Fecundidad de 1999") | ///
		(survey == "Encuesta de Fecundidad y Valores 2006" & agegroup != 45) | ///
		(survey == "National Health Survey" & year == 2000 & iso3 == "BTN") | ///
		(iso3 == "PNG" & survey == "Demographic and Health Survey") | ///
		(iso3 == "USA" & survey == "1995 National Survey of Family Growth") | ///
		(iso3 == "USA" & survey == "2002 National Survey of Family Growth" & year == 2002) | ///
		(iso3 == "BEL" & survey == "FFS") | ///
		(iso3 == "KAZ" & report_data == 1 & year == 1999) | ///
		(survey == "Mongolia Reproductive Health Survey 1998") | ///
		(iso3 == "GNQ" & report_data == 1 & year == 2000) | ///
		(iso3 == "NGA" & report_data == 1 & survey == "") | ///
		(iso3 == "RWA" & report_data == 1 & survey == "") | ///
		(iso3 == "IND" & survey == "DHS") | ///
		(survey == "Pakistan Fertility and Family Planning Survey 1996-1997") | ///
		(survey == "Reproductive Health Survey" & iso3 == "LAO")

			// identify outliers from 2010
			replace modall_prev = .  if ///
	/* ******************* */ (iso3 == "USA" & survey == "2002 National Survey of Family Growth" & year == 2006) | ///
	/* ******************* */ (iso3 == "USA" & modall_prev < .01 & agegroup == 45) | ///
	/* ******************* */ (iso3 == "NER" & survey == "DHS" & year == 1997) | ///
	/* ******************* */ (iso3 == "KAZ" & report_data == 1 & year == 2006) | ///
	/* ******************* */ (iso3 == "MNE" & survey == "MICS" & year == 2006) | ///
	/* ******************* */ (iso3 == "UGA" & report_data == 1 & year == 2005) | ///
	/* ******************* */ (iso3 == "CRI" & survey == "RHS" & report_data == 1) | ///
	/* ******************* */ (iso3 == "SLV" & survey == "RHS" & report_data == 1 & year == 2002) | ///
	/* ******************* */ (iso3 == "SUR" & survey == "MICS" & year == 2000) | ///
	/* ******************* */(iso3 == "SOM" & report_data == 1 & year == 2005) | ///
	/* ******************* */ (iso3 == "SDN" & survey == "DHS")

	// identify outliers from 2010
			replace modcurrmarr_prev = .  if ///
	/* ******************* */ (iso3 == "USA" & survey == "2002 National Survey of Family Growth" & year == 2006) | ///
	/* ******************* */ (iso3 == "USA" & modall_prev < .01 & agegroup == 45) | ///
	/* ******************* */ (iso3 == "NER" & survey == "DHS" & year == 1997) | ///
	/* ******************* */ (iso3 == "KAZ" & report_data == 1 & year == 2006) | ///
	/* ******************* */ (iso3 == "MNE" & survey == "MICS" & year == 2006) | ///
	/* ******************* */ (iso3 == "UGA" & report_data == 1 & year == 2005) | ///
	/* ******************* */ (iso3 == "CRI" & survey == "RHS" & report_data == 1) | ///
	/* ******************* */ (iso3 == "SLV" & survey == "RHS" & report_data == 1 & year == 2002) | ///
	/* ******************* */ (iso3 == "SUR" & survey == "MICS" & year == 2000) | ///
	/* ******************* */(iso3 == "SOM" & report_data == 1 & year == 2005) | ///
	/* ******************* */ (iso3 == "SDN" & survey == "DHS")


		// replace outliers
		gen outlier = .

		replace outlier = 1 if ///
		(survey == "1995 National Health Survey" & iso3 == "AUS") | ///
		(iso3 == "NOR" & survey == "Web-based survey") | ///
		(filename == "crude_int_mics2_alb_2000_wm") | ///
		(survey == "1991 Bangladesh Contraceptive Prevalence Survey") | ///
		(survey == "MACRO_DHS" & year == 2001 & iso3 == "BGD") | ///
		(iso3 == "IND" & survey == "MICS") | ///
		(survey == "Nepal Living Standards Survey 2003-2004") | ///
		(iso3 == "MDV" & survey == "Reproductive Health Baseline Survey" & year == 1999) | ///
		(iso3 == "GEO" & filename == "CRUDE_INT_RHS_GEO_2005_PWN_v03132008.dta") | ///
		(iso3 == "MWI" & survey == "UNICEF_MICS") | ///
		(iso3 == "KAZ" & survey == "UNICEF_MICS") | ///
		(iso3 == "MNG" & survey == "UNICEF_MICS") | ///
		(survey == "DLHS" & agegroup == 45) | ///
		(survey == "FFS" & iso3 == "CZE") | ///
		(iso3 == "GBR" & survey == "Web-based survey") | ///
		(survey == "MICS 2" & iso3 == "MDA")

		replace outlier = 1 if ///
		(survey == "Pakistan Contraceptive Prevalence Survey 1994-1995") | ///
		(survey == "Pakistan Reproductive Health and Family Planning Survey 2000-2001") | ///
		(survey == "Pakistan Social and Living Standards Measurement Survey 2005-2006") | ///
		(iso3 == "CHN" & survey== "Demographic and Reproductive Health Survey") | ///
		(iso3 == "COL" & survey== "Colombia FPS 1987") | ///
		(filename == "GHA_SP_DHS5_2007_2008_WN_PH2_Y2009M06D01.DTA") | ///
		(iso3 == "IDN" & survey == "National Socio-economic Survey 2005") | ///
		(iso3 == "SWZ" & survey == "MICS 2") | ///
		(iso3 == "TGO" & survey == "MICS 2") | ///
		(iso3 == "MAR" & survey == "PAPFAM") | ///
		(filename == "CRUDE_INT_RHS_ECU_1989_WN.dta") | ///
		(iso3 == "UKR" & survey == "MICS 3") | ///
		(iso3 == "UZB" & survey == "MICS 2") | ///
		(survey == "MICS 2" & iso3 == "GUY") | ///
		(iso3 == "TZA" & year == 2000 & survey == "DHS-xs") | ///
		(iso3 == "ZMB" & survey == "MICS 2") | ///
		(iso3 == "DJI" & survey == "MICS 3")



			drop dup

			duplicates drop iso3 year agegroup survey filename, force





			drop if filename == "AUS_CONTRACEPTION_USE_AND_EASE_1995_FILE_A_AND_B_MERGED.DTA"




save "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\modern_contra\modern_contra_extracted_and_report_data.dta", replace
