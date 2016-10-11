// Get 1000 draws of predicted DWs from MEPS

if c(os) == "Windows" {
	global SAVE_DIR "strDir"
	global R "strPathToR"
}
if c(os) == "Unix" {
	set more off
	global SAVE_DIR "strDir"
	global R "strPathToR"
}

tempfile dwdraws
foreach survey in "meps" "ahs1" "ahs12" "nesarc" {

	if "`survey'"=="meps" {
		local condvar "condition"
	}
	else if "`survey'"=="ahs1" | "`survey'"=="ahs12" {
		local condvar "como"
	}
	else {
		local condvar "condition"
	}

	forvalues i=1/1000 {
		cap use "$SAVE_DIR/3a_`survey'_dw_draws/`i'",clear

		cap merge 1:1 `condvar' using `dwdraws', nogen
		cap save `dwdraws', replace
	}

	egen mean_dw = rowmean(dw_t*)
	egen lower_dw  = rowpctile(dw_t*), p(2.5)
	egen upper_dw  = rowpctile(dw_t*), p(97.5)

	rename `condvar' acause
	replace acause = substr(acause,2,.)
	order acause mean_dw lower_dw upper_dw dw_t*
	sort acause

	save "$SAVE_DIR/3d_customdws_`survey'.dta", replace

}

// END OF DO FILE
