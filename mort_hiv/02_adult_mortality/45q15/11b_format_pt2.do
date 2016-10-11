
* merge NIDs from iDie onto raw 5q0 & 45q15
/* 
1) Set locals of the filepaths
	A)inputs
	B)outputs 
		i)What outputs are actually created will depend on whether any sources have been added or dropped, but you set the locals either way

2) Kids data points
	A) format the dataset of all sources with their NIDs
	B) Bring together adjusted and unadjusted 5q0 data points
	C) Merge on the NIDs so that all sources have NIDs
		i) Get a dataset of which sources have been dropped
			a) If this was this supposed to happen, delete them from the "raw_data_with_nids" file
			b) If this was not supposed to happen, investigate why they were dropped
		ii) Get a dataset of all the sources that do not have NIDs
			a) Be sure to fill in the NID and process = 5q0. This is the list of all sources without NIDs/parent NIDs
			b) Then, copy and paste that into the input file (raw_data_with_nids)
			c) save that input file, then run this code again
			d) You do not need to update the type id or method id because this code will automatically fill it in later once you add the nid information
			e) also keep in mind that if you update NIDs for one country-source for CBH, make sure you've captured all of the CBH from that country-source

3) Adult data points
	A) format the dataset of all sources with their NIDs
	B) Merge on the NIDs so that all sources have NIDs
		i) Get a dataset of which sources have been dropped
			a) If this was this supposed to happen, delete them from the "raw_data_with_nids" file
			b) If this was not supposed to happen, investigate why they were dropped
		ii) Get a dataset of all the sources that do not have NIDs
			a) Be sure to fill in the NID and process = 45q15. This is the list of all sources without NIDs/parent NIDs
			b) Then, copy and paste that into the input file (raw_data_with_nids)
			c) save that input file, then run this code again
			d) You do not need to update the type id or method id because this code will automatically fill it in later once you add the nid information

4) Creation of variables needed for the visualization
	A) Type id (what is the type of data source)
	B) Method id (what is the method used on that data source)

5) final checks and save
 */

clear all
set more off
cap restore, not

local indir = "strPath"
local inputfile = "`indir'/raw_data_with_nids.xlsx"
** for testing purposes only: this file is missing quite a number of rows so that we can see how the code will run when we need to fill in NIDs
** uncomment this when you want to bring in the real dataset
** local inputfile = "`indir'/01_archive/raw_data_with_nids_carlys_last_edits_tester.xlsx"

local raw5q0_filepath = "strPath/raw.5q0.unadjusted - 05-12-14_gbd2013.txt"
local prediction_model_filepath = "strPath/prediction_model_results_all_stages_2014-05-12.txt"
local raw45q15 = "strPath/raw.45q1527_Jun_2014_gbd2013.txt"

local outdir = "strPath"
local date = c(current_date)

** for when you need to add NIDs, these files will be created.  if all sources have nids, these will not be created
local neednidschild = "`indir'/02_temp/need_nids_child_`date'.xlsx"
local neednidsadult = "`indir'/02_temp/need_nids_adult_`date'.xlsx"

** for when you have dropped NIDs, these files will be created.  if no sources have been dropped, these will not be created.  you'll need to make sure that those sources were supposed to be dropped
local droppednidschild = "`indir'/02_temp/dropped_nids_child_`date'.xlsx"
local droppednidsadult = "`indir'/02_temp/dropped_nids_adult_`date'.xlsx"

