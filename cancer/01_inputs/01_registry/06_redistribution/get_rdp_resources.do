
// Purpose:		Prepare files needed for redistribution

** **************************************************************************
** CONFIGURATION
** **************************************************************************
// Clear memory and set memory and variable limits
	clear all
	set mem 10G
	set maxvar 32000

// Set to run all selected code without pausing
	set more off

// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" global j "J:"
	
// set output folder
	// local output_folder = "$j/WORK/07_registry/cancer/01_inputs/programs/redistribution/maps"
	local output_folder = "/ihme/gbd/WORK/07_registry/cancer/01_inputs/rdp/maps"
	cap mkdir "`output_folder'"

// set version for the location set
	local location_set_version_id 38
	
** ****************************************************************
** GET RESOURCES
** ****************************************************************

// Pull location hierarchy
	// Get data from hierarchy
		odbc load, exec("SELECT * FROM shared.location_hierarchy_history WHERE location_set_version_id = `location_set_version_id'") dsn(PRODCOD) clear
	// Keep only what we need
		keep location_id ihme_loc_id path_to_top_parent is_estimate most_detailed location_name developed
	// Fix India urban path to parrent
		replace path_to_top_parent = "1,158,159,163,44538,44540" if location_id == 44540
	// Save temp file
	preserve
		odbc load, exec("SELECT location_id, location_ascii_name FROM shared.location;") dsn(PRODCOD) clear
		rename location_ascii_name parent_name
		rename location_id parent_id
		tempfile location_hierarchy
		save `location_hierarchy', replace
	restore
	// Split path to top parent
		split path_to_top_parent, p(",")
	// Rename path to parent splits
		local i = 1
		foreach t in global super_region region country subnational_level1 subnational_level2 subnational_level3 {
			rename path_to_top_parent`i' parent_id
			destring(parent_id), replace
			merge m:1 parent_id using `location_hierarchy', keep(1 3) keepusing(parent_name) nogen
			rename parent_id `t'
			rename parent_name `t'_name
			** drop `t'_name
			local i = `i' + 1
		}
	// Rename development status
		replace developed = "0" if inlist(country_name, "China", "India", "Kenya", "Saudi Arabia")
		gen dev_status = "D" + developed
		** gen dev_status = developed
		** destring(dev_status), replace
	// handle exceptions
		// England
			gen tag_england = 1 if subnational_level1 == 4749 & location_id != 4749
			replace subnational_level1 = subnational_level2 if tag_england == 1
			replace subnational_level1_name = subnational_level2_name if tag_england == 1
			replace subnational_level2 = subnational_level3 if tag_england == 1
			replace subnational_level2_name = subnational_level3_name if tag_england == 1
			replace subnational_level3 = . if tag_england == 1
			replace subnational_level3_name = "" if tag_england == 1
			drop tag_england
		// China (without Hong Kong and Macao)
			gen tag_chn_wo_hkmc = 1 if subnational_level1 == 44533 & location_id != 44533
			replace subnational_level1 = subnational_level2 if tag_chn_wo_hkmc == 1
			replace subnational_level1_name = subnational_level2_name if tag_chn_wo_hkmc == 1
			replace subnational_level2 = subnational_level3 if tag_chn_wo_hkmc == 1
			replace subnational_level2_name = subnational_level3_name if tag_chn_wo_hkmc == 1
			replace subnational_level3 = . if tag_chn_wo_hkmc == 1
			replace subnational_level3_name = "" if tag_chn_wo_hkmc == 1
			drop tag_chn_wo_hkmc
		// Append in US county list from US county team
			drop if country_name == "United States" & subnational_level2_name != ""
			tempfile location_hierarchy
			save `location_hierarchy', replace
			insheet using "$j/WORK/03_cod/01_database/02_programs/redistribution/code/us_counties.csv", comma names clear
			rename state_location_id location_id
			rename cnty_location_id subnational_level2
			rename cnty_name subnational_level2_name
			merge m:1 location_id using `location_hierarchy', keep(1 3) keepusing(ihme_loc_id global dev_status super_region region country subnational_level1 global_name super_region_name region_name country_name subnational_level1_name) nogen
			replace location_id = subnational_level2
			replace ihme_loc_id = "USA_"+string(location_id)
			keep location_id ihme_loc_id global* dev_status super_region* region* country* subnational_*
			append using `location_hierarchy'
		// Append King county list from US county team
		quietly {
			tempfile location_hierarchy
			save `location_hierarchy', replace
			foreach c in 43944 43945 43946 43948 43949 43950 43951 43952 43953 43954 43955 43956 43957 43958 43959 43960 43961 43963 43964 43965 43966 43967 43968 43969 43971 43972 43973 43974 43975 43976 43977 43978 43979 43980 43981 43982 43983 43985 43986 43987 43989 43990 43992 43993 43994 43995 43996 43997 43998 43999 44000 44001 44002 44003 44004 44005 44007 44008 44009 44010 44011 44012 44013 44014 44015 44016 44017 44018 44019 44021 44023 44024 44025 44026 44027 44029 44030 44031 44032 44033 44034 44035 44037 44038 44039 44040 44041 44042 44043 44044 44045 44046 44047 44048 44049 44050 44051 44053 44054 44055 44057 44058 44059 44060 44062 44063 44064 44065 44066 44068 44069 44070 44071 44073 44074 44075 44076 44078 44079 44081 44082 44083 44084 44086 44087 44088 44089 44090 44091 44092 44093 44094 44095 44096 44097 44099 44100 44101 44102 44103 44104 44105 44106 44107 44109 44110 44111 44112 44113 44115 44116 44117 44119 44120 44121 44122 44123 44124 44126 44127 44129 44130 44131 44132 44133 44135 44137 44138 44141 44142 44143 44144 44146 44147 44148 44149 44150 44151 44153 44154 44155 44156 44158 44159 44160 44161 44163 44164 44165 44166 44168 44169 44170 44171 44173 44174 44175 44176 44177 44178 44179 44180 44181 44183 44184 44185 44186 44188 44189 44190 44191 44192 44194 44196 44197 44200 44201 44202 44204 44205 44206 44207 44209 44210 44212 44213 44216 44217 44218 44219 44221 44222 44223 44224 44225 44226 44227 44228 44229 44231 44232 44234 44235 44236 44237 44238 44239 44240 44241 44242 44243 44244 44245 44246 44247 44248 44250 44251 44252 44253 44254 44255 44256 44258 44259 44260 44262 44263 44265 44266 44269 44270 44271 44272 44275 44276 44277 44278 44279 44281 44283 44284 44285 44286 44288 44289 44290 44292 44293 44294 44295 44296 44298 44299 44302 44303 44304 44305 44306 44307 44308 44311 44312 44313 44315 44316 44317 44318 44319 44320 44321 44322 44324 44325 44326 44328 44329 44330 44331 44333 44334 44336 44337 44338 44339 44340 44342 44343 44344 44346 44347 44348 44350 44351 44353 44355 44356 44357 44360 44361 44362 44363 44364 44365 44366 44368 44369 44370 44371 44372 44373 44375 44376 44377 44378 44380 44381 44383 44384 44385 44386 44390 44391 44393 44394 44395 44396 44397 44398 44403 44405 44407 44409 44411 44412 44413 44414 44415 44416 44417 44418 44419 44420 44421 44422 44423 44424 44425 44427 44428 44429 44431 44432 44434 44435 44436 44437 {
				use `location_hierarchy', clear
				keep if location_id == 3543
				replace location_id = `c'
				replace ihme_loc_id = "USA_`c'"
				replace subnational_level2 = `c'
				replace subnational_level2_name = "King County - `c'"
				append using `location_hierarchy'
				tempfile location_hierarchy
				save `location_hierarchy', replace
			}
		}
	// Reformat
		foreach var of varlist global super_region region country subnational_level1 subnational_level2 {
			rename `var' `var'_id
			rename `var'_name `var'
			replace `var' = subinstr(`var', "'", "", .)
		}
		keep location_id ihme_loc_id global global_id dev_status super_region super_region_id region region_id country country_id subnational_level1 subnational_level1_id subnational_level2 subnational_level2_id
		order location_id ihme_loc_id global global_id dev_status super_region super_region_id region region_id country country_id subnational_level1 subnational_level1_id subnational_level2 subnational_level2_id
		sort global super_region region country subnational_level1 subnational_level2
	// Save
		tempfile location_hierarchy
		save `location_hierarchy', replace
		save "`output_folder'/location_hierarchy.dta", replace

