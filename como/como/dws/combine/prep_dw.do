// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:	Create epi folder structure
// code:		do "/home/j/WORK/04_epi/03_outputs/01_code/02_dw/prep_dw.do"

// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	local out_dir "$prefix/WORK/04_epi/03_outputs/01_code/02_dw"
	local tmp_dir "/clustertmp/WORK/04_epi/03_outputs/01_code/02_dw"

// move DWs into place
	use "$prefix/WORK/00_dimensions/03_causes/healthstates.dta", clear
	keep if hhseqid != . & cause_version == 2
	tempfile hs
	save `hs', replace
	insheet using "$prefix/Project/GBD/dalynator/yld/disability_weights/dw_draws_09192011.csv", comma clear
	merge 1:1 hhseqid using `hs', keep(3) nogen
	renpfix meandw dw
	rename dw1000 dw0
	keep healthstate_id healthstate dw*
	sort healthstate_id
	format %16.0g dw*
	outsheet using "`out_dir'/dw_gbd2010.csv", comma replace
	outsheet using "`tmp_dir'/dw_gbd2010.csv", comma replace