** ******************************************
** KIDS
** ******************************************
	** mort viz data
	import excel using "`inputfile'", clear firstrow sheet( "raw_data_with_nids")
		keep if process == "5q0"
		** don't need the adult-only variables
		drop original_source_type original_deaths_source source_date_corrected
		rename original_* *
		rename (source_date in_direct) (sourcedate indirect)
		replace process = "5q0" if process == ""
		duplicates drop

		isid iso3 source sourcedate indirect
		tempfile mortvizkids
		save `mortvizkids', replace

	**  merge adjusted and unadusted 5q0 data: need variables from both datasets
		** the adjusted results
		insheet using "`prediction_model_filepath'", clear
		drop if data == 0
		isid ptid
		rename mort mortadj
			drop if mortadj == "NA"
			destring mortadj, replace force
		keep iso3 year category vr mortadj ptid source1 source adjre_fe reference
		rename source source_adj
		
		tempfile adj
		save `adj', replace
		
		** the unadjusted results
		insheet using "`raw5q0_filepath'", clear
		tostring ptid, replace
		merge m:1 ptid using `adj'
			** it's okay that there is _m==1: these are the outliers and shocks
			assert _m==1 if outlier == 1
			assert _m==1 if shock == 1
			assert _m != 2
			drop if _m==2
			
			** mark which ones are adjusted
			destring mortadj, replace 
			
			gen adjust = "unadjusted"
			replace adjust = "adjusted" if vr == "1" & category == "vr_biased"
			drop _m compiling dataage sdq5 log10sdq5 ptid source_adj source1
			
		rename (q5 mortadj) (data_raw data_final)
		
	replace source = lower(source)
	merge m:1 iso3 source sourcedate indirect using `mortvizkids'
	
	** I think this is here that you would stop and assert that all sources have nids, becuase you'll have added nids to all new sources at an earlier stage

	/*
	** check which sources have been dropped: should they have been dropped?
	count if _m == 2
	local numbernotmerged = `r(N)'
	qui {
		if `numbernotmerged' == 0 {
			noi di ""
		}
		if `numbernotmerged'  != 0 {
			preserve
			keep if _m==2
			keep date_added iso3 process source sourcedate indirect type_id method_id
			replace process = "5q0"
			replace date_added = "`date'" 
			rename (source sourcedate indirect) (original_source original_source_date original_in_direct)
			* to match the columns in the raw_data_with_nids file, add in the other variables that are missing
			* we won't add the type and method id variables because code below will automatically fill them in
			* deaths_source and source_type are variables only for adults; so keep these blank
			* we are keeping type_id and method_id because maybe we only dropped the source for one type of method
			generate original_source_type = ""
			generate original_deaths_source = ""
			generate ParentNID = .
			generate nid = .
			generate source_date_corrected = .
			duplicates drop
			compress
			order date_added iso3 process original_source original_source_date original_in_direct original_source_type original_deaths_source Parent nid source_date_corrected type_id method_id
			rename date_added date_dropped
			export excel "`droppednidschild'", firstrow(variables) sheet( "NIDs dropped") replace
			restore
			noi di in red "Some child sources were dropped; these are _m==2." 
			noi di "Check this file: if these were supposed to be dropped, delete them from `inputfile'"
			noi di "if they were not supposed to be dropped, look into why they were"
			noi di "`droppednidschild'"
			stop
		}

	}
	
	** check which sources need NIDs
	count if _m == 1
	local numbernotmerged = `r(N)'
	qui {
		if `numbernotmerged' == 0 {
			noi di ""
		}
		if `numbernotmerged'  != 0 {
			preserve
			keep if _m==1
			keep date_added iso3 process source sourcedate indirect 
			replace process = "5q0"
			replace date_added = "`date'" if date == ""
			rename (source sourcedate indirect) (original_source original_source_date original_in_direct)
			* to match the columns in the raw_data_with_nids file, add in the other variables that are missing
			* we won't add the type and method id variables because code below will automatically fill them in
			* deaths_source and source_type are variables only for adults; so keep these blank
			generate original_source_type = ""
			generate original_deaths_source = ""
			generate ParentNID = .
			generate nid = .
			duplicates drop
			compress
			order date_added iso3 process original_source original_source_date original_in_direct original_source_type original_deaths_source  Parent nid
			export excel "`neednidschild'", firstrow(variables) sheet( "Need nids") replace
			restore
			noi di in red "Not all of your child sources have NIDs; these are _m==1." 
			noi di "Edit this file:"
			noi di "`neednidschild'"
			noi di "Be sure to fill in the NID and process = 5q0. This is the list of all sources without NIDs/parent NIDs"
			noi di "Then, copy and paste that into the input file"
			noi di "(`inputfile'),"
			noi di "save that input file, then run this code again"
			noi di "You do not need to update the type id or method id because this code will automatically fill it in later once you add the nid information"
			noi di "also keep in mind that if you update NIDs for one country-source for CBH, make sure you've captured all of the CBH from that country-source"
			
			stop
		}

	}
	*/
	
	drop _m
	rename indirect type
	tostring adjust, replace
	gen sex = "both"
	
	tempfile kids
	save `kids', replace
	
** ******************************************
** Adults
** ******************************************
	import excel using "`inputfile'", clear firstrow sheet( "raw_data_with_nids")
	keep if process == "45q15"
	** don't need the kids-only variables
	drop original_source original_in_direct
	replace original_source_date = source_date_corrected
	drop source_date_corrected
	rename original_* *
	replace process = "45q15" if process == ""	
	destring source_date, replace
	duplicates drop

	isid iso3 source_date source_type deaths_source
	tempfile mortvizadults
	save `mortvizadults', replace

	insheet using "`raw45q15'", clear
	replace year = floor(year)
	** unless otherwise filled in like for sibs, we will make the sourcedate the floor of the estimate year, for lack of something better
	replace source_date = year if source_date == .
	replace deaths_source = lower(deaths_source)
		replace deaths_source = "who" if deaths_source == "who_causesofdeath"
	
	merge m:1 iso3 source_type deaths_source source_date using `mortvizadults'
	
	** I think this is here that you would stop and assert that all sources have nids, becuase you'll have added nids to all new sources at an earlier stage

	/*
	* check which sources have been dropped: should they have been dropped?
	count if _m == 2
	local numbernotmerged = `r(N)'
	qui {
		if `numbernotmerged' == 0 {
			noi di ""
		}
		if `numbernotmerged'  != 0 {
			preserve
			keep if _m==2
			keep date_added iso3 process source_date deaths_source source_type type_id method_id
			replace process = "45q15"
			replace date_added = "`date'" if date == ""
			rename (source_date deaths_source source_type) (original_source_date original_deaths_source original_source_type)
			* to match the columns in the raw_data_with_nids file, add in the other variables that are missing
			* source, source date and indirect are variables only for children; so keep these blank
			* for adults, use the sourcedate variable we created above
			* we are keeping type_id and method_id because maybe we only dropped the source for one type of method
			generate original_source = ""
			generate original_in_direct = ""
			generate source_date_corrected = original_source_date
			generate ParentNID = .
			generate nid = .
			duplicates drop
			compress
			order date_added iso3 process original_source original_source_date original_in_direct original_source_type original_deaths_source  Parent nid source_date_corrected type_id method_id
			rename date_added date_dropped
			export excel "`droppednidsadult'", firstrow(variables) sheet( "NIDs dropped") replace
			restore
			noi di in red "Some adult sources have been dropped; these are _m==2." 
			noi di "Check this file: if these were supposed to be dropped, delete them from `inputfile'"
			noi di "if they were not supposed to be dropped, look into why they were"
			noi di "`droppednidsadult'"
			stop
		}

	}
	
	* check which sources need NIDs
	count if _m == 1
	local numbernotmerged = `r(N)'
	qui {
		if `numbernotmerged' == 0 {
			noi di ""
		}
		if `numbernotmerged'  != 0 {
			preserve
			keep if _m==1
			keep date_added iso3 process source_date deaths_source source_type
			replace process = "45q15"
			replace date_added = "`date'" if date == ""
			rename (source_date deaths_source source_type) (original_source_date original_deaths_source original_source_type)
			* to match the columns in the raw_data_with_nids file, add in the other variables that are missing
			* we won't add the type and method id variables because code below will automatically fill them in
			* source, source date and indirect are variables only for children; so keep these blank
			* for adults, use the sourcedate variable we created above
			generate original_source = ""
			generate original_in_direct = ""
			generate source_date_corrected = original_source_date
			generate ParentNID = .
			generate nid = .
			duplicates drop
			compress
			order date_added iso3 process original_source original_source_date original_in_direct original_source_type original_deaths_source Parent nid source_date_corrected
			export excel "`neednidsadult'", firstrow(variables) sheet( "Need nids") replace
			restore
			noi di in red "Not all of your adult sources have NIDs; these are _m==1." 
			noi di "Edit this file:"
			noi di "`neednidsadult'"
			noi di "Be sure to fill in the NID and process = 45q15. This is the list of all sources without NIDs/parent NIDs"
			noi di "Then, copy and paste that into the input file"
			noi di "(`inputfile'),"
			noi di "save that input file, then run this code again"
			noi di "You do not need to update the type id or method id because this code will automatically fill it in later once you add the nid information"
			stop
		}
	}
	*/

	drop _m
	rename (deaths_source source_type source_date adj45q15 obs45q15) (source type sourcedate data_final data_raw)
	tostring sourcedate, replace
	