// Upload ICD10 and ICD9 package sets. Verify that all of the redistribution packages for the code version are present & copy resources
	foreach code_version in ICD10 ICD9_detail {
		// Get data
			use "$j/WORK/00_dimensions/03_causes/temp/packagesets_`code_version'.dta", clear
			copy "$j/WORK/00_dimensions/03_causes/temp/packagesets_`code_version'.dta" "`output_folder'/packagesets_`code_version'.dta", public replace
		// Verify that all packages exist and if they do, copy them to a temp folder on ihme/gbd
			levelsof(package_set_id), local(package_set_ids) clean
			foreach package_set_id of local package_set_ids {
				local checkfile = "/ihme/cod/prep/01_database/02_programs/redistribution/rdp/`package_set_id'/cause_map.csv"
				display "Checking for formatted redistribution package for package_set_id `package_set_id':"
				display "                /ihme/cod/prep/01_database/02_programs/redistribution/rdp/`package_set_id'"
				local c = 0
				capture confirm file "`checkfile'"
				while _rc {
					sleep 15000
					if `c' > 0 display "Number of attempts: `c'"
					capture confirm file "`checkfile'"
					if `c' >= 25 {
						display in red ""
						display in red "BREAKING REDISTRIBUTION"
						display in red "Redistribution package for package_set_id `package_set_id' not found after 20 tries"
						display in red "This may be because the redistribution package took too long to generate or because there was a problem generating the packages"
						BREAK
					}
					local c = `c' + 1
				}
				capture mkdir "`output_folder'/`package_set_id'"
				display "Found package set! Adding packages to rdp folder..."
				local file_set: dir "/ihme/cod/prep/01_database/02_programs/redistribution/rdp/`package_set_id'/" files "*", respectcase
					foreach f of local file_set {
						display "Copying `f'"
						if "`f'" == "cause_map.csv" copy "/ihme/cod/prep/01_database/02_programs/redistribution/rdp/`package_set_id'/`f'" "`output_folder'/`package_set_id'/_package_map.csv", replace public
						else copy "/ihme/cod/prep/01_database/02_programs/redistribution/rdp/`package_set_id'/`f'" "`output_folder'/`package_set_id'/`f'", replace public
					}
					display "Done!"
			}	
	}

// Generate Cause map
	foreach data_type in "inc" "mor"{
		// Get map of ICD10 codes that may not be in the cancer map (duplicates will be dropped below)
			use "$j/WORK/00_dimensions/03_causes/temp/map_ICD10.dta", clear
			keep cause_code yll_cause yld_cause
			gen coding_system = "ICD10"
			tempfile cause_map
			save `cause_map', replace

		// Get map of ICD9_detail codes that may not be in the cancer map (duplicates will be dropped below)
			use "$j/WORK/00_dimensions/03_causes/temp/map_ICD9_detail.dta", clear
			keep cause_code yll_cause yld_cause
			gen coding_system = "ICD9_detail"

		// Combine Additional ICD maps
			append using `cause_map'
			if "`data_type'" == "mor" {
				drop yld_cause
				rename (cause_code yll_cause) (cause gbd_cause)
			}
			else {
				drop yll_cause
				rename (cause_code yld_cause) (cause gbd_cause)
			}
			gen cod = 1
			save `cause_map', replace

		// Create versions of GBD codes for ICD9 and ICD10
			use "$j/WORK/07_registry/cancer/01_inputs/programs/mapping/data/map_cancer_`data_type'.dta", clear
			keep if coding_system == "GBD"
			replace cause = cause_name
			replace coding_system = "ICD10"
			tempfile GBD_codes
			save `GBD_codes', replace
			replace coding_system = "ICD9_detail"
			append using `GBD_codes'
			save `GBD_codes', replace

		// Access cancer map and add the gbd codes to it
			use "$j/WORK/07_registry/cancer/01_inputs/programs/mapping/data/map_cancer_`data_type'.dta", clear
			keep if inlist(coding_system, "ICD10", "ICD9_detail")
			append using `GBD_codes'
			keep coding_system cause gbd_cause
			gen cod = 0

		// Combine all datasets
			append using `cause_map'
			save `cause_map', replace

		// drop duplicates
			replace gbd_cause = subinstr(gbd_cause, "_cancer", "", .)
			keep cod cause gbd_cause coding_system
			duplicates drop
			duplicates tag coding_system cause, gen(dup)
			drop if dup != 0 & cod == 1
			drop dup cod
			save `cause_map', replace
		
		// add copies of codes with no decimal
			drop if !regexm(cause, "\.")
			replace cause = subinstr(cause, ".", "", 1) 
			drop if regexm(cause, "\.") & coding_system == "ICD9_detail"
			replace cause = subinstr(cause, ".", "", .)
			gen dec_removed = 1
			append using `cause_map'
			duplicates tag coding_system cause, gen(dup)
			drop if dup != 0 & dec_removed != 1
			drop dup dec_removed
		
		// drop remaining duplicates
			duplicates drop
			duplicates tag coding_system cause, gen(dup)
			count if dup != 0
			if r(N) > 0{
				di "ERROR: duplicates exist in cause map"
				BREAK
			}
			drop dup

		// Save
			replace cause = trim(itrim(cause))
			save "`output_folder'/cause_map_`data_type'.dta", replace
	}

** *********************
** END
** *********************
