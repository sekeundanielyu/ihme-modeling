// Set up burden of pain counterfactual using disability weights that have % of disability attributable to pain removed

cap program drop pain_get_ncode_dw_map
program define pain_get_ncode_dw_map
	version 12
	syntax , Out_dir(string) Category(string) prefix(string)
	
	qui {
	
// Bring in dataset from Nick K
import excel "`prefix'/WORK/04_epi/03_outputs/01_code/01_como/prod/como_bop/modify_dws/healthstates_2013_final_GBPainscores_2015_2_23.xlsx", firstrow sheet("Sheet1") clear	
keep healthstate_id Average
rename Average pain_adjustment
tempfile pain_adj
save `pain_adj'
	
// Define filepaths
	local in_dir "`prefix'/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2013/02_inputs"
	local n_hs_input "`in_dir'/parameters/maps/ncode_dws_map_spinal.csv"
	local hs_dw_input "`prefix'/WORK/04_epi/03_outputs/01_code/02_dw/02_standard/dw_full.csv"
	local tbi_pct_data "`prefix'/LIMITED_USE/PROJECT_FOLDERS/NLD/RADBOUD_UNIVERSITY_BRAIN_INJURY_COHORT_STUDY_RUBICS/NLD_RUBICS_1998_2011_AGGREGATED_DATA.CSV"
	
// Import N-code to health state map
	import delimited using "`n_hs_input'", clear case(preserve) delim(",") varnames(1)
	keep ncode hs_`category' hhseqid_`category'
	drop if hs_`category' == "" | hs_`category' == "custom"
	rename hs_`category' healthstate
	tempfile n_hs
	save `n_hs'
	
// Import Health-state to DW map
	import delimited using "`hs_dw_input'", clear case(preserve) delim(",") varnames(1) asdouble
	duplicates drop hhseqid, force
	// MERGE ON NICK K. PAIN ADJUSTMENT - "pain_adjustment" is the proportion of that DW that is due to pain, so we want to subtract that out to have a counterfactual "pain-free" DW
	merge m:1 healthstate_id using `pain_adj'
	drop if _merge == 2
	drop _merge
		// Nick K. didn't make adjustment factors for our special spinal lesions severity levels B, C - just give those average pain_adjustment of A, D healthstates
		if "`category'" == "lt_t" {
		sum pain_adjustment if hhseqid == 303 | hhseqid == 229
		replace pain_adjustment = r(mean) if hhseqid == 239
		sum pain_adjustment if hhseqid == 301 | hhseqid == 229
		replace pain_adjustment = r(mean) if hhseqid == 241		
		}
		if "`category'" == "lt_u" {
		sum pain_adjustment if hhseqid == 304 | hhseqid == 229
		replace pain_adjustment = r(mean) if hhseqid == 240
		sum pain_adjustment if hhseqid == 302 | hhseqid == 229
		replace pain_adjustment = r(mean) if hhseqid == 242	
		}
	drop healthstate_id
	// drop if healthstate == ""
	rename hhseqid hhseqid_`category'
	// APPLY PAIN ADJUSTMENT TO DW DRAWS
	forvalues i = 0/999 {
		replace draw`i' = pain_adjustment * draw`i'
	}
	tempfile hs_dw
	save `hs_dw'
	drop if healthstate == ""
	tempfile hs_dw_tbi
	save `hs_dw_tbi'
	use `hs_dw', clear
	
// Merge 2 maps together
	merge 1:m hhseqid_`category' using `n_hs', keep(match) nogen
	drop healthstate
	tempfile n_dw
	save `n_dw'
	
// Calculate long-term TBI values and insert
	if "`category'" != "st" {
		
	// Generate file of TBI draws
		capture mkdir "`out_dir'/tbi_pct_draws"
		gen_tbi_pct_draws, in_path("`tbi_pct_data'") out_dir("`out_dir'/tbi_pct_draws")
		
		foreach n in N27 N28 {
		// Import % draws
			import delimited using "`out_dir'/tbi_pct_draws/`n'.csv", clear varnames(1)
			rename draw* pct*
			
		// Merge file onto health state to DW map
			merge 1:1 healthstate using `hs_dw_tbi', keep(match) nogen
		
		// Collapse to one set of DW draws
			forvalues x = 0/999 {
				replace draw`x' = draw`x' * pct_`x'
				drop pct_`x'
			}
			collapse (sum) draw*
			gen ncode = "`n'"
			tempfile `n'
			save ``n''
			
		// Erase the temporary % file
			erase "`out_dir'/tbi_pct_draws/`n'.csv"
		}
		
	// Append onto rest of N-code to DW map
		use `n_dw', clear
		foreach n in N27 N28 {
			append using ``n''
		}
		save `n_dw', replace
	}
	
// Remove now empty temporary directory
	cap rmdir "`out_dir'/tbi_pct_draws"

// Format
	order ncode, first
	sort_by_ncode ncode
	format draw* %16.0g

// Save final file
	rename ncode n_code
	keep n_code draw*
	export delimited using "`out_dir'/PAIN_`category'_dws_by_ncode.csv", replace delim(",")
	
	}
	
end
