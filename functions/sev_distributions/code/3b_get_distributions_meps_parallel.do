// Get 1000 draws of distributions form MEPS

set more off

** set OS
if c(os) == "Windows" {
	global SAVE_DIR "strDir"
	global R "strPathToR"
}
if c(os) == "Unix" {
	global SAVE_DIR "strDir"
	global R "strPathToR"
}

// set path - use all relative paths from here on
cd "$H/MEPS/severity_distributions"
global dir = subinstr("`c(pwd)'","\","/",.)
global CW_DATADIR "$j/Project/GBD/Systematic Reviews/ANALYSES/MEPS/data/1_crosswalk_survey"
global MEPS_DATADIR "$j/Project/GBD/Systematic Reviews/ANALYSES/MEPS/data/2_meps"
global DATADIR "$j/Project/GBD/Systematic Reviews/ANALYSES/MEPS/data"


// Names
global surveys ahs1mo ahs12mo nesarc meps

// External Files that get called on
global gbd_dws "$j/WORK/04_epi/03_outputs/01_code/02_dw/02_standard/dw.csv"

// Save the name of the file with the most updated causes of severity distribution as a macro
global causename gbd2013_causes

// the date so that all files saved as outputs are dated
global date = subinstr(lower("`c(current_date)'")," ","",.)
// global date "19jun2014"

// Accept yld_cause and grouping as arguments
local yld_cause = "`1'"

// get disability weights
insheet using "$gbd_dws", clear
rename draw* meandw*
keep hhseqid meandw0- meandw999
duplicates drop
tempfile weights
save `weights', replace

// start distributions analysis
local icd_map = "gbd2010"
if "`icd_map'"=="gbd2013" {

	import excel using "./gbd_2013_maps/icd_healthstate.xls", firstrow clear
	keep yld_cause grouping healthstate hhseqid
	duplicates drop

}
else if "`icd_map'"=="gbd2010" {
	insheet using "./gbd_2013_maps/gbd2013_keep_list.csv", names clear
	tempfile keeplist
	save `keeplist'

	import excel using "$j/WORK/04_epi/02_models/01_code/06_custom/_exclusivity_adjustments/sequelae.xlsx", sheet(Sheet1) first clear
	keep acause from_grouping from_healthstate resid_grouping resid_healthstate
	gen grouping = from_grouping
	gen healthstate = from_healthstate
	duplicates drop
	tempfile excl_remaps
	save `excl_remaps'

	import excel using "$j/WORK/00_dimensions/00_schema/dimensions.xlsx", sheet(sequelae) first clear
	keep acause grouping healthstate
	merge 1:1 acause grouping healthstate using `excl_remaps', keep(1 3) nogen
	replace healthstate = resid_healthstate if resid_healthstate!=""
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
	drop if acause=="cvd_stroke_isch"
	replace acause="cvd_stroke" if regexm(acause,"stroke")

	rename acause yld_cause

}

// pull 1000 draws for each hhseqid
destring hhseqid, force replace
merge m:1 hhseqid using `weights', keep(match master) nogenerate
duplicates drop

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
keep if yld_cause=="`yld_cause'"
levelsof grouping, local(groupings)

tempfile allcause
save `allcause'

tempfile all_summaries
foreach grouping of local groupings {
	use `allcause', clear
	keep if grouping=="`grouping'"

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
	local num 1000

	// we now have severity cutoffs for each condition, now for each draw of each condition, we have to get the dristibution out of meps.
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
		di in red "computing `yld_cause' `grouping' distribution `i'/1000"
		di in red "`pctcompl'% complete"
		cap use "$SAVE_DIR/3a_meps_bootstrap_datasets/`i'/t`yld_cause'",clear
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
			di in red "Could not find file for `yld_cause' `grouping'"

			restore
			local count = `count' + 1
			continue
		}
		local count = `count' + 1
	}

	cap append using `all_summaries'
	save `all_summaries', replace
}

// reporting
egen dist_mean = rowmean(dist*)
egen dist_lci  = rowpctile(dist*), p(2.5)
egen dist_uci  = rowpctile(dist*), p(97.5)

replace grouping = from_grouping if from_grouping!=""
replace healthstate = from_healthstate if from_healthstate!=""

rename mean_DW JS_seq_DW
sort yld_cause grouping severity
outsheet using "$SAVE_DIR/3b_meps_distributions/`yld_cause'_1000_draws.csv", comma replace

keep yld_cause grouping healthstate hhseqid severity JS_seq_DW dist_*
order yld_cause grouping healthstate hhseqid severity JS_seq_DW dist_mean dist_lci dist_uci

tostring hhseqid, replace force

sort yld_cause grouping severity
replace JS = 0 if severity == 0
replace hhseqid = "999" if severity == 0
outsheet using "$SAVE_DIR/3b_meps_distributions/`yld_cause'_summary.csv", comma replace

// END OF DO FILE
