	clear
	set more off, perm
	set seed 0
	set odbcmgr unixodbc

	local check 99
	if `check' == 1 {
		local 1 /snfs1
		local 2 /snfs3/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/03b_EN_matrices/02_temp/03_data
		}
// Import macros
	global prefix `1'
	local data_dir `2'

// Settings
	set seed 0
	local input_dir "$prefix/LIMITED_USE/PROJECT_FOLDERS/CHN/GBD_COLLABORATORS/NATIONAL_INJURY_SURVEILLANCE_SYSTEM"
	local aggregated_ncodes ncode1 ncode2 ncode31 ncode4 ncode5 ncode6 ncode7 ncode2_n89
	** define children of each aggregated ncode
	local c_ncode1 n1 n2 n3 n4 n5 n6 n7
	local c_ncode2 n8 n9 n10
	local c_ncode2_n89 n8 n9
	local c_ncode31 n11 n12 n13
	local c_ncode4 n15 n16 n17 n18 n19 n20 n21 n22 n23 n24 n25 n26
	local c_ncode5 n27 n28
	local c_ncode6 n30 n31 n32
	local c_ncode7 n33 n34

// Get N-code and E-code maps
	import excel ecode=B gbd_e_code=C using "`input_dir'/ecode values.xlsx", sheet("Sheet1") cellrange(A2) clear
	drop if ecode == "-"
	tempfile e_map
	save `e_map'

	import excel gbd_n_code=A ncode=D using "`input_dir'/ncode variables.xlsx", sheet("Sheet1") cellrange(A2) clear
	** drop burns map b/c will need ICD ratios to split these 
	drop if inlist(ncode,"ncode2_n89","")
	tempfile n_map
	save `n_map'


// Append datasets
	// local files: dir "`input_dir'" files "* NISS 2014-1-15.dta", respectcase
	local files: dir "`input_dir'" files "*final.dta", respectcase
	clear
	cap erase `appended'
	tempfile appended
	foreach f of local files {
		// Import
				use  "`input_dir'/`f'", clear
		
		gen year = substr("`f'",1,4)
		destring year, replace
		keep year sex age ncode* ecode
		
		// Add disaggregated burns N-codes which aren't in orginal dataset
		gen ncode2_n89_n8 = .
		gen ncode2_n89_n9 = .
		
		// Drop patients that aren't mapped to any N-code
		destring ncode*, replace
		egen tmp = rowtotal(ncode*)
		drop if tmp == 0
		drop tmp
		
		// Drop aggregated n_codes where a dissagregated n-code is coded too
		foreach var of local aggregated_ncodes {
			egen tmp = rowtotal(`var'_*)
			replace `var' = . if `var' == 1 & tmp > 0
			drop tmp
		}
		
		// Distribute remaining aggregated N-codes based on uniform distribution
		** TODO: Incorporate ratios seen in other EN datasets to inform distribution
		tempfile distributed
		foreach agg_n of local aggregated_ncodes {
			preserve
			keep if `agg_n' == 1
			if _N == 0 {
				restore
			}
			else {
				local num_child = wordcount("`c_`agg_n''")
				gen selection = ceil(`num_child'*runiform())
				gen n_target = word("`c_`agg_n''",selection)
				foreach target of local c_`agg_n' {
					replace `agg_n'_`target' = 1 if n_target == "`target'"
				}
				drop n_target selection
				save `distributed', replace
				restore
				drop if `agg_n' == 1
				append using `distributed'
			}
		}
		drop `aggregated_ncodes'
			
		// shrink width of dataset
		gen n_code = ""
		foreach var of varlist ncode* {
			assert `var' == 1 | `var' == .
			replace n_code = n_code + " " + "`var'" if `var' == 1
			drop `var'
		}
		split n_code
		drop n_code
		
		// Append
		cap destring sex, replace
		keep year age sex ecode n_code*
		cap confirm file `appended'
		if !_rc append using `appended'
		save `appended', replace
	}

// Clean
	** sex
	replace sex = . if !inlist(sex,1,2)
	
	** age
	replace age = . if age > 120
	
	** drop patients without e-code
	drop if ecode == ""
	
// Merge on e-code and n-code maps
	merge m:1 ecode using `e_map', nogen keep(match)
	foreach var of varlist n_code* {
		rename `var' ncode
		merge m:1 ncode using `n_map', nogen keep(match master)
		drop ncode
		rename gbd_n_code `var'
	}
	rename (gbd_e_code n_code*) (final_ecode_1 final_ncode_*)
	drop ecode
	
// Add characteristics of dataset
	gen iso3 = "CHN"
	gen inpatient = 0
	
// Drop all "multiple significant injuries" - we've decided that this is too hard to estimate accurately because of different coding styles, different minor injuries getting grouped into this category, etc.  Our long-term incidence was just implausibly high because of a large amount of short-term incidence coupled with a high long-term probability because the follow-up studies/our DWs are for very severe multiple injuries - Nick G
	drop if final_ncode_1 == "N48"
	forvalues i=1/13 {
		replace final_ncode_`i' = "" if final_ncode_`i' == "N48"
	}

// Save cleaned data
	export delimited using "`data_dir'/00_cleaned/cleaned_chinese_niss.csv", delim(",") replace
	