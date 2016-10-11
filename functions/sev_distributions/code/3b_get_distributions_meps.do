// Get 1000 draws of distributions form MEPS


// get disability weights
	insheet using "$gbd_dws", clear
	rename draw* meandw*

    // Epilepsy ratios
    // 283
    preserve
    keep if hhseqid == 283 | hhseqid == 44 | hhseqid == 48
    sort hhseqid
    set obs 4
    replace hhseqid = 2834448 in 4
    forvalues i = 0/999 {
        local 1 = meandw`i' in 1
        local 2 = meandw`i' in 2
        local 3 = meandw`i' in 3
        replace meandw`i' = `3'*`1'/`2' in 4
    }
    keep in 4
    tempfile 2834448
    save `2834448', replace
    restore
    // 284
    preserve
    keep if hhseqid == 284 | hhseqid == 46 | hhseqid == 49
    sort hhseqid
    set obs 4
    replace hhseqid = 2844649 in 4
    forvalues i = 0/999 {
        local 1 = meandw`i' in 1
        local 2 = meandw`i' in 2
        local 3 = meandw`i' in 3
        replace meandw`i' = `3'*`1'/`2' in 4
    }
    keep in 4
    tempfile 2844649
    save `2844649', replace
    restore
    // 283 p2
    preserve
    keep if hhseqid == 283 | hhseqid == 45 | hhseqid == 48
    sort hhseqid
    set obs 4
    replace hhseqid = 2834548 in 4
    forvalues i = 0/999 {
        local 1 = meandw`i' in 1
        local 2 = meandw`i' in 2
        local 3 = meandw`i' in 3
        replace meandw`i' = `3'*`1'/`2' in 4
    }
    keep in 4
    tempfile 2834548
    save `2834548', replace
    restore
    // 284 p2
    preserve
    keep if hhseqid == 284 | hhseqid == 47 | hhseqid == 49
    sort hhseqid
    set obs 4
    replace hhseqid = 2844749 in 4
    forvalues i = 0/999 {
        local 1 = meandw`i' in 1
        local 2 = meandw`i' in 2
        local 3 = meandw`i' in 3
        replace meandw`i' = `3'*`1'/`2' in 4
    }
    keep in 4
    tempfile 2844749
    save `2844749', replace
    restore

    append using `2834448' `2844649'  `2834548' `2844749'

    keep hhseqid meandw0- meandw999
    duplicates drop
    tempfile weights
    save `weights', replace

// start distributions analysis
local icd_map = "gbd2010"
if "`icd_map'"=="gbd2013" {

	import excel using "./gbd_2013_maps/icd_healthstate.xls", firstrow clear
	// keep if run == 1
	// keep code severity hhseqid cause meps
	keep yld_cause grouping healthstate hhseqid
	duplicates drop

}
else if "`icd_map'"=="gbd2010" {
	insheet using "./gbd_2013_maps/gbd2013_keep_list.csv", names clear
	tempfile keeplist
	save `keeplist'

	import excel using "$j/WORK/00_dimensions/00_schema/dimensions.xlsx", sheet(sequelae) first clear
	keep acause grouping healthstate
	tempfile sequelae
	save `sequelae'

	import excel using "$j/WORK/00_dimensions/00_schema/dimensions.xlsx", sheet(healthstates) first clear
	keep healthstate hhseqid
	merge 1:m healthstate using `sequelae', keep(3) nogen
	drop if hhseqid == .

	replace acause="cvd_ihd_angina" if acause=="cvd_ihd" & grouping=="angina"
	replace acause="cvd_hf" if grouping=="_hf"
	replace acause="msk_pain_lowback_noleg" if acause=="msk_pain_lowback" & regexm(healthstate, "_noleg")
	replace acause="msk_pain_lowback_wleg" if acause=="msk_pain_lowback" & regexm(healthstate, "_leg")
	replace acause="skin_bacterial_abs_cell" if acause=="skin_bacterial" & grouping=="abscess"
	replace acause="skin_bacterial_abs_cell" if acause=="skin_cellulitis"
	replace acause="skin_bacterial_impetigo" if acause=="skin_bacterial" & grouping=="impetigo"
	replace acause="cvd_stroke" if regexm(acause,"stroke")

	merge m:1 acause using `keeplist', keep(3) nogen
	rename acause yld_cause

}

// pull 1000 draws for each hhseqid
destring hhseqid, force replace
merge m:1 hhseqid using `weights', keep(match master) nogenerate

// get the mean weight for reporitng later on
egen mean_DW = rowmean(meandw*)

// Generate severities based on constituent healthstates
sort yld_cause grouping mean_DW
bysort yld_cause grouping: gen severity = _n


// get max number of severities for each cause
bysort yld_cause grouping: egen maxsev = max(severity)

// for causes with more than one severity, make a new line for asymptomatic
expand 2 if severity == 1 & maxsev > 1, gen(asymp)
replace asymp = 1 if severity == 1 & maxsev == 1 // for those with only one weight we only get asymp
replace asymp = 0 if asymp == .
replace severity = 0 if asymp == 1

// get 1000 draws of the midpoints between draws
forvalues d = 0/999 {
	qui gen MID`d'a = 0 if asymp == 1
	qui gen MID`d'b = 0 if asymp == 1
}

// get midpoints
egen acause_grouping = group(yld_cause grouping)
levelsof acause_grouping, local(list)
foreach acg of local list {
	preserve
	qui keep if acause_grouping == `acg'
	qui count if asymp == 0
	if `r(N)' != 0 {
		sort severity
		forvalues d = 0/999 {
			qui {
				replace     MID`d'a = 0 							  if severity == 1
				replace     MID`d'b = (meandw`d'[2] + meandw`d'[3])/2 if severity == 1

				replace     MID`d'a = (meandw`d'[2] + meandw`d'[3])/2 if severity == 2
				replace     MID`d'b = (meandw`d'[3] + meandw`d'[4])/2 if severity == 2

				replace     MID`d'a = (meandw`d'[3] + meandw`d'[4])/2 if severity == 3
				replace     MID`d'b = (meandw`d'[4] + meandw`d'[5])/2 if severity == 3

				replace     MID`d'a = (meandw`d'[4] + meandw`d'[5])/2 if severity == 4
				replace     MID`d'b = (meandw`d'[5] + meandw`d'[6])/2 if severity == 4

				replace     MID`d'a = (meandw`d'[5] + meandw`d'[6])/2 if severity == 5
				replace     MID`d'b = (meandw`d'[6] + meandw`d'[7])/2 if severity == 5

				replace     MID`d'a = (meandw`d'[6] + meandw`d'[7])/2 if severity == 6
				replace     MID`d'b = (meandw`d'[7] + meandw`d'[8])/2 if severity == 6

				replace     MID`d'a = (meandw`d'[7] + meandw`d'[8])/2 if severity == 7
				replace     MID`d'b = (meandw`d'[8] + meandw`d'[9])/2 if severity == 7

				replace     MID`d'a = (meandw`d'[8] + meandw`d'[9])/2 if severity == 8
				replace     MID`d'b = (meandw`d'[9] + meandw`d'[10])/2 if severity == 8

				replace     MID`d'a = (meandw`d'[9] + meandw`d'[10])/2 if severity == 9
				replace     MID`d'b = (meandw`d'[10] + meandw`d'[11])/2 if severity == 9

				replace     MID`d'a = (meandw`d'[10] + meandw`d'[11])/2 if severity == 10
				replace     MID`d'b = (meandw`d'[12] + meandw`d'[13])/2 if severity == 10

				replace MID`d'b = 1 if severity == maxsev
			}
		}
	}
	tempfile `acg'
	qui save ``acg'', replace
	restore
}
clear
foreach acg of local list {
	append using ``acg''
}

// drop 1000 draws of DW, dont need them anymore
drop meandw0-meandw999

