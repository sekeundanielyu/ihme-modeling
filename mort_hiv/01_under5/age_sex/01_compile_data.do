** ***********************************************************************************************
** Description: compiles the data to be used for the age/sex model 
**		(1) compiles CBH data for all sexes
**		(2) compiles VR data from COD for all sexes (note that this data has had the under-5 deaths redistributed
**			to age 0 and 1-4, and has also had unknown deaths for all ages redistributed to the most granular 
**			level that COD uses, which includes the infant breakdown into early, late, and post-neonatal. Conversely, 
**			reported age 0 deaths are not redistributed to early, late, and post-neonatal. 
**		(3) compiles VR data from Mortality for all sexes
**		(4) compiles population data (with exceptions for India SRS and China WHO data) 
**		(5) calculates risks for VR
**		(6) marks exclusions
**		(7) marks data types (i.e. age format)
** 		(8) makes transformations
** ***********************************************************************************************


** *************************	
** Set up Stata 
** *************************

	clear all 
	capture cleartmp 
	set more off 
	capture restore, not
	

	if (c(os)=="Unix") {
		local user = "`1'"
		di "`1'"
		di "`user'"
		set odbcmgr unixodbc
		global j ""
		local code_dir  ""
		qui do "get_locations.ado"
	}
	else { 
		global j ""
		qui do "get_locations.ado" 
	}
	
	capture log close
	log using "input_log.log", replace
	
	** directories 
	global cbh_dir				""
	global save_dir 			""
	
	** vr files 
	global cod_vr_file			"VR_data_master_file_noshocks.dta" 
	global mort_vr_file 		"d00_compiled_deaths.dta" 
	
	** population/births files 
	global natl_pop_file 		"population_gbd2015.dta" 
	global all_pop_file 		"d09_denominators.dta"
	global births_file 			"births_gbd2015.dta"

	** 5q0 files 
	global raw5q0_file 			"raw.5q0.unadjusted.txt"
	global estimate5q0_file		"estimated_5q0_noshocks.txt"
	
	** get IHME indicator countries
	get_locations, level(estimate)
	keep if level_all == 1
	keep ihme_loc_id local_id_2013 region_name
	replace local_id_2013 = "CHN" if ihme_loc_id == "CHN_44533"
	tempfile codes
	save `codes', replace

** *************************	
** Compile CBH data 
** *************************
	** instead of using manually added surveys like we used to, look for all folders in this folder, and try to grab files
	** a diagnostic file is made at the end of this code that lists the missing ones
	** further, if we'd like to outlier/exclude some data, we will mark them near the bottom of this code
	local surveys: dir "$cbh_dir" dirs "*", respectcase

	** some of the folders we looped over in the directory don't actually contain CBH's, we will list those so they can be taken out of the file that summarizes
	local non_data_folders = "Skeleton FUNCTIONS archive"	
	
	local missing_files ""
	tempfile temp 
	local count = 0 
	foreach survey of local surveys { 
		di in white "  `survey'" 
		
		local non_dat = 0
		foreach folder of local non_data_folders {
			if (regexm("`survey'","`folder'")) local non_dat = 1
		}
		
		if (`non_dat' == 0) {
			foreach sex in males females both { 
				if ("`survey'" == "DHS-OTHER") {
					foreach fold in "/In-depth" "/Special" {
						local survey "DHS-OTHER`fold'"
						cap use "q5 - `sex' - 5.dta", clear 
						if _rc != 0 {
							local missing_files "`missing_files' `survey'-`sex'"
						} 
						else {
							local count = `count' + 1 
							gen source2 = "`survey'"
							gen sex = subinstr("`sex'", "s", "", 1) 			
							if (`count' > 1) append using `temp'
							save `temp', replace 
						}
					}
				
				}
				else {
					cap use "q5 - `sex' - 5.dta", clear 
					if _rc != 0 {
						local missing_files "`missing_files' `survey'-`sex'"
					} 
					else {
						local count = `count' + 1 
						gen source2 = "`survey'"
						gen sex = subinstr("`sex'", "s", "", 1) 			
						if (`count' > 1) append using `temp'
						save `temp', replace 
					}
				}
			} 
		}
	} 
	drop if q5 == . 	
	gen source_y = source
	replace source = source2
	
	** get year of survey for later use
	gen survey_year = substr(source_y,-4,4)
	destring survey_year, replace
	
	drop if source == "COD_DHS_2014" & country == "PER"
	
	** which surveys we are missing output files from:
	di "`missing_files'"
	preserve
	clear
	local numobs = wordcount("`missing_files'")
	set obs `numobs'
	gen file = ""
	local count = 1
	foreach missfile of local missing_files {
		replace file = "`missfile'" if _n == `count'
		local count = `count' + 1
	}
	if (`numobs' == 0) {
		set obs 1
		replace file = "no input folders missing files"
	}
	outsheet using "input_folders_missing_files.csv", comma replace
	restore
	
	** format source variable for consistency with "raw.5q0.txt" -- will now switch to source_y variable since it is more specific, but keeping these now for use later below
	replace source = "DHS IN" if source == "DHS-OTHER/In-depth" 
	replace source = "DHS SP" if source == "DHS-OTHER/Special" 
	replace source = "DHS" if source == "DHS_TLS" 
	replace source = "IFHS" if source == "IRQ IFHS"
	replace source = "IRN HH SVY" if source == "IRN DHS" 
	replace source = "TLS2003" if source == "East Timor 2003"
	replace source = "MICS3" if source == "MICS" 
	
	** keep appropriate variables and convert everything to q-space 
	replace p_nn = p_enn*p_lnn if p_nn == . 
	gen p_inf = p_nn*p_pnn 
	gen p_ch = p_1p1*p_1p2*p_1p3*p_1p4
	gen p_u5 = 1-q5
	egen deaths_u5 = rowtotal(death_count*)
	keep country year sex source source_y p_enn p_lnn p_nn p_pnn p_inf p_ch p_u5 deaths_u5 survey_year
	rename country iso3
	order iso3 year sex source source_y p_enn p_lnn p_nn p_pnn p_inf p_ch p_u5 deaths_u5 
	
	foreach age in enn lnn nn pnn inf ch u5 { 
		replace p_`age' = 1-p_`age'
	}
	rename p_* q_*
	
	duplicates drop
	bysort iso3 year source_y: egen count = count(year)
	assert count <= 3
	gen withinsex = 1 if count < 3
	replace withinsex = 0 if withinsex == .
	drop count
	isid iso3 source_y year sex
	tempfile cbh
	save `cbh', replace
	
	** get ihme_loc_id if not present
	use `codes', clear
	rename local_id_2013 iso3
	drop if iso3 == ""
	merge 1:m iso3 using `cbh'
	drop if _m == 1
	drop _m
	replace ihme_loc_id = iso3 if ihme_loc_id == ""
	save `cbh', replace
	merge m:1 ihme_loc_id using `codes'
	drop if ihme_loc_id == "IND_4637" | ihme_loc_id == "IND_4638"
	
	preserve
	keep if _m == 1
	if (_N == 0) { 
		set obs 1
		replace ihme_loc_id = "ALL IHME_LOC_ID MERGED FROM CBH"
	}
	outsheet using "input_data_no_ihme_loc_id.csv", comma replace
	restore
	
	keep if _m == 3
	drop _m local_id_2013 iso3 region_name
	
	** save CBH data 
	tempfile cbh
	save `cbh', replace 
	
	
** *************************	
** Compile VR deaths
** *************************
	
** prep COD VR file 
	use "$cod_vr_file", clear

	keep iso3 location_id sex subdiv source year deaths2 deaths3 deaths91 deaths93 deaths94 im_frmat child_split
	
	summ year
	local yearmax = r(max)
	
	preserve
	quiet run "create_connection_string.ado"
	create_connection_string, strConnection
	local conn_string_download = r(conn_string)
	odbc load, exec("SELECT location_id, location_parent_id, location_level, path_to_top_parent FROM shared.location;") `conn_string_download' clear
	keep if regexm(path_to_top_parent,"102")
	keep if location_level == 3
	local exp = `yearmax' - 1949
	expand `exp'
	bysort location_id: gen year = 1949 + _n
	tempfile locmap
	save `locmap', replace
	restore, preserve
	keep if iso3 == "USA" & location_id != .
	merge m:1 location_id year using `locmap'
	drop if _m == 1
	drop _m
			
	assert deaths2 != . if deaths3 != .
	assert deaths3 != . if deaths2 != .
	drop if im_frmat != 2

	levelsof location_parent_id, local(parents)
	
	forvalues i = 1950/`yearmax' {
		foreach j of local parents {
			cap assert deaths2 != . if location_parent_id == `j' & year == `i'
			if (_rc != 0) drop if location_parent_id == `j' & year == `i'
		}
	}
	
	foreach age of varlist deaths* {
		assert `age' != .
	}
	
	collapse (sum) deaths*, by(iso3 location_parent_id year subdiv child_split im_frmat sex)
	rename location_parent_id location_id
	isid location_id sex year
	gen source = "Collapsed Subnat"
	tempfile addstates
	save `addstates', replace
	restore
	append using `addstates'
	
	gen ihme_loc_id = iso3
	replace ihme_loc_id = iso3 + "_" + string(location_id) if location_id != .
	replace ihme_loc_id = "PRI" if location_id == 385
	drop iso3 location_id
	
	merge m:1 ihme_loc_id using `codes'
	keep if _m == 3
	drop _m
	
	** check that the infant formats haven't changed
	drop if im_frmat == 9 
	summ im_frmat
	assert `r(max)' == 8 
	
	** change subnational data into our format and drop china subnational until it is in a format where it's aggregated to province
	gen source_type = "VR" 
	replace source_type = "DSP" if substr(ihme_loc_id,1,3) == "CHN" & (source == "China_2004_2012" | source == "China_1991_2002")
	drop if inlist(subdiv, "A30","A10","A30.","A70","A80")
	drop if ihme_loc_id == "QAT" & (subdiv != "" & subdiv != ".")
	drop if inlist(source,"UK_deprivation_1981_2000","UK_deprivation_2001_2012")
	drop if ihme_loc_id == "MAR" & source != "ICD10"
	replace subdiv = "" if inlist(subdiv,"A20",".","..")
	gen loc_substr = substr(ihme_loc_id,-4,4)
	replace subdiv = "" if loc_substr == subdiv
	replace loc_substr = substr(ihme_loc_id,-3,3)
	replace subdiv = "" if loc_substr == subdiv
	replace subdiv = "" if inlist(subdiv,"East Midlands","Scotland","South East","South West" ,"Stockholm county","Sweden excluding Stockholm county","Wales","East of England") & strlen(ihme_loc_id) > 3
	replace subdiv = "" if inlist(subdiv,"London","North East","North West","Northern Ireland","West Midlands","Yorkshire and The Humber") & strlen(ihme_loc_id) > 3
	replace subdiv = "" if inlist(subdiv,"Aichika","Akita","Aomori","Chiba","Eastern Cape", "Ehime", "Free State") & strlen(ihme_loc_id) > 3
	replace subdiv = "" if inlist(subdiv, "Fukui", "Fukuoka","Fukushima","Gauteng") & strlen(ihme_loc_id) > 3
	replace subdiv = "" if inlist(subdiv,"Gifu","Gumma","Hiroshima","Hokkaido","Hyogo","Ibaraki","Ishikawa") & strlen(ihme_loc_id) > 3
	replace subdiv = "" if inlist(subdiv,"Iwate","Kagawa","Kagoshima","Kanagawa") & strlen(ihme_loc_id) > 3
	replace subdiv = "" if inlist(subdiv,"Kochi","Kumamoto","KwaZulu-Natal","Kyoto","Limpopo","Mie") & strlen(ihme_loc_id) > 3
	replace subdiv = "" if inlist(subdiv,"Miyagi","Miyazaki","Mpumalanga","Nagano") & strlen(ihme_loc_id) > 3
	replace subdiv = "" if inlist(subdiv,"Nagasaki","Nara","Niigata","Northern Cape","Oita","Okayama") & strlen(ihme_loc_id) > 3
	replace subdiv = "" if inlist(subdiv,"Okinawa","Osaka","Saga","Saitama","Shiga","Shimane","Shizuoka") & strlen(ihme_loc_id) > 3
	replace subdiv = "" if inlist(subdiv,"Tochigi","Tokushima","Tokyo","Tottori","Toyama","Wakayama") & strlen(ihme_loc_id) > 3
	replace subdiv = "" if inlist(subdiv,"Western Cape","Yamagata","Yamaguchi","Yamanashi") & strlen(ihme_loc_id) > 3
	
	preserve 
	keep if subdiv != ""
	if (_N == 0) {
		set obs 1
		replace subdiv = "NO NEW SUBDIV VALUES TO RESOLVE"
	}
	outsheet using "cod_vr_new_subdiv.csv", comma replace
	restore
	
	drop if subdiv != ""
	drop subdiv loc_substr
	
	drop if child_split == 1
	drop child_split
	
	duplicates tag ihme_loc_id year sex, gen(dup)
	drop if dup == 1 & (ihme_loc_id == "GEO" | ihme_loc_id == "VIR" | ihme_loc_id== "PHL") // Maya added PHL
	drop if source == "Russia_FMD_2012_2013" & year >=2012
	drop dup
	isid ihme_loc_id year sex
	
	** generate appropriate death variables
		** early-late neonatal split 
	gen deaths_enn = deaths91 if im_frmat == 1 | im_frmat == 2
	gen deaths_lnn = deaths93 if im_frmat == 1 | im_frmat == 2 
	gen deaths_pnn = deaths94 if im_frmat == 1 | im_frmat == 2 
	
		** neonatal-post-neonatal split 
	gen deaths_nn = deaths91 + deaths93 if im_frmat == 1 | im_frmat == 2 | im_frmat == 4
	
		** infant-child split 
	gen deaths_inf = deaths2
	gen deaths_ch  = deaths3
	drop im_frmat
	
	** format sex variable 
	tostring sex, replace
	replace sex = "male" if sex == "1" 
	replace sex = "female" if sex == "2" 
	keep ihme_loc_id year sex deaths_* source_type source
	rename source cod_source
	compress	
	
	replace source_type = "DSP3" if source_type == "DSP" & year >=2004 
	replace source_type = "VR2" if source_type == "VR" & ihme_loc_id == "KOR" & year > 1977
	replace source_type = "VR1" if source_type == "VR" & ihme_loc_id == "TUR" & year < 2009
	replace source_type = "VR2" if source_type == "VR" & ihme_loc_id == "TUR" & year >= 2009
	
	summ year
	local yearmax = r(max)
	tempfile cod_vr
	save `cod_vr', replace
	
** aggregate up- go up by level
	tempfile add_nats
	local count = 0
	foreach lev in 5 4 {
		di "`lev'"
		get_locations, level(subnational)
		local exp = `yearmax' - 1949
		expand `exp'
		bysort ihme_loc_id: gen year = 1949 + _n
		
		merge 1:m ihme_loc_id year using `cod_vr'
		drop if _m == 2
		assert deaths_ch != . if deaths_inf != .
		assert deaths_inf != . if deaths_ch != .

		keep if level == `lev'
		levelsof parent_id, local(parents)
		
		forvalues i = 1950/`yearmax' {
			foreach j of local parents {
				cap assert deaths_ch != . if parent_id == `j' & year == `i'
				if (_rc != 0) drop if parent_id == `j' & year == `i'
			}
		}
		
		foreach age in enn lnn pnn nn inf ch {
			gen miss_`age' = 1 if deaths_`age' == .
		}
		
		collapse (sum) deaths* miss*, by(parent_id year sex source_type)
		rename parent_id location_id
		
		foreach age in enn lnn pnn nn inf ch {
			replace deaths_`age' = . if miss_`age' != 0
		}
		gen cod_source = "Collapsed Subnat"
		keep year cod_source sex location_id source_type deaths_enn deaths_lnn deaths_pnn deaths_nn deaths_inf deaths_ch
		tempfile tmp
		save `tmp', replace
		
		get_locations, level()
		keep ihme_loc_id location_id
		merge 1:m location_id using `tmp'
		keep if _m == 3
		drop location_id
		keep year cod_source sex ihme_loc_id source_type deaths_enn deaths_lnn deaths_pnn deaths_nn deaths_inf deaths_ch
		
		append using `cod_vr'
		save `cod_vr', replace
		local count = `count' + 1
	
	}
	
	** if we have national data already here, then we'll drop the aggregated subnats
	duplicates tag ihme_loc_id year sex source_type, gen(dup)
	drop if dup > 0 & cod_source == "Collapsed Subnat"
	drop dup
	isid ihme_loc_id year sex source_type
	
	merge m:1 ihme_loc_id using `codes'
	keep if _m == 3
	drop _m
	keep year cod_source sex ihme_loc_id source_type deaths_enn deaths_lnn deaths_pnn deaths_nn deaths_inf deaths_ch
	
	rename deaths_inf deaths_inf_cod
	rename deaths_ch deaths_ch_cod 
	save `cod_vr', replace
	
** load demographics VR data 
	use "$mort_vr_file", clear 
	merge m:1 ihme_loc_id using `codes'
	keep if _m == 3 & year >= 1950
	drop _m region_name
	
	drop if regexm(deaths_footnote, "Fake number") == 1
	
	** keep VR and SRS 
	gen source_type1 = "SRS" if regexm(source_type, "SRS") == 1 
	replace source_type1 = "VR" if regexm(source_type, "VR") == 1
	replace source_type1 = "DSP" if regexm(source_type, "DSP") == 1
	keep if source_type1 == "VR" | source_type1 == "SRS" | source_type1 == "DSP"
	drop source_type1
	
	** get infant and child deaths 
	gen deaths_inf = DATUM0to0 
	gen deaths_ch = DATUM1to4
	drop if deaths_inf == . | deaths_ch == . 
	keep ihme_loc_id year sex source_type deaths_source deaths_inf deaths_ch 
	rename deaths_source mortality_source
	compress 
	gen neonatal = 0 
	
** merge COD and demographics VR files 
	merge 1:1 ihme_loc_id year sex source_type using `cod_vr'
	
	drop if _m == 2
	
	assert deaths_nn <= ((deaths_lnn + deaths_enn)*1.02) if deaths_lnn != . & deaths_enn != .
	assert deaths_nn >= ((deaths_lnn + deaths_enn)*.98) if deaths_lnn != . & deaths_enn != .
	replace deaths_nn = deaths_enn + deaths_lnn if deaths_enn != . & deaths_lnn != .
	
	assert deaths_inf_cod <= ((deaths_nn + deaths_pnn)*1.02) if deaths_nn != . & deaths_pnn != .
	assert deaths_inf_cod >= ((deaths_nn + deaths_pnn)*.98) if deaths_nn != . & deaths_pnn != .
	replace deaths_inf_cod = deaths_nn + deaths_pnn if deaths_nn != . & deaths_pnn != .
	
	
	** drop enn, lnn, pnn, nn if the inf or ch deaths are too far off from the ones we use for mortality
	replace deaths_enn =  . if (deaths_inf_cod > deaths_inf*1.05 | deaths_inf_cod < deaths_inf*.95) | (deaths_ch_cod > deaths_ch*1.05 | deaths_ch_cod < deaths_ch*.95) 
	replace deaths_lnn =  . if (deaths_inf_cod > deaths_inf*1.05 | deaths_inf_cod < deaths_inf*.95) | (deaths_ch_cod > deaths_ch*1.05 | deaths_ch_cod < deaths_ch*.95) 
	replace deaths_pnn =  . if (deaths_inf_cod > deaths_inf*1.05 | deaths_inf_cod < deaths_inf*.95) | (deaths_ch_cod > deaths_ch*1.05 | deaths_ch_cod < deaths_ch*.95) 
	replace deaths_nn = . if (deaths_inf_cod > deaths_inf*1.05 | deaths_inf_cod < deaths_inf*.95) | (deaths_ch_cod > deaths_ch*1.05 | deaths_ch_cod < deaths_ch*.95) 
	replace deaths_inf = deaths_inf_cod if deaths_nn != .
	replace deaths_ch = deaths_ch_cod if deaths_nn != .
	
	
** generate both sexes
	keep ihme_loc_id sex year source_type deaths_enn deaths_lnn deaths_pnn deaths_inf deaths_ch deaths_nn 
	drop if sex == "both" 
	tempfile temp
	save `temp', replace 
	gen count = 1
	foreach var of varlist deaths* { 
		replace `var' = -99999999 if `var' == . 
	} 
	collapse (sum) deaths* count, by(ihme_loc_id year source_type)
	keep if count == 2
	foreach var of varlist deaths* { 
		replace `var' = . if `var' < 0 
	} 
	** this make "both" missing if one or the other sex is missing
	
	drop count
	gen sex = "both" 
	append using `temp' 
	bysort ihme_loc_id year: egen count = count(year)
	keep if count >= 3 	
	drop count 	
	
	
** identify age split
	gen type = 1 if deaths_enn != . & deaths_lnn !=. & deaths_pnn != . & deaths_ch != . 
	replace type = 2 if deaths_nn !=. & deaths_pnn != . & deaths_ch != . & type == . 
	replace type = 3 if deaths_inf != . & deaths_ch != . & type == . 
	
	** make consistent across sex
	bysort ihme_loc_id year sex source_type: egen temp = max(type) 
	replace type = temp 
	drop temp 
	replace deaths_enn = . if type > 1
	replace deaths_lnn = . if type > 1
	replace deaths_nn = . if type > 2
	replace deaths_pnn = . if type > 2
	gen deaths_u5 = deaths_inf + deaths_ch
	
** format
	sort ihme_loc_id source_type sex year
	order ihme_loc_id source_type sex year type deaths*
	compress
	tempfile vr_deaths
	save `vr_deaths'

	
** *************************	
** Compile populations
** *************************	

** for VR, use national population estimates
	use "$natl_pop_file", clear
	keep if age_group_name == "<1 year" | age_group_name == "1 to 4"
	keep ihme_loc_id sex year age_group_name pop
	replace age_group_name = "ch" if age_group_name == "1 to 4"
	replace age_group_name = "inf" if age_group_name == "<1 year"
	rename pop pop_
	reshape wide pop_, i(ihme_loc_id sex year) j(age_group_name, string)
	tempfile natl_pop
	save `natl_pop', replace
	
	use "$births_file", clear
	keep ihme_loc_id year sex births
	merge 1:1 ihme_loc_id sex year using `natl_pop'
	drop _m
	gen source_type = "VR" 
	save `natl_pop', replace
	
** for SRS, use SRS populations where available, national populations elsewise 
	use "$all_pop_file", clear
	keep if source_type == "SRS" | ((ihme_loc_id == "PAK" | ihme_loc_id == "BGD") & source_type == "IHME") |  source_type == "DSP"
	replace source_type = "SRS" if (ihme_loc_id == "PAK" | ihme_loc_id == "BGD" & source_type == "IHME") 
	gen pop_inf = c1_0to0
	gen pop_ch = c1_1to4
	keep ihme_loc_id year sex source_type pop*
	append using `natl_pop'
	gen mergesource = source_type
	tempfile all_pop
	save `all_pop', replace

	
** *************************	
**  Calculate rates from VR/SRS
** *************************	
	
** merge deaths and population 	
	use `vr_deaths', clear
	gen mergesource = source_type
	replace mergesource = "DSP" if regexm(source_type,"DSP") == 1
	replace mergesource = "SRS" if regexm(source_type,"SRS") == 1
	replace mergesource = "VR" if regexm(source_type,"VR") == 1
	drop if ihme_loc_id == "ZAF" & source_type == "VR-SSA"
	merge 1:1 ihme_loc_id year sex mergesource using `all_pop'
	assert _m !=1
	keep if _m == 3
	drop _m mergesource
	
** calculate qx 
	g q_enn = deaths_enn/births
	g q_lnn = deaths_lnn/(births-deaths_enn)
	g q_nn = 1-(1-q_enn)*(1-q_lnn)
	
	g m_inf = deaths_inf/pop_inf 
	g m_ch = deaths_ch/pop_ch

** 1a0 (from Preston/Heuveline/Guillot demography book) 
	gen ax_1a0=. 
	replace ax_1a0 = 0.330 if sex=="male" & m_inf>=0.107
	replace ax_1a0 = 0.350 if sex=="female" & m_inf>=0.107
	replace ax_1a0 = (0.330 + 0.350)/2 if sex=="both" & m_inf>=0.107
	replace ax_1a0 = 0.045 + 2.684*m_inf if sex=="male" & m_inf<0.107
	replace ax_1a0 = 0.053 + 2.800*m_inf if sex=="female" & m_inf<0.107 
	replace ax_1a0 = (0.045 + 2.684*m_inf + 0.053 + 2.800*m_inf)/2 if sex=="both" & m_inf<0.107	
** 4a1 (from Preston/Heuveline/Guillot demography book) 
	gen ax_4a1=.
	replace ax_4a1 = 1.352 if sex=="male" & m_inf>=0.107
	replace ax_4a1 = 1.361 if sex=="female" & m_inf>=0.107
	replace ax_4a1 = (1.352+1.361)/2 if sex=="both" & m_inf>=0.107
	replace ax_4a1 = 1.651-2.816*m_inf if sex=="male" & m_inf<0.107
	replace ax_4a1 = 1.522-1.518*m_inf if sex=="female" & m_inf<0.107 
	replace ax_4a1 = (1.651-2.816*m_inf + 1.522-1.518*m_inf)/2 if sex=="both" & m_inf<0.107

	gen q_inf = 1*m_inf/(1+(1-ax_1a0)*m_inf)
	g q_ch = 4*m_ch/(1+(4-ax_4a1)*m_ch)
	g q_u5 = 1-(1-q_inf)*(1-q_ch)

	g q_pnn = 1 - (1-q_inf)/(1-q_nn)
	
	gen pop_5 = pop_inf + pop_ch
	keep ihme_loc_id sex year source_type q_enn q_lnn q_nn q_pnn q_inf q_ch q_u5 deaths_* pop_5 
	order ihme_loc_id sex year source_type q_enn q_lnn q_nn q_pnn q_inf q_ch q_u5 deaths_* pop_5 
	
** center year for VR and then save
	replace year = floor(year) + 0.5 
	rename source_type source
	drop if q_inf == . & q_ch == . & q_u5 == . 
	tempfile vr
	save `vr', replace

** Add aggregate estimates that we don't have deaths and exposure separately for	
	** add any aggregate estimates
	use "IND_SRS_1995_2013.dta", clear
	foreach var in q_enn q_lnn q_nn q_pnn q_inf q_ch q_u5 {
		cap gen `var' = .
	}
	foreach var in deaths_inf deaths_ch deaths_enn deaths_lnn deaths_pnn deaths_nn deaths_u5 pop_5 {
		cap gen `var' = 999999
	}
	tempfile add_agg_ests
	save `add_agg_ests', replace

	

	
** *************************
** Combine all sources
** *************************

	use `vr', clear
	append using `cbh' 	
	append using `add_agg_ests'
	drop if year < 1950	
	
** *************************	
** Mark exclusions 
** *************************	

	gen exclude = 0 	
	
** exclude CBH estimates more than 15 years before the survey
	replace exclude = 11 if year < survey_year - 15 & survey_year != .
	drop survey_year

** exclude small VR countries - below an under-5 population of 20,000
	preserve
	keep if sex == "both" & (regexm(source,"VR") == 1 | regexm(source,"SRS") == 1)
	keep ihme_loc_id year pop_5
	keep if pop_5 < 20000
	gen source = "VR" 
	tempfile too_small
	save `too_small', replace
	restore 
		
	merge m:1 ihme_loc_id year source using `too_small' 
	replace exclude = 1 if _m == 3 
	drop _m pop_5
	
	** create variable to use after merge with 5q0 outliers below in order to identify if points should be outliered based on their type
	gen broadsource = source
	replace broadsource = "DSP" if regexm(source,"DSP") == 1
	replace broadsource = "VR" if regexm(source,"VR") == 1
	replace broadsource = "SRS" if regexm(source,"SRS") == 1
	
** Exclude anything that is outliered or scrubbed from GPR 
	preserve
	** find VR/SRS we don't want to exclude (i.e. exclude all other VR/SRS) 
	insheet using "$raw5q0_file", clear
	drop if ihme_loc_id == "BGD" & source == "SRS" & (year == 2002.5 | year == 2001.5)
	gen broadsource = source
	replace broadsource = "DSP" if regexm(source,"DSP") == 1
	replace broadsource = "VR" if regexm(source,"VR") == 1
	replace broadsource = "SRS" if regexm(source,"SRS") == 1
	keep if broadsource == "VR" | broadsource == "SRS" | broadsource == "DSP"
	duplicates drop ihme_loc_id year broadsource, force
	drop if outlier == 1 | shock == 1 
	keep ihme_loc_id year source broadsource
	tempfile gpr_vr
	save `gpr_vr', replace
	
	** find CBH we want to exclude because it's in a fatal discontinuity year
	insheet using "$raw5q0_file", clear
	keep if indirect == "direct" 
	keep if shock == 1 
	keep ihme_loc_id year source 
	rename source source_y
	tempfile gpr_cbh_shock
	save `gpr_cbh_shock', replace
	
	** find CBH surveys we want to exclude 
	insheet using "$raw5q0_file", clear
	keep if indirect == "direct" 
	keep if outlier == 1 
	keep ihme_loc_id source 
	rename source source_y
	duplicates drop 
	tempfile gpr_cbh_survey
	save `gpr_cbh_survey', replace 	
	
	** find surveys we want to keep if they haven't been excluded
	insheet using "$raw5q0_file", clear
	keep if indirect == "direct"
	keep if outlier != 1 & shock != 1 
	keep ihme_loc_id source
	rename source source_y
	duplicates drop 
	tempfile gpr_cbh_keep
	save `gpr_cbh_keep', replace  
	restore 
	
	merge m:1 ihme_loc_id year broadsource using `gpr_vr'
	drop if _m == 2	
	replace exclude = 2 if _m == 1 & (broadsource == "VR" | broadsource == "SRS" | broadsource == "DSP") 
	drop _m 

	merge m:1 ihme_loc_id year source_y using `gpr_cbh_shock' 
	drop if _m == 2 
	replace exclude = 2 if _m == 3
	drop _m 
	
	merge m:1 ihme_loc_id source_y using `gpr_cbh_survey'
	drop if _m == 2
	replace exclude = 2 if _m == 3 
	drop _m 
	
	merge m:1 ihme_loc_id source_y using `gpr_cbh_keep'
	drop if _m == 2
	replace exclude = 2 if _m == 1 & !regexm(source,"VR") & !regexm(source,"SRS") & !regexm(source,"DSP") 
	drop _m
	compress 
	
** Exclude any VR/SRS that is incomplete (calculate directly by comparing to GPR estimates) 
	preserve
	keep if (broadsource == "VR" | broadsource == "SRS" | broadsource == "DSP") & sex == "both"
	keep ihme_loc_id year source broadsource q_u5
	tempfile incomplete
	save `incomplete', replace
	
	insheet using "$estimate5q0_file", clear 
	rename med q5med
	cap destring q5med, replace force
	keep ihme_loc_id year q5med
	merge 1:m ihme_loc_id year using `incomplete' 
	assert _m != 2
	drop if _m == 1 
	drop _m 
	
	replace year = floor(year)
	summ year	
	local min = `r(min)'
	local max = `r(max)' 
	reshape wide q5med q_u5, i(ihme_loc_id source) j(year)
	order ihme_loc_id q5med* q_u5*
	forvalues y=`min'/`max' { 
		local lower = `y' - 4 
		if (`lower' < `min') local lower = `min'
		local upper = `y' + 4 
		if (`upper' > `max') local upper = `max' 
		egen temp1 = rowmean(q5med`lower'-q5med`upper')
		egen temp2 = rowmean(q_u5`lower'-q_u5`upper')
		** completeness over 9-year average of data and of estimates
		gen avg_complete`y' = temp2 / temp1 						 
		drop temp*
	} 
	reshape long q5med q_u5 avg_complete, i(ihme_loc_id source) j(year)
	replace year = year + 0.5 
	drop if q_u5 == .
	
	** completeness for each individual year
	gen complete = q_u5/q5med 	
	
	gen keep = (complete > 1.1 | complete < 0.9) 	
	
	replace keep = 0 if (avg_complete > 0.9 & avg_complete < 1.1) 	
	
	replace keep = 1 if (complete > 1.5 | complete < 0.5) 			 

	keep if keep == 1 
	keep ihme_loc_id year source 
	save `incomplete', replace 	
	restore
	
	merge m:1 ihme_loc_id year source using `incomplete'
	replace exclude = 3 if _m == 3 & (broadsource == "VR" | broadsource == "SRS" | broadsource == "DSP") 
	drop _m
	
	reshape wide q* deaths*, i(ihme_loc_id year source source_y exclude) j(sex, string)
	foreach age in enn lnn pnn inf ch u5 { 
		gen ratio = q_`age'female / q_`age'male
		replace exclude = 4 if (ratio > 2 | ratio < 0.5) & ratio != .
		drop ratio
	} 
	reshape long 
	
** Exclude anything where all rates are 0 
	replace exclude = 5 if q_inf == 0 & q_ch == 0 
	preserve
	keep if exclude == 5 
	keep ihme_loc_id year source source_y
	duplicates drop 
	tempfile exclude
	save `exclude' 
	restore
	merge m:1 ihme_loc_id year source source_y using `exclude'
	replace exclude = 5 if _m == 3 & exclude == 0
	drop _m 
	
	replace exclude = 6 if ihme_loc_id == "COL" & source != "VR" 
	replace exclude = 6 if ihme_loc_id == "DZA" & source != "VR" 
	replace exclude = 6 if ihme_loc_id == "ECU" & source != "VR" 
	replace exclude = 6 if ihme_loc_id == "GTM" & source != "VR" 
	replace exclude = 6 if ihme_loc_id == "JOR" & source != "VR" 

	preserve
	keep if sex == "both"
	keep if deaths_u5 < 200 
	keep ihme_loc_id year source source_y
	tempfile toolow
	save `toolow', replace
	restore
	merge m:1 ihme_loc_id year source source_y using `toolow'
	replace exclude = 7 if _m == 3 & exclude == 0
	drop _m deaths*
	
	** exclude if improbable deaths/births ratios occur (q_enn > 1, q_lnn < 0)
	replace exclude = 9 if q_enn > 1 & q_enn != .
	replace exclude = 9 if q_lnn < 0 & q_lnn != .


	replace exclude = 8 if ihme_loc_id == "ALB" & source == "VR" & year < 1965 & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "BHR" & source == "VR" & (floor(year) == 1980 | floor(year) == 1985) & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "CAF" & source == "DHS" & (floor(year) == 1967 | floor(year) == 1972) & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "CUB" & source == "VR" & (floor(year) == 1959 | floor(year) == 1960 | floor(year) == 1961) & exclude == 0 
	
	replace exclude = 8 if ihme_loc_id == "GTM" & source == "VR" & (floor(year) == 1980 | floor(year) == 1984) & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "IDN" & source == "DHS" & floor(year) == 1960 & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "IND" & source == "DHS" & (year == 1964 | year == 1969) & exclude == 0
	replace exclude = 8 if ihme_loc_id == "ISR" & source == "VR" & floor(year) == 1984 & exclude == 0 
	
	replace exclude = 8 if ihme_loc_id == "KEN" & source == "DHS" & floor(year) == 1966 & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "KOR" & source == "VR" & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "KWT" & source == "VR" & floor(year) == 1972 & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "LUX" & source == "VR" & (floor(year) == 1991 | floor(year) == 1998) & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "MEX" & source == "VR" & exclude == 0 & year == 1970.5
	replace exclude = 8 if ihme_loc_id == "MLI" & source == "DHS" & floor(year) == 1964 & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "MNG" & source == "VR" & floor(year) == 1985 & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "MRT" & source == "PAPCHILD" & floor(year) == 1973 & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "NGA" & source == "DHS" & (floor(year) == 1966 | floor(year) == 1971) & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "NLD" & source == "VR" & floor(year) == 1969 & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "NPL" & source == "DHS" & floor(year) == 1968 & exclude == 0 
	
	replace exclude = 8 if ihme_loc_id == "PAK" & source == "DHS" & (floor(year) == 1964 | floor(year) == 1969) & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "PER" & source == "DHS" & floor(year) == 1961 & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "POL" & source == "VR" & (floor(year) == 1969 | floor(year) == 1970 | floor(year) == 1971) & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "SDN" & source == "DHS" & (floor(year) == 1982 | floor(year) == 1987) & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "SEN" & source == "MIS" & floor(year) == 1981 & exclude == 0 
	replace exclude = 8 if ihme_loc_id == "SLE" & source == "DHS" & (floor(year) == 1991 | floor(year) == 2001) & exclude == 0 
	
	replace exclude = 8 if ihme_loc_id == "ZMB" & source == "DHS" & (floor(year) == 1965 | floor(year) == 2005) & exclude == 0 
	
	foreach age in enn lnn nn pnn inf ch u5 {
	gen out_`age' = 0
	}
	foreach age in enn nn inf u5 {
		replace out_`age' = 1 if ihme_loc_id == "ARM" & source == "VR" & (floor(year) < 2005) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "AZE" & source == "VR" & (floor(year) < 2005) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "BGR" & source == "VR" & (floor(year) < 2005) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "BLR" & source == "VR" & (floor(year) < 2005) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "EST" & source == "VR" & (floor(year) < 1996) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "GEO" & source == "VR" & (floor(year) < 2005) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "HRV" & source == "VR" & (floor(year) < 2000) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "KAZ" & source == "VR" & (floor(year) < 2008) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "KGZ" & source == "VR" & (floor(year) < 2007) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "LTU" & source == "VR" & (floor(year) < 1995) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "LVA" & source == "VR" & (floor(year) < 1993) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "MDA" & source == "VR" & (floor(year) < 2005) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "POL" & source == "VR" & (floor(year) < 1994) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "ROU" & source == "VR" & (floor(year) < 2005) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "RUS" & source == "VR" & (floor(year) < 2005) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "TJK" & source == "VR" & (floor(year) < 2005) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "TKM" & source == "VR" & (floor(year) < 2007) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "UKR" & source == "VR" & (floor(year) < 2005) & exclude == 0
		replace out_`age' = 1 if ihme_loc_id == "UZB" & source == "VR" & (floor(year) < 2005) & exclude == 0
	}
		
	
** Make sure exclusions are the constant across country-year-sources
	preserve
	replace exclude = 1 if exclude > 0 
	contract ihme_loc_id year source source_y exclude
	replace source_y = "not CBH" if source_y == ""
	local identify = "ihme_loc_id year source source_y"
	isid `identify'
	restore 
	
	tempfile almost
	save `almost', replace
	
	keep if sex == "both"
	tempfile tomerge
	save `tomerge', replace
	
	** Add completeness variable by source comparing q_u5 to the 5q0 model estimate
	insheet using "estimated_5q0_noshocks.txt", clear
	keep ihme_loc_id year med
	gen sex = "both"
	merge 1:m ihme_loc_id year using `tomerge'
	sort ihme_loc_id sex year
	by ihme_loc_id: ipolate med year, gen(med_interp) epolate
	gen s_comp = q_u5/med_interp
	drop if _m == 1
	drop med_interp med sex _m
	keep `identify' s_comp
	replace source_y = "999" if source_y == ""
	isid `identify'
	replace source_y = "" if source_y == "999"
	expand 3
	sort `identify'
	by `identify': gen sex = _n
	tostring sex, replace
	replace sex = "male" if sex == "1"
	replace sex = "female" if sex == "2" 
	replace sex = "both" if sex == "3"
	merge 1:1 `identify' sex using `almost', assert(3) nogen
	
	
	
	
** *************************	
** Create transformations and do checks
** *************************
	drop if q_enn == . & q_lnn == . & q_nn == . & q_pnn == . & q_inf == . & q_ch == . & q_u5 == .
	
	foreach var of varlist q* {
		di in red "`var'"
		replace `var' = 0 if `var' < 0 & exclude != 0
		replace exclude = 9 if `var' <= 0 
	}
	replace exclude = 10 if withinsex == 1
	
** Label exclusions  
	label define exclude 0 "keep" 1 "low population" 2 "excluded from gpr" 3 "incomplete" 4 "implausible sex ratio" 5 "all zero" 6 "vr available" 7 "too few deaths" 8 "manual" 9 "implausible deaths/births" 10 "inadequate sex data" 11 "CBH before range"
	label values exclude exclude 	
	

	** probability of dying in the early neonatal period; conditional on dying in the first five years 
	gen prob_enn = q_enn/q_u5 
    ** probability of dying in the late neonatal period; conditional on dying in the first five years	
	gen prob_lnn = (1-q_enn)*q_lnn/q_u5 
    ** probability of dying in the post-neonatal period; conditional on dying in the first five years	
	gen prob_pnn = (1-q_nn)*q_pnn/q_u5
	** probability of dying in the infant period; conditional on dying in the first five years 
	gen prob_inf = q_inf/q_u5 	
    ** probability of dying in the child period; conditional on dying in the first five years	
	gen prob_ch = (1-q_inf)*q_ch/q_u5 				

	
** *************************	
** Mark data types
** *************************
	gen age_type = "inf/ch" if q_enn == . & q_lnn == . & q_pnn == . 
	replace age_type = "nn/pnn/ch" if q_enn == . & q_lnn == . & q_nn != . & q_pnn != . 
	replace age_type = "enn/lnn/pnn/ch" if q_enn != . & q_lnn !=. & q_pnn != . 
	count if age_type == "" 
	assert `r(N)' == 0 
	assert q_inf != . & q_ch != . if age_type == "inf/ch"
	assert q_nn != . & q_pnn != . & q_ch != . if age_type == "nn/pnn/ch"
	assert q_enn != . & q_lnn != . & q_pnn != . & q_ch != . if age_type == "enn/lnn/pnn/ch"

** *************************	
** Save
** *************************
	merge m:1 ihme_loc_id using `codes'
	drop if _m == 2
	drop _m local_id_2013
	
	gen real_year = year
	replace year = floor(year)
	merge m:1 ihme_loc_id year sex using `natl_pop'
	keep if _m == 3
	drop _m year source_type
	rename real_year year
	
	order region_name ihme_loc_id year sex source age_type exclude q_* prob_* pop_* births
	replace source_y = "not CBH" if source_y == ""
	isid ihme_loc_id year sex source source_y
	replace source = source + "___" + source_y
	drop source_y
	
** unoutliering VR if adult completeness is complete and the reason for outliering is low population or too few deaths
	preserve
	use "d10_45q15.dta", clear
	keep ihme_loc_id year sex source_type comp
	keep if source_type == "VR"
	drop if comp == .
	isid ihme_loc_id year sex comp
	collapse (mean) comp, by(ihme_loc_id year)
	keep if comp >= .95
	drop comp
	replace year = year + .5
	tempfile adult_comp
	save `adult_comp', replace
	restore
	
	merge m:1 ihme_loc_id year using `adult_comp'
	replace exclude = 0 if (exclude == 1 | exclude == 7) & regexm(source,"VR") & _m == 3
	drop _m
	
	compress
	
	local date = subinstr("`c(current_date)'", " ", "_", 2)
	saveold "$save_dir/input_data.dta", replace
	saveold "$save_dir/archive/input_data_`date'.dta", replace

	log close
	exit, clear
	