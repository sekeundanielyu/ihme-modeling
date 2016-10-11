// Inputs: Raw data in panels from HH and Medical Conditions files
// Output: One large pooled file. 2 rows per ID (one for each measurement, at rounds 2 and 4). Indicator Variable for each condition, and SF12 measurement.


// loop through every panel in the data.
forvalues p = 4/14 {

	di in red "CURRENTLY LOOPING THROUGH PANEL `p'"

// Go through HH Conditions file and grab Round 4/2 MCS and PCS summary scores
	use "$MEPS_DATADIR/PANEL_`p'/HH_CONSOLIDATED", clear
	foreach var of varlist * {
		qui local x = lower("`var'")
		qui cap rename `var' `x'
	}

	keep dupersid begrf* endrf* mcs42 pcs42 sfflag42 datayear panel age* sex

// SF started panel 4, year 2000. Drop if data is from before that.
	drop if panel == 4 & datayear == 1999

	// label rounds
	egen minyeardummy = min(datayear)
	gen round = 2 if datayear == minyeardummy
	replace round = 4 if round == .
	replace round = 4 if datayear == 2000 & panel ==4

	// take age as mean of rounds 2 and 4
	replace age42 = age31 if age42 == -1 // deal with missing
	replace age42 = . if age42 == . // take missing from rounds 3 or 1 if missing from 4/2
	gen age_rnd2 = age42 if round == 2
	bysort dupersid: egen age = mean(age42)
	replace age = round(age,1)


	// keep only needed variables
	keep dupersid mcs pcs round datayear age sex
	rename pcs pcs_r
	rename mcs mcs_r


	reshape wide mcs_r pcs_r datayear, i(dupersid) j(round)

	// save data to this point. it is wide so each observation is a person.
	tempfile SF12WIDE
	save `SF12WIDE', replace


	// Go into medical conditions file and get all conditions
	use "$MEPS_DATADIR/PANEL_`p'/IND_MEDICAL_CONDITIONS", clear
	foreach var of varlist * {
		qui local x = lower("`var'")
		qui cap rename `var' `x'
	}
	// no condition data from round 5, it occured after health status measure was taken
	// assign to the rounds not the datayear!
	drop if condrn == 5

	// merge on
	merge m:1 dupersid using `SF12WIDE' // some people will not merge - because they had no conditions on file
	drop _
	gen dummy = 1

	// keep everyone
	tempfile everyone
	save `everyone', replace


		// now open up the full dataset and extract all comorbidities
		// map to comorbidities
			// get map
			preserve

			local icd_map = "gbd2010"
			if "`icd_map'"=="gbd2013" {
				import excel using "./gbd_2013_maps/icd_healthstate.xls", firstrow clear
				keep cause_code yld_cause
				duplicates drop
				drop if yld_cause == "_gc"
				rename (cause_code yld_cause) (icd cond_name)

				replace icd = "00" + icd if length(icd) == 1
				replace icd = "0"  + icd if length(icd) == 2

				drop if regex(icd,"E") | regex(icd,"V")

				tempfile map
				save `map', replace
			}
			else if "`icd_map'"=="gbd2010" {
				insheet using "./gbd_2013_maps/GBD2010_ICD9_cause_mapping_long.csv", clear

				rename gbd2013_cause cond_name
				rename icd9_codes icd
				tostring icd, replace

				replace icd = "00" + icd if length(icd) == 1
				replace icd = "0"  + icd if length(icd) == 2

				keep cond_name icd
				tempfile map
				save `map', replace
			}

			restore

		rename  icd9codx icd
		merge m:m icd using `map', keep(3) nogen

		// map conditions to rounds. -- use CRND variables for this.
		gen round = .

		// split if seen in both time periods
		forvalues i=1/4{
			replace crnd`i' = 0 if crnd`i'== -1
		}
		gen round2 = 1 if crnd1 == 1 | crnd2 == 1
		gen round4 = 1 if crnd3 == 1 | crnd4 == 1
		replace round2 = 1 if condrn == 1 & round == .
		replace round2 = 1 if condrn == 2 & round == .
		replace round4 = 1 if condrn == 3 & round == .
		replace round4 = 1 if condrn == 4 & round == .

		// expand if falls in both periods
		expand 2 if round2 ==1 & round4 == 1, gen(x)
		replace round = 2 if round2 == 1
		replace round = 4 if round4 == 1
		replace round = 2 if x == 1

		// reshape wide by condition so each obs will be a indidual/round
		gen t = 1
		drop icd

		duplicates drop dupersid round cond_name, force
		keep cond_name sex age t dupersid round panel

		reshape wide t, i(dupersid round) j(cond_name) string


		// at this point all the comorbidities are mapped but respondent-rounds with none are not in here, they will be added now.
		preserve
		use dupersid mcs* pcs* age sex using `everyone', clear

		duplicates drop
		reshape long mcs_r pcs_r , i(dupersid) j(round)

		tempfile everyonetworounds
		save `everyonetworounds', replace
		restore

		merge 1:1 dupersid round using `everyonetworounds'
		drop _merge
		foreach var of varlist t* {
			replace `var' = 0 if `var' == .
		}


			replace panel = `p'
			replace mcs = . if mcs < 0
			replace pcs = . if pcs < 0


			// generate an ID variable
			tostring panel, force replace
			gen str id = dupersid + panel

		order dupersid panel  round  sex age pcs_r mcs_r t*

		tempfile panel`p'
		save `panel`p'', replace
		di in red "PANEL `p' of 13 finished"
}


// ID VARIABLE is now dupersid + panel  -- append all MEPS DATA
	forvalues p = 4/13 {
		di in red "appending panel `p'"
		append using `panel`p''
	}

	// clean data a bit more
	foreach var of varlist t* {
		replace `var' = 0 if `var' == .
	}

	// bin ages to 5 year age groups. start with 20.
	gen age_gr = .
	forvalues i = 5(5)75 {
		replace age_gr = `i' if age >= `i' & age <= (`i' + 4)
	}
	replace age_gr = 80 if age >= 80
	replace age_gr = 0 if age == 0
	replace age_gr = 1 if age >=1 & age <= 4
	replace age_gr = . if age == .
	drop age

	// data from panel 4, 5, and the first half of panel 6 are sf-12v1, MEPS documentation suggests the following adjustment:
	// source: http://meps.ahrq.gov/mepsweb/data_stats/download_data/pufs/h79/h79doc.pdf (page C-63)
	destring panel, replace
	replace pcs = pcs + 1.07897 if panel <= 6
	replace mcs = mcs - 0.16934 if panel <= 6
	replace pcs = pcs - 1.07897 if panel == 6 & round == 4
	replace mcs = mcs + 0.16934 if panel == 6 & round == 4


	// ages under 15 should not have pcs/mcs
	replace pcs = . if age < 15
	replace mcs = . if age < 15

// final universe with all MEPS observations cleaned and with comorbidities (for the last year - injury codes are since injury)
	drop if mcs_r == .
	drop if pcs_r == .


// add in the values for the crosswalk, which is the next step
	gen sf = mcs+pcs
	gen predict = sf

	append using "$SAVE_DIR/1_crosswalk_data.dta"

	order id dupersid panel round age_gr sex pcs_r mcs_r sf predict dw
	gen key = _n
	save "$SAVE_DIR/2a_meps_prepped_to_crosswalk_all_conditions.dta", replace


// Subset chronic
	if "`icd_map'"=="gbd2013"{
		preserve
		keep if _n==1
		reshape long t, i(id dupersid panel round age_gr sex key) j(yld_cause) string
		tempfile conds
		save `conds'
		import excel using "./gbd_2013_maps/chronic_map.xlsx", firstrow cellrange(A2) clear
		merge 1:1 yld_cause using `conds', keep(3) nogen
		drop if is_chronic=="no"
		levelsof yld_cause, local(cond)
		local condlist
		foreach c of local cond {
		di in red "keep `c'"
			local condlist `condlist' t`c'
		}
		restore

		keep id dupersid panel round age_gr sex pcs_r mcs_r sf predict dw key `condlist'
	}
		if "`icd_map'"=="gbd2010" {
		preserve
		keep if _n==1
		reshape long t, i(id dupersid panel round age_gr sex key) j(yld_cause) string
		tempfile conds
		save `conds'
		import excel using "./gbd_2013_maps/chronic_map_gbd2010.xlsx", firstrow clear
		merge 1:1 yld_cause using `conds', keep(2 3) nogen
		drop if is_chronic=="no"
		levelsof yld_cause, local(cond)
		local condlist
		foreach c of local cond {
		di in red "keep `c'"
			local condlist `condlist' t`c'
		}
		restore

		keep id dupersid panel round age_gr sex pcs_r mcs_r sf predict dw key `condlist'
	}

	save "$SAVE_DIR/2a_meps_prepped_to_crosswalk_chronic_conditions_only.dta", replace

// save key only
	keep sf dw key predict
	saveold "$SAVE_DIR/2a_meps_crosswalk_key.dta", replace

// END OF DO FILE
