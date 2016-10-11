	
	clear
	set more off, perm
	
	local prefix `1'
	local data_dir `2'
	global S_ADO `3'
	// Directory of general GBD ado functions
	local gbd_ado `4'
	// Step diagnostics directory
	local diag_dir `5'
	// Name for this job
	local name `6'
	// Directory of check files
	local check_file_dir `7'
	// Log directory
	local log_dir `8'
	// Code directory
	local code_dir `9'
	
	log using "`log_dir'/WITH_AGE_01_summary_stats.smcl", replace name(summ_stats)

// Settings
	set type double, perm
	adopath + "/snfs1/WORK/10_gbd/00_library/functions"
	
	tempfile appended
	forvalues x = 0/2 {
		use "`data_dir'/01_prob_draws/`x'_squeeze_WITH_AGE.dta", clear
	
	// Squeezing so that probability draws are never greater than 1- now happens at draw level in earlier code.
	// TODO: determine whether we indeed want to pursue this strategy, instead of allowing >100%
	// probabilities (and losing the interpretation as "probability"
		fastrowmean draw_*, mean_var_name("mean_")
		fastpctile draw_*, pct(2.5 97.5) names(ll_ ul_)
		drop draw_*
		gen pf = `x'
		if `x' append using `appended'
		save `appended', replace
	}
	drop _merge
	reshape wide mean_ ul_ ll_ n_, i(n_code age) j(pf)
	rename (*_0 *_1 *_2) (*_otp *_inp *_pool)
	tempfile main
	save `main', replace
	
// Merge on names of n-codes
	insheet using "`code_dir'/ncode_names.csv", comma names clear
	rename ncode_name name
	tempfile names
	save `names', replace
	merge 1:m n_code using `main', nogen assert(match master)
	
// Sort, format, save
	order n_code age name mean_inp ll_inp ul_inp n_inp mean_otp ll_otp ul_otp n_otp mean_pool ll_pool ul_pool n_pool
	sort_by_ncode n_code
	format mean_* ll_* ul_* %16.0g
	export delimited using "`data_dir'/WITH_AGE_long_term_prob_summary_stats.csv", delim(",") replace
	
// create check files
	file open done_summary using "`check_file_dir'/summary_stats.txt", replace write
	file close done_summary
	
	log close summ_stats	
	