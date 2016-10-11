// Get 1000 draws of distributions

cap restore, not

clear all
set mem 300m
set maxvar 30000
set more off


foreach mo in 1 12 {

	// make sure aus means have been compiled from the bootstrap
	insheet using "$dir/gbd_2013_maps/${causename}.csv", comma clear

	// start distributions analysis
	keep if run == 1

	keep cause grouping healthstate severity hhseqid ahs`mo'

	// drop if not tracking in aus 1mo
	drop if ahs`mo' == ""

	// pull 1000 draws for each hhseqid
	destring hhseqid, force replace

	preserve
	insheet using "$gbd_dws", clear
	rename draw* meandw*
	keep hhseqid meandw0- meandw999
	keep hhseqid meandw0- meandw999
	tempfile weights
	save `weights', replace
	restore

	merge m:1 hhseqid using `weights', keep(match master) nogenerate

	// get the mean weight for reporitng later on
	egen mean_DW = rowmean(meandw*)

	// get max number of severities for each cause
	bysort cause grouping: egen maxsev = max(severity)

	// for causes with more than one severity, make a new line for asymptomatic
	expand 2 if severity == 1 & maxsev > 1, gen(asymp)
	replace asymp = 1 if severity == 1 & maxsev == 1 // for those with only one weight we only get asymp
	replace asymp = 0 if asymp == .
	replace severity = 0 if asymp == 1

	// get 1000 draws of the midpoints between draws
	forvalues d = 0/999 {
		gen 		MID`d'a = 0 if asymp == 1
		gen 		MID`d'b = 0 if asymp == 1
	}

	egen acause_grouping = group(cause grouping)
	levelsof acause_grouping, local(list)
	foreach acg of local list {
		preserve
		qui keep if acause_grouping == `acg'

		count if asymp == 0
		if `r(N)' != 0 {
			sort severity
			forvalues d = 0/999 {
				replace     MID`d'a = 0 							  if severity == 1
				replace     MID`d'b = (meandw`d'[2] + meandw`d'[3])/2 if severity == 1

				replace     MID`d'a = (meandw`d'[2] + meandw`d'[3])/2 if severity == 2
				replace     MID`d'b = (meandw`d'[3] + meandw`d'[4])/2 if severity == 2

				replace     MID`d'a = (meandw`d'[3] + meandw`d'[4])/2 if severity == 3
				replace     MID`d'b = (meandw`d'[4] + meandw`d'[5])/2 if severity == 3

				replace     MID`d'a = (meandw`d'[4] + meandw`d'[5])/2 if severity == 4
				replace     MID`d'b = (meandw`d'[5] + meandw`d'[6])/2 if severity == 4

				replace     MID`d'b = (meandw`d'[5] + meandw`d'[6])/2 if severity == 4
				replace     MID`d'b = (meandw`d'[6] + meandw`d'[7])/2 if severity == 4

				replace MID`d'b = 1 if severity == maxsev
			}
		}
		tempfile `acg'
		save ``acg'', replace
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
		gen dist`i' = .
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

		qui keep if acause_grouping == `acg'
		local c = ahs`mo' // aus1 variable name
		forvalues i = 0/999 {
			local pctcompl = round(((`count'/6000)*100),.001)
			di in red "computing `cause' distribution `i'/1000"
			di in red "`pctcompl'% complete"

			// get severity cutoffs
			sort severity
			local maxsev = maxsev
			local cutoffasymp = 0

			// reset cutoffs each time
			forvalues s = 1/5 {
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
			if maxsev == 5 {
				local cutoff5a = MID`i'a[6]
				local cutoff5b = MID`i'b[6]
			}

			// now go into the bootstrapped draws with the cutoffs and grab the distribution.
			preserve
			use "$SAVE_DIR/3a_ahs`mo'_bootstrap_datasets//`i'//`c'", clear

			gen DW_diff_data = 1-((1-dw_hat)/(1-dw_s))
			count if DW_diff_data!=.
			local total = `r(N)'
			count if DW_diff_data < 0
			local pct0 = `r(N)'/`total'

			local j 1
			while `j' <= `maxsev' {
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

	rename mean_DW ahs`mo'mo_DW

	save "$SAVE_DIR/3b_ahs`mo'mo_severity_distributions_1000_draws_${date}.dta", replace
	save "$SAVE_DIR/3b_ahs`mo'mo_severity_distributions_1000_draws_current.dta", replace

	keep cause grouping healthstate severity hhseqid ahs`mo'mo_DW dist_*
	order cause grouping healthstate severity hhseqid ahs`mo'mo_DW dist_mean dist_lci dist_uci
	rename dist* ahs`mo'modist*

	tostring hhseqid, replace force
	replace hhseqid = "?" if hhseqid == "."
	replace hhseqid = "." if hhseqid == "?"

	sort cause severity
	replace ahs`mo'mo_DW = 0 if severity == 0
	outsheet using "$SAVE_DIR/3b_ahs`mo'mo_severity_distributions_${date}.csv", comma replace
	outsheet using "$SAVE_DIR//3b_ahs`mo'mo_severity_distributions_current.csv", comma replace
}

// END OF DO FILE