// make 1000 distribution variables
forvalues i = 0/999 {
	qui gen dist`i' = .
}

// make maxsev 0 if only 1 dw.
replace maxsev = 0 if maxsev == 1

local count = 1
count if severity == 0
local num `r(N)'
local num = `num'*1000

tempfile pre
save `pre', replace
// we now have severity cutoffs for each condition, now for each draw of each condition, we have to get the dristibution out of meps.
foreach acg of local list {
	use `pre', clear

	keep if acause_grouping == `acg'
	local cause = yld_cause[1]
	local grouping = grouping[1]
	forvalues i = 0/999 {
		local pctcompl = round(((`count'/`num')*100),.001)
		di in red "computing `cause' `grouping' distribution `i'/1000"
		di in red "`pctcompl'% complete"

		// get severity cutoffs
		sort severity
		local maxsev = maxsev
		di in red "`maxsev'"
		local cutoffasymp = 0

		// reset cutoffs each time
		forvalues s = 1/10 {
			local cutoff`s'a
			local cutoff`s'b
		}

		if maxsev >= 1 {
			local cutoff1a = MID`i'a[2]
			local cutoff1b = MID`i'b[2]
		}
		if maxsev >= 2 {
			local cutoff2a = MID`i'a[3]
			local cutoff2b = MID`i'b[3]
		}
		if maxsev >= 3 {
			local cutoff3a = MID`i'a[4]
			local cutoff3b = MID`i'b[4]
		}
		if maxsev >= 4 {
			local cutoff4a = MID`i'a[5]
			local cutoff4b = MID`i'b[5]
		}
		if maxsev >= 5 {
			local cutoff5a = MID`i'a[6]
			local cutoff5b = MID`i'b[6]
		}
		if maxsev >= 6 {
			local cutoff6a = MID`i'a[7]
			local cutoff6b = MID`i'b[7]
		}
		if maxsev >= 7 {
			local cutoff7a = MID`i'a[8]
			local cutoff7b = MID`i'b[8]
		}
		if maxsev >= 8 {
			local cutoff8a = MID`i'a[9]
			local cutoff8b = MID`i'b[9]
		}
		if maxsev >= 9 {
			local cutoff9a = MID`i'a[10]
			local cutoff9b = MID`i'b[10]
		}
		if maxsev == 10 {
			local cutoff10a = MID`i'a[11]
			local cutoff10b = MID`i'b[11]
		}

		// now go into the bootstrapped draws with the cutoffs and grab the distribution.
		preserve
		di in red "computing `cause' `grouping' distribution `i'/1000"
		di in red "`pctcompl'% complete"
		cap use "$SAVE_DIR/3a_meps_bootstrap_datasets/`i'/t`cause'",clear
		if !_rc {
			// Plot the distribution of DWs

			count if DW_diff_data!=.
			local total = `r(N)'

			count if DW_diff_data < 0
			local pct0 = `r(N)'/`total'
			local j 1
			while `j' <= `maxsev' {
				di in red "`j' of `maxsev' cutoffs == `cutoff`j'a' and `cutoff`j'b'"
				count  if DW_diff_data >= `cutoff`j'a' & DW_diff_data < `cutoff`j'b'
				local pct`j' = `r(N)'/`total'
				local j = `j' + 1

			}

			restore

			// fill in the distribution amounts
			local j 0
			while `j' <= `maxsev' {
				replace dist`i' = `pct`j'' if severity == `j'
				local j = `j' + 1
			}
		}
		else {
			di in red "Could not find file for `cause' `grouping'"

			if "`cause'"=="skin_bacterial_abs_cell" {
				pause on
				pause
			}

			restore
			local count = `count' + 1
			continue
		}

	local count = `count' + 1
	}
	tempfile `acg'
	save ``acg'', replace
}

clear
foreach acg of local list {
	append using ``acg''
}

// reporting
egen dist_mean = rowmean(dist*)
egen dist_lci  = rowpctile(dist*), p(2.5)
egen dist_uci  = rowpctile(dist*), p(97.5)

rename mean_DW JS_seq_DW
sort yld_cause grouping severity
save "$SAVE_DIR/3b_meps_severity_distributions_1000_draws_${date}.dta", replace
save "$SAVE_DIR/3b_meps_severity_distributions_1000_draws_current.dta", replace

keep yld_cause grouping healthstate hhseqid severity JS_seq_DW dist_*
order yld_cause grouping healthstate hhseqid severity JS_seq_DW dist_mean dist_lci dist_uci

tostring hhseqid, replace force

sort yld_cause grouping severity
replace JS = 0 if severity == 0
replace hhseqid = "999" if severity == 0
outsheet using "$SAVE_DIR/3b_meps_severity_distributions_${date}.csv", comma replace
outsheet using "$SAVE_DIR/3b_meps_severity_distributions_current.csv", comma replace

// END OF DO FILE