** ******************************************
** Bring adults and kids together
** ******************************************	
append using `kids'
assert nid != .

** ****************************************************
** Make all the relevant variables that you need to show up in MortViz
** ****************************************************
** 1. type id's
/* type_id	type_short
1	VR
2	SRS
3	DSP
4	DSS
5	Census
6	Standard DHS
7	Other DHS
8	RHS
9	PAPFAM
10	PAPCHILD
11	MICS
12	WFS
13	LSMS
14	MIS
15	AIS
16	Other
17	UNICEF (for later)
18	VR pre-2009 (for completeness)
19	VR post-2009 (for completeness)
20	DSP before 1996 (for completeness)
21	DSP 1996-2003 (for completeness)
22	DSP 2004 and after (for completeness)
23	DSP 1996-2000 (for completeness)
 */

		replace type_id = 1 if (regexm(source, "Vital Registration") == 1 | regexm(type, "VR") | regexm(lower(source), "vr") == 1) & type_id == .
		replace type_id = 2 if (((regexm(source, "Sample Registration System") == 1 ) | source == "srs" | regexm(source, "srs vital registration") == 1) & ///
			source != "Demographic Sample Survey and Sample Registration System (Personal communication)" | regexm(type, "SRS")) & type_id == .
			replace type_id = 2 if (iso3 == "PAK" & inlist(source, "Population Growth Survey", "Demographic Survey", ///
                                                            "Population Growth Survey (DYB)", "Demographic Survey (DYB)", ///
                                                            "Population Growth Survey (Report)", "Demographic Survey (Report)")) & type_id == .
		replace type_id = 3 if (regexm(source, "Disease Surveillance Points") == 1 | regexm(source, "dsp") == 1) & type_id == .
		replace type_id = 4 if regexm(lower(source), "dss") == 1 & type_id == .
		replace type_id = 6 if ((regexm(source, "Standard") == 1 & source!= "dhs") | (regexm(source, "Demographic and Health Survey")  == 1 & source != "Turkey Demographic and Health Survey" & /// 
					source != "Iran Demographic and Health Survey" & source != "Secretariat of the Pacific Community Demographic and Health Survey" | ///
					regexm(source, "dhs")==1 | source == "tls2003")) & type_id ==.
		replace type_id = 5 if ((source == "Census" | source == "Census (DYB)" | source == "Census (IPUMS)" | source == "Census (WHO)" | ///
					source == "Census (MOH)" | source == "Census (National Institute of Statistics)" | source == "Census (Report)" | ///
					source == "Census (Central Statistical Agency)" | source == "Census (Census tables)" | source == "Census (OECD)" | ///
					source == "Census (Personal communication)" | regexm(lower(source), "census")==1) & ///
					(regexm(lower(source), "pilot") != 1 | regexm(lower(source), "sample") != 1) | regexm(type, "CENSUS") | ///
					regexm(source, "mex_ipums") == 1) & type_id == .
		replace type_id = 7 if ((regexm(source, "Standard") != 1 & source!= "dhs") | (regexm(source, "Demographic and Health Survey")  == 1 & source != "Turkey Demographic and Health Survey" & /// 
					source != "Iran Demographic and Health Survey" & source != "Secretariat of the Pacific Community Demographic and Health Survey" | ///
					regexm(source, "dhs")==1 | source == "tls2003")) & type_id ==.
		replace type_id = 8 if (regexm(lower(source), "heproductive health survey") == 1 | regexm(source, "rhs") == 1) & type_id == .
		replace type_id = 9 if (regexm(source, "Pan Arab Project for Family Health") == 1 | source == "gulf family health survey report" | ///
			regexm(source, "oman family health survey") | source == "Gulf Family Health Survey" | source == "papfam" | ///
			regexm(source, "pan arab project for family health")==1 | regexm(source, "papfam") == 1) & type_id == .
		replace type_id = 10 if (regexm(source, "Pan Arab Project for Child Development") == 1 | source == "gulf child health survey report" | ///
			regexm(lower(source), "oman child health survey") | regexm(source, "papchild") == 1 | regexm(source, "kwt_1987_child_health_survey")) & type_id == .
		replace type_id = 11 if (regexm(source, "Multiple Indicator Cluster Survey") == 1 | regexm(source, "mics") == 1) & type_id == .
		replace type_id = 12 if (regexm(source, "World Fertility Survey") == 1 | regexm(source, "wfs") == 1) & type_id == .
		replace type_id = 13 if (regexm(source, "Living Standards Measurement S") == 1 | regexm(source, "lsms") == 1) & type_id == .
		replace type_id = 14 if (regexm(source, "Malaria Indicator Survey") == 1 | regexm(source, "mis") == 1) & type_id == .
		replace type_id = 15 if (regexm(source, "AIDS Indicator Survey") == 1 | regexm(source, "ais") == 1) & type_id == .
		tab source if type_id == .
		di in red "make sure that all the above sources are okay to be labeled as Other"
		pause
		replace type_id = 16 if type_id == .

	gen type_short = ""
		replace type_short = "VR" if type_id == 1
		replace type_short = "SRS" if type_id == 2
		replace type_short = "DSP" if type_id == 3
		replace type_short = "DSS" if type_id == 4
		replace type_short = "Standard DHS" if type_id == 6
		replace type_short = "Census" if type_id == 5
		replace type_short = "Other DHS" if type_id == 7
		replace type_short = "RHS" if type_id == 8
		replace type_short = "PAPFAM" if type_id == 9
		replace type_short = "PAPCHILD" if type_id == 10
		replace type_short = "MICS" if type_id == 11
		replace type_short = "WFS" if type_id == 12
		replace type_short = "LSMS" if type_id == 13
		replace type_short = "MIS" if type_id == 14
		replace type_short = "AIS" if type_id == 15
		replace type_short = "Other" if type_id == 16
		
	gen type_full = ""
		replace type_full = "Vital registration" if type_id == 1
		replace type_full = "Sample registration system" if type_id == 2
		replace type_full = "Disease surveillance points" if type_id == 3
		replace type_full = "Demographic surveillance sites" if type_id == 4
		replace type_full = "Standard demographic and health survey" if type_id == 6
		replace type_full = "Census" if type_id == 5
		replace type_full = "Other demographic and health survey" if type_id == 7
		replace type_full = "Reproductive Health Survey" if type_id == 8
		replace type_full = "Pan Arab Project for Family Health" if type_id == 9
		replace type_full = "Pan Arab Project for Child Development" if type_id == 10
		replace type_full = "Multiple Indicator Cluster Survey" if type_id == 11
		replace type_full = "World Fertility Survey" if type_id == 12
		replace type_full = "Living Standards Measurement Study" if type_id == 13
		replace type_full = "Malaria Indicator Survey" if type_id == 14
		replace type_full = "AIDS Indicator Survey" if type_id == 15
		replace type_full = "Other survey" if type_id == 16
		
	gen type_color = ""
		replace type_color = "160,32,240" if type_id == 1
		replace type_color = "0,255,0" if type_id == 2
		replace type_color = "0,238,0" if type_id == 3
		replace type_color = "0,205,0" if type_id == 4
		replace type_color = "255,165,0" if type_id == 6
		replace type_color = "0,0,255" if type_id == 5
		replace type_color = "255,0,0" if type_id == 7
		replace type_color = "205,133,0" if type_id == 8
		replace type_color = "255,105,180" if type_id == 9
		replace type_color = "255,110,180" if type_id == 10
		replace type_color = "0,100,0" if type_id == 11
		replace type_color = "0,250,154" if type_id == 12
		replace type_color = "139,34,82" if type_id == 13
		replace type_color = "139,134,78" if type_id == 14
		replace type_color = "92,172,238" if type_id == 15
		replace type_color = "139,69,19" if type_id == 16

** 2. method id's		
/* 
1	Dir-Unadj
2	Dir-Adj
3	CBH
4	SBH
5	Sibs
6	U5-Comp. (for completeness)
7	SEG (for completeness)
8	GGB (for completeness)
9	GGBSEG (for completeness)
 */
	replace method_id = 1 if method_id == . & inlist(adjust, "complete", "unadjusted") & !(inlist(type, "SIBLING_HISTORIES", "direct", "indirect", "indirect, MAC only"))
	replace method_id = 2 if method_id == . & inlist(adjust, "ddm_adjusted", "adjusted") & !(inlist(type, "SIBLING_HISTORIES", "direct", "indirect", "indirect, MAC only"))
	replace method_id = 3 if regexm(type, "direct") == 1 & method_id == .
	replace method_id = 4 if regexm(type, "indirect") == 1 & method_id == .
	replace method_id = 5 if type == "SIBLING_HISTORIES" & method_id == .
		
	gen method_short = ""
		replace method_short = "Unadj" if method_id == 1
		replace method_short = "Adj" if method_id == 2
		replace method_short = "CBH" if method_id == 3
		replace method_short = "SBH" if method_id == 4
		replace method_short = "Sibs" if method_id == 5
		
	gen method_full = ""
		replace method_full = "Direct unadjusted" if method_id == 1
		replace method_full = "Direct adjusted" if method_id == 2
		replace method_full = "Complete birth history" if method_id == 3
		replace method_full = "Summary birth history" if method_id == 4
		replace method_full = "Sibling history" if method_id == 5	
		
	gen method_shape = ""
		replace method_shape = "circle" if method_id == 1
		replace method_shape = "diamond" if method_id == 2
		replace method_shape = "up triangle" if method_id == 3
		replace method_shape = "down triangle" if method_id == 4
		replace method_shape = "square" if method_id == 5
	
** 3. Last things

	replace data_final = data_raw if data_final==. 
	assert data_final != .
		
	** sibling histories do not have a raw point; set the raw value to be equal to the final value
	replace data_raw = data_final if data_raw == .
	
	** make source_identifiers
	generate source_citation = source
	** egen source_id = group(ParentNID nid)
	egen source_id = group(source_citation nid)
	
saveold "`outdir'/archive/raw_5q0_and_45q15_with_nids_all_vars_`date'.dta", replace

keep iso3 year sex data_raw data_final type_id method_id type_short type_full type_color method_short method_full method_shape outlier process shock adjre_fe reference nid ParentNID source_id source_citation

** Format idie data
gen deaths_citation = .
gen pop_citation = .
gen iso3number = .
gen sexnumber = .





saveold "`outdir'/raw_5q0_and_45q15_with_nids.dta", replace
saveold "`outdir'/archive/raw_5q0_and_45q15_with_nids_`date'.dta", replace